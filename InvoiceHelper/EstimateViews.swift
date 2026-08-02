import SwiftUI

struct EstimateListView: View {
    @EnvironmentObject private var store: AppStore
    @State private var previewEstimateId: String?
    @State private var showEstimatePreview = false

    var body: some View {
        List {
            if !store.estimates.isEmpty {
                Picker("Status", selection: Binding(
                    get: { store.estimateStatusFilter },
                    set: { store.estimateStatusFilter = $0 }
                )) {
                    Text("All").tag(Optional<EstimateStatus>.none)
                    ForEach(EstimateStatus.allCases, id: \.self) { s in
                        Text(s.rawValue.replacingOccurrences(of: "_", with: " ").capitalized).tag(Optional(s))
                    }
                }
            }
            ForEach(store.filteredEstimates) { est in
                NavigationLink(destination: EstimateDetailView(estimateId: est.id)) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(est.estimateNumber).font(.headline)
                            Spacer()
                            Text(InvoiceLogic.formatCurrency(amount: est.total, code: store.companyProfile?.currency ?? "GBP"))
                                .font(.subheadline)
                        }
                        Text(customerName(est.customerId)).font(.subheadline).foregroundStyle(.secondary)
                        Text(est.status.rawValue.replacingOccurrences(of: "_", with: " "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .searchable(text: $store.estimateSearch, prompt: "Search estimates")
        .navigationTitle("Estimates")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                NavigationLink("New") {
                    EstimateEditorView(estimate: nil, onEstimateCreated: { id in
                        previewEstimateId = id
                        showEstimatePreview = true
                    })
                }
            }
        }
        .refreshable { store.reloadEstimates() }
        .sheet(isPresented: $showEstimatePreview) {
            if let id = previewEstimateId {
                NavigationStack {
                    EstimateDetailView(estimateId: id)
                        .environmentObject(store)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") {
                                    showEstimatePreview = false
                                    previewEstimateId = nil
                                }
                            }
                        }
                }
            }
        }
    }

    private func customerName(_ id: String) -> String {
        store.customers.first { $0.id == id }?.name ?? "Unknown"
    }
}

struct EstimateDetailView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let estimateId: String
    @State private var errorMessage: String?
    @State private var showCreatedInvoice = false
    @State private var createdInvoiceId: String?
    @State private var showDeleteConfirm = false

    private var estimate: Estimate? { store.estimates.first { $0.id == estimateId } }

    var body: some View {
        Group {
            if let est = estimate {
                List {
                    if let profile = store.companyProfile {
                        Section {
                            HStack(alignment: .center, spacing: 14) {
                                CompanyLogoImageView(logo: profile.logo, size: 52, clipCircle: false, scaleToFit: true)
                                    .background(Color(.secondarySystemFill))
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(profile.name).font(.headline)
                                    Text(profile.email).font(.subheadline).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    Section {
                        if est.status == .expired {
                            LabeledContent("Status", value: "Expired")
                        } else {
                            Picker("Status", selection: Binding(
                                get: { store.estimates.first(where: { $0.id == estimateId })?.status ?? .pending },
                                set: { newStatus in
                                    do {
                                        try store.updateEstimate(id: estimateId) { $0.status = newStatus }
                                    } catch {
                                        errorMessage = error.localizedDescription
                                    }
                                }
                            )) {
                                ForEach(EstimateStatus.allCases.filter { $0 != .expired }, id: \.self) { s in
                                    Text(s.rawValue.replacingOccurrences(of: "_", with: " ").capitalized).tag(s)
                                }
                            }
                        }
                        LabeledContent("Customer", value: customerName(est.customerId))
                        LabeledContent("Valid until", value: shortDate(est.validUntil))
                    }
                    Section("Line items") {
                        ForEach(est.items) { item in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.description).font(.headline)
                                Text("\(formatQty(item.quantity)) × \(formatMoney(item.unitPrice))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(formatMoney(item.amount)).font(.subheadline)
                            }
                        }
                    }
                    Section("Totals") {
                        LabeledContent("Subtotal", value: formatMoney(est.subtotal))
                        LabeledContent("Tax (\(formatQty(est.taxRate))%)", value: formatMoney(est.tax))
                        LabeledContent("Total", value: formatMoney(est.total))
                    }
                    if let n = est.notes, !n.isEmpty { Section("Notes") { Text(n) } }
                    if est.status == .pending || est.status == .accepted {
                        Section {
                            Button("Create invoice from estimate") {
                                Task {
                                    do {
                                        let inv = try await store.createInvoiceFromEstimate(estimateId: estimateId)
                                        createdInvoiceId = inv.id
                                        showCreatedInvoice = true
                                    } catch {
                                        errorMessage = error.localizedDescription
                                    }
                                }
                            }
                        }
                    }
                    Section {
                        NavigationLink("Edit estimate") {
                            EstimateEditorView(estimate: est)
                        }
                        .disabled(est.status == .expired)
                    }
                    Section {
                        Button("Delete", role: .destructive) {
                            showDeleteConfirm = true
                        }
                    }
                }
                .navigationTitle(est.estimateNumber)
                .navigationBarTitleDisplayMode(.inline)
            } else {
                ContentUnavailableView("Estimate not found", systemImage: "doc.text")
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
        .alert("Delete estimate?", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                guard let est = estimate else { return }
                do {
                    try store.deleteEstimate(id: est.id)
                    dismiss()
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        } message: {
            Text("This estimate will be permanently removed.")
        }
        .sheet(isPresented: $showCreatedInvoice, onDismiss: { createdInvoiceId = nil }) {
            if let id = createdInvoiceId {
                NavigationStack {
                    InvoiceDetailView(invoiceId: id)
                        .environmentObject(store)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { showCreatedInvoice = false }
                            }
                        }
                }
            }
        }
    }

    private func customerName(_ id: String) -> String {
        store.customers.first { $0.id == id }?.name ?? "Unknown"
    }

    private func formatMoney(_ v: Double) -> String {
        InvoiceLogic.formatCurrency(amount: v, code: store.companyProfile?.currency ?? "GBP")
    }

    private func formatQty(_ v: Double) -> String {
        v == floor(v) ? String(format: "%.0f", v) : String(format: "%.2f", v)
    }

    private func shortDate(_ iso: String) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var d = f.date(from: iso)
        if d == nil {
            f.formatOptions = [.withFullDate, .withDashSeparatorInDate]
            d = f.date(from: String(iso.prefix(10)))
        }
        guard let d else { return iso }
        let out = DateFormatter()
        out.dateStyle = .medium
        return out.string(from: d)
    }
}

struct EstimateEditorView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    var estimate: Estimate?
    var onEstimateCreated: ((String) -> Void)? = nil

    @State private var customerId = ""
    @State private var taxRate: Double = 20
    @State private var validUntil = Date()
    @State private var notes = ""
    @State private var lines: [LineRow] = [LineRow()]
    @State private var errorMessage: String?
    @State private var addCustomerSheet: AddCustomerSheetToken?
    @State private var showSavedItemsPicker = false

    struct LineRow: Identifiable {
        let id: UUID
        var description: String
        var quantity: String
        var unitPrice: String

        init(id: UUID = UUID(), description: String = "", quantity: String = "", unitPrice: String = "") {
            self.id = id
            self.description = description
            self.quantity = quantity
            self.unitPrice = unitPrice
        }
    }

    private var selectedCustomer: Customer? {
        store.customers.first { $0.id == customerId }
    }

    var body: some View {
        Form {
            CollapsibleCustomerSection(customerId: $customerId, onRequestAddCustomer: {
                DispatchQueue.main.async {
                    addCustomerSheet = AddCustomerSheetToken()
                }
            })
            Section("Validity & tax") {
                DatePicker("Valid until", selection: $validUntil, displayedComponents: .date)
                Picker("Tax rate %", selection: $taxRate) {
                    ForEach(InvoiceLogic.taxRates, id: \.self) { r in
                        Text("\(formatQty(r))%").tag(r)
                    }
                }
            }
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
                Button("Add Item") { lines.append(LineRow()) }
                Button {
                    showSavedItemsPicker = true
                } label: {
                    Label("Add from saved items", systemImage: "tray.and.arrow.down")
                }
            }
            Section {
                TextField("Notes (optional)", text: $notes, axis: .vertical)
                    .lineLimit(2...8)
                    .textInputAutocapitalization(.sentences)
            }
            if let errorMessage { Section { Text(errorMessage).foregroundStyle(.red) } }
            if let hint = estimateSaveBlockedHint {
                Section {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.body)
                        Text(hint)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            Section {
                Button(estimate == nil ? "Create estimate" : "Save changes") { save() }
                    .buttonStyle(PrimaryFormButtonStyle())
                    .disabled(customerId.isEmpty || !linesValid)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                CustomerToolbarTitle(
                    customer: selectedCustomer,
                    createLabel: "New estimate",
                    editLabel: "Edit estimate",
                    isCreate: estimate == nil
                )
            }
        }
        .sheet(item: $addCustomerSheet, onDismiss: {
            addCustomerSheet = nil
        }) { _ in
            AddCustomerEditorSheet(customerId: $customerId, onCancel: { addCustomerSheet = nil })
                .environmentObject(store)
        }
        .sheet(isPresented: $showSavedItemsPicker) {
            NavigationStack {
                SavedItemsPickerView { items in
                    appendFromSavedItems(items)
                }
                .environmentObject(store)
            }
        }
        .onAppear {
            if let e = estimate {
                customerId = e.customerId
                taxRate = e.taxRate
                validUntil = parseDate(e.validUntil) ?? Date()
                notes = e.notes ?? ""
                lines = e.items.map { item in
                    LineRow(
                        description: item.description,
                        quantity: formatQty(item.quantity),
                        unitPrice: String(item.unitPrice)
                    )
                }
                if lines.isEmpty { lines = [LineRow()] }
            } else {
                let offset = store.defaultEstimateValidDaysFromCreation
                validUntil = Calendar.current.date(byAdding: .day, value: offset, to: Date()) ?? Date()
            }
        }
    }

    private var linesValid: Bool {
        lines.contains { row in
            let desc = row.description.trimmingCharacters(in: .whitespaces)
            let q = Double(row.quantity.replacingOccurrences(of: ",", with: ".")) ?? 0
            let p = Double(row.unitPrice.replacingOccurrences(of: ",", with: ".")) ?? 0
            return !desc.isEmpty && q > 0 && p > 0
        }
    }

    private var estimateSaveBlockedHint: String? {
        if customerId.isEmpty {
            return "Select a customer before creating the estimate."
        }
        if !linesValid {
            return "Add at least one line item with a description, quantity greater than 0, and unit price greater than 0."
        }
        return nil
    }

    private func formatQty(_ v: Double) -> String {
        v == floor(v) ? String(format: "%.0f", v) : String(format: "%.2f", v)
    }

    private func appendFromSavedItems(_ saved: [SavedItem]) {
        for s in saved {
            let ei = EstimateItem(from: s)
            lines.append(
                LineRow(
                    description: ei.description,
                    quantity: formatQty(ei.quantity),
                    unitPrice: String(ei.unitPrice)
                )
            )
        }
    }

    private func parseDate(_ iso: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: iso) { return d }
        f.formatOptions = [.withFullDate, .withDashSeparatorInDate]
        return f.date(from: String(iso.prefix(10)))
    }

    private func iso(_ d: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: d)
    }

    private func buildItems() -> [EstimateItem]? {
        var items: [EstimateItem] = []
        for row in lines {
            let desc = row.description.trimmingCharacters(in: .whitespaces)
            guard !desc.isEmpty else { continue }
            guard let q = Double(row.quantity.replacingOccurrences(of: ",", with: ".")),
                  let p = Double(row.unitPrice.replacingOccurrences(of: ",", with: ".")),
                  q > 0 else { return nil }
            items.append(EstimateItem(description: desc, quantity: q, unitPrice: p, amount: q * p))
        }
        return items.isEmpty ? nil : items
    }

    private func save() {
        errorMessage = nil
        guard let items = buildItems() else {
            errorMessage = "Each line needs a description, quantity above 0, and unit price above 0. Remove empty lines or complete them."
            return
        }
        do {
            if estimate == nil {
                let e = try store.addEstimate(customerId: customerId, items: items, taxRate: taxRate, validUntilISO: iso(validUntil), notes: notes.isEmpty ? nil : notes)
                onEstimateCreated?(e.id)
            } else if let id = estimate?.id {
                try store.updateEstimate(id: id) { e in
                    e.customerId = customerId
                    e.items = items
                    e.taxRate = taxRate
                    e.validUntil = iso(validUntil)
                    e.notes = notes.isEmpty ? nil : notes
                }
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
