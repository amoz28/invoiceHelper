import Foundation

// Domain models aligned with React Native InvoiceHelper `src/types/index.ts`

struct AuthSession: Codable, Equatable {
    var userId: String
    var email: String
}

/// Typed navigation value so plain `String` does not collide with other routes in the same `NavigationStack`.
struct InvoiceDetailNavigationID: Hashable {
    var invoiceId: String
}

struct AppUser: Codable, Identifiable, Equatable {
    var id: String
    var email: String
    var companyName: String
    var password: String
    var companyProfile: CompanyProfile?
    var createdAt: String?
}

struct UserExport: Codable, Equatable {
    var id: String
    var email: String
    var companyName: String
    var companyProfile: CompanyProfile?
    var createdAt: String?
}

struct Address: Codable, Equatable {
    var street: String
    var city: String
    var state: String
    var postalCode: String
    var country: String
}

struct BankDetails: Codable, Equatable {
    var accountName: String
    var accountNumber: String
    var bankName: String
    var swiftCode: String
    var sortCode: String?
    var iban: String?
}

struct CompanyProfile: Codable, Equatable {
    var id: String
    var name: String
    var email: String
    var phone: String
    var website: String?
    /// Optional HTTPS link (e.g. Stripe, PayPal) shown on invoice PDF as a clickable link.
    var paymentLink: String?
    var billingAddress: Address
    var bankDetails: BankDetails
    var currency: String
    var taxId: String?
    var logo: String?
    var isProfileComplete: Bool
    /// Days after invoice date for due date (0 = same day). `nil` means same day.
    var defaultInvoiceDueDaysFromInvoiceDate: Int?
    /// Days from creation for estimate “valid until” (0 = same day). `nil` means same day.
    var defaultEstimateValidDaysFromCreation: Int?
}

struct Customer: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var displayName: String?
    var email: String
    var phone: String?
    var billingAddress: Address
    var notes: String?
    var createdAt: String
    var updatedAt: String
}

struct SavedItem: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var description: String?
    var defaultQuantity: Double
    var defaultUnitPrice: Double
    var createdAt: String
    var updatedAt: String
}

/// Reusable job title/description templates; separate from invoice `SavedItem` catalog.
struct SavedJobTemplate: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var description: String?
    var createdAt: String
    var updatedAt: String
}

struct InvoiceItem: Codable, Identifiable, Equatable {
    var id: String
    var description: String
    var quantity: Double
    var unitPrice: Double
    var amount: Double

    init(id: String = UUID().uuidString, description: String, quantity: Double, unitPrice: Double, amount: Double? = nil) {
        self.id = id
        self.description = description
        self.quantity = quantity
        self.unitPrice = unitPrice
        self.amount = amount ?? (quantity * unitPrice)
    }

    init(id: String = UUID().uuidString, from savedItem: SavedItem) {
        self.id = id
        self.description = savedItem.description?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? savedItem.description!
            : savedItem.name
        self.quantity = savedItem.defaultQuantity
        self.unitPrice = savedItem.defaultUnitPrice
        self.amount = savedItem.defaultQuantity * savedItem.defaultUnitPrice
    }

    enum CodingKeys: String, CodingKey { case id, description, quantity, unitPrice, amount }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        description = try c.decode(String.self, forKey: .description)
        quantity = try c.decode(Double.self, forKey: .quantity)
        unitPrice = try c.decode(Double.self, forKey: .unitPrice)
        let decodedAmount = try c.decodeIfPresent(Double.self, forKey: .amount)
        amount = decodedAmount ?? (quantity * unitPrice)
    }
}

enum PaymentMethod: String, Codable, CaseIterable {
    case BAC
    case Cash
    case Card
}

struct Payment: Codable, Identifiable, Equatable {
    var id: String
    var invoiceId: String
    var amount: Double
    var method: PaymentMethod
    var date: String
    var notes: String?
}

enum InvoiceStatus: String, Codable, CaseIterable {
    case draft
    case sent
    case paid
    case overdue
    case partially_paid
    case cancelled

    /// Human-readable label for UI (matches list filters).
    var displayLabel: String {
        rawValue.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

struct Invoice: Codable, Identifiable, Equatable {
    var id: String
    var invoiceNumber: String
    var customerId: String
    var items: [InvoiceItem]
    var subtotal: Double
    var tax: Double
    var taxRate: Double
    var total: Double
    var status: InvoiceStatus
    var notes: String?
    var terms: String?
    var date: String
    var dueDate: String
    var createdAt: String
    var updatedAt: String
    var payments: [Payment]?
}

struct EstimateItem: Codable, Identifiable, Equatable {
    var id: String
    var description: String
    var quantity: Double
    var unitPrice: Double
    var amount: Double

    enum CodingKeys: String, CodingKey { case id, description, quantity, unitPrice, amount }

    init(id: String = UUID().uuidString, description: String, quantity: Double, unitPrice: Double, amount: Double) {
        self.id = id
        self.description = description
        self.quantity = quantity
        self.unitPrice = unitPrice
        self.amount = amount
    }

    init(id: String = UUID().uuidString, from savedItem: SavedItem) {
        self.id = id
        self.description = savedItem.description?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? savedItem.description!
            : savedItem.name
        self.quantity = savedItem.defaultQuantity
        self.unitPrice = savedItem.defaultUnitPrice
        self.amount = savedItem.defaultQuantity * savedItem.defaultUnitPrice
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        description = try c.decode(String.self, forKey: .description)
        quantity = try c.decode(Double.self, forKey: .quantity)
        unitPrice = try c.decode(Double.self, forKey: .unitPrice)
        let decodedAmount = try c.decodeIfPresent(Double.self, forKey: .amount)
        amount = decodedAmount ?? (quantity * unitPrice)
    }
}

enum EstimateStatus: String, Codable, CaseIterable {
    case pending
    case accepted
    case rejected
    case expired
}

struct Estimate: Codable, Identifiable, Equatable {
    var id: String
    var estimateNumber: String
    var customerId: String
    var items: [EstimateItem]
    var subtotal: Double
    var tax: Double
    var taxRate: Double
    var total: Double
    var status: EstimateStatus
    var notes: String?
    var validUntil: String
    var createdAt: String
    var updatedAt: String
}

enum JobStatus: String, Codable, CaseIterable {
    case pending
    case in_progress
    case completed
    case cancelled
}

enum RecurringFrequency: String, Codable, CaseIterable {
    case monthly
    case sixMonths = "6months"
    case annually
    case none
}

struct JobNoteEntry: Codable, Identifiable, Equatable {
    var id: String
    var text: String
    var createdAt: String
}

struct ScheduledJob: Codable, Identifiable, Equatable {
    var id: String
    var customerId: String?
    var customerName: String
    var title: String
    var description: String?
    var startDate: String
    var endDate: String
    var status: JobStatus
    var isRecurring: Bool
    var recurringFrequency: RecurringFrequency
    var nextOccurrence: String?
    var noteEntries: [JobNoteEntry]
    var customerAddress: String?
    var hasReminder: Bool
    var createdAt: String
    var updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id, customerId, customerName, title, description, startDate, endDate, status
        case isRecurring, recurringFrequency, nextOccurrence, notes, noteEntries, customerAddress, hasReminder, createdAt, updatedAt
    }

    init(
        id: String,
        customerId: String?,
        customerName: String,
        title: String,
        description: String?,
        startDate: String,
        endDate: String,
        status: JobStatus,
        isRecurring: Bool,
        recurringFrequency: RecurringFrequency,
        nextOccurrence: String?,
        noteEntries: [JobNoteEntry],
        customerAddress: String?,
        hasReminder: Bool,
        createdAt: String,
        updatedAt: String
    ) {
        self.id = id
        self.customerId = customerId
        self.customerName = customerName
        self.title = title
        self.description = description
        self.startDate = startDate
        self.endDate = endDate
        self.status = status
        self.isRecurring = isRecurring
        self.recurringFrequency = recurringFrequency
        self.nextOccurrence = nextOccurrence
        self.noteEntries = noteEntries
        self.customerAddress = customerAddress
        self.hasReminder = hasReminder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        customerId = try c.decodeIfPresent(String.self, forKey: .customerId)
        customerName = try c.decode(String.self, forKey: .customerName)
        title = try c.decode(String.self, forKey: .title)
        description = try c.decodeIfPresent(String.self, forKey: .description)
        startDate = try c.decode(String.self, forKey: .startDate)
        endDate = try c.decode(String.self, forKey: .endDate)
        status = try c.decode(JobStatus.self, forKey: .status)
        isRecurring = try c.decode(Bool.self, forKey: .isRecurring)
        recurringFrequency = try c.decode(RecurringFrequency.self, forKey: .recurringFrequency)
        nextOccurrence = try c.decodeIfPresent(String.self, forKey: .nextOccurrence)
        customerAddress = try c.decodeIfPresent(String.self, forKey: .customerAddress)
        hasReminder = try c.decode(Bool.self, forKey: .hasReminder)
        createdAt = try c.decode(String.self, forKey: .createdAt)
        updatedAt = try c.decode(String.self, forKey: .updatedAt)

        if let entries = try c.decodeIfPresent([JobNoteEntry].self, forKey: .noteEntries), !entries.isEmpty {
            noteEntries = entries
        } else if let legacy = try c.decodeIfPresent(String.self, forKey: .notes),
                  !legacy.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            noteEntries = [JobNoteEntry(id: UUID().uuidString, text: legacy, createdAt: createdAt)]
        } else {
            noteEntries = []
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encodeIfPresent(customerId, forKey: .customerId)
        try c.encode(customerName, forKey: .customerName)
        try c.encode(title, forKey: .title)
        try c.encodeIfPresent(description, forKey: .description)
        try c.encode(startDate, forKey: .startDate)
        try c.encode(endDate, forKey: .endDate)
        try c.encode(status, forKey: .status)
        try c.encode(isRecurring, forKey: .isRecurring)
        try c.encode(recurringFrequency, forKey: .recurringFrequency)
        try c.encodeIfPresent(nextOccurrence, forKey: .nextOccurrence)
        try c.encode(noteEntries, forKey: .noteEntries)
        try c.encodeIfPresent(customerAddress, forKey: .customerAddress)
        try c.encode(hasReminder, forKey: .hasReminder)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(updatedAt, forKey: .updatedAt)
    }
}

struct CurrencyOption: Identifiable, Equatable {
    var id: String { code }
    var code: String
    var symbol: String
    var name: String
}

struct ExportData: Codable, Equatable {
    var version: String
    var exportDate: String
    var applicationName: String
    var users: [UserExport]
    var companyProfile: CompanyProfile?
    var customers: [Customer]
    var savedItems: [SavedItem]
    var savedJobTemplates: [SavedJobTemplate]
    var invoices: [Invoice]
    var payments: [Payment]
    var estimates: [Estimate]
    var jobs: [ScheduledJob]

    enum CodingKeys: String, CodingKey {
        case version, exportDate, applicationName, users, companyProfile, customers, savedItems, savedJobTemplates
        case invoices, payments, estimates, jobs
    }

    init(
        version: String,
        exportDate: String,
        applicationName: String,
        users: [UserExport],
        companyProfile: CompanyProfile?,
        customers: [Customer],
        savedItems: [SavedItem],
        savedJobTemplates: [SavedJobTemplate],
        invoices: [Invoice],
        payments: [Payment],
        estimates: [Estimate],
        jobs: [ScheduledJob]
    ) {
        self.version = version
        self.exportDate = exportDate
        self.applicationName = applicationName
        self.users = users
        self.companyProfile = companyProfile
        self.customers = customers
        self.savedItems = savedItems
        self.savedJobTemplates = savedJobTemplates
        self.invoices = invoices
        self.payments = payments
        self.estimates = estimates
        self.jobs = jobs
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(String.self, forKey: .version)
        exportDate = try c.decode(String.self, forKey: .exportDate)
        applicationName = try c.decode(String.self, forKey: .applicationName)
        users = try c.decode([UserExport].self, forKey: .users)
        companyProfile = try c.decodeIfPresent(CompanyProfile.self, forKey: .companyProfile)
        customers = try c.decode([Customer].self, forKey: .customers)
        savedItems = try c.decodeIfPresent([SavedItem].self, forKey: .savedItems) ?? []
        savedJobTemplates = try c.decodeIfPresent([SavedJobTemplate].self, forKey: .savedJobTemplates) ?? []
        invoices = try c.decode([Invoice].self, forKey: .invoices)
        payments = try c.decode([Payment].self, forKey: .payments)
        estimates = try c.decode([Estimate].self, forKey: .estimates)
        jobs = try c.decode([ScheduledJob].self, forKey: .jobs)
    }
}
