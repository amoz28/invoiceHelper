import SwiftUI

/// Dictation sheet used by the invoice editor and by the dashboard quick entry FAB.
struct VoiceInputView: View {
    @StateObject private var voice = VoiceRecognitionManager()
    @StateObject private var translator = TranslationService()
    @StateObject private var parser = VoiceCommandParser()

    @Environment(\.dismiss) private var dismiss

    /// Called when the user accepts the parsed result. The sheet dismisses itself afterwards.
    var onItemsAdded: ([VoiceLineItem]) -> Void
    var onNoteAdded: (String) -> Void
    var onTaxRateChanged: (Double) -> Void

    @State private var translatedText = ""
    @State private var parseTask: Task<Void, Never>?

    private var textToParse: String {
        voice.currentLanguage == .romanian && !translatedText.isEmpty ? translatedText : voice.recognizedText
    }

    private var parsed: VoiceCommandResult? {
        guard let result = parser.lastParsedCommand, !result.isEmpty else { return nil }
        return result
    }

    private var canApply: Bool {
        guard let parsed else { return false }
        switch parsed.action {
        case .addItems:
            return parsed.items.contains { $0.unitPrice > 0 && $0.quantity > 0 }
        case .setTaxRate:
            return parsed.taxRate != nil
        case .setNotes:
            return !(parsed.notes?.isEmpty ?? true)
        case .unknown:
            return false
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Picker("Language", selection: Binding(
                        get: { voice.currentLanguage },
                        set: { voice.setLanguage($0) }
                    )) {
                        ForEach(VoiceRecognitionManager.SupportedLanguage.allCases) { language in
                            Text(language.displayName).tag(language)
                        }
                    }
                    .pickerStyle(.segmented)

                    if voice.isListening {
                        HStack(spacing: 8) {
                            ProgressView().tint(AppTheme.infoBlue)
                            Text("Listening")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(AppTheme.infoBlue)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(12)
                        .background(AppTheme.infoBlue.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }

                    if voice.recognizedText.isEmpty && !voice.isListening {
                        hintCard
                    }

                    if !voice.recognizedText.isEmpty {
                        labelledBlock(title: "You said", text: voice.recognizedText, tint: nil)
                    }

                    if voice.currentLanguage == .romanian && !translatedText.isEmpty {
                        labelledBlock(title: "Translated", text: translatedText, tint: AppTheme.infoBlue)
                    }

                    if translator.isTranslating {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Translating")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let parsed {
                        previewSection(parsed)
                    }

                    if let message = voice.error ?? parser.error {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text(message)
                                .font(.caption)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
                .padding(16)
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 10) {
                    Button {
                        if voice.isListening {
                            voice.stopListening()
                        } else {
                            Task { await voice.startListening() }
                        }
                        Haptics.light()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: voice.isListening ? "stop.circle.fill" : "mic.circle.fill")
                                .font(.title3.weight(.semibold))
                            Text(voice.isListening ? "Stop" : "Start speaking")
                                .font(.subheadline.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .foregroundStyle(.white)
                        .background(voice.isListening ? Color.red : AppTheme.infoBlue,
                                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    Button {
                        apply()
                    } label: {
                        Text("Add to invoice")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .foregroundStyle(.white)
                            .background(canApply ? AppTheme.revenueGreen : Color.gray.opacity(0.4),
                                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canApply)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(.bar)
            }
            .navigationTitle("Speak your invoice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        voice.stopListening()
                        dismiss()
                    }
                }
            }
            .onChange(of: voice.recognizedText) { _, newValue in
                scheduleParse(for: newValue)
            }
            .onDisappear {
                parseTask?.cancel()
                voice.stopListening()
            }
        }
    }

    // MARK: - Pieces

    private var hintCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Try saying")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("Two hours web design at fifty")
            Text("Set tax to twenty percent")
            Text("Note, payment due within thirty days")
        }
        .font(.subheadline)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func labelledBlock(title: String, text: String, tint: Color?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(text)
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background((tint ?? Color(.secondarySystemGroupedBackground)).opacity(tint == nil ? 1 : 0.12),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    @ViewBuilder
    private func previewSection(_ result: VoiceCommandResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Preview")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            switch result.action {
            case .addItems:
                ForEach(result.items) { item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.description)
                                .font(.subheadline.weight(.semibold))
                            Text("\(formatQty(item.quantity)) x \(formatMoney(item.unitPrice))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        Text(formatMoney(item.amount))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(item.unitPrice > 0 ? AppTheme.revenueGreen : .secondary)
                    }
                    .padding(10)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            case .setTaxRate:
                if let rate = result.taxRate {
                    Text("Tax rate \(formatQty(rate))%")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            case .setNotes:
                if let note = result.notes {
                    Text(note)
                        .font(.subheadline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            case .unknown:
                EmptyView()
            }
        }
    }

    // MARK: - Behaviour

    /// Debounced so we do not translate on every partial dictation result.
    private func scheduleParse(for text: String) {
        parseTask?.cancel()
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            translatedText = ""
            parser.lastParsedCommand = nil
            return
        }

        parseTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }

            if voice.currentLanguage == .romanian {
                let english = await translator.translateRomanianToEnglish(text)
                guard !Task.isCancelled else { return }
                translatedText = english
                parser.parseCommand(english)
            } else {
                translatedText = ""
                parser.parseCommand(text)
            }
        }
    }

    private func apply() {
        guard let result = parser.lastParsedCommand else { return }

        switch result.action {
        case .addItems:
            let usable = result.items.filter { $0.quantity > 0 && $0.unitPrice > 0 }
            guard !usable.isEmpty else { return }
            onItemsAdded(usable)
        case .setNotes:
            guard let note = result.notes, !note.isEmpty else { return }
            onNoteAdded(note)
        case .setTaxRate:
            guard let rate = result.taxRate else { return }
            onTaxRateChanged(rate)
        case .unknown:
            return
        }

        voice.stopListening()
        dismiss()
    }

    private func formatQty(_ value: Double) -> String {
        value == value.rounded() ? String(format: "%.0f", value) : String(format: "%.2f", value)
    }

    private func formatMoney(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}
