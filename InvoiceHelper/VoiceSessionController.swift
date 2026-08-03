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

    /// How long a pause ends the user's turn.
    var endpointSilence: TimeInterval = 1.2

    private let audioEngine = AVAudioEngine()
    private let synthesizer = AVSpeechSynthesizer()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var silenceTimer: Timer?
    private var lastTranscriptChange = Date()
    /// Set while the app is talking, so its own voice is not treated as user input.
    private var suppressRecognition = false

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    // MARK: - Session lifecycle

    func start() async {
        guard case .idle = state else { return }
        guard await requestPermissions() else { return }
        exchanges.removeAll()
        partialTranscript = ""
        beginListening()
    }

    func stop() {
        silenceTimer?.invalidate()
        silenceTimer = nil
        endRecognition()
        synthesizer.stopSpeaking(at: .immediate)
        deactivateSession()
        state = .idle
        partialTranscript = ""
    }

    /// Speaks a line without expecting the user to have said anything first,
    /// used for the opening question.
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
            try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.duckOthers, .defaultToSpeaker])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            state = .failed("Could not start audio: \(error.localizedDescription)")
            return
        }

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        req.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
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
        startSilenceTimer()

        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                guard !self.suppressRecognition else { return }

                if let result {
                    let text = result.bestTranscription.formattedString
                    if text != self.partialTranscript {
                        self.partialTranscript = text
                        self.lastTranscriptChange = Date()
                    }
                }
                if error != nil {
                    // Endpointing drives turn ends; a recognizer error mid-turn is
                    // only fatal if we have nothing at all to work with.
                    if self.partialTranscript.isEmpty {
                        self.beginListening()
                    } else {
                        self.finishTurn()
                    }
                }
            }
        }
    }

    /// Polls rather than using the recognizer's own endpointing, which is tuned for
    /// dictation and waits too long to feel conversational.
    private func startSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, case .listening = self.state else { return }
                guard !self.partialTranscript.isEmpty else { return }
                if Date().timeIntervalSince(self.lastTranscriptChange) >= self.endpointSilence {
                    self.finishTurn()
                }
            }
        }
    }

    private func finishTurn() {
        let utterance = partialTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !utterance.isEmpty else { return }

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
        state = .speaking
        suppressRecognition = true
        endRecognition()

        let utterance = AVSpeechUtterance(string: line)
        utterance.voice = AVSpeechSynthesisVoice(language: locale.identifier)
            ?? AVSpeechSynthesisVoice(language: "en-GB")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.postUtteranceDelay = 0.1
        synthesizer.speak(utterance)
    }

    /// Lets the user talk over the app. Called by the view when the mic button is tapped
    /// while the app is mid-sentence.
    func bargeIn() {
        guard case .speaking = state else { return }
        synthesizer.stopSpeaking(at: .immediate)
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
            handleSpeechEnded()
        }
    }

    @MainActor
    private func handleSpeechEnded() {
        suppressRecognition = false
        guard case .speaking = state else { return }
        beginListening()
    }
}
