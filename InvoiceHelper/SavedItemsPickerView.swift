import SwiftUI

/// Multi-select catalog picker for inserting saved line items into invoice/estimate editors.
struct SavedItemsPickerView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    var onAdd: ([SavedItem]) -> Void

    @State private var search = ""
    @State private var selectedIds = Set<String>()

    private var currencyCode: String { store.companyProfile?.currency ?? "GBP" }

    private var filteredItems: [SavedItem] {
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return store.savedItems }
        return store.savedItems.filter { item in
            if item.name.lowercased().contains(q) { return true }
            if let d = item.description?.lowercased(), d.contains(q) { return true }
            return false
        }
    }

    var body: some View {
        Group {
            if store.savedItems.isEmpty {
                ContentUnavailableView {
                    Label("No saved line items", systemImage: "list.bullet.rectangle")
                } description: {
                    Text("Add reusable products or services in Settings → Sales → Saved line items, then return here.")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Group {
                    if filteredItems.isEmpty {
                        ContentUnavailableView.search(text: search)
                    } else {
                        List {
                            ForEach(filteredItems) { item in
                                Button {
                                    toggle(item.id)
                                } label: {
                                    HStack(alignment: .top, spacing: 12) {
                                        Image(systemName: selectedIds.contains(item.id) ? "checkmark.circle.fill" : "circle")
                                            .font(.title3)
                                            .foregroundStyle(selectedIds.contains(item.id) ? AppTheme.infoBlue : .secondary)
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(item.name)
                                                .font(.body.weight(.medium))
                                                .foregroundStyle(.primary)
                                            HStack(spacing: 6) {
                                                Text(InvoiceLogic.formatCurrency(amount: item.defaultUnitPrice, code: currencyCode))
                                                Text("·")
                                                    .foregroundStyle(.tertiary)
                                                Text("Qty \(formatQty(item.defaultQuantity))")
                                            }
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            if let d = item.description?.trimmingCharacters(in: .whitespacesAndNewlines), !d.isEmpty {
                                                Text(d)
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                                    .lineLimit(2)
                                            }
                                        }
                                        Spacer(minLength: 0)
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .searchable(text: $search, prompt: "Search")
            }
        }
        .navigationTitle("Insert saved items")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !store.savedItems.isEmpty {
                Button {
                    let picked = filteredItems.filter { selectedIds.contains($0.id) }
                    guard !picked.isEmpty else { return }
                    Haptics.light()
                    onAdd(picked)
                    dismiss()
                } label: {
                    Text(selectedIds.isEmpty ? "Select items" : "Add \(selectedIds.count) item\(selectedIds.count == 1 ? "" : "s")")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.infoBlue)
                .disabled(selectedIds.isEmpty)
                .padding()
                .background(.bar)
            }
        }
    }

    private func toggle(_ id: String) {
        if selectedIds.contains(id) {
            selectedIds.remove(id)
        } else {
            selectedIds.insert(id)
        }
    }

    private func formatQty(_ q: Double) -> String {
        q == floor(q) ? String(format: "%.0f", q) : String(format: "%.2f", q)
    }
}
