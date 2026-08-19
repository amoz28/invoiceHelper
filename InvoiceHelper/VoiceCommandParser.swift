import Foundation

struct VoiceLineItem: Identifiable {
    let id = UUID()
    var description: String
    var quantity: Double
    var unitPrice: Double

    var amount: Double { quantity * unitPrice }
}

struct VoiceCommandResult {
    enum CommandAction {
        case addItems
        case setTaxRate
        case setNotes
        case unknown
    }

    var items: [VoiceLineItem] = []
    var taxRate: Double?
    var notes: String?
    var action: CommandAction = .unknown

    var isEmpty: Bool {
        items.isEmpty && taxRate == nil && (notes?.isEmpty ?? true)
    }
}

/// Turns a dictated sentence into invoice data. Deliberately simple and rule based
/// so it works with no network and stays predictable.
@MainActor
final class VoiceCommandParser: ObservableObject {
    @Published var lastParsedCommand: VoiceCommandResult?
    @Published var error: String?

    private static let numberWords: [String: Double] = [
        "zero": 0, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
        "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10,
        "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14, "fifteen": 15,
        "sixteen": 16, "seventeen": 17, "eighteen": 18, "nineteen": 19, "twenty": 20,
        "thirty": 30, "forty": 40, "fifty": 50, "sixty": 60, "seventy": 70,
        "eighty": 80, "ninety": 90, "hundred": 100,
    ]

    /// Words that carry no meaning in an item description.
    private static let filler = ["add", "item", "an", "a", "of", "please", "invoice", "for"]

    @discardableResult
    func parseCommand(_ rawText: String) -> VoiceCommandResult {
        error = nil
        let text = normalise(rawText)
        guard !text.isEmpty else {
            let empty = VoiceCommandResult()
            lastParsedCommand = empty
            return empty
        }

        let lower = text.lowercased()

        if lower.contains("tax") || lower.contains("vat") {
            return finish(parseTax(text))
        }
        if lower.contains("note") || lower.contains("memo") || lower.contains("terms") {
            return finish(parseNote(text))
        }
        return finish(parseLineItem(text))
    }

    // MARK: - Line items

    /// Matches "2 hours web development at 50", "web design 3 at 120", "5 x cleaning for 40".
    private func parseLineItem(_ text: String) -> VoiceCommandResult {
        var result = VoiceCommandResult()
        result.action = .addItems

        let patterns = [
            // <qty> <description> at|for|@ <price>
            #"(\d+(?:[.,]\d+)?)\s*(?:x\s+)?(.+?)\s+(?:at|for|@|each at)\s+(\d+(?:[.,]\d+)?)"#,
            // <description> <qty> at|for <price>
            #"(.+?)\s+(\d+(?:[.,]\d+)?)\s+(?:at|for|@)\s+(\d+(?:[.,]\d+)?)"#,
        ]

        let ns = text as NSString
        let fullRange = NSRange(location: 0, length: ns.length)

        for (index, pattern) in patterns.enumerated() {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let matches = regex.matches(in: text, options: [], range: fullRange)
            guard !matches.isEmpty else { continue }

            for match in matches where match.numberOfRanges >= 4 {
                // The first pattern puts quantity first; the second puts description first.
                let qtyGroup = index == 0 ? 1 : 2
                let descGroup = index == 0 ? 2 : 1
                let priceGroup = 3

                guard let qty = number(from: ns.substring(with: match.range(at: qtyGroup))),
                      let price = number(from: ns.substring(with: match.range(at: priceGroup))),
                      qty > 0, price > 0 else { continue }

                let description = cleanDescription(ns.substring(with: match.range(at: descGroup)))
                guard !description.isEmpty else { continue }

                result.items.append(VoiceLineItem(description: description, quantity: qty, unitPrice: price))
            }

            // Stop at the first pattern that produced anything, so we do not double count.
            if !result.items.isEmpty { break }
        }

        if result.items.isEmpty {
            let description = cleanDescription(text)
            if !description.isEmpty {
                result.items.append(VoiceLineItem(description: description, quantity: 1, unitPrice: 0))
            }
            error = "No price detected. Try saying it as: two hours web design at fifty."
        }

        return result
    }

    // MARK: - Tax

    private func parseTax(_ text: String) -> VoiceCommandResult {
        var result = VoiceCommandResult()
        result.action = .setTaxRate

        if let value = firstNumber(in: text), value >= 0, value <= 100 {
            result.taxRate = value
        } else {
            error = "No tax percentage detected. Try: set tax to twenty percent."
        }
        return result
    }

    // MARK: - Notes

    private func parseNote(_ text: String) -> VoiceCommandResult {
        var result = VoiceCommandResult()
        result.action = .setNotes

        let ns = text as NSString
        let fullRange = NSRange(location: 0, length: ns.length)
        let pattern = #"(?:notes?|memo|terms)\s*[:\-]?\s*(.+)"#

        if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
           let match = regex.firstMatch(in: text, options: [], range: fullRange),
           match.numberOfRanges >= 2 {
            let note = ns.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
            if !note.isEmpty { result.notes = note }
        }

        if result.notes == nil {
            error = "No note text detected. Try: note, payment due within thirty days."
        }
        return result
    }

    // MARK: - Helpers

    private func finish(_ result: VoiceCommandResult) -> VoiceCommandResult {
        lastParsedCommand = result
        return result
    }

    /// Converts spoken number words to digits so the regexes have something to match.
    private func normalise(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        let words = trimmed.split(separator: " ").map(String.init)
        let converted = words.map { word -> String in
            let stripped = word.trimmingCharacters(in: .punctuationCharacters).lowercased()
            if let value = Self.numberWords[stripped] {
                return formatted(value)
            }
            return word
        }
        return converted.joined(separator: " ")
    }

    private func number(from string: String) -> Double? {
        Double(string.replacingOccurrences(of: ",", with: "."))
    }

    private func firstNumber(in text: String) -> Double? {
        let ns = text as NSString
        let range = NSRange(location: 0, length: ns.length)
        guard let regex = try? NSRegularExpression(pattern: #"\d+(?:[.,]\d+)?"#),
              let match = regex.firstMatch(in: text, options: [], range: range) else { return nil }
        return number(from: ns.substring(with: match.range))
    }

    private func cleanDescription(_ raw: String) -> String {
        let words = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ")
            .map(String.init)
            .filter { !Self.filler.contains($0.lowercased()) }

        let joined = words.joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: " ,.-"))
        return joined.prefix(1).uppercased() + joined.dropFirst()
    }

    private func formatted(_ value: Double) -> String {
        value == value.rounded() ? String(format: "%.0f", value) : String(format: "%.2f", value)
    }
}
