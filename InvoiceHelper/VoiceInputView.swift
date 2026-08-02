import SwiftUI

struct VoiceInputView: View {
    @StateObject private var voiceManager = VoiceRecognitionManager()
    @StateObject private var translationService = TranslationService()
    @StateObject private var commandParser = VoiceCommandParser()

    @Binding var isPresented: Bool
    var onItemsAdded: ([VoiceLineItem]) -> Void
    var onNoteAdded: (String) -> Void
    var onTaxRateChanged: (Double) -> Void

    @State private var translatedText = ""
    @State private var showResults = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header
                VStack(spacing: 12) {
                    Text("Create Invoice with Voice")
                        .font(.title2.weight(.bold))
                    
                    // Language selector
                    Picker("Language", selection: $voiceManager.currentLanguage) {
                        ForEach(VoiceRecognitionManager.SupportedLanguage.allCases, id: \.self) { lang in
                            Text(lang.displayName).tag(lang)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .padding()
                .background(Color(.systemGroupedBackground))

                // Content
                ScrollView {
                    VStack(spacing: 16) {
                        // Recording indicator
                        if voiceManager.isListening {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .tint(AppTheme.infoBlue)
                                Text("Listening...")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(AppTheme.infoBlue)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(12)
                            .background(AppTheme.infoBlue.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                        }

                        // Transcription display
                        if !voiceManager.recognizedText.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("You said:")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Text(voiceManager.recognizedText)
                                    .font(.body)
                                    .padding(12)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
                            }
                        }

                        // Translation display (if needed)
                        if voiceManager.currentLanguage == .romanian && !translatedText.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Translation:")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Text(translatedText)
                                    .font(.body)
                                    .padding(12)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(AppTheme.infoBlue.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                            }
                        }

                        // Parsed results preview
                        if let command = commandParser.lastParsedCommand, !command.items.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Preview:")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)

                                ForEach(Array(command.items.enumerated()), id: \.offset) { _, item in
                                    HStack(alignment: .top, spacing: 8) {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(item.description)
                                                .font(.subheadline.weight(.semibold))
                                            Text("\(formatQty(item.quantity)) × €\(formatPrice(item.unitPrice))")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Text("€\(formatPrice(item.amount))")
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(AppTheme.revenueGreen)
                                    }
                                    .padding(10)
                                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
                                }
                            }
                        }

                        // Error message
                        if let error = voiceManager.error ?? translationService.error ?? commandParser.error {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .foregroundStyle(.orange)
                                Text(error)
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                        }

                        Spacer()
                    }
                    .padding()
                }
                .background(Color(.systemGroupedBackground))

                // Action buttons
                VStack(spacing: 12) {
                    Button {
                        if voiceManager.isListening {
                            voiceManager.stopListening()
                        } else {
                            Task { await voiceManager.startListening() }
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: voiceManager.isListening ? "stop.circle.fill" : "mic.circle.fill")
                                .font(.title3)
                            Text(voiceManager.isListening ? "Stop recording" : "Start recording")
                                .font(.subheadline.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(12)
                        .foregroundStyle(.white)
                        .background(voiceManager.isListening ? Color.red : AppTheme.infoBlue, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)

                    if !voiceManager.recognizedText.isEmpty && !commandParser.lastParsedCommand!.items.isEmpty {
                        Button {
                            addItemsAndClose()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.circle.fill")
                                Text("Add items to invoice")
                                    .font(.subheadline.weight(.semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(12)
                            .foregroundStyle(.white)
                            .background(AppTheme.revenueGreen, in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                    }

                    Button("Cancel") {
                        voiceManager.stopListening()
                        isPresented = false
                    }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
                }
                .padding()
                .background(Color(.systemGroupedBackground))
            }
            .onChange(of: voiceManager.recognizedText) { _, newText in
                Task {
                    if voiceManager.currentLanguage == .romanian {
                        translatedText = await translationService.translateRomanianToEnglish(newText)
                        _ = commandParser.parseCommand(translatedText)
                    } else {
                        _ = commandParser.parseCommand(newText)
                    }
                }
            }
        }
    }

    private func addItemsAndClose() {
        guard let command = commandParser.lastParsedCommand else { return }

        switch command.action {
        case .addItems:
            onItemsAdded(command.items)
        case .setNotes:
            if let notes = command.notes {
                onNoteAdded(notes)
            }
        case .setTaxRate:
            if let taxRate = command.taxRate {
                onTaxRateChanged(taxRate)
            }
        case .unknown:
            break
        }

        voiceManager.stopListening()
        isPresented = false
    }

    private func formatQty(_ v: Double) -> String {
        v == floor(v) ? String(format: "%.0f", v) : String(format: "%.2f", v)
    }

    private func formatPrice(_ v: Double) -> String {
        String(format: "%.2f", v)
    }
}

#Preview {
    @State var isPresented = true
    return VoiceInputView(
        isPresented: $isPresented,
        onItemsAdded: { _ in },
        onNoteAdded: { _ in },
        onTaxRateChanged: { _ in }
    )
}
