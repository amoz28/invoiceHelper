import Foundation

struct VoiceLineItem {
    var description: String
    var quantity: Double
    var unitPrice: Double

    var amount: Double { quantity * unitPrice }
}

struct VoiceCommandResult {
    var items: [VoiceLineItem] = []
    var taxRate: Double?
    var notes: String?
    var action: CommandAction = .addItems

    enum CommandAction {
        case addItems
        case setTaxRate
        case setNotes
        case unknown
    }
}

@MainActor
final class VoiceCommandParser: ObservableObject {
    @Published var lastParsedCommand: VoiceCommandResult?
    @Published var error: String?

    /// Parse natural language command to extract invoice data
    func parseCommand(_ text: String) -> VoiceCommandResult {
        error = nil
        let lowercased = text.lowercased()

        // Detect tax rate commands
        if lowercased.contains("tax") || lowercased.contains("vat") {
            return parseTaxCommand(text)
        }

        // Detect note commands
        if lowercased.contains("note") || lowercased.contains("memo") {
            return parseNoteCommand(text)
        }

        // Default: parse as line item(s)
        return parseLineItems(text)
    }

    /// Parse line item from voice: "Add item: 2 hours web development at 50 euros"
    private func parseLineItems(_ text: String) -> VoiceCommandResult {
        var result = VoiceCommandResult()

        let patterns = [
            // Pattern: "quantity description at price"
            try? NSRegularExpression(pattern: "(\\d+(?:\\.\\d+)?)\\s+(.+?)\\s+(?:at|for|@)\\s+(\\d+(?:\\.\\d+)?)", options: .caseInsensitive),
            // Pattern: "description quantity price"
            try? NSRegularExpression(pattern: "(.+?)\\s+(\\d+(?:\\.\\d+)?)\\s+(?:units?|items?)?\\s+(\\d+(?:\\.\\d+)?)", options: .caseInsensitive),
        ]

        let nsString = text as NSString
        let range = NSRange(location: 0, length: nsString.length)

        for pattern in patterns.compactMap({ $0 }) {
            let matches = pattern.matches(in: text, options: [], range: range)

            for match in matches {
                if match.numberOfRanges >= 4 {
                    let quantityRange = match.range(at: 1)
                    let descRange = match.range(at: 2)
                    let priceRange = match.range(at: 3)

                    if let qty = Double(nsString.substring(with: quantityRange)),
                       let price = Double(nsString.substring(with: priceRange)) {
                        let desc = nsString.substring(with: descRange).trimmingCharacters(in: .whitespaces)

                        if !desc.isEmpty && qty > 0 && price > 0 {
                            result.items.append(VoiceLineItem(
                                description: desc,
                                quantity: qty,
                                unitPrice: price
                            ))
                        }
                    }
                }
            }
        }

        // Fallback: if no structured pattern matched, treat entire text as description
        if result.items.isEmpty {
            let cleanedText = text.trimmingCharacters(in: .whitespaces)
            if !cleanedText.isEmpty {
                result.items.append(VoiceLineItem(
                    description: cleanedText,
                    quantity: 1,
                    unitPrice: 0  // Price not specified
                ))
                error = "Could not extract price. Please say: 'Item description, quantity, and price'"
            }
        }

        result.action = .addItems
        lastParsedCommand = result
        return result
    }

    /// Parse tax rate from voice: "Set tax to 20 percent"
    private func parseTaxCommand(_ text: String) -> VoiceCommandResult {
        var result = VoiceCommandResult()
        result.action = .setTaxRate

        let pattern = try? NSRegularExpression(pattern: "(\\d+(?:\\.\\d+)?)", options: .caseInsensitive)
        let nsString = text as NSString
        let range = NSRange(location: 0, length: nsString.length)

        if let match = pattern?.firstMatch(in: text, options: [], range: range) {
            if let taxStr = Double(nsString.substring(with: match.range)) {
                result.taxRate = taxStr
            }
        }

        lastParsedCommand = result
        return result
    }

    /// Parse notes from voice: "Add note: Payment due within 30 days"
    private func parseNoteCommand(_ text: String) -> VoiceCommandResult {
        var result = VoiceCommandResult()
        result.action = .setNotes

        // Extract everything after "note:" or "memo:"
        let patterns = [
            try? NSRegularExpression(pattern: "note[:]?\\s+(.+)", options: .caseInsensitive),
            try? NSRegularExpression(pattern: "memo[:]?\\s+(.+)", options: .caseInsensitive),
        ]

        let nsString = text as NSString
        let range = NSRange(location: 0, length: nsString.length)

        for pattern in patterns.compactMap({ $0 }) {
            if let match = pattern.firstMatch(in: text, options: [], range: range) {
                if match.numberOfRanges >= 2 {
                    let noteRange = match.range(at: 1)
                    result.notes = nsString.substring(with: noteRange).trimmingCharacters(in: .whitespaces)
                    break
                }
            }
        }

        lastParsedCommand = result
        return result
    }

    /// Extract numbers (written as words) to digits
    private func wordNumberToDigit(_ word: String) -> Double? {
        let numberWords: [String: Double] = [
            "zero": 0, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
            "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10,
            "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14, "fifteen": 15,
            "sixteen": 16, "seventeen": 17, "eighteen": 18, "nineteen": 19, "twenty": 20,
            "thirty": 30, "forty": 40, "fifty": 50, "sixty": 60, "seventy": 70,
            "eighty": 80, "ninety": 90, "hundred": 100, "thousand": 1000,
        ]
        return numberWords[word.lowercased()]
    }
}
