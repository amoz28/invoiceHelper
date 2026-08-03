import Foundation
import Speech
import AVFoundation

/// Wraps `SFSpeechRecognizer` for on-device dictation in English and Romanian.
@MainActor
final class VoiceRecognitionManager: NSObject, ObservableObject {
    enum SupportedLanguage: String, CaseIterable, Identifiable {
        case english = "en-GB"
        case romanian = "ro-RO"

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .english: return "English"
            case .romanian: return "Romanian"
            }
        }
    }

    @Published var isListening = false
    @Published var recognizedText = ""
    @Published var error: String?
    @Published var currentLanguage: SupportedLanguage = .english

    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    /// Asks for speech + microphone permission. Safe to call repeatedly.
    func requestPermissions() async -> Bool {
        let speechGranted = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
        guard speechGranted else {
            error = "Speech recognition permission was denied. Enable it in Settings, Privacy, Speech Recognition."
            return false
        }

        let micGranted = await withCheckedContinuation { continuation in
            if #available(iOS 17.0, *) {
                AVAudioApplication.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            } else {
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        }
        guard micGranted else {
            error = "Microphone permission was denied. Enable it in Settings, Privacy, Microphone."
            return false
        }

        return true
    }

    func startListening() async {
        guard !isListening else { return }
        error = nil
        recognizedText = ""

        guard await requestPermissions() else { return }

        let locale = Locale(identifier: currentLanguage.rawValue)
        guard let recognizer = SFSpeechRecognizer(locale: locale) else {
            error = "\(currentLanguage.displayName) is not supported for dictation on this device."
            return
        }
        guard recognizer.isAvailable else {
            error = "\(currentLanguage.displayName) dictation is not available right now. Check the language is downloaded in Settings."
            return
        }

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            self.error = "Could not start audio: \(error.localizedDescription)"
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // Keeps dictation working with no network where the device supports it.
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        recognitionRequest = request

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else {
            self.error = "No audio input available."
            teardownAudio()
            return
        }

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            self.error = "Could not start recording: \(error.localizedDescription)"
            teardownAudio()
            return
        }

        isListening = true

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, taskError in
            Task { @MainActor in
                guard let self else { return }
                if let result {
                    self.recognizedText = result.bestTranscription.formattedString
                    if result.isFinal { self.stopListening() }
                }
                if let taskError {
                    // A cancelled task is expected when the user taps Stop.
                    let nsError = taskError as NSError
                    let userCancelled = nsError.domain == "kAFAssistantErrorDomain" && nsError.code == 216
                    if !userCancelled && self.recognizedText.isEmpty {
                        self.error = taskError.localizedDescription
                    }
                    self.stopListening()
                }
            }
        }
    }

    func stopListening() {
        guard isListening || recognitionTask != nil else { return }
        isListening = false
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        teardownAudio()
    }

    private func teardownAudio() {
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func setLanguage(_ language: SupportedLanguage) {
        guard language != currentLanguage else { return }
        stopListening()
        currentLanguage = language
        recognizedText = ""
        error = nil
    }
}
