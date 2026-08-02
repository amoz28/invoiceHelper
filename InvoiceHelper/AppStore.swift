import Foundation
import SwiftUI

@MainActor
final class AppStore: ObservableObject {
    @Published private(set) var session: AuthSession?
    @Published private(set) var currentUser: AppUser?
    @Published var companyProfile: CompanyProfile?
    @Published var customers: [Customer] = []
    @Published var savedItems: [SavedItem] = []
    @Published var savedJobTemplates: [SavedJobTemplate] = []
    @Published var invoices: [Invoice] = []
    @Published var jobs: [ScheduledJob] = []
    @Published var estimates: [Estimate] = []
    @Published var customerSearch = ""
    @Published var invoiceSearch = ""
    @Published var invoiceStatusFilter: InvoiceStatus?
    @Published var estimateSearch = ""
    @Published var estimateStatusFilter: EstimateStatus?
    @Published var authError: String?
    @Published var isBootstrapping = true
    /// When set, `InvoiceListView` applies a one-shot customer filter (cleared after apply).
    @Published var invoiceListCustomerFilterId: String?
    /// Switch main tab to Invoices after navigating for a customer.
    @Published var shouldSelectInvoicesTab = false

    private let disk = LocalPersistence()

    /// Set to `true` when the user has an active Premium subscription (e.g. after in-app purchase). Placeholder until IAP is wired.
    var isPremiumSubscriber: Bool {
        UserDefaults.standard.bool(forKey: "subscription.premium")
    }

    var isAuthenticated: Bool { session != nil }
    var needsCompanySetup: Bool {
        guard companyProfile != nil else { return true }
        return companyProfile?.isProfileComplete != true
    }

    /// Days after invoice date for default due date (0 = same calendar day).
    var defaultInvoiceDueDaysFromInvoiceDate: Int {
        companyProfile?.defaultInvoiceDueDaysFromInvoiceDate ?? 0
    }

    /// Days after creation for default estimate “valid until” (0 = same day).
    var defaultEstimateValidDaysFromCreation: Int {
        companyProfile?.defaultEstimateValidDaysFromCreation ?? 0
    }

    func navigateToInvoicesForCustomer(_ customerId: String) {
        invoiceListCustomerFilterId = customerId
        shouldSelectInvoicesTab = true
    }

    func bootstrap() async {
        isBootstrapping = true
        defer { isBootstrapping = false }
        session = disk.decode(AuthSession.self, key: StorageKeys.auth)
        loadUsersAndProfile()
        if session != nil, currentUser == nil {
            try? disk.remove(StorageKeys.auth)
            session = nil
        }
        customers = disk.decode([Customer].self, key: StorageKeys.customers) ?? []
        reloadSavedItems()
        reloadSavedJobTemplates()
        reloadJobs()
        reloadEstimates()
        await reloadInvoices()
    }

    func reloadJobs() {
        jobs = disk.decode([ScheduledJob].self, key: StorageKeys.jobs) ?? []
    }

    func reloadSavedItems() {
        savedItems = (disk.decode([SavedItem].self, key: StorageKeys.savedItems) ?? [])
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func reloadSavedJobTemplates() {
        savedJobTemplates = (disk.decode([SavedJobTemplate].self, key: StorageKeys.savedJobTemplates) ?? [])
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func loadUsersAndProfile() {
        let users = disk.decode([AppUser].self, key: StorageKeys.users) ?? []
        if let s = session, let u = users.first(where: { $0.id == s.userId }) {
            currentUser = u
        } else {
            currentUser = nil
        }
        companyProfile = disk.decode(CompanyProfile.self, key: StorageKeys.companySettings)
    }

    func reloadInvoices() async {
        var list = disk.decode([Invoice].self, key: StorageKeys.invoices) ?? []
        for i in list.indices {
            let pid = list[i].id
            let payments = disk.decode([Payment].self, key: disk.paymentKey(invoiceId: pid)) ?? []
            let paid = payments.reduce(0) { $0 + $1.amount }
            let status = InvoiceLogic.resolvedInvoiceStatus(
                dueDate: list[i].dueDate,
                storedStatus: list[i].status,
                total: list[i].total,
                totalPaid: paid
            )
            list[i].status = status
            list[i].payments = payments
        }
        invoices = list
    }

    private func persistInvoicesStripPayments(_ list: [Invoice]) throws {
        let stripped = list.map { inv -> Invoice in
            var copy = inv
            copy.payments = nil
            return copy
        }
        try disk.encode(stripped, key: StorageKeys.invoices)
    }

    func register(email: String, password: String, companyName: String) throws {
        authError = nil
        guard InvoiceLogic.validateEmail(email) else {
            throw NSError(domain: "InvoiceHelper", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid email"])
        }
        let pw = InvoiceLogic.validatePassword(password)
        guard pw.valid else {
            throw NSError(domain: "InvoiceHelper", code: 2, userInfo: [NSLocalizedDescriptionKey: pw.errors.joined(separator: "\n")])
        }
        guard companyName.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 else {
            throw NSError(domain: "InvoiceHelper", code: 3, userInfo: [NSLocalizedDescriptionKey: "Company name must be at least 2 characters"])
        }
        var users = disk.decode([AppUser].self, key: StorageKeys.users) ?? []
        if users.contains(where: { $0.email.lowercased() == email.lowercased() }) {
            throw NSError(domain: "InvoiceHelper", code: 4, userInfo: [NSLocalizedDescriptionKey: "Email already registered"])
        }
        let id = InvoiceLogic.generateId()
        let user = AppUser(
            id: id,
            email: email.trimmingCharacters(in: .whitespacesAndNewlines),
            companyName: companyName.trimmingCharacters(in: .whitespacesAndNewlines),
            password: InvoiceLogic.hashPassword(password),
            companyProfile: nil,
            createdAt: ISO8601DateFormatter().string(from: Date())
        )
        users.append(user)
        try disk.encode(users, key: StorageKeys.users)
        try disk.encode(AuthSession(userId: id, email: user.email), key: StorageKeys.auth)
        session = AuthSession(userId: id, email: user.email)
        currentUser = user
    }

    func login(email: String, password: String) throws {
        authError = nil
        let users = disk.decode([AppUser].self, key: StorageKeys.users) ?? []
        let hash = InvoiceLogic.hashPassword(password)
        guard let user = users.first(where: { $0.email.lowercased() == email.lowercased() }) else {
            throw NSError(domain: "InvoiceHelper", code: 10, userInfo: [NSLocalizedDescriptionKey: "Invalid credentials"])
        }
        guard user.password == hash, !user.password.isEmpty else {
            throw NSError(domain: "InvoiceHelper", code: 11, userInfo: [NSLocalizedDescriptionKey: "Invalid credentials"])
        }
        try disk.encode(AuthSession(userId: user.id, email: user.email), key: StorageKeys.auth)
        session = AuthSession(userId: user.id, email: user.email)
        currentUser = user
        loadUsersAndProfile()
    }

    /// Sets a new password for an existing account (local device only; no email is sent).
    func resetPassword(email: String, newPassword: String) throws {
        authError = nil
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard InvoiceLogic.validateEmail(trimmed) else {
            throw NSError(domain: "InvoiceHelper", code: 12, userInfo: [NSLocalizedDescriptionKey: "Invalid email"])
        }
        let pw = InvoiceLogic.validatePassword(newPassword)
        guard pw.valid else {
            throw NSError(domain: "InvoiceHelper", code: 13, userInfo: [NSLocalizedDescriptionKey: pw.errors.joined(separator: "\n")])
        }
        var users = disk.decode([AppUser].self, key: StorageKeys.users) ?? []
        guard let idx = users.firstIndex(where: { $0.email.lowercased() == trimmed.lowercased() }) else {
            throw NSError(domain: "InvoiceHelper", code: 14, userInfo: [NSLocalizedDescriptionKey: "No account found for this email."])
        }
        users[idx].password = InvoiceLogic.hashPassword(newPassword)
        try disk.encode(users, key: StorageKeys.users)
    }

    /// Change password while signed in (requires current password).
    func changePassword(currentPassword: String, newPassword: String) throws {
        authError = nil
        guard let session else {
            throw NSError(domain: "InvoiceHelper", code: 15, userInfo: [NSLocalizedDescriptionKey: "Not signed in"])
        }
        let pwNew = InvoiceLogic.validatePassword(newPassword)
        guard pwNew.valid else {
            throw NSError(domain: "InvoiceHelper", code: 16, userInfo: [NSLocalizedDescriptionKey: pwNew.errors.joined(separator: "\n")])
        }
        var users = disk.decode([AppUser].self, key: StorageKeys.users) ?? []
        guard let idx = users.firstIndex(where: { $0.id == session.userId }) else {
            throw NSError(domain: "InvoiceHelper", code: 17, userInfo: [NSLocalizedDescriptionKey: "Account not found"])
        }
        let currentHash = InvoiceLogic.hashPassword(currentPassword)
        if users[idx].password.isEmpty {
            // Imported backup users may have no password; allow setting first password without old one.
        } else {
            guard users[idx].password == currentHash else {
                throw NSError(domain: "InvoiceHelper", code: 18, userInfo: [NSLocalizedDescriptionKey: "Current password is incorrect"])
            }
        }
        guard newPassword != currentPassword else {
            throw NSError(domain: "InvoiceHelper", code: 19, userInfo: [NSLocalizedDescriptionKey: "New password must be different from your current password"])
        }
        users[idx].password = InvoiceLogic.hashPassword(newPassword)
        try disk.encode(users, key: StorageKeys.users)
    }

    func logout() throws {
        try disk.remove(StorageKeys.auth)
        session = nil
        currentUser = nil
    }

    func saveCompanyProfile(_ profile: CompanyProfile) throws {
        try disk.encode(profile, key: StorageKeys.companySettings)
        companyProfile = profile
    }

    func upsertCustomer(_ customer: Customer) throws {
        if let idx = customers.firstIndex(where: { $0.id == customer.id }) {
            customers[idx] = customer
        } else {
            customers.append(customer)
        }
        try disk.encode(customers, key: StorageKeys.customers)
    }

    func deleteCustomer(id: String) throws {
        customers.removeAll { $0.id == id }
        try disk.encode(customers, key: StorageKeys.customers)
    }

    func addSavedItem(name: String, description: String?, defaultQuantity: Double, defaultUnitPrice: Double) throws -> SavedItem {
        let now = ISO8601DateFormatter().string(from: Date())
        let item = SavedItem(
            id: InvoiceLogic.generateId(),
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            description: description?.trimmingCharacters(in: .whitespacesAndNewlines),
            defaultQuantity: defaultQuantity,
            defaultUnitPrice: defaultUnitPrice,
            createdAt: now,
            updatedAt: now
        )
        savedItems.append(item)
        try persistSavedItems()
        reloadSavedItems()
        guard let saved = savedItems.first(where: { $0.id == item.id }) else { return item }
        return saved
    }

    func updateSavedItem(_ item: SavedItem) throws {
        guard let idx = savedItems.firstIndex(where: { $0.id == item.id }) else { return }
        var updated = item
        updated.name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.description = item.description?.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.updatedAt = ISO8601DateFormatter().string(from: Date())
        savedItems[idx] = updated
        try persistSavedItems()
        reloadSavedItems()
    }

    func deleteSavedItem(id: String) throws {
        savedItems.removeAll { $0.id == id }
        try persistSavedItems()
        reloadSavedItems()
    }

    func addSavedJobTemplate(name: String, description: String?) throws -> SavedJobTemplate {
        let now = ISO8601DateFormatter().string(from: Date())
        let desc = description?.trimmingCharacters(in: .whitespacesAndNewlines)
        let item = SavedJobTemplate(
            id: InvoiceLogic.generateId(),
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            description: (desc?.isEmpty == false) ? desc : nil,
            createdAt: now,
            updatedAt: now
        )
        savedJobTemplates.append(item)
        try persistSavedJobTemplates()
        reloadSavedJobTemplates()
        guard let saved = savedJobTemplates.first(where: { $0.id == item.id }) else { return item }
        return saved
    }

    func updateSavedJobTemplate(_ item: SavedJobTemplate) throws {
        guard let idx = savedJobTemplates.firstIndex(where: { $0.id == item.id }) else { return }
        var updated = item
        updated.name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let desc = item.description?.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.description = (desc?.isEmpty == false) ? desc : nil
        updated.updatedAt = ISO8601DateFormatter().string(from: Date())
        savedJobTemplates[idx] = updated
        try persistSavedJobTemplates()
        reloadSavedJobTemplates()
    }

    func deleteSavedJobTemplate(id: String) throws {
        savedJobTemplates.removeAll { $0.id == id }
        try persistSavedJobTemplates()
        reloadSavedJobTemplates()
    }

    /// Invoices for a customer (for list stats; matches RN `getCustomerInvoices` / `getCustomerTotalInvoiced`).
    func invoices(forCustomerId customerId: String) -> [Invoice] {
        invoices.filter { $0.customerId == customerId }
    }

    func totalInvoiced(forCustomerId customerId: String) -> Double {
        invoices(forCustomerId: customerId).reduce(0) { $0 + $1.total }
    }

    /// Draft invoice from an estimate (pending or accepted). Original estimate is unchanged.
    func createInvoiceFromEstimate(estimateId: String) async throws -> Invoice {
        guard let est = estimates.first(where: { $0.id == estimateId }) else {
            throw NSError(domain: "InvoiceHelper", code: 30, userInfo: [NSLocalizedDescriptionKey: "Estimate not found"])
        }
        guard est.status == .pending || est.status == .accepted else {
            throw NSError(
                domain: "InvoiceHelper",
                code: 31,
                userInfo: [NSLocalizedDescriptionKey: "Only pending or accepted estimates can be turned into an invoice."]
            )
        }
        let items: [InvoiceItem] = est.items.map { ei in
            InvoiceItem(description: ei.description, quantity: ei.quantity, unitPrice: ei.unitPrice, amount: ei.amount)
        }
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let now = Date()
        let due = Calendar.current.date(byAdding: .day, value: 14, to: now) ?? now
        let convertedLine = "Converted from \(est.estimateNumber)."
        let notes: String = {
            if let n = est.notes, !n.isEmpty { return "\(n)\n\n\(convertedLine)" }
            return convertedLine
        }()
        return try await addInvoice(
            customerId: est.customerId,
            items: items,
            taxRate: est.taxRate,
            date: fmt.string(from: now),
            dueDate: fmt.string(from: due),
            notes: notes,
            terms: nil
        )
    }

    func addInvoice(
        customerId: String,
        items: [InvoiceItem],
        taxRate: Double,
        date: String,
        dueDate: String,
        notes: String?,
        terms: String?
    ) async throws -> Invoice {
        let totals = InvoiceLogic.calculateInvoiceTotals(items: items, taxRate: taxRate)
        let id = InvoiceLogic.generateId()
        let now = ISO8601DateFormatter().string(from: Date())
        var inv = Invoice(
            id: id,
            invoiceNumber: InvoiceLogic.generateInvoiceNumber(id: id),
            customerId: customerId,
            items: items,
            subtotal: totals.subtotal,
            tax: totals.tax,
            taxRate: taxRate,
            total: totals.total,
            status: .draft,
            notes: notes,
            terms: terms,
            date: date,
            dueDate: dueDate,
            createdAt: now,
            updatedAt: now,
            payments: []
        )
        var list = disk.decode([Invoice].self, key: StorageKeys.invoices) ?? []
        list.append(inv)
        try persistInvoicesStripPayments(list)
        try disk.encode([Payment](), key: disk.paymentKey(invoiceId: id))
        await reloadInvoices()
        guard let final = invoices.first(where: { $0.id == id }) else { return inv }
        return final
    }

    func updateInvoice(id: String, mutate: (inout Invoice) -> Void) async throws {
        var list = disk.decode([Invoice].self, key: StorageKeys.invoices) ?? []
        guard let idx = list.firstIndex(where: { $0.id == id }) else { return }
        mutate(&list[idx])
        let t = InvoiceLogic.calculateInvoiceTotals(items: list[idx].items, taxRate: list[idx].taxRate)
        list[idx].subtotal = t.subtotal
        list[idx].tax = t.tax
        list[idx].total = t.total
        list[idx].updatedAt = ISO8601DateFormatter().string(from: Date())
        let payments = disk.decode([Payment].self, key: disk.paymentKey(invoiceId: id)) ?? []
        let paid = payments.reduce(0) { $0 + $1.amount }
        list[idx].status = InvoiceLogic.resolvedInvoiceStatus(
            dueDate: list[idx].dueDate,
            storedStatus: list[idx].status,
            total: list[idx].total,
            totalPaid: paid
        )
        try persistInvoicesStripPayments(list)
        await reloadInvoices()
    }

    func deleteInvoice(id: String) async throws {
        var list = disk.decode([Invoice].self, key: StorageKeys.invoices) ?? []
        list.removeAll { $0.id == id }
        try persistInvoicesStripPayments(list)
        try disk.remove(disk.paymentKey(invoiceId: id))
        await reloadInvoices()
    }

    func addPayment(invoiceId: String, amount: Double, method: PaymentMethod, date: String, notes: String?) async throws {
        guard let inv = disk.decode([Invoice].self, key: StorageKeys.invoices)?.first(where: { $0.id == invoiceId }) else {
            throw NSError(domain: "InvoiceHelper", code: 20, userInfo: [NSLocalizedDescriptionKey: "Invoice not found"])
        }
        var payments = disk.decode([Payment].self, key: disk.paymentKey(invoiceId: invoiceId)) ?? []
        let paid = payments.reduce(0) { $0 + $1.amount }
        if paid + amount > inv.total + 0.0001 {
            throw NSError(domain: "InvoiceHelper", code: 21, userInfo: [NSLocalizedDescriptionKey: "Payment exceeds invoice total"])
        }
        let p = Payment(id: InvoiceLogic.generateId(), invoiceId: invoiceId, amount: amount, method: method, date: date, notes: notes)
        payments.append(p)
        try disk.encode(payments, key: disk.paymentKey(invoiceId: invoiceId))
        var all = disk.decode([Invoice].self, key: StorageKeys.invoices) ?? []
        if let i = all.firstIndex(where: { $0.id == invoiceId }) {
            let totalPaid = payments.reduce(0) { $0 + $1.amount }
            all[i].status = InvoiceLogic.resolvedInvoiceStatus(
                dueDate: all[i].dueDate,
                storedStatus: all[i].status,
                total: all[i].total,
                totalPaid: totalPaid
            )
            all[i].updatedAt = ISO8601DateFormatter().string(from: Date())
        }
        try persistInvoicesStripPayments(all)
        await reloadInvoices()
    }

    func upsertJob(_ job: ScheduledJob) throws {
        if let idx = jobs.firstIndex(where: { $0.id == job.id }) {
            jobs[idx] = job
        } else {
            jobs.append(job)
        }
        try disk.encode(jobs, key: StorageKeys.jobs)
    }

    func updateJob(id: String, mutate: (inout ScheduledJob) -> Void) throws {
        var list = disk.decode([ScheduledJob].self, key: StorageKeys.jobs) ?? []
        guard let idx = list.firstIndex(where: { $0.id == id }) else { return }
        mutate(&list[idx])
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        list[idx].updatedAt = fmt.string(from: Date())
        try disk.encode(list, key: StorageKeys.jobs)
        reloadJobs()
    }

    func deleteJob(id: String) throws {
        jobs.removeAll { $0.id == id }
        try disk.encode(jobs, key: StorageKeys.jobs)
    }

    // MARK: - Estimates (parity with InvoiceHelper storage + estimatesSlice)

    func reloadEstimates() {
        var list = disk.decode([Estimate].self, key: StorageKeys.estimates) ?? []
        let now = ISO8601DateFormatter().string(from: Date())
        var changed = false
        for i in list.indices {
            if list[i].status == .pending, InvoiceLogic.isEstimateExpired(validUntil: list[i].validUntil) {
                list[i].status = .expired
                list[i].updatedAt = now
                changed = true
            }
        }
        if changed {
            try? disk.encode(list, key: StorageKeys.estimates)
        }
        estimates = list.sorted { $0.createdAt > $1.createdAt }
    }

    private func persistEstimates() throws {
        try disk.encode(estimates, key: StorageKeys.estimates)
    }

    private func persistSavedItems() throws {
        try disk.encode(savedItems, key: StorageKeys.savedItems)
    }

    private func persistSavedJobTemplates() throws {
        try disk.encode(savedJobTemplates, key: StorageKeys.savedJobTemplates)
    }

    @discardableResult
    func addEstimate(customerId: String, items: [EstimateItem], taxRate: Double, validUntilISO: String, notes: String?) throws -> Estimate {
        let t = InvoiceLogic.calculateEstimateTotals(items: items, taxRate: taxRate)
        let id = InvoiceLogic.generateId()
        let now = ISO8601DateFormatter().string(from: Date())
        let e = Estimate(
            id: id,
            estimateNumber: InvoiceLogic.generateEstimateNumber(id: id),
            customerId: customerId,
            items: items,
            subtotal: t.subtotal,
            tax: t.tax,
            taxRate: taxRate,
            total: t.total,
            status: .pending,
            notes: notes,
            validUntil: validUntilISO,
            createdAt: now,
            updatedAt: now
        )
        estimates.append(e)
        estimates.sort { $0.createdAt > $1.createdAt }
        try persistEstimates()
        return e
    }

    func updateEstimate(id: String, mutate: (inout Estimate) -> Void) throws {
        guard let idx = estimates.firstIndex(where: { $0.id == id }) else { return }
        mutate(&estimates[idx])
        let t = InvoiceLogic.calculateEstimateTotals(items: estimates[idx].items, taxRate: estimates[idx].taxRate)
        estimates[idx].subtotal = t.subtotal
        estimates[idx].tax = t.tax
        estimates[idx].total = t.total
        estimates[idx].updatedAt = ISO8601DateFormatter().string(from: Date())
        try persistEstimates()
    }

    func deleteEstimate(id: String) throws {
        estimates.removeAll { $0.id == id }
        try persistEstimates()
    }

    var filteredEstimates: [Estimate] {
        let q = estimateSearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return estimates
            .filter { est in
                if let f = estimateStatusFilter, est.status != f { return false }
                if q.isEmpty { return true }
                if est.estimateNumber.lowercased().contains(q) { return true }
                if let c = customers.first(where: { $0.id == est.customerId }) {
                    return c.name.lowercased().contains(q) || c.email.lowercased().contains(q)
                }
                return false
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    var pendingEstimatesCount: Int {
        estimates.filter { $0.status == .pending && !InvoiceLogic.isEstimateExpired(validUntil: $0.validUntil) }.count
    }

    func exportData() throws -> Data {
        let users = disk.decode([AppUser].self, key: StorageKeys.users) ?? []
        let usersExport: [UserExport] = users.map {
            UserExport(id: $0.id, email: $0.email, companyName: $0.companyName, companyProfile: $0.companyProfile, createdAt: $0.createdAt)
        }
        let invRaw = disk.decode([Invoice].self, key: StorageKeys.invoices) ?? []
        var allPayments: [Payment] = []
        for inv in invRaw {
            allPayments.append(contentsOf: disk.decode([Payment].self, key: disk.paymentKey(invoiceId: inv.id)) ?? [])
        }
        let export = ExportData(
            version: "1.0.0",
            exportDate: ISO8601DateFormatter().string(from: Date()),
            applicationName: "InvoiceHelper",
            users: usersExport,
            companyProfile: companyProfile,
            customers: customers,
            savedItems: savedItems,
            savedJobTemplates: savedJobTemplates,
            invoices: invRaw.map { var i = $0; i.payments = nil; return i },
            payments: allPayments,
            estimates: estimates,
            jobs: jobs
        )
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try enc.encode(export)
    }

    /// Applies a cloud snapshot to local storage without clearing auth or user accounts (unlike `importData`).
    func applyCloudSnapshot(_ data: Data) async throws {
        let imported = try JSONDecoder().decode(ExportData.self, from: data)
        let existingInvoices = disk.decode([Invoice].self, key: StorageKeys.invoices) ?? []
        for inv in existingInvoices {
            try? disk.remove(disk.paymentKey(invoiceId: inv.id))
        }
        for key in disk.listPaymentStorageKeys() {
            try? disk.remove(key)
        }
        if let p = imported.companyProfile {
            try disk.encode(p, key: StorageKeys.companySettings)
        }
        try disk.encode(imported.customers, key: StorageKeys.customers)
        try disk.encode(imported.savedItems, key: StorageKeys.savedItems)
        try disk.encode(imported.savedJobTemplates, key: StorageKeys.savedJobTemplates)
        try disk.encode(imported.invoices.map { var i = $0; i.payments = nil; return i }, key: StorageKeys.invoices)
        try disk.encode(imported.estimates, key: StorageKeys.estimates)
        try disk.encode(imported.jobs, key: StorageKeys.jobs)
        for pay in imported.payments {
            var bucket = disk.decode([Payment].self, key: disk.paymentKey(invoiceId: pay.invoiceId)) ?? []
            if !bucket.contains(where: { $0.id == pay.id }) {
                bucket.append(pay)
            }
            try disk.encode(bucket, key: disk.paymentKey(invoiceId: pay.invoiceId))
        }
        loadUsersAndProfile()
        customers = imported.customers
        reloadSavedItems()
        reloadSavedJobTemplates()
        reloadJobs()
        reloadEstimates()
        await reloadInvoices()
    }

    func importData(_ data: Data) async throws {
        let imported = try JSONDecoder().decode(ExportData.self, from: data)
        let existing = disk.decode([Invoice].self, key: StorageKeys.invoices) ?? []
        for inv in existing {
            try? disk.remove(disk.paymentKey(invoiceId: inv.id))
        }
        for key in disk.listPaymentStorageKeys() {
            try? disk.remove(key)
        }
        try? disk.remove(StorageKeys.auth)
        try? disk.remove(StorageKeys.users)
        try? disk.remove(StorageKeys.companySettings)
        try? disk.remove(StorageKeys.customers)
        try? disk.remove(StorageKeys.savedItems)
        try? disk.remove(StorageKeys.savedJobTemplates)
        try? disk.remove(StorageKeys.invoices)
        try? disk.remove(StorageKeys.estimates)
        try? disk.remove(StorageKeys.jobs)

        let users: [AppUser] = imported.users.map {
            AppUser(id: $0.id, email: $0.email, companyName: $0.companyName, password: "", companyProfile: $0.companyProfile, createdAt: $0.createdAt)
        }
        try disk.encode(users, key: StorageKeys.users)
        if let p = imported.companyProfile {
            try disk.encode(p, key: StorageKeys.companySettings)
        }
        try disk.encode(imported.customers, key: StorageKeys.customers)
        try disk.encode(imported.savedItems, key: StorageKeys.savedItems)
        try disk.encode(imported.savedJobTemplates, key: StorageKeys.savedJobTemplates)
        try disk.encode(imported.invoices.map { var i = $0; i.payments = nil; return i }, key: StorageKeys.invoices)
        try disk.encode(imported.estimates, key: StorageKeys.estimates)
        try disk.encode(imported.jobs, key: StorageKeys.jobs)
        for pay in imported.payments {
            var bucket = disk.decode([Payment].self, key: disk.paymentKey(invoiceId: pay.invoiceId)) ?? []
            if !bucket.contains(where: { $0.id == pay.id }) {
                bucket.append(pay)
            }
            try disk.encode(bucket, key: disk.paymentKey(invoiceId: pay.invoiceId))
        }
        session = nil
        currentUser = nil
        await bootstrap()
    }

    // MARK: - Dashboard helpers

    func customerMatchesSearch(_ c: Customer) -> Bool {
        let q = customerSearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty { return true }
        return c.name.lowercased().contains(q)
            || (c.displayName ?? "").lowercased().contains(q)
            || c.email.lowercased().contains(q)
    }

    var filteredCustomers: [Customer] {
        customers.filter { customerMatchesSearch($0) }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var filteredInvoices: [Invoice] {
        let q = invoiceSearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return invoices
            .filter { inv in
                if let f = invoiceStatusFilter, inv.status != f { return false }
                if q.isEmpty { return true }
                if inv.invoiceNumber.lowercased().contains(q) { return true }
                if let c = customers.first(where: { $0.id == inv.customerId }) {
                    return c.name.lowercased().contains(q) || c.email.lowercased().contains(q)
                }
                return false
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    /// Matches React Native `DashboardScreen` total revenue: sum of payments on invoices with status `paid`.
    var totalRevenueCollected: Double {
        invoices
            .filter { $0.status == .paid }
            .reduce(0) { sum, inv in
                let paid = (inv.payments ?? []).reduce(0) { $0 + $1.amount }
                return sum + paid
            }
    }

    /// Remaining balance on invoices that are not paid or cancelled (matches RN dashboard `outstanding`).
    var outstandingAmount: Double {
        invoices.reduce(0) { sum, inv in
            guard inv.status != .paid, inv.status != .cancelled else { return sum }
            let paid = (inv.payments ?? []).reduce(0) { $0 + $1.amount }
            return sum + max(0, inv.total - paid)
        }
    }

    var pendingDraftOrSentInvoices: [Invoice] {
        invoices.filter { $0.status == .draft || $0.status == .sent }
    }

    var pendingDraftOrSentAmount: Double {
        pendingDraftOrSentInvoices.reduce(0) { $0 + $1.total }
    }

    var overdueInvoiceCount: Int {
        invoices.filter { $0.status == .overdue }.count
    }

    /// Jobs scheduled for today that are not completed (RN dashboard “Today’s jobs”).
    var todaysActiveJobCount: Int {
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        let end = cal.date(byAdding: .day, value: 1, to: start) ?? start
        return jobs.filter { job in
            guard job.status != .completed else { return false }
            return jobStartDate(job.startDate).map { $0 >= start && $0 < end } ?? false
        }.count
    }

    /// Pending jobs whose start date is before today (RN dashboard “Overdue jobs”).
    var overduePendingJobsCount: Int {
        JobSchedulingHelpers.overduePendingCount(jobs: jobs)
    }

    /// Optional range for filtering overdue jobs when drilling in from the dashboard (matches RN).
    var overdueJobsDashboardRange: JobDateRange? {
        JobSchedulingHelpers.overdueDashboardRange(jobs: jobs)
    }

    private func jobStartDate(_ iso: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: iso) { return d }
        f.formatOptions = [.withInternetDateTime]
        if let d = f.date(from: iso) { return d }
        f.formatOptions = [.withFullDate, .withDashSeparatorInDate]
        return f.date(from: String(iso.prefix(10)))
    }
}
