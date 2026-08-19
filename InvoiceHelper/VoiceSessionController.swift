import Foundation
import Speech
import AVFoundation

/// Owns one continuous voice conversation: microphone, endpointing, and speech output.
///
/// The key difference from `VoiceRecognitionManager` is that a turn ends on silence
/// rather than on a button press, and the controller can speak back. Callers observe
/// `state` and supply an `onTurn` handler that returns the line to say next.
@MainActor
final class VoiceSessionController: NSObject, ObservableObject {
    enum State: Equatable {
        case idle
        case listening
        case thinking
        case speaking
        case failed(String)

        var isActive: Bool {
            switch self {
            case .idle, .failed: return false
            case .listening, .thinking, .speaking: return true
            }
        }
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var partialTranscript = ""
    /// Everything said so far this session, oldest first. Drives the on-screen log.
    @Published private(set) var exchanges: [Exchange] = []

    struct Exchange: Identifiable, Equatable {
        enum Speaker { case user, app }
        let id = UUID()
        let speaker: Speaker
        let text: String
    }

    /// Called when the user finishes a turn. Return the reply to speak, or nil to stay quiet
    /// and keep listening. Runs on the main actor.
    var onTurn: ((String) async -> String?)?

    /// Locale used for both recognition and speech output.
    var locale: Locale = Locale(identifier: "en-GB")

    /// Words to bias recognition towards, typically customer and saved item names.
    var contextualStrings: [String] = []

    /// How long a pause ends the user's turn. Kept short so replies feel snappy;
    /// echo rejection + post-speech cooldown prevent the app from hearing itself.
    var endpointSilence: TimeInterval = 0.85

    private let audioEngine = AVAudioEngine()
    private let synthesizer = AVSpeechSynthesizer()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var silenceTimer: Timer?
    private var lastTranscriptChange = Date()
    /// Set while the app is talking, so its own voice is not treated as user input.
    private var suppressRecognition = false
    /// Last line spoken by the app — used to reject speaker echo as a fake answer.
    private var lastSpokenLine = ""
    /// Generation token so a delayed post-speech cooldown cannot restart listening
    /// after stop / barge-in / a newer speak cycle.
    private var listenGeneration = 0
    /// Skip the post-speech pause once (barge-in should listen immediately).
    private var skipNextSpeechCooldown = false
    /// Quiet gap after TTS so room echo is not transcribed as the user's answer.
    private let postSpeechCooldownNanoseconds: UInt64 = 380_000_000

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    // MARK: - Session lifecycle

    /// Requests permissions and resets session state. Does **not** open the mic —
    /// call `say(_:)` for the opening line so listening starts only after speech ends.
    func start() async {
        guard case .idle = state else { return }
        guard await requestPermissions() else { return }
        exchanges.removeAll()
        partialTranscript = ""
        lastSpokenLine = ""
    }

    func stop() {
        listenGeneration += 1
        silenceTimer?.invalidate()
        silenceTimer = nil
        endRecognition()
        synthesizer.stopSpeaking(at: .immediate)
        deactivateSession()
        state = .idle
        partialTranscript = ""
        suppressRecognition = false
        skipNextSpeechCooldown = false
        isSuspended = false
    }

    /// Speaks a line without expecting the user to have said anything first,
    /// used for the opening question. Listening resumes only after speech finishes.
    func say(_ line: String) {
        guard !line.isEmpty else { return }
        exchanges.append(Exchange(speaker: .app, text: line))
        speak(line)
    }

    // MARK: - Listening

    private func beginListening() {
        endRecognition()

        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            state = .failed("Dictation is not available for \(locale.identifier) right now.")
            return
        }

        do {
            let session = AVAudioSession.sharedInstance()
            // playAndRecord so the synthesizer can speak without tearing the session down.
            // Allow Bluetooth; keep defaultToSpeaker so prompts are audible without headphones.
            try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.duckOthers, .defaultToSpeaker, .allowBluetooth])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            state = .failed("Could not start audio: \(error.localizedDescription)")
            return
        }

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        // Prefer Apple's cloud recognizer when available — faster finals and better
        // natural-language accuracy than forcing on-device for short conversational turns.
        req.requiresOnDeviceRecognition = false
        if !contextualStrings.isEmpty {
            req.contextualStrings = Array(contextualStrings.prefix(100))
        }
        request = req

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else {
            state = .failed("No audio input available.")
            return
        }

        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            req.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            state = .failed("Could not start recording: \(error.localizedDescription)")
            endRecognition()
            return
        }

        state = .listening
        partialTranscript = ""
        lastTranscriptChange = Date()
        suppressRecognition = false
        startSilenceTimer()

        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                guard !self.suppressRecognition else { return }
                guard case .listening = self.state else { return }

                if let result {
                    let text = result.bestTranscription.formattedString
                    if self.isLikelyEcho(text) {
                        // Keep listening; do not advance the silence clock on echo.
                        return
                    }
                    if text != self.partialTranscript {
                        self.partialTranscript = text
                        self.lastTranscriptChange = Date()
                    }
                    // Recognizer finals often arrive before our silence timer — take them.
                    if result.isFinal,
                       !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        self.finishTurn()
                        return
                    }
                }
                if error != nil {
                    // Endpointing drives turn ends; a recognizer error mid-turn is
                    // only fatal if we have nothing at all to work with.
                    if self.partialTranscript.isEmpty {
                        self.beginListening()
                    } else if !self.isLikelyEcho(self.partialTranscript) {
                        self.finishTurn()
                    } else {
                        self.partialTranscript = ""
                        self.beginListening()
                    }
                }
            }
        }
    }

    /// Polls rather than using the recognizer's own endpointing, which is tuned for
    /// dictation and waits too long to feel conversational.
    private func startSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, case .listening = self.state else { return }
                let text = self.partialTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return }
                if self.isLikelyEcho(text) {
                    self.partialTranscript = ""
                    return
                }
                if Date().timeIntervalSince(self.lastTranscriptChange) >= self.endpointSilence {
                    self.finishTurn()
                }
            }
        }
    }

    private func finishTurn() {
        let utterance = partialTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !utterance.isEmpty else { return }
        guard !isLikelyEcho(utterance) else {
            partialTranscript = ""
            lastTranscriptChange = Date()
            return
        }

        silenceTimer?.invalidate()
        silenceTimer = nil
        endRecognition()

        exchanges.append(Exchange(speaker: .user, text: utterance))
        partialTranscript = ""
        state = .thinking

        Task {
            let reply = await onTurn?(utterance)
            guard state == .thinking else { return }
            if let reply, !reply.isEmpty {
                exchanges.append(Exchange(speaker: .app, text: reply))
                speak(reply)
            } else {
                beginListening()
            }
        }
    }

    private func endRecognition() {
        if audioEngine.isRunning { audioEngine.stop() }
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
    }

    private func deactivateSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Speaking

    private func speak(_ line: String) {
        listenGeneration += 1
        state = .speaking
        suppressRecognition = true
        silenceTimer?.invalidate()
        silenceTimer = nil
        endRecognition()
        lastSpokenLine = line

        let utterance = AVSpeechUtterance(string: line)
        utterance.voice = preferredVoice()
        // Near-default rate with a slight warm tilt; premium/enhanced voices carry naturalness.
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.96
        utterance.pitchMultiplier = 1.02
        utterance.preUtteranceDelay = 0.05
        utterance.postUtteranceDelay = 0.05
        synthesizer.speak(utterance)
    }

    /// Prefers premium/enhanced voices for the session locale (downloadable in Settings →
    /// Accessibility → Spoken Content → Voices). Falls back gracefully if only compact voices exist.
    private func preferredVoice() -> AVSpeechSynthesisVoice? {
        let preferred = locale.identifier
        let voices = AVSpeechSynthesisVoice.speechVoices()

        func qualityScore(_ quality: AVSpeechSynthesisVoiceQuality) -> Int {
            switch quality {
            case .premium: return 50
            case .enhanced: return 30
            default: return 0
            }
        }

        func languageScore(_ language: String) -> Int {
            if language == preferred { return 100 }
            if language.hasPrefix("en-GB"), preferred.hasPrefix("en") { return 80 }
            if language.hasPrefix("en"), preferred.hasPrefix("en") { return 40 }
            if language.hasPrefix(String(preferred.prefix(2))) { return 20 }
            return -1
        }

        func nameBonus(_ name: String) -> Int {
            let n = name.lowercased()
            var bonus = 0
            if n.contains("siri") { bonus += 12 }
            // Natural-sounding English voices commonly installed on iOS.
            for hint in ["martha", "arthur", "daniel", "kate", "serena", "moira", "samantha", "aaron"] {
                if n.contains(hint) { bonus += 8; break }
            }
            return bonus
        }

        let ranked = voices.compactMap { voice -> (AVSpeechSynthesisVoice, Int)? in
            let lang = languageScore(voice.language)
            guard lang >= 0 else { return nil }
            return (voice, lang + qualityScore(voice.quality) + nameBonus(voice.name))
        }.sorted { $0.1 > $1.1 }

        if let best = ranked.first { return best.0 }
        return AVSpeechSynthesisVoice(language: "en-GB")
            ?? AVSpeechSynthesisVoice(language: "en-US")
    }

    /// Lets the user talk over the app. Called by the view when the mic button is tapped
    /// while the app is mid-sentence.
    func bargeIn() {
        guard case .speaking = state else { return }
        listenGeneration += 1
        skipNextSpeechCooldown = true
        synthesizer.stopSpeaking(at: .immediate)
        // Listen immediately; the cancel callback must not schedule another cooldown.
        suppressRecognition = false
        beginListening()
        skipNextSpeechCooldown = false
    }

    // MARK: - Echo rejection

    /// Speaker output often lands back in the mic right after TTS. Reject transcripts
    /// that are mostly the line we just spoke.
    private func isLikelyEcho(_ transcript: String) -> Bool {
        let spoken = normalizedForEcho(lastSpokenLine)
        let heard = normalizedForEcho(transcript)
        guard !spoken.isEmpty, !heard.isEmpty else { return false }

        if spoken.contains(heard), heard.count >= 4 { return true }
        if heard.contains(spoken), spoken.count >= 8 { return true }

        let spokenTokens = Set(spoken.split(separator: " ").map(String.init).filter { $0.count > 2 })
        let heardTokens = Set(heard.split(separator: " ").map(String.init).filter { $0.count > 2 })
        guard !heardTokens.isEmpty, !spokenTokens.isEmpty else { return false }
        let overlap = spokenTokens.intersection(heardTokens).count
        let ratio = Double(overlap) / Double(heardTokens.count)
        return ratio >= 0.7 && overlap >= 2
    }

    private func normalizedForEcho(_ text: String) -> String {
        text
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    // MARK: - Suspend and resume

    /// True while suspended by the keyboard, so resume() knows there is something
    /// to go back to and a second suspend is a no-op.
    private(set) var isSuspended = false

    /// Stops listening without ending the session. Used while the keyboard is up:
    /// otherwise the recognizer transcribes room noise and muttering straight into
    /// whichever field is focused.
    func suspend() {
        guard !isSuspended, state.isActive else { return }
        isSuspended = true
        listenGeneration += 1
        synthesizer.stopSpeaking(at: .immediate)
        silenceTimer?.invalidate()
        silenceTimer = nil
        endRecognition()
        deactivateSession()
        partialTranscript = ""
        suppressRecognition = false
        state = .idle
    }

    /// Picks listening back up where suspend() left it.
    func resume() {
        guard isSuspended else { return }
        isSuspended = false
        beginListening()
    }

    // MARK: - Permissions

    private func requestPermissions() async -> Bool {
        let speech = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
        }
        guard speech else {
            state = .failed("Speech recognition permission was denied. Enable it in Settings, Privacy, Speech Recognition.")
            return false
        }

        let mic = await withCheckedContinuation { continuation in
            if #available(iOS 17.0, *) {
                AVAudioApplication.requestRecordPermission { continuation.resume(returning: $0) }
            } else {
                AVAudioSession.sharedInstance().requestRecordPermission { continuation.resume(returning: $0) }
            }
        }
        guard mic else {
            state = .failed("Microphone permission was denied. Enable it in Settings, Privacy, Microphone.")
            return false
        }
        return true
    }

    private func scheduleListenAfterSpeech() {
        let generation = listenGeneration
        if skipNextSpeechCooldown {
            skipNextSpeechCooldown = false
            suppressRecognition = false
            beginListening()
            return
        }

        suppressRecognition = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: postSpeechCooldownNanoseconds)
            guard generation == listenGeneration else { return }
            guard case .speaking = state else { return }
            suppressRecognition = false
            beginListening()
        }
    }
}

// MARK: - AVSpeechSynthesizerDelegate

extension VoiceSessionController: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            handleSpeechEnded()
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            // Barge-in already opened the mic; ignore this callback.
            guard case .speaking = state else { return }
            handleSpeechEnded()
        }
    }

    @MainActor
    private func handleSpeechEnded() {
        guard case .speaking = state else { return }
        scheduleListenAfterSpeech()
    }
}
