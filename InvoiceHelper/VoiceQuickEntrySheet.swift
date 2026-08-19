import SwiftUI

/// Dashboard quick entry: pick a customer, dictate the work, and land in the editor
/// with the line items already filled in.
struct VoiceQuickEntrySheet: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    /// Called with the new invoice id once it has been saved.
    var onInvoiceCreated: (String) -> Void

    @State private var customerId: String?
    @State private var lines: [InvoiceEditorView.LineRow] = [InvoiceEditorView.LineRow()]
    @State private var taxRate: Double = 20
    @State private var notes = ""
    @State private var showDictation = false
    @State private var errorMessage: String?
    @State private var isSaving = false
    @State private var search = ""

    private var filteredCustomers: [Customer] {
        let trimmed = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return store.customers }
        return store.customers.filter {
            $0.name.localizedCaseInsensitiveContains(trimmed)
                || ($0.displayName ?? "").localizedCaseInsensitiveContains(trimmed)
                || $0.email.localizedCaseInsensitiveContains(trimmed)
        }
    }

    private var validLines: [InvoiceItem] {
        lines.compactMap { row in
            let description = row.description.trimmingCharacters(in: .whitespaces)
            guard !description.isEmpty,
                  let quantity = Double(row.quantity.replacingOccurrences(of: ",", with: ".")),
                  let unitPrice = Double(row.unitPrice.replacingOccurrences(of: ",", with: ".")),
                  quantity > 0, unitPrice > 0
            else { return nil }
            return InvoiceItem(description: description, quantity: quantity, unitPrice: unitPrice)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if customerId == nil {
                    customerPicker
                } else {
                    dictationStage
                }
            }
            .navigationTitle(customerId == nil ? "Who is this for?" : "Voice invoice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                if customerId != nil {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Back") {
                            customerId = nil
                            lines = [InvoiceEditorView.LineRow()]
                            notes = ""
                        }
                    }
                }
            }
            .alert("Error", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            .sheet(isPresented: $showDictation) {
                VoiceInputView(
                    onItemsAdded: { items in
                        VoiceInvoiceIntegration.addVoiceItems(items, to: &lines)
                    },
                    onNoteAdded: { note in
                        VoiceInvoiceIntegration.addVoiceNote(note, to: &notes)
                    },
                    onTaxRateChanged: { rate in
                        VoiceInvoiceIntegration.applyVoiceTaxRate(rate, to: &taxRate)
                    }
                )
            }
        }
    }

    // MARK: - Stage one

    private var customerPicker: some View {
        Group {
            if store.customers.isEmpty {
                ContentUnavailableView(
                    "No customers yet",
                    systemImage: "person.crop.circle.badge.plus",
                    description: Text("Add a customer before creating an invoice by voice.")
                )
            } else {
                List(filteredCustomers) { customer in
                    Button {
                        customerId = customer.id
                        showDictation = true
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(CustomerHeader.primary(customer))
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                if !customer.email.isEmpty {
                                    Text(customer.email)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer(minLength: 8)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .searchable(text: $search, prompt: "Search customers")
            }
        }
    }

    // MARK: - Stage two

    private var dictationStage: some View {
        List {
            if let id = customerId, let customer = store.customers.first(where: { $0.id == id }) {
                Section("Customer") {
                    Text(CustomerHeader.primary(customer))
                        .font(.body.weight(.semibold))
                }
            }

            Section("Line items") {
                if validLines.isEmpty {
                    Text("Nothing captured yet. Tap Dictate and describe the work.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(lines.enumerated()), id: \.element.id) { index, row in
                        if !row.description.trimmingCharacters(in: .whitespaces).isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(row.description)
                                    .font(.subheadline.weight(.medium))
                                Text("\(row.quantity) x \(row.unitPrice)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button("Remove", role: .destructive) {
                                    lines.remove(at: index)
                                    if lines.isEmpty { lines = [InvoiceEditorView.LineRow()] }
                                }
                            }
                        }
                    }
                }

                Button {
                    showDictation = true
                } label: {
                    Label("Dictate", systemImage: "mic.circle.fill")
                }
                .tint(AppTheme.infoBlue)
            }

            Section("Tax") {
                Picker("Tax rate %", selection: $taxRate) {
                    ForEach(InvoiceLogic.taxRates, id: \.self) { rate in
                        Text(rate == rate.rounded() ? String(format: "%.0f%%", rate) : String(format: "%.2f%%", rate))
                            .tag(rate)
                    }
                }
            }

            if !notes.isEmpty {
                Section("Notes") {
                    Text(notes)
                }
            }

            Section {
                Button {
                    Task { await save() }
                } label: {
                    if isSaving {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Create invoice")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(PrimaryFormButtonStyle())
                .disabled(validLines.isEmpty || isSaving)
            } footer: {
                if validLines.isEmpty {
                    Text("Dictate at least one item with a quantity and a price.")
                        .font(.caption)
                }
            }
        }
    }

    private func save() async {
        guard let customerId, !validLines.isEmpty else { return }
        isSaving = true
        defer { isSaving = false }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let today = Date()
        let due = Calendar.current.date(
            byAdding: .day,
            value: store.defaultInvoiceDueDaysFromInvoiceDate,
            to: today
        ) ?? today

        do {
            let invoice = try await store.addInvoice(
                customerId: customerId,
                items: validLines,
                taxRate: taxRate,
                date: formatter.string(from: today),
                dueDate: formatter.string(from: due),
                notes: notes.isEmpty ? nil : notes,
                terms: nil
            )
            onInvoiceCreated(invoice.id)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
