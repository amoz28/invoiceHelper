import Foundation

enum InvoiceLogic {
    static let passwordSalt = "invoicehelper_salt_2024"
    static let taxRates: [Double] = [0, 5, 7.5, 10, 12.5, 15, 20, 25]

    static let currencies: [CurrencyOption] = [
        CurrencyOption(code: "GBP", symbol: "£", name: "British Pound"),
        CurrencyOption(code: "NGN", symbol: "₦", name: "Nigerian Naira"),
        CurrencyOption(code: "USD", symbol: "$", name: "US Dollar"),
        CurrencyOption(code: "EUR", symbol: "€", name: "Euro"),
        CurrencyOption(code: "CAD", symbol: "C$", name: "Canadian Dollar"),
        CurrencyOption(code: "GHS", symbol: "₵", name: "Ghanaian Cedi"),
    ]

    static func generateId() -> String {
        let ms = Int(Date().timeIntervalSince1970 * 1000)
        let suffix = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(9)).lowercased()
        return "\(ms)-\(suffix)"
    }

    static func hashPassword(_ password: String) -> String {
        Data((password + passwordSalt).utf8).base64EncodedString()
    }

    static func validateEmail(_ email: String) -> Bool {
        let pattern = #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#
        return email.range(of: pattern, options: .regularExpression) != nil
    }

    static func validatePassword(_ password: String) -> (valid: Bool, errors: [String]) {
        var errors: [String] = []
        if password.count < 8 { errors.append("Password must be at least 8 characters long") }
        if password.range(of: "[A-Z]", options: .regularExpression) == nil {
            errors.append("Password must contain at least one uppercase letter")
        }
        if password.range(of: "[a-z]", options: .regularExpression) == nil {
            errors.append("Password must contain at least one lowercase letter")
        }
        if password.range(of: "[0-9]", options: .regularExpression) == nil {
            errors.append("Password must contain at least one number")
        }
        return (errors.isEmpty, errors)
    }

    static func generateInvoiceNumber(id: String) -> String {
        let lastSix = String(id.suffix(6)).uppercased()
        return "INV-\(lastSix)"
    }

    static func generateEstimateNumber(id: String) -> String {
        let lastSix = String(id.suffix(6)).uppercased()
        return "EST-\(lastSix)"
    }

    static func calculateEstimateTotals(items: [EstimateItem], taxRate: Double) -> (subtotal: Double, tax: Double, total: Double) {
        let subtotal = items.reduce(0) { $0 + ($1.quantity * $1.unitPrice) }
        let tax = subtotal * taxRate / 100
        return (subtotal, tax, subtotal + tax)
    }

    static func isEstimateExpired(validUntil: String) -> Bool {
        guard let d = parseISODate(validUntil) else { return false }
        return d < Date()
    }

    private static func parseISODate(_ iso: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: iso) { return d }
        f.formatOptions = [.withInternetDateTime]
        if let d = f.date(from: iso) { return d }
        f.formatOptions = [.withFullDate, .withDashSeparatorInDate]
        return f.date(from: String(iso.prefix(10)))
    }

    /// Medium-style date for lists and dashboard (ISO invoice `date` / `dueDate` strings).
    static func formatDisplayDate(iso: String) -> String {
        guard let d = parseISODate(iso) else { return iso }
        let out = DateFormatter()
        out.dateStyle = .medium
        return out.string(from: d)
    }

    static func currencySymbol(for code: String) -> String {
        currencies.first { $0.code == code }?.symbol ?? "$"
    }

    static func formatCurrency(amount: Double, code: String) -> String {
        let sym = currencySymbol(for: code)
        return String(format: "%@%.2f", sym, amount)
    }

    static func totalPaid(for invoice: Invoice) -> Double {
        (invoice.payments ?? []).reduce(0) { $0 + $1.amount }
    }

    /// True when recorded payments cover the invoice total (matches detail screen payment button).
    static func isFullyPaid(_ invoice: Invoice) -> Bool {
        totalPaid(for: invoice) >= invoice.total - 0.0001
    }

    static func calculateInvoiceTotals(items: [InvoiceItem], taxRate: Double) -> (subtotal: Double, tax: Double, total: Double) {
        let subtotal = items.reduce(0) { $0 + ($1.quantity * $1.unitPrice) }
        let tax = subtotal * taxRate / 100
        return (subtotal, tax, subtotal + tax)
    }

    private static func calculatePaymentStatus(invoiceTotal: Double, totalPaid: Double) -> String {
        if totalPaid == 0 { return "unpaid" }
        if totalPaid >= invoiceTotal { return "paid" }
        return "partially_paid"
    }

    private static func isInvoiceOverdue(dueDate: String, status: InvoiceStatus, totalPaid: Double) -> Bool {
        if status == .paid || status == .cancelled { return false }
        guard let due = parseISODate(dueDate) else { return false }
        return due < Date()
    }

    static func resolvedInvoiceStatus(dueDate: String, storedStatus: InvoiceStatus, total: Double, totalPaid: Double) -> InvoiceStatus {
        if storedStatus == .cancelled { return .cancelled }
        let pay = calculatePaymentStatus(invoiceTotal: total, totalPaid: totalPaid)
        if pay == "paid" { return .paid }
        if pay == "partially_paid" { return .partially_paid }
        if isInvoiceOverdue(dueDate: dueDate, status: storedStatus, totalPaid: totalPaid) { return .overdue }
        return storedStatus == .paid || storedStatus == .partially_paid ? storedStatus : storedStatus
    }
}
