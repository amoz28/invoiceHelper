import Foundation

/// Turns an utterance into an intent, using the current gap as context.
///
/// Matching is meaning-based via `VoiceMeaning` rather than exact catalog strings,
/// so "sounds good", "that'll do", and "one more please" still land correctly.
struct SlotParser {
    private static let numberWords: [String: Double] = [
        "zero": 0, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6,
        "seven": 7, "eight": 8, "nine": 9, "ten": 10, "eleven": 11, "twelve": 12,
        "thirteen": 13, "fourteen": 14, "fifteen": 15, "sixteen": 16, "seventeen": 17,
        "eighteen": 18, "nineteen": 19, "twenty": 20, "thirty": 30, "forty": 40,
        "fifty": 50, "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90,
        "hundred": 100, "a": 1, "an": 1, "couple": 2, "half": 0.5,
    ]

    /// Dropped from item descriptions.
    private static let descriptionFiller = ["i", "did", "we", "add", "put", "down",
                                            "some", "a", "an", "the", "of", "for",
                                            "please", "just", "and"]

    func parse(
        _ utterance: String,
        gap: InvoiceDraft.Gap,
        isConfirming: Bool,
        awaitingDescriptionConfirm: Bool = false
    ) -> VoiceIntent {
        let text = utterance.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return .unclear }

        // Global commands win over slot parsing.
        if VoiceMeaning.isCancel(text) { return .cancel }
        if VoiceMeaning.isRepeat(text) { return .repeatLast }
        if VoiceMeaning.isSkip(text) { return .skip }
        if VoiceMeaning.isUndo(text) { return .undo }

        let lower = text.lowercased()

        // Explicit overrides work at any point in the conversation.
        if lower.contains("tax") || lower.contains("vat") {
            if let rate = firstNumber(in: text), rate >= 0, rate <= 100 {
                return .setTax(rate)
            }
        }
        if let note = noteText(in: text) {
            return .addNote(note)
        }

        // After a description: yes / "that's all" moves on; more words extend it.
        // Bare "no" means the description is incomplete (prompt polarity is "is that all?").
        if awaitingDescriptionConfirm {
            if VoiceMeaning.isBareNegative(text) {
                return .unclear
            }
            if VoiceMeaning.isAffirmative(text) || VoiceMeaning.isDescriptionComplete(text) {
                return .confirmDescription
            }
            if let item = fullItem(in: text) { return item }
            let more = cleanDescription(text)
            return more.isEmpty ? .unclear : .itemDescription(more)
        }

        // Confirming the whole invoice.
        if isConfirming {
            if VoiceMeaning.isFinish(text) || VoiceMeaning.isAffirmative(text) {
                return .finish
            }
        }

        switch gap {
        case .slot(let slot):
            return parse(text, lower: lower, for: slot)

        case .anythingElse:
            if VoiceMeaning.isDoneOrNoMore(text) {
                return .noMoreItems
            }
            if VoiceMeaning.wantsAnotherItem(text) || VoiceMeaning.isAffirmative(text) {
                return .moreItems
            }
            if let item = fullItem(in: text) { return item }
            let more = cleanDescription(text)
            return more.isEmpty ? .unclear : .itemDescription(more)

        case .readyToConfirm:
            if VoiceMeaning.isAffirmative(text) || VoiceMeaning.isFinish(text) {
                return .finish
            }
            if let item = fullItem(in: text) { return item }
            return .unclear
        }
    }

    private func parse(_ text: String, lower: String, for slot: SlotID) -> VoiceIntent {
        switch slot {
        case .customer:
            let cleaned = VoiceMeaning.stripCustomerFiller(text)
            return .setCustomer(cleaned.isEmpty ? text : cleaned)

        case .itemDescription:
            if let item = fullItem(in: text) { return item }
            let description = cleanDescription(text)
            return description.isEmpty ? .unclear : .itemDescription(description)

        case .itemQuantity:
            if let value = firstNumber(in: text), value > 0 { return .quantity(value) }
            return fullItem(in: text) ?? .unclear

        case .itemPrice:
            if let value = firstNumber(in: text), value > 0 { return .price(value) }
            return fullItem(in: text) ?? .unclear

        case .taxRate:
            if VoiceMeaning.isAffirmative(text) { return .confirmTax }
            if let rate = firstNumber(in: text), rate >= 0, rate <= 100 { return .setTax(rate) }
            return .unclear
        }
    }

    // MARK: - Extractors

    /// "two hours of joinery at forty", "3 doors at 120 each".
    private func fullItem(in text: String) -> VoiceIntent? {
        let normalised = normaliseNumbers(text)
        let ns = normalised as NSString
        let range = NSRange(location: 0, length: ns.length)
        let pattern = #"(\d+(?:[.,]\d+)?)\s+(.+?)\s+(?:at|for|@)\s+(\d+(?:[.,]\d+)?)"#

        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: normalised, options: [], range: range),
              match.numberOfRanges >= 4,
              let quantity = double(ns.substring(with: match.range(at: 1))),
              let price = double(ns.substring(with: match.range(at: 3))),
              quantity > 0, price > 0
        else { return nil }

        let description = cleanDescription(ns.substring(with: match.range(at: 2)))
        guard !description.isEmpty else { return nil }
        return .fullItem(description: description, quantity: quantity, price: price)
    }

    private func noteText(in text: String) -> String? {
        let ns = text as NSString
        let range = NSRange(location: 0, length: ns.length)
        let pattern = #"(?:add a note|note that|note|memo)\s*[:,\-]?\s*(.+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges >= 2
        else { return nil }
        let note = ns.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
        return note.isEmpty ? nil : note
    }

    private func firstNumber(in text: String) -> Double? {
        let normalised = normaliseNumbers(text)
        let ns = normalised as NSString
        let range = NSRange(location: 0, length: ns.length)
        guard let regex = try? NSRegularExpression(pattern: #"\d+(?:[.,]\d+)?"#),
              let match = regex.firstMatch(in: normalised, options: [], range: range)
        else { return nil }
        return double(ns.substring(with: match.range))
    }

    private func normaliseNumbers(_ text: String) -> String {
        let tokens = text.split(separator: " ").map(String.init)
        var output: [String] = []
        var pendingTens: Double?

        func flush() {
            if let tens = pendingTens {
                output.append(format(tens))
                pendingTens = nil
            }
        }

        for token in tokens {
            let key = token.trimmingCharacters(in: .punctuationCharacters).lowercased()
            guard let value = Self.numberWords[key] else {
                flush()
                output.append(token)
                continue
            }

            if let tens = pendingTens {
                if tens >= 20, value < 10 {
                    output.append(format(tens + value))
                    pendingTens = nil
                } else {
                    output.append(format(tens))
                    pendingTens = value
                }
            } else if value >= 20, value < 100 {
                pendingTens = value
            } else {
                output.append(format(value))
            }
        }
        flush()
        return output.joined(separator: " ")
    }

    private func cleanDescription(_ raw: String) -> String {
        let words = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ")
            .map(String.init)

        var trimmed = words
        while let first = trimmed.first,
              Self.descriptionFiller.contains(first.lowercased()),
              trimmed.count > 1 {
            trimmed.removeFirst()
        }

        let joined = trimmed.joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: " ,.-"))
        guard !joined.isEmpty else { return "" }
        return joined.prefix(1).uppercased() + joined.dropFirst()
    }

    private func double(_ string: String) -> Double? {
        Double(string.replacingOccurrences(of: ",", with: "."))
    }

    private func format(_ value: Double) -> String {
        value == value.rounded() ? String(format: "%.0f", value) : String(format: "%.2f", value)
    }
}
