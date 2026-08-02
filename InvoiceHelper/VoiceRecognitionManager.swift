import Foundation
import Speech
import AVFoundation

@MainActor
final class VoiceRecognitionManager: NSObject, ObservableObject {
    @Published var isListening = false
    @Published var recognizedText = ""
    @Published var error: String?
    @Published var currentLanguage: SupportedLanguage = .english

    private let speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    enum SupportedLanguage: String, CaseIterable {
        case english = "en-US"
        case romanian = "ro-RO"

        var displayName: String {
            switch self {
            case .english: "English"
            case .romanian: "Romanian"
            }
        }
    }

    override init() {
        self.speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: SupportedLanguage.english.rawValue))
        super.init()
        requestMicrophoneAuthorization()
    }

    /// Request microphone permission from the user
    private func requestMicrophoneAuthorization() {
        AVAudioApplication.requestRecordPermission { granted in
            DispatchQueue.main.async {
                if !granted {
                    self.error = "Microphone permission denied. Please enable it in Settings."
                }
            }
        }
    }

    /// Start listening for voice input
    func startListening() async {
        error = nil
        guard !isListening else { return }

        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            self.error = "Audio session error: \(error.localizedDescription)"
            return
        }

        guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
            error = "Speech recognition authorization required"
            return
        }

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            error = "Unable to create recognition request"
            return
        }

        recognitionRequest.shouldReportPartialResults = true

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)!

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            recognitionRequest.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
            isListening = true
            recognizedText = ""

            let locale = Locale(identifier: currentLanguage.rawValue)
            let recognizer = SFSpeechRecognizer(locale: locale) ?? SFSpeechRecognizer()!

            recognitionTask = recognizer.recognitionTask(with: recognitionRequest) { result, error in
                DispatchQueue.main.async {
                    if let result = result {
                        self.recognizedText = result.bestTranscription.formattedString
                    }

                    if let error = error {
                        self.error = error.localizedDescription
                        self.stopListening()
                    }

                    if let isFinal = result?.isFinal, isFinal {
                        self.stopListening()
                    }
                }
            }
        } catch {
            self.error = "Audio engine error: \(error.localizedDescription)"
        }
    }

    /// Stop listening and clean up
    func stopListening() {
        isListening = false
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
    }

    /// Change the recognition language
    func setLanguage(_ language: SupportedLanguage) {
        currentLanguage = language
    }
}
