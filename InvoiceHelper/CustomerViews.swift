import SwiftUI

// MARK: - Display names (display name bold in headers; legal name as small sub when present)

enum CustomerHeader {
    static func primary(_ c: Customer) -> String {
        let d = c.displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !d.isEmpty { return d }
        return c.name
    }

    /// Legal / full name under the display name; only when display name is set.
    static func secondary(_ c: Customer) -> String? {
        let d = c.displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !d.isEmpty { return c.name }
        return nil
    }
}

/// Toolbar title for invoice / estimate / job editors when a customer is chosen.
struct CustomerToolbarTitle: View {
    var customer: Customer?
    var createLabel: String
    var editLabel: String
    var isCreate: Bool

    var body: some View {
        Group {
            if let c = customer {
                VStack(spacing: 2) {
                    Text(CustomerHeader.primary(c))
                        .font(.headline)
                        .lineLimit(1)
                    if let sub = CustomerHeader.secondary(c) {
                        Text(sub)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            } else {
                Text(isCreate ? createLabel : editLabel)
                    .font(.headline)
            }
        }
    }
}

struct CollapsibleCustomerSection: View {
    @EnvironmentObject private var store: AppStore
    @Binding var customerId: String
    /// Present add-customer from the parent editor (sheet must not be attached inside the form row).
    var onRequestAddCustomer: () -> Void
    @State private var isExpanded = true

    private var selected: Customer? {
        store.customers.first { $0.id == customerId }
    }

    var body: some View {
        Section {
            DisclosureGroup(isExpanded: $isExpanded) {
                SearchableCustomerPicker(customerId: $customerId, onRequestAddCustomer: onRequestAddCustomer)
            } label: {
                HStack {
                    Text("Customer")
                    Spacer()
                    if let c = selected {
                        Text(CustomerHeader.primary(c))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
        .onAppear {
            isExpanded = customerId.isEmpty
        }
        .onChange(of: customerId) { _, new in
            if !new.isEmpty { isExpanded = false }
        }
    }
}

struct CustomerListView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.colorScheme) private var colorScheme
    @State private var previewCustomerId: String?
    @State private var showCustomerPreview = false

    private var rowForeground: Color {
        colorScheme == .light ? .black : Color.primary
    }

    private var secondaryForeground: Color {
        colorScheme == .light ? Color.black.opacity(0.55) : Color.secondary
    }

    var body: some View {
        List {
            ForEach(store.filteredCustomers) { c in
                NavigationLink(destination: CustomerDetailView(customer: c)) {
                    customerRow(c)
                }
            }
        }
        .searchable(text: $store.customerSearch, prompt: "Search customers")
        .navigationTitle("Customers")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await store.reloadInvoices() }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                NavigationLink("Add") {
                    CustomerEditorView(customer: nil, onCustomerCreated: { id in
                        previewCustomerId = id
                        showCustomerPreview = true
                    })
                }
            }
        }
        .sheet(isPresented: $showCustomerPreview) {
            if let id = previewCustomerId {
                NavigationStack {
                    CustomerDetailByIdView(customerId: id)
                        .environmentObject(store)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") {
                                    showCustomerPreview = false
                                    previewCustomerId = nil
                                }
                            }
                        }
                }
            }
        }
    }

    @ViewBuilder
    private func customerRow(_ c: Customer) -> some View {
        let count = store.invoices(forCustomerId: c.id).count
        let total = store.totalInvoiced(forCustomerId: c.id)
        let code = store.companyProfile?.currency ?? "GBP"
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(CustomerHeader.primary(c))
                    .font(.headline)
                    .foregroundStyle(rowForeground)
                if let sub = CustomerHeader.secondary(c) {
                    Text(sub)
                        .font(.caption2)
                        .foregroundStyle(secondaryForeground)
                }
                Text(c.email)
                    .font(.subheadline)
                    .foregroundStyle(secondaryForeground)
                if let p = c.phone, !p.isEmpty {
                    Text(p)
                        .font(.caption)
                        .foregroundStyle(secondaryForeground)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 6) {
                Text("\(count) \(count == 1 ? "Invoice" : "Invoices")")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(rowForeground)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color(.secondarySystemFill))
                    .clipShape(Capsule())
                Text(InvoiceLogic.formatCurrency(amount: total, code: code))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(rowForeground)
                    .multilineTextAlignment(.trailing)
            }
        }
        .padding(.vertical, 2)
    }
}

struct CustomerDetailByIdView: View {
    @EnvironmentObject private var store: AppStore
    let customerId: String

    private var customer: Customer? { store.customers.first { $0.id == customerId } }

    var body: some View {
        Group {
            if let c = customer {
                CustomerDetailView(customer: c)
            } else {
                ContentUnavailableView("Customer not found", systemImage: "person")
            }
        }
    }
}

struct CustomerDetailView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(AppPreferences.Keys.showJobsTab) private var showJobsTab = true
    let customer: Customer

    private var listRowForeground: Color {
        colorScheme == .light ? .black : Color.primary
    }

    /// With jobs: 0 = Invoices, 1 = Jobs, 2 = Details. Without jobs: 0 = Invoices, 1 = Details.
    @State private var tab = 0
    @State private var expandedInvoiceId: String?
    @State private var paymentSheetInvoiceId: String?
    @State private var pdfShareItem: SharePDFURL?
    @State private var invoiceListErrorMessage: String?

    private var jobsForCustomer: [ScheduledJob] {
        let id = customer.id
        let nameLower = customer.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return store.jobs.filter { job in
            if let cid = job.customerId, cid == id { return true }
            return job.customerName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == nameLower
        }
        .sorted { $0.startDate > $1.startDate }
    }

    private var invoicesForCustomer: [Invoice] {
        store.invoices(forCustomerId: customer.id).sorted { $0.createdAt > $1.createdAt }
    }

    private var detailsTabTag: Int { showJobsTab ? 2 : 1 }

    var body: some View {
        List {
            Section {
                Picker("View", selection: $tab) {
                    Text("Invoices").tag(0)
                    if showJobsTab {
                        Text("Jobs").tag(1)
                    }
                    Text("Details").tag(detailsTabTag)
                }
                .pickerStyle(.segmented)
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            .listRowBackground(Color.clear)

            if tab == 0 {
                Section {
                    NavigationLink {
                        InvoiceEditorView(mode: .create, invoiceId: nil, initialCustomerId: customer.id)
                    } label: {
                        Label("Create invoice", systemImage: "doc.badge.plus")
                    }
                }
                if invoicesForCustomer.isEmpty {
                    Section {
                        ContentUnavailableView(
                            "No invoices yet",
                            systemImage: "doc.text",
                            description: Text("Invoices for this customer will appear here.")
                        )
                    }
                } else {
                    Section {
                        ForEach(invoicesForCustomer) { inv in
                            InvoiceListRowWithLongPressActions(
                                invoice: inv,
                                customerLine: InvoiceLogic.formatDisplayDate(iso: inv.date),
                                totalFormatted: InvoiceLogic.formatCurrency(amount: inv.total, code: store.companyProfile?.currency ?? "GBP"),
                                foreground: listRowForeground,
                                /// Use destination-based links here only. A `navigationDestination(for:)` on this screen
                                /// with `NavigationLink(value:)` is known to mis-order the stack (same screen on push, invoice after back).
                                useValueNavigation: false,
                                expandedInvoiceId: $expandedInvoiceId,
                                paymentSheetInvoiceId: $paymentSheetInvoiceId,
                                pdfShareItem: $pdfShareItem,
                                listErrorMessage: $invoiceListErrorMessage
                            )
                        }
                    }
                }
            } else if showJobsTab && tab == 1 {
                if jobsForCustomer.isEmpty {
                    Section {
                        ContentUnavailableView(
                            "No jobs yet",
                            systemImage: "calendar",
                            description: Text("Jobs linked to this customer will appear here.")
                        )
                    }
                } else {
                    Section {
                        ForEach(jobsForCustomer) { job in
                            NavigationLink(destination: JobDetailView(jobId: job.id)) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(job.title).font(.headline)
                                    Text(job.customerName).font(.subheadline).foregroundStyle(.secondary)
                                    Text(shortJobDate(job.startDate))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            } else if tab == detailsTabTag {
                Section("Contact") {
                    if let sub = CustomerHeader.secondary(customer) {
                        LabeledContent("Legal name", value: sub)
                    }
                    if let mailURL = URL(string: "mailto:\(customer.email)") {
                        Link(destination: mailURL) {
                            LabeledContent("Email", value: customer.email)
                                .foregroundStyle(AppTheme.infoBlue)
                        }
                    }
                    if let p = customer.phone, !p.isEmpty, let telURL = phoneCallURL(phone: p) {
                        Link(destination: telURL) {
                            LabeledContent("Phone", value: p)
                                .foregroundStyle(AppTheme.infoBlue)
                        }
                    }
                }
                Section("Billing address") {
                    if let url = mapsURL(address: customer.billingAddress) {
                        Link(destination: url) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(customer.billingAddress.street)
                                Text("\(customer.billingAddress.city), \(customer.billingAddress.state) \(customer.billingAddress.postalCode)")
                                Text(customer.billingAddress.country)
                            }
                            .foregroundStyle(AppTheme.infoBlue)
                        }
                    } else {
                        Text(customer.billingAddress.street)
                        Text("\(customer.billingAddress.city), \(customer.billingAddress.state) \(customer.billingAddress.postalCode)")
                        Text(customer.billingAddress.country)
                    }
                }
                if let n = customer.notes, !n.isEmpty {
                    Section("Notes") { Text(n) }
                }
            }
        }
        .onChange(of: showJobsTab) { _, show in
            if show {
                if tab == 1 { tab = 2 }
            } else {
                if tab == 1 { tab = 0 }
                else if tab == 2 { tab = 1 }
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Group {
                    if let mapURL = mapsURL(address: customer.billingAddress) {
                        Link(destination: mapURL) {
                            VStack(spacing: 2) {
                                Text(CustomerHeader.primary(customer))
                                    .font(.headline)
                                    .lineLimit(1)
                                if let sub = CustomerHeader.secondary(customer) {
                                    Text(sub)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            .foregroundStyle(.primary)
                        }
                        .accessibilityHint("Opens address in Maps")
                    } else {
                        VStack(spacing: 2) {
                            Text(CustomerHeader.primary(customer))
                                .font(.headline)
                                .lineLimit(1)
                            if let sub = CustomerHeader.secondary(customer) {
                                Text(sub)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }
            ToolbarItem(placement: .primaryAction) {
                NavigationLink("Edit") {
                    CustomerEditorView(customer: customer)
                }
            }
        }
        .alert("Error", isPresented: Binding(
            get: { invoiceListErrorMessage != nil },
            set: { if !$0 { invoiceListErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { invoiceListErrorMessage = nil }
        } message: {
            Text(invoiceListErrorMessage ?? "")
        }
        .sheet(isPresented: Binding(
            get: { paymentSheetInvoiceId != nil },
            set: { if !$0 { paymentSheetInvoiceId = nil } }
        )) {
            if let id = paymentSheetInvoiceId, let inv = store.invoices.first(where: { $0.id == id }) {
                PaymentSheet(invoiceId: inv.id, maxRemaining: inv.total - InvoiceLogic.totalPaid(for: inv))
                    .environmentObject(store)
            }
        }
        .sheet(item: $pdfShareItem) { item in
            PDFActivityView(activityItems: [item.url]) { completed in
                if completed, let pid = item.invoiceIdForMarkSent,
                   let inv = store.invoices.first(where: { $0.id == pid }), inv.status == .draft {
                    Task {
                        try? await store.updateInvoice(id: inv.id) { $0.status = .sent }
                    }
                }
            }
        }
    }

    private func mapsURL(address: Address) -> URL? {
        let s = "\(address.street), \(address.city), \(address.state) \(address.postalCode), \(address.country)"
        let q = s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return URL(string: "http://maps.apple.com/?q=\(q)")
    }

    private func phoneCallURL(phone: String) -> URL? {
        let trimmed = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(string: "tel:\(trimmed)")
    }

    private func shortJobDate(_ iso: String) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var d = f.date(from: iso)
        if d == nil {
            f.formatOptions = [.withInternetDateTime]
            d = f.date(from: iso)
        }
        if d == nil {
            f.formatOptions = [.withFullDate, .withDashSeparatorInDate]
            d = f.date(from: String(iso.prefix(10)))
        }
        guard let d else { return iso }
        let out = DateFormatter()
        out.dateStyle = .medium
        out.timeStyle = .short
        return out.string(from: d)
    }
}

/// Token for `sheet(item:)` when adding a customer from invoice / estimate / job editors.
struct AddCustomerSheetToken: Identifiable {
    let id = UUID()
}

/// Sheet content for creating a customer without nesting `.sheet` inside `Form` rows.
struct AddCustomerEditorSheet: View {
    @EnvironmentObject private var store: AppStore
    @Binding var customerId: String
    var onCancel: () -> Void

    var body: some View {
        NavigationStack {
            CustomerEditorView(customer: nil, onCustomerCreated: { id in
                customerId = id
            })
            .environmentObject(store)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
            }
        }
    }
}

/// Searchable customer list for invoice/estimate editors (replaces plain `Picker`).
struct SearchableCustomerPicker: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.colorScheme) private var colorScheme
    @Binding var customerId: String
    @State private var search = ""
    /// Parent editor owns `sheet(item:)` — nested sheets inside `Form` / `DisclosureGroup` dismiss incorrectly on first presentation.
    var onRequestAddCustomer: () -> Void

    private var rowForeground: Color {
        colorScheme == .light ? .black : Color.primary
    }

    private var secondaryForeground: Color {
        colorScheme == .light ? Color.black.opacity(0.55) : Color.secondary
    }

    private var filtered: [Customer] {
        let sorted = store.customers.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty { return sorted }
        return sorted.filter { c in
            c.name.lowercased().contains(q)
                || (c.displayName ?? "").lowercased().contains(q)
                || c.email.lowercased().contains(q)
        }
    }

    var body: some View {
        Group {
            if store.customers.isEmpty {
                HStack(alignment: .center, spacing: 10) {
                    Text("No customers yet. Add one to continue.")
                        .font(.subheadline)
                        .foregroundStyle(rowForeground)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    addCustomerButton
                }
            } else {
                HStack(alignment: .center, spacing: 8) {
                    TextField("Search customers", text: $search)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .foregroundStyle(rowForeground)
                    addCustomerButton
                }
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(filtered) { c in
                            Button {
                                customerId = c.id
                            } label: {
                                HStack(alignment: .center) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(CustomerHeader.primary(c))
                                            .font(.body.weight(.semibold))
                                            .foregroundStyle(rowForeground)
                                        if let sub = CustomerHeader.secondary(c) {
                                            Text(sub)
                                                .font(.caption2)
                                                .foregroundStyle(secondaryForeground)
                                        }
                                        Text(c.email)
                                            .font(.caption)
                                            .foregroundStyle(secondaryForeground)
                                    }
                                    Spacer(minLength: 0)
                                    if customerId == c.id {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(AppTheme.infoBlue)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            Divider()
                        }
                    }
                }
                .frame(maxHeight: 280)
            }
        }
    }

    private var addCustomerButton: some View {
        Button {
            DispatchQueue.main.async {
                onRequestAddCustomer()
            }
        } label: {
            Image(systemName: "person.badge.plus")
                .font(.body.weight(.semibold))
                .foregroundStyle(AppTheme.infoBlue)
                .frame(minWidth: 36, minHeight: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add customer")
    }
}

struct CustomerEditorView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    /// nil = create
    var customer: Customer?
    var onCustomerCreated: ((String) -> Void)? = nil

    @State private var name = ""
    @State private var displayName = ""
    @State private var email = ""
    @State private var phone = ""
    @State private var street = ""
    @State private var city = ""
    @State private var state = ""
    @State private var postalCode = ""
    @State private var country = ""
    @State private var notes = ""
    @State private var errorMessage: String?
    @State private var confirmSave = false

    var body: some View {
        Form {
            Section("Customer") {
                TextField("Name *", text: $name)
                TextField("Display name (optional)", text: $displayName)
                TextField("Email *", text: $email)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                TextField("Phone (optional)", text: $phone)
                    .keyboardType(.phonePad)
            }
            Section("Billing address") {
                TextField("Street *", text: $street)
                TextField("City *", text: $city)
                TextField("State *", text: $state)
                TextField("Postal code *", text: $postalCode)
                TextField("Country *", text: $country)
            }
            Section("Notes") {
                TextField("Notes", text: $notes, axis: .vertical)
                    .lineLimit(3...6)
            }
            if let errorMessage { Section { Text(errorMessage).foregroundStyle(.red) } }
            Section {
                Button(customer == nil ? "Create customer" : "Save changes") {
                    if customer == nil {
                        save()
                    } else {
                        confirmSave = true
                    }
                }
                    .buttonStyle(PrimaryFormButtonStyle())
                    .disabled(!isValid)
            }
        }
        .navigationTitle(customer == nil ? "New customer" : "Edit customer")
        .confirmationDialog("Save changes to this customer?", isPresented: $confirmSave, titleVisibility: .visible) {
            Button("Save", role: .none) { save() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Updates apply to new invoices and jobs that use this customer.")
        }
        .onAppear {
            guard let c = customer else { return }
            name = c.name
            displayName = c.displayName ?? ""
            email = c.email
            phone = c.phone ?? ""
            street = c.billingAddress.street
            city = c.billingAddress.city
            state = c.billingAddress.state
            postalCode = c.billingAddress.postalCode
            country = c.billingAddress.country
            notes = c.notes ?? ""
        }
    }

    private var isValid: Bool {
        !name.isEmpty && InvoiceLogic.validateEmail(email)
            && !street.isEmpty && !city.isEmpty && !state.isEmpty && !postalCode.isEmpty && !country.isEmpty
    }

    private func save() {
        errorMessage = nil
        let now = ISO8601DateFormatter().string(from: Date())
        let id = customer?.id ?? InvoiceLogic.generateId()
        let c = Customer(
            id: id,
            name: name,
            displayName: displayName.isEmpty ? nil : displayName,
            email: email,
            phone: phone.isEmpty ? nil : phone,
            billingAddress: Address(street: street, city: city, state: state, postalCode: postalCode, country: country),
            notes: notes.isEmpty ? nil : notes,
            createdAt: customer?.createdAt ?? now,
            updatedAt: now
        )
        do {
            try store.upsertCustomer(c)
            if customer == nil {
                onCustomerCreated?(c.id)
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
