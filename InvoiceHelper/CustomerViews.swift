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

    static func initials(_ c: Customer) -> String {
        let source = primary(c)
        let parts = source
            .split(whereSeparator: { $0.isWhitespace || $0 == "-" })
            .prefix(2)
        let letters = parts.compactMap { $0.first.map(String.init) }
        if letters.isEmpty {
            return String(source.prefix(1)).uppercased()
        }
        return letters.joined().uppercased()
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

// MARK: - Shared chrome

private struct CustomerAvatarView: View {
    let customer: Customer
    var size: CGFloat = 44

    var body: some View {
        Text(CustomerHeader.initials(customer))
            .font(.system(size: size * 0.36, weight: .semibold, design: .rounded))
            .foregroundStyle(AppTheme.infoBlue)
            .frame(width: size, height: size)
            .background(AppTheme.infoBlue.opacity(0.12), in: Circle())
            .accessibilityHidden(true)
    }
}

private struct CustomerCardBackground: View {
    var body: some View {
        AppSurfaceCard()
    }
}

// MARK: - List

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

    private var customers: [Customer] { store.filteredCustomers }

    var body: some View {
        Group {
            if customers.isEmpty && store.customerSearch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                emptyState
            } else {
                customerList
            }
        }
        .background(Color(.systemGroupedBackground))
        .searchable(text: $store.customerSearch, prompt: "Search customers")
        .navigationTitle("Customers")
        .navigationBarTitleDisplayMode(.large)
        .refreshable { await store.reloadInvoices() }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                NavigationLink {
                    CustomerEditorView(customer: nil, onCustomerCreated: { id in
                        previewCustomerId = id
                        showCustomerPreview = true
                    })
                } label: {
                    Image(systemName: "plus")
                        .font(.body.weight(.semibold))
                }
                .accessibilityLabel("Add customer")
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

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 40)
            Image(systemName: "person.2")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(AppTheme.infoBlue.opacity(0.8))
                .frame(width: 72, height: 72)
                .background(AppTheme.infoBlue.opacity(0.1), in: Circle())
            Text("No customers yet")
                .font(.title3.weight(.semibold))
            Text("Add your first customer to start invoicing.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            NavigationLink {
                CustomerEditorView(customer: nil, onCustomerCreated: { id in
                    previewCustomerId = id
                    showCustomerPreview = true
                })
            } label: {
                Text("Add customer")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: 220)
                    .padding(.vertical, 14)
                    .background(AppTheme.infoBlue, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var customerList: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                if customers.isEmpty {
                    Text("No matches")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                } else {
                    ForEach(customers) { c in
                        NavigationLink(destination: CustomerDetailView(customer: c)) {
                            customerRow(c)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
    }

    private func customerRow(_ c: Customer) -> some View {
        let count = store.invoices(forCustomerId: c.id).count
        let total = store.totalInvoiced(forCustomerId: c.id)
        let code = store.companyProfile?.currency ?? "GBP"

        return HStack(alignment: .center, spacing: 14) {
            CustomerAvatarView(customer: c, size: 48)

            VStack(alignment: .leading, spacing: 3) {
                Text(CustomerHeader.primary(c))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(rowForeground)
                    .lineLimit(1)
                if let sub = CustomerHeader.secondary(c) {
                    Text(sub)
                        .font(.caption)
                        .foregroundStyle(secondaryForeground)
                        .lineLimit(1)
                }
                Text(c.email)
                    .font(.subheadline)
                    .foregroundStyle(secondaryForeground)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 4) {
                Text(InvoiceLogic.formatCurrency(amount: total, code: code))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(rowForeground)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(count == 1 ? "1 invoice" : "\(count) invoices")
                    .font(.caption)
                    .foregroundStyle(secondaryForeground)
            }

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(CustomerCardBackground())
        .contentShape(Rectangle())
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

// MARK: - Detail

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

    private var currencyCode: String { store.companyProfile?.currency ?? "GBP" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                profileHeader
                statsRow
                segmentControl
                tabContent
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .background(Color(.systemGroupedBackground))
        .onChange(of: showJobsTab) { _, show in
            if show {
                if tab == 1 { tab = 2 }
            } else {
                if tab == 1 { tab = 0 }
                else if tab == 2 { tab = 1 }
            }
        }
        .navigationTitle(CustomerHeader.primary(customer))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                NavigationLink {
                    CustomerEditorView(customer: customer)
                } label: {
                    Text("Edit")
                        .fontWeight(.semibold)
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

    private var profileHeader: some View {
        VStack(spacing: 16) {
            CustomerAvatarView(customer: customer, size: 72)

            VStack(spacing: 4) {
                Text(CustomerHeader.primary(customer))
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)
                if let sub = CustomerHeader.secondary(customer) {
                    Text(sub)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 12) {
                if let mailURL = URL(string: "mailto:\(customer.email)") {
                    Link(destination: mailURL) {
                        actionChip(title: "Email", systemImage: "envelope.fill")
                    }
                }
                if let p = customer.phone, !p.isEmpty, let telURL = phoneCallURL(phone: p) {
                    Link(destination: telURL) {
                        actionChip(title: "Call", systemImage: "phone.fill")
                    }
                }
                if let mapURL = mapsURL(address: customer.billingAddress) {
                    Link(destination: mapURL) {
                        actionChip(title: "Map", systemImage: "map.fill")
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private func actionChip(title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(AppTheme.infoBlue)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(AppTheme.infoBlue.opacity(0.12), in: Capsule())
    }

    private var statsRow: some View {
        let invoiceCount = invoicesForCustomer.count
        let total = store.totalInvoiced(forCustomerId: customer.id)
        let jobCount = jobsForCustomer.count

        return HStack(spacing: 10) {
            detailStat(title: "Invoiced", value: InvoiceLogic.formatCurrency(amount: total, code: currencyCode))
            detailStat(title: "Invoices", value: "\(invoiceCount)")
            if showJobsTab {
                detailStat(title: "Jobs", value: "\(jobCount)")
            }
        }
    }

    private func detailStat(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(listRowForeground)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(CustomerCardBackground())
    }

    private var segmentControl: some View {
        AppSegmentedTabs(
            tabs: {
                var items: [(tag: Int, title: String)] = [(0, "Invoices")]
                if showJobsTab {
                    items.append((1, "Jobs"))
                }
                items.append((detailsTabTag, "Details"))
                return items
            }(),
            selection: $tab
        )
    }

    @ViewBuilder
    private var tabContent: some View {
        if tab == 0 {
            invoicesTab
        } else if showJobsTab && tab == 1 {
            jobsTab
        } else if tab == detailsTabTag {
            detailsTab
        }
    }

    private var invoicesTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            NavigationLink {
                InvoiceEditorView(mode: .create, invoiceId: nil, initialCustomerId: customer.id)
            } label: {
                Label("New invoice", systemImage: "doc.badge.plus")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(AppTheme.infoBlue, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)

            if invoicesForCustomer.isEmpty {
                emptyCard(
                    icon: "doc.text",
                    title: "No invoices yet",
                    message: "Create one to bill this customer."
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(invoicesForCustomer.enumerated()), id: \.element.id) { index, inv in
                        InvoiceListRowWithLongPressActions(
                            invoice: inv,
                            customerLine: InvoiceLogic.formatDisplayDate(iso: inv.date),
                            totalFormatted: InvoiceLogic.formatCurrency(amount: inv.total, code: currencyCode),
                            foreground: listRowForeground,
                            /// Destination-based links avoid stack mis-order on this screen.
                            useValueNavigation: false,
                            expandedInvoiceId: $expandedInvoiceId,
                            paymentSheetInvoiceId: $paymentSheetInvoiceId,
                            pdfShareItem: $pdfShareItem,
                            listErrorMessage: $invoiceListErrorMessage
                        )
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        if index < invoicesForCustomer.count - 1 {
                            Divider().padding(.leading, 14)
                        }
                    }
                }
                .background(CustomerCardBackground())
            }
        }
    }

    private var jobsTab: some View {
        Group {
            if jobsForCustomer.isEmpty {
                emptyCard(
                    icon: "calendar",
                    title: "No jobs yet",
                    message: "Jobs linked to this customer will show here."
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(jobsForCustomer.enumerated()), id: \.element.id) { index, job in
                        NavigationLink(destination: JobDetailView(jobId: job.id)) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(job.title)
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(listRowForeground)
                                    Text(shortJobDate(job.startDate))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 14)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if index < jobsForCustomer.count - 1 {
                            Divider().padding(.leading, 14)
                        }
                    }
                }
                .background(CustomerCardBackground())
            }
        }
    }

    private var detailsTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            detailGroup(title: "Contact") {
                if let sub = CustomerHeader.secondary(customer) {
                    detailLine(label: "Legal name", value: sub)
                }
                detailLine(label: "Email", value: customer.email)
                if let p = customer.phone, !p.isEmpty {
                    detailLine(label: "Phone", value: p)
                }
            }

            detailGroup(title: "Billing address") {
                Text(customer.billingAddress.street)
                Text("\(customer.billingAddress.city), \(customer.billingAddress.state) \(customer.billingAddress.postalCode)")
                Text(customer.billingAddress.country)
            }
            .font(.body)
            .foregroundStyle(listRowForeground)

            if let n = customer.notes, !n.isEmpty {
                detailGroup(title: "Notes") {
                    Text(n)
                        .font(.body)
                        .foregroundStyle(listRowForeground)
                }
            }
        }
    }

    private func detailGroup<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            VStack(alignment: .leading, spacing: 8) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(CustomerCardBackground())
        }
    }

    private func detailLine(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.body)
                .foregroundStyle(listRowForeground)
        }
    }

    private func emptyCard(icon: String, title: String, message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.body.weight(.medium))
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
        .background(CustomerCardBackground())
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
                                HStack(alignment: .center, spacing: 12) {
                                    CustomerAvatarView(customer: c, size: 36)
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
                                .padding(.vertical, 8)
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

// MARK: - Create / Edit

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

    private var isCreate: Bool { customer == nil }

    var body: some View {
        Form {
            Section {
                TextField("Full name", text: $name)
                    .textContentType(.name)
                TextField("Display name", text: $displayName)
                    .textContentType(.nickname)
            } header: {
                Text("Who")
            } footer: {
                Text("Display name is optional — use a short name if the legal name is long.")
            }

            Section("Contact") {
                TextField("Email", text: $email)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .textContentType(.emailAddress)
                    .autocorrectionDisabled()
                TextField("Phone", text: $phone)
                    .keyboardType(.phonePad)
                    .textContentType(.telephoneNumber)
            }

            Section("Billing address") {
                TextField("Street", text: $street)
                    .textContentType(.streetAddressLine1)
                TextField("City", text: $city)
                    .textContentType(.addressCity)
                TextField("County / state", text: $state)
                    .textContentType(.addressState)
                TextField("Postcode", text: $postalCode)
                    .textContentType(.postalCode)
                TextField("Country", text: $country)
                    .textContentType(.countryName)
            }

            Section("Notes") {
                TextField("Anything useful to remember", text: $notes, axis: .vertical)
                    .lineLimit(3...6)
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(AppTheme.outstandingRed)
                }
            }

            Section {
                Button(isCreate ? "Add customer" : "Save changes") {
                    if isCreate {
                        save()
                    } else {
                        confirmSave = true
                    }
                }
                .buttonStyle(PrimaryFormButtonStyle())
                .disabled(!isValid)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.clear)
            }
        }
        .navigationTitle(isCreate ? "New customer" : "Edit customer")
        .navigationBarTitleDisplayMode(.inline)
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
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && InvoiceLogic.validateEmail(email)
            && !street.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !city.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !state.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !postalCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !country.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func save() {
        errorMessage = nil
        let now = ISO8601DateFormatter().string(from: Date())
        let id = customer?.id ?? InvoiceLogic.generateId()
        let c = Customer(
            id: id,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            displayName: {
                let d = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
                return d.isEmpty ? nil : d
            }(),
            email: email.trimmingCharacters(in: .whitespacesAndNewlines),
            phone: {
                let p = phone.trimmingCharacters(in: .whitespacesAndNewlines)
                return p.isEmpty ? nil : p
            }(),
            billingAddress: Address(
                street: street.trimmingCharacters(in: .whitespacesAndNewlines),
                city: city.trimmingCharacters(in: .whitespacesAndNewlines),
                state: state.trimmingCharacters(in: .whitespacesAndNewlines),
                postalCode: postalCode.trimmingCharacters(in: .whitespacesAndNewlines),
                country: country.trimmingCharacters(in: .whitespacesAndNewlines)
            ),
            notes: {
                let n = notes.trimmingCharacters(in: .whitespacesAndNewlines)
                return n.isEmpty ? nil : n
            }(),
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
