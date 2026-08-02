import SwiftUI
import UIKit

struct InvoiceStatusBadge: View {
    let status: InvoiceStatus

    var body: some View {
        let tint = AppTheme.invoiceStatusColor(status)
        Text(status.displayLabel)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(tint)
            .background(tint.opacity(0.18), in: Capsule())
    }
}

/// Shared label layout for invoice rows (Invoices tab, dashboard “Recent”, customer invoice list).
struct InvoiceListRowContent: View {
    let invoiceNumber: String
    let status: InvoiceStatus
    let customerLine: String
    let totalFormatted: String
    let foreground: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center) {
                Text(invoiceNumber)
                    .font(.headline)
                    .foregroundStyle(foreground)
                Spacer(minLength: 8)
                InvoiceStatusBadge(status: status)
            }
            HStack(alignment: .firstTextBaseline) {
                Text(customerLine)
                    .font(.subheadline)
                    .foregroundStyle(foreground)
                Spacer(minLength: 8)
                Text(totalFormatted)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(foreground)
            }
        }
    }
}

struct InvoiceListView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.colorScheme) private var colorScheme
    @State private var previewInvoiceId: String?
    @State private var showInvoicePreview = false
    /// One-shot filter from “navigate to this customer’s invoices” (e.g. after sharing an invoice).
    @State private var listCustomerFilterId: String?
    @State private var expandedInvoiceId: String?
    @State private var paymentSheetInvoiceId: String?
    @State private var pdfShareItem: SharePDFURL?
    @State private var listErrorMessage: String?

    private var displayedInvoices: [Invoice] {
        let base = store.filteredInvoices
        if let id = listCustomerFilterId {
            return base.filter { $0.customerId == id }
        }
        return base
    }

    /// On white list rows (light mode), use black for readability.
    private var listRowForeground: Color {
        colorScheme == .light ? .black : Color.primary
    }

    var body: some View {
        List {
            if !store.invoices.isEmpty {
                Picker("Status", selection: Binding(
                    get: { store.invoiceStatusFilter },
                    set: { store.invoiceStatusFilter = $0 }
                )) {
                    Text("All").tag(Optional<InvoiceStatus>.none)
                    ForEach(InvoiceStatus.allCases, id: \.self) { s in
                        Text(s.rawValue.replacingOccurrences(of: "_", with: " ")).tag(Optional(s))
                    }
                }
            }
            if let fid = listCustomerFilterId, let c = store.customers.first(where: { $0.id == fid }) {
                Section {
                    HStack {
                        Text("Showing invoices for \(c.name)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Clear") {
                            listCustomerFilterId = nil
                        }
                        .font(.subheadline.weight(.semibold))
                    }
                }
            }
            ForEach(displayedInvoices) { inv in
                InvoiceListRowWithLongPressActions(
                    invoice: inv,
                    customerLine: customerName(inv.customerId),
                    totalFormatted: InvoiceLogic.formatCurrency(amount: inv.total, code: store.companyProfile?.currency ?? "GBP"),
                    foreground: listRowForeground,
                    useValueNavigation: true,
                    expandedInvoiceId: $expandedInvoiceId,
                    paymentSheetInvoiceId: $paymentSheetInvoiceId,
                    pdfShareItem: $pdfShareItem,
                    listErrorMessage: $listErrorMessage
                )
            }
        }
        .searchable(text: $store.invoiceSearch, prompt: "Search invoices")
        .navigationDestination(for: InvoiceDetailNavigationID.self) { route in
            InvoiceDetailView(invoiceId: route.invoiceId)
        }
        .navigationTitle("Invoices")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                NavigationLink("New") {
                    InvoiceEditorView(mode: .create, invoiceId: nil, onInvoiceCreated: { id in
                        previewInvoiceId = id
                        showInvoicePreview = true
                    })
                }
            }
        }
        .onAppear { applyPendingCustomerFilter() }
        .onChange(of: store.invoiceListCustomerFilterId) { _, _ in applyPendingCustomerFilter() }
        .onChange(of: displayedInvoices.map(\.id)) { _, _ in
            if let ex = expandedInvoiceId, !displayedInvoices.contains(where: { $0.id == ex }) {
                expandedInvoiceId = nil
            }
        }
        .refreshable { await store.reloadInvoices() }
        .alert("Error", isPresented: Binding(
            get: { listErrorMessage != nil },
            set: { if !$0 { listErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { listErrorMessage = nil }
        } message: {
            Text(listErrorMessage ?? "")
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
        .sheet(isPresented: $showInvoicePreview) {
            if let id = previewInvoiceId {
                NavigationStack {
                    InvoiceDetailView(invoiceId: id)
                        .environmentObject(store)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") {
                                    showInvoicePreview = false
                                    previewInvoiceId = nil
                                }
                            }
                        }
                }
            }
        }
    }

    private func applyPendingCustomerFilter() {
        if let id = store.invoiceListCustomerFilterId {
            listCustomerFilterId = id
            store.invoiceListCustomerFilterId = nil
        }
    }

    private func customerName(_ id: String) -> String {
        store.customers.first { $0.id == id }?.name ?? "Unknown"
    }
}

struct SharePDFURL: Identifiable {
    let id = UUID()
    let url: URL
    /// When set, draft invoices are marked sent after a successful share (same as detail).
    var invoiceIdForMarkSent: String?
}

enum InvoicePDFShareHelper {
    @MainActor
    static func makeTemporaryPDFURL(invoice: Invoice, store: AppStore) async throws -> URL {
        guard let profile = store.companyProfile else {
            throw NSError(domain: "InvoiceHelper", code: 1, userInfo: [NSLocalizedDescriptionKey: "Company profile is missing."])
        }
        guard let customer = store.customers.first(where: { $0.id == invoice.customerId }) else {
            throw NSError(domain: "InvoiceHelper", code: 2, userInfo: [NSLocalizedDescriptionKey: "Customer not found for this invoice."])
        }
        let data = await InvoicePDFGenerator.generatePDFData(invoice: invoice, company: profile, customer: customer)
        let safeName = invoice.invoiceNumber.replacingOccurrences(of: "/", with: "-")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Invoice_\(safeName).pdf")
        try data.write(to: url, options: .atomic)
        return url
    }
}

/// Long-press to reveal actions under the row (Samsung-style call log). Tap row still opens detail.
struct InvoiceListRowWithLongPressActions: View {
    @EnvironmentObject private var store: AppStore
    let invoice: Invoice
    let customerLine: String
    let totalFormatted: String
    let foreground: Color
    /// When `true`, uses `NavigationLink(value:)` with `InvoiceDetailNavigationID` (avoids `String` route collisions).
    var useValueNavigation = false
    @Binding var expandedInvoiceId: String?
    @Binding var paymentSheetInvoiceId: String?
    @Binding var pdfShareItem: SharePDFURL?
    @Binding var listErrorMessage: String?

    private var isExpanded: Bool { expandedInvoiceId == invoice.id }
    private var canShowPaymentActions: Bool {
        invoice.status != .cancelled && !InvoiceLogic.isFullyPaid(invoice)
    }

    /// Parent `onLongPressGesture` delays taps and breaks `NavigationLink`; `simultaneousGesture` does not.
    private var expandOnLongPress: some Gesture {
        LongPressGesture(minimumDuration: 0.45)
            .onEnded { _ in
                withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                    expandedInvoiceId = isExpanded ? nil : invoice.id
                }
                Haptics.light()
            }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                if useValueNavigation {
                    NavigationLink(value: InvoiceDetailNavigationID(invoiceId: invoice.id)) {
                        InvoiceListRowContent(
                            invoiceNumber: invoice.invoiceNumber,
                            status: invoice.status,
                            customerLine: customerLine,
                            totalFormatted: totalFormatted,
                            foreground: foreground
                        )
                    }
                    .buttonStyle(.plain)
                    .simultaneousGesture(expandOnLongPress)
                } else {
                    NavigationLink(destination: InvoiceDetailView(invoiceId: invoice.id)) {
                        InvoiceListRowContent(
                            invoiceNumber: invoice.invoiceNumber,
                            status: invoice.status,
                            customerLine: customerLine,
                            totalFormatted: totalFormatted,
                            foreground: foreground
                        )
                    }
                    .buttonStyle(.plain)
                    .simultaneousGesture(expandOnLongPress)
                }
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    Divider()
                        .padding(.bottom, 2)
                    if canShowPaymentActions {
                        HStack(alignment: .center, spacing: 10) {
                            Button {
                                Task { await resendInvoice() }
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "paperplane.fill")
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(AppTheme.infoBlue)
                                    Text("Resend invoice")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(AppTheme.infoBlue)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.75)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 11)
                                .background(
                                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                                        .fill(Color(.tertiarySystemGroupedBackground))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                                        .strokeBorder(AppTheme.infoBlue.opacity(0.45), lineWidth: 1.5)
                                )
                            }
                            .buttonStyle(.plain)

                            Button {
                                paymentSheetInvoiceId = invoice.id
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "banknote.fill")
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(.white)
                                    Text("Record payment")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.white)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.75)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 11)
                                .background(
                                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                                        .fill(AppTheme.revenueGreen)
                                )
                                .shadow(color: AppTheme.revenueGreen.opacity(0.35), radius: 6, y: 2)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color(.secondarySystemGroupedBackground))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                        )
                        .shadow(color: Color.black.opacity(0.07), radius: 10, x: 0, y: 4)
                    } else {
                        Text(invoice.status == .cancelled ? "Cancelled" : "Paid in full")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color(.secondarySystemGroupedBackground))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                            )
                    }
                }
                .padding(.top, 6)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func resendInvoice() async {
        do {
            let url = try await InvoicePDFShareHelper.makeTemporaryPDFURL(invoice: invoice, store: store)
            await MainActor.run {
                pdfShareItem = SharePDFURL(url: url, invoiceIdForMarkSent: invoice.id)
                expandedInvoiceId = nil
            }
        } catch {
            await MainActor.run {
                listErrorMessage = error.localizedDescription
            }
        }
    }
}

struct InvoiceDetailView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let invoiceId: String
    @State private var showPayment = false
    @State private var errorMessage: String?
    @State private var pdfShareItem: SharePDFURL?
    @State private var showDeleteConfirm = false

    private var invoice: Invoice? { store.invoices.first { $0.id == invoiceId } }

    var body: some View {
        Group {
            if let inv = invoice {
                List {
                    if let profile = store.companyProfile {
                        Section {
                            VStack(spacing: 10) {
                                CompanyLogoImageView(logo: profile.logo, size: 56, clipCircle: false, scaleToFit: true, showsStroke: false)
                                    .frame(maxWidth: .infinity)
                                Text(profile.name)
                                    .font(.headline)
                                    .multilineTextAlignment(.center)
                                Text(profile.email)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 3)
                        }
                        .listRowBackground(Color.clear)
                    }
                    Section {
                        HStack(alignment: .center, spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Customer")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(customerDisplayTitle(inv.customerId))
                                    .font(.body.weight(.semibold))
                            }
                            Spacer(minLength: 8)
                            Button("Payment") { showPayment = true }
                                .buttonStyle(.borderedProminent)
                                .tint(AppTheme.infoBlue)
                                .disabled(inv.status == .cancelled || InvoiceLogic.isFullyPaid(inv))
                        }
                    }
                    Section {
                        LabeledContent("Date", value: shortDate(inv.date))
                        LabeledContent("Due", value: shortDate(inv.dueDate))
                    }
                    Section("Line items") {
                        ForEach(inv.items) { item in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(item.description)
                                    .font(.body.weight(.medium))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .multilineTextAlignment(.leading)
                                HStack {
                                    Text("\(formatQty(item.quantity)) × \(formatMoney(item.unitPrice))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text(formatMoney(item.amount))
                                        .font(.subheadline.weight(.semibold))
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    Section("Totals") {
                        LabeledContent("Subtotal", value: formatMoney(inv.subtotal))
                        LabeledContent("Tax (\(formatQty(inv.taxRate))%)", value: formatMoney(inv.tax))
                        LabeledContent("Total", value: formatMoney(inv.total))
                    }
                    if let pays = inv.payments, !pays.isEmpty {
                        Section("Payments") {
                            ForEach(pays) { p in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(formatMoney(p.amount)).font(.headline)
                                    Text("\(p.method.rawValue) · \(shortDate(p.date))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    if let n = inv.notes, !n.isEmpty { Section("Notes") { Text(n) } }
                    if let t = inv.terms, !t.isEmpty { Section("Terms") { Text(t) } }
                    if inv.status == .draft {
                        Button("Mark as sent") {
                            Task {
                                do {
                                    try await store.updateInvoice(id: inv.id) { $0.status = .sent }
                                } catch {
                                    errorMessage = error.localizedDescription
                                }
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(AppTheme.infoBlue)
                    }
                    if canEdit(inv) {
                        NavigationLink("Edit invoice") {
                            InvoiceEditorView(mode: .edit, invoiceId: inv.id)
                        }
                    }
                    if inv.status == .draft && (inv.payments ?? []).isEmpty {
                        Button("Delete", role: .destructive) {
                            showDeleteConfirm = true
                        }
                    }
                }
                .navigationTitle(inv.invoiceNumber)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            prepareAndSharePDF(invoice: inv)
                        } label: {
                            Label("Share PDF", systemImage: "square.and.arrow.up")
                        }
                        .disabled(store.companyProfile == nil || store.customers.first(where: { $0.id == inv.customerId }) == nil)
                    }
                }
                .sheet(isPresented: $showPayment) {
                    PaymentSheet(invoiceId: inv.id, maxRemaining: inv.total - InvoiceLogic.totalPaid(for: inv))
                }
            } else {
                ContentUnavailableView("Invoice not found", systemImage: "doc")
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
        .alert("Delete invoice?", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                Task {
                    do {
                        try await store.deleteInvoice(id: invoiceId)
                        dismiss()
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            }
        } message: {
            Text("This draft invoice will be permanently removed.")
        }
        .sheet(item: $pdfShareItem) { item in
            PDFActivityView(activityItems: [item.url]) { completed in
                if completed {
                    afterSuccessfulShare()
                }
            }
        }
    }

    private func afterSuccessfulShare() {
        Task {
            await markSentIfDraft()
            await MainActor.run {
                if let inv = store.invoices.first(where: { $0.id == invoiceId }) {
                    store.navigateToInvoicesForCustomer(inv.customerId)
                }
                dismiss()
            }
        }
    }

    private func markSentIfDraft() async {
        guard let inv = store.invoices.first(where: { $0.id == invoiceId }), inv.status == .draft else { return }
        try? await store.updateInvoice(id: inv.id) { $0.status = .sent }
    }

    private func prepareAndSharePDF(invoice: Invoice) {
        Task {
            do {
                let url = try await InvoicePDFShareHelper.makeTemporaryPDFURL(invoice: invoice, store: store)
                await MainActor.run {
                    pdfShareItem = SharePDFURL(url: url, invoiceIdForMarkSent: nil)
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func canEdit(_ inv: Invoice) -> Bool {
        InvoiceLogic.totalPaid(for: inv) == 0 && inv.status != .cancelled
    }

    private func customerDisplayTitle(_ id: String) -> String {
        guard let c = store.customers.first(where: { $0.id == id }) else { return "Unknown" }
        return CustomerHeader.primary(c)
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

struct PaymentSheet: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let invoiceId: String
    let maxRemaining: Double

    @State private var amountStr = ""
    @State private var method: PaymentMethod = .BAC
    @State private var date = Date()
    @State private var notes = ""
    @State private var errorMessage: String?

    private var invoice: Invoice? { store.invoices.first { $0.id == invoiceId } }
    private var currencyCode: String { store.companyProfile?.currency ?? "GBP" }
    private var totalAmount: Double { invoice?.total ?? 0 }
    private var outstandingAmount: Double { maxRemaining }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Total") {
                        Text(InvoiceLogic.formatCurrency(amount: totalAmount, code: currencyCode))
                            .fontWeight(.semibold)
                    }
                    Button {
                        fillAmountWithOutstanding()
                    } label: {
                        HStack(alignment: .firstTextBaseline) {
                            Text("Outstanding")
                                .foregroundStyle(.primary)
                            Spacer(minLength: 12)
                            Text(InvoiceLogic.formatCurrency(amount: outstandingAmount, code: currencyCode))
                                .fontWeight(.semibold)
                                .foregroundStyle(AppTheme.infoBlue)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Fills the amount field with the outstanding balance.")
                } header: {
                    Text("Invoice amounts")
                } footer: {
                    Text("Tap Outstanding to copy the remaining balance into Amount.")
                        .font(.caption)
                }
                Section {
                    TextField("Amount", text: $amountStr)
                        .keyboardType(.decimalPad)
                    Picker("Method", selection: $method) {
                        ForEach(PaymentMethod.allCases, id: \.self) { m in
                            Text(m.rawValue).tag(m)
                        }
                    }
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                }
                Section {
                    TextField("Notes (optional)", text: $notes, axis: .vertical)
                        .lineLimit(2...6)
                }
                if let errorMessage { Section { Text(errorMessage).foregroundStyle(.red) } }
                Section {
                    Button("Record payment") { Task { await submit() } }
                        .buttonStyle(PrimaryFormButtonStyle())
                }
            }
            .navigationTitle("Add payment")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private func fillAmountWithOutstanding() {
        amountStr = String(format: "%.2f", outstandingAmount)
        Haptics.light()
    }

    private func submit() async {
        errorMessage = nil
        guard let amt = Double(amountStr.replacingOccurrences(of: ",", with: ".")), amt > 0 else {
            errorMessage = "Enter a valid amount"
            return
        }
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let iso = fmt.string(from: date)
        do {
            try await store.addPayment(invoiceId: invoiceId, amount: amt, method: method, date: iso, notes: notes.isEmpty ? nil : notes)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Shared qty / unit price row with a vertical separator between fields (invoice & estimate editors).
struct InvoiceLineQtyUnitRow: View {
    @Binding var quantity: String
    @Binding var unitPrice: String

    var body: some View {
        HStack(spacing: 0) {
            TextField("Qty", text: $quantity)
                .keyboardType(.decimalPad)
            Rectangle()
                .fill(Color(.separator))
                .frame(width: 1)
                .padding(.vertical, 6)
            TextField("Unit price", text: $unitPrice)
                .keyboardType(.decimalPad)
        }
    }
}

struct InvoiceEditorView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    enum Mode { case create, edit }
    var mode: Mode
    var invoiceId: String?
    /// When creating, pre-select this customer (e.g. from customer detail).
    var initialCustomerId: String?
    /// After creating an invoice, called with new id so the parent can show a preview.
    var onInvoiceCreated: ((String) -> Void)? = nil

    @State private var customerId = ""
    @State private var taxRate: Double = 20
    @State private var invoiceDate = Date()
    @State private var dueDate = Date()
    @State private var notes = ""
    @State private var terms = ""
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
            Section("Dates & tax") {
                DatePicker("Invoice date", selection: $invoiceDate, displayedComponents: .date)
                DatePicker("Due date", selection: $dueDate, displayedComponents: .date)
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
                Button("Add Item") {
                    lines.append(LineRow())
                }
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
                TextField("Terms (optional)", text: $terms, axis: .vertical)
                    .lineLimit(2...8)
                    .textInputAutocapitalization(.sentences)
            }
            if let errorMessage { Section { Text(errorMessage).foregroundStyle(.red) } }
            if let hint = invoiceSaveBlockedHint {
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
                Button(mode == .create ? "Create invoice" : "Save changes") { Task { await save() } }
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
                    createLabel: "New invoice",
                    editLabel: "Edit invoice",
                    isCreate: mode == .create
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
            if mode == .edit, let id = invoiceId, let inv = store.invoices.first(where: { $0.id == id }) {
                customerId = inv.customerId
                taxRate = inv.taxRate
                invoiceDate = parseDate(inv.date) ?? Date()
                dueDate = parseDate(inv.dueDate) ?? Date()
                notes = inv.notes ?? ""
                terms = inv.terms ?? ""
                lines = inv.items.map { item in
                    LineRow(
                        description: item.description,
                        quantity: formatQty(item.quantity),
                        unitPrice: String(item.unitPrice)
                    )
                }
                if lines.isEmpty { lines = [LineRow()] }
            } else if mode == .create {
                if let pre = initialCustomerId, customerId.isEmpty {
                    customerId = pre
                }
                syncDueDateFromInvoiceDate()
            }
        }
        .onChange(of: invoiceDate) { _, newDate in
            guard mode == .create else { return }
            let offset = store.defaultInvoiceDueDaysFromInvoiceDate
            dueDate = Calendar.current.date(byAdding: .day, value: offset, to: newDate) ?? newDate
        }
    }

    private func syncDueDateFromInvoiceDate() {
        let offset = store.defaultInvoiceDueDaysFromInvoiceDate
        dueDate = Calendar.current.date(byAdding: .day, value: offset, to: invoiceDate) ?? invoiceDate
    }

    private var linesValid: Bool {
        lines.contains { row in
            let desc = row.description.trimmingCharacters(in: .whitespaces)
            let q = Double(row.quantity.replacingOccurrences(of: ",", with: ".")) ?? 0
            let p = Double(row.unitPrice.replacingOccurrences(of: ",", with: ".")) ?? 0
            return !desc.isEmpty && q > 0 && p > 0
        }
    }

    /// Shown when Create/Save is disabled so the user knows what to fix.
    private var invoiceSaveBlockedHint: String? {
        if customerId.isEmpty {
            return "Select a customer before creating the invoice."
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
            let inv = InvoiceItem(from: s)
            lines.append(
                LineRow(
                    description: inv.description,
                    quantity: formatQty(inv.quantity),
                    unitPrice: String(inv.unitPrice)
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

    private func buildItems() -> [InvoiceItem]? {
        var items: [InvoiceItem] = []
        for row in lines {
            let desc = row.description.trimmingCharacters(in: .whitespaces)
            guard !desc.isEmpty else { continue }
            guard let q = Double(row.quantity.replacingOccurrences(of: ",", with: ".")),
                  let p = Double(row.unitPrice.replacingOccurrences(of: ",", with: ".")),
                  q > 0 else { return nil }
            items.append(InvoiceItem(description: desc, quantity: q, unitPrice: p))
        }
        return items.isEmpty ? nil : items
    }

    private func save() async {
        errorMessage = nil
        guard let items = buildItems() else {
            errorMessage = "Each line needs a description, quantity above 0, and unit price above 0. Remove empty lines or complete them."
            return
        }
        do {
            if mode == .create {
                let inv = try await store.addInvoice(
                    customerId: customerId,
                    items: items,
                    taxRate: taxRate,
                    date: iso(invoiceDate),
                    dueDate: iso(dueDate),
                    notes: notes.isEmpty ? nil : notes,
                    terms: terms.isEmpty ? nil : terms
                )
                onInvoiceCreated?(inv.id)
            } else if let id = invoiceId {
                try await store.updateInvoice(id: id) { inv in
                    inv.customerId = customerId
                    inv.items = items
                    inv.taxRate = taxRate
                    inv.date = iso(invoiceDate)
                    inv.dueDate = iso(dueDate)
                    inv.notes = notes.isEmpty ? nil : notes
                    inv.terms = terms.isEmpty ? nil : terms
                }
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - UIKit share sheets

struct PDFActivityView: UIViewControllerRepresentable {
    var activityItems: [Any]
    var onComplete: ((Bool) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(onComplete: onComplete)
    }

    final class Coordinator {
        var onComplete: ((Bool) -> Void)?
        init(onComplete: ((Bool) -> Void)?) { self.onComplete = onComplete }
    }

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let c = UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
        c.completionWithItemsHandler = { _, completed, _, _ in
            context.coordinator.onComplete?(completed)
        }
        if let pop = c.popoverPresentationController {
            let v = UIView()
            let b = UIScreen.main.bounds
            v.bounds = CGRect(x: 0, y: 0, width: 1, height: 1)
            v.center = CGPoint(x: b.midX, y: b.midY)
            pop.sourceView = v
            pop.sourceRect = v.bounds
            pop.permittedArrowDirections = []
        }
        return c
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
        context.coordinator.onComplete = onComplete
    }
}
