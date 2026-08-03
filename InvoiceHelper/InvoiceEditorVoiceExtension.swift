import Foundation

/// Bridges the parsed dictation result into the invoice editor's local form state.
enum VoiceInvoiceIntegration {
    /// Appends dictated items. Reuses the first row if it is still blank so a fresh
    /// editor does not end up with an empty line above the dictated one.
    static func addVoiceItems(_ voiceItems: [VoiceLineItem], to lines: inout [InvoiceEditorView.LineRow]) {
        guard !voiceItems.isEmpty else { return }

        let rows = voiceItems.map { item in
            InvoiceEditorView.LineRow(
                description: item.description,
                quantity: formatNumber(item.quantity),
                unitPrice: formatNumber(item.unitPrice)
            )
        }

        if lines.count == 1, isBlank(lines[0]) {
            lines = rows
        } else {
            lines.append(contentsOf: rows)
        }
    }

    static func addVoiceNote(_ note: String, to notes: inout String) {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        notes = notes.isEmpty ? trimmed : notes + "\n" + trimmed
    }

    /// Snaps to the nearest rate the editor's picker offers, since it is a fixed list.
    static func applyVoiceTaxRate(_ rate: Double, to taxRate: inout Double) {
        guard rate >= 0, rate <= 100 else { return }
        if let exact = InvoiceLogic.taxRates.first(where: { $0 == rate }) {
            taxRate = exact
        } else if let nearest = InvoiceLogic.taxRates.min(by: { abs($0 - rate) < abs($1 - rate) }) {
            taxRate = nearest
        }
    }

    private static func isBlank(_ row: InvoiceEditorView.LineRow) -> Bool {
        row.description.trimmingCharacters(in: .whitespaces).isEmpty
            && row.quantity.trimmingCharacters(in: .whitespaces).isEmpty
            && row.unitPrice.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private static func formatNumber(_ value: Double) -> String {
        value == value.rounded() ? String(format: "%.0f", value) : String(format: "%.2f", value)
    }
}
