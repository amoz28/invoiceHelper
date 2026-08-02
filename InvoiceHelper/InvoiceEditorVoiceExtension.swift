import SwiftUI

/// This extension shows how to integrate voice input into InvoiceEditorView.
/// Copy the @State variable and modify the Section("Line items") to add the voice button.

extension InvoiceEditorView {
    /// Add this @State variable to InvoiceEditorView:
    /// @State private var showVoiceInput = false

    /// Modify the Section("Line items") in InvoiceEditorView to include this:
    func lineItemsSection() -> some View {
        Section("Line items") {
            ForEach(Array(lines.enumerated()), id: \.element.id) { index, _ in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 8) {
                        VStack(alignment: .leading, spacing: 8) {
                            TextField("Description", text: $lines[index].description, axis: .vertical)
                                .lineLimit(2...8)
                                .textInputAutocapitalization(.sentences)
                            Divider()
                            InvoiceLineQtyUnitRow(
                                quantity: $lines[index].quantity,
                                unitPrice: $lines[index].unitPrice
                            )
                        }
                        if lines.count > 1 {
                            Button(role: .destructive) {
                                lines.remove(at: index)
                            } label: {
                                Image(systemName: "trash.circle.fill")
                                    .font(.title3)
                                    .symbolRenderingMode(.hierarchical)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Remove item")
                        }
                    }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    if lines.count > 1 {
                        Button("Remove", role: .destructive) {
                            lines.remove(at: index)
                        }
                    }
                }
            }
            .onDelete { lines.remove(atOffsets: $0) }

            Button("Add Item") {
                lines.append(LineRow())
            }

            Button {
                // showVoiceInput = true
            } label: {
                Label("Add via voice", systemImage: "mic.circle.fill")
            }
            .tint(AppTheme.infoBlue)

            Button {
                // showSavedItemsPicker = true
            } label: {
                Label("Add from saved items", systemImage: "tray.and.arrow.down")
            }
        }
    }
}

/// Integration helper struct for voice commands
struct VoiceInvoiceIntegration {
    /// Handle voice item additions
    static func addVoiceItems(_ voiceItems: [VoiceLineItem], to lines: inout [InvoiceEditorView.LineRow]) {
        for voiceItem in voiceItems {
            lines.append(InvoiceEditorView.LineRow(
                description: voiceItem.description,
                quantity: String(format: "%.2f", voiceItem.quantity),
                unitPrice: String(format: "%.2f", voiceItem.unitPrice)
            ))
        }
    }

    /// Handle voice note additions
    static func addVoiceNote(_ note: String, to currentNotes: inout String) {
        if currentNotes.isEmpty {
            currentNotes = note
        } else {
            currentNotes += "\n\(note)"
        }
    }

    /// Handle voice tax rate changes
    static func applyVoiceTaxRate(_ rate: Double, to taxRate: inout Double) {
        if rate >= 0 && rate <= 100 {
            taxRate = rate
        }
    }
}
