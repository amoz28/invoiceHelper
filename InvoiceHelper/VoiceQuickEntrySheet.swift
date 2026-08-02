import SwiftUI

struct VoiceQuickEntrySheet: View {
    @EnvironmentObject private var store: AppStore
    @Binding var isPresented: Bool
    
    @State private var selectedCustomerId: String?
    @State private var showVoiceInput = false
    @State private var tempLines: [InvoiceEditorView.LineRow] = []
    @State private var tempTaxRate: Double = 20
    @State private var tempNotes = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack {
                if selectedCustomerId == nil {
                    // Step 1: Select Customer
                    List {
                        if store.customers.isEmpty {
                            Text("No customers found. Create a customer first.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(store.customers) { customer in
                                Button {
                                    selectedCustomerId = customer.id
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(customer.name)
                                                .font(.headline)
                                                .foregroundStyle(.primary)
                                            Text(customer.email)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                    .navigationTitle("Select Customer")
                } else {
                    // Step 2: Voice Input
                    VoiceInputView(
                        isPresented: $showVoiceInput,
                        onItemsAdded: { voiceItems in
                            VoiceInvoiceIntegration.addVoiceItems(voiceItems, to: &tempLines)
                            createInvoice()
                        },
                        onNoteAdded: { note in
                            VoiceInvoiceIntegration.addVoiceNote(note, to: &tempNotes)
                        },
                        onTaxRateChanged: { rate in
                            VoiceInvoiceIntegration.applyVoiceTaxRate(rate, to: &tempTaxRate)
                        }
                    )
                    .onAppear {
                        showVoiceInput = true
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
            }
            .alert("Error", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func createInvoice() {
        guard let customerId = selectedCustomerId, !tempLines.isEmpty else { return }
        
        let items = tempLines.compactMap { row -> InvoiceItem? in
            let desc = row.description.trimmingCharacters(in: .whitespaces)
            guard !desc.isEmpty,
                  let q = Double(row.quantity.replacingOccurrences(of: ",", with: ".")),
                  let p = Double(row.unitPrice.replacingOccurrences(of: ",", with: ".")),
                  q > 0 else { return nil }
            return InvoiceItem(description: desc, quantity: q, unitPrice: p)
        }
        
        guard !items.isEmpty else {
            errorMessage = "No valid items to add"
            return
        }
        
        Task {
            do {
                let dueDate = Calendar.current.date(byAdding: .day, value: store.defaultInvoiceDueDaysFromInvoiceDate, to: Date()) ?? Date()
                _ = try await store.addInvoice(
                    customerId: customerId,
                    items: items,
                    taxRate: tempTaxRate,
                    date: ISO8601DateFormatter().string(from: Date()),
                    dueDate: ISO8601DateFormatter().string(from: dueDate),
                    notes: tempNotes.isEmpty ? nil : tempNotes,
                    terms: nil
                )
                await MainActor.run {
                    isPresented = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}
