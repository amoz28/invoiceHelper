import Foundation

/// File-backed store using the same logical keys as React Native `src/constants/index.ts` / `storage.ts`.
enum StorageKeys {
    static let auth = "@eazybook/auth"
    static let users = "@eazybook/users"
    static let customers = "@eazybook/customers"
    static let savedItems = "@eazybook/saved_items"
    static let savedJobTemplates = "@eazybook/saved_job_templates"
    static let invoices = "@eazybook/invoices"
    static let estimates = "@eazybook/estimates"
    static let companySettings = "companySettings"
    static let jobs = "jobs"
    static let paymentPrefix = "invoice_payments_"
}

final class LocalPersistence {
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        return e
    }()

    private let decoder = JSONDecoder()

    private var baseURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("InvoiceHelper", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private func fileURL(forKey key: String) -> URL {
        let safe = key
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "@", with: "")
        return baseURL.appendingPathComponent("\(safe).json")
    }

    func readRaw(_ key: String) -> Data? {
        let url = fileURL(forKey: key)
        return try? Data(contentsOf: url)
    }

    func writeRaw(_ data: Data, key: String) throws {
        try data.write(to: fileURL(forKey: key), options: .atomic)
    }

    func remove(_ key: String) throws {
        let url = fileURL(forKey: key)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    func decode<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = readRaw(key) else { return nil }
        return try? decoder.decode(T.self, from: data)
    }

    func encode<T: Encodable>(_ value: T, key: String) throws {
        let data = try encoder.encode(value)
        try writeRaw(data, key: key)
    }

    func paymentKey(invoiceId: String) -> String {
        StorageKeys.paymentPrefix + invoiceId
    }

    func allPaymentKeys(forInvoiceIds ids: [String]) -> [String] {
        ids.map { paymentKey(invoiceId: $0) }
    }

    /// Storage filenames for `invoice_payments_{invoiceId}` keys (no `@` prefix).
    func listPaymentStorageKeys() -> [String] {
        guard let files = try? FileManager.default.contentsOfDirectory(at: baseURL, includingPropertiesForKeys: nil) else { return [] }
        return files
            .map(\.lastPathComponent)
            .filter { $0.hasPrefix("invoice_payments_") && $0.hasSuffix(".json") }
            .map { String($0.dropLast(".json".count)) }
    }
}
