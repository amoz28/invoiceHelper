import SwiftUI

/// Multi-select picker for job templates (separate from invoice `SavedItem` catalog).
struct SavedJobTemplatesPickerView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    var onAdd: ([SavedJobTemplate]) -> Void

    @State private var search = ""
    @State private var selectedIds = Set<String>()

    private var filteredTemplates: [SavedJobTemplate] {
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return store.savedJobTemplates }
        return store.savedJobTemplates.filter { t in
            if t.name.lowercased().contains(q) { return true }
            if let d = t.description?.lowercased(), d.contains(q) { return true }
            return false
        }
    }

    var body: some View {
        Group {
            if store.savedJobTemplates.isEmpty {
                ContentUnavailableView {
                    Label("No job templates", systemImage: "calendar.badge.clock")
                } description: {
                    Text("Add reusable job titles in Settings → Jobs → Saved job templates, then return here.")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Group {
                    if filteredTemplates.isEmpty {
                        ContentUnavailableView.search(text: search)
                    } else {
                        List {
                            ForEach(filteredTemplates) { item in
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
                                            if let d = item.description?.trimmingCharacters(in: .whitespacesAndNewlines), !d.isEmpty {
                                                Text(d)
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                                    .lineLimit(3)
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
        .navigationTitle("Insert job templates")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !store.savedJobTemplates.isEmpty {
                Button {
                    let picked = filteredTemplates.filter { selectedIds.contains($0.id) }
                    guard !picked.isEmpty else { return }
                    Haptics.light()
                    onAdd(picked)
                    dismiss()
                } label: {
                    Text(selectedIds.isEmpty ? "Select templates" : "Add \(selectedIds.count) template\(selectedIds.count == 1 ? "" : "s")")
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
}
