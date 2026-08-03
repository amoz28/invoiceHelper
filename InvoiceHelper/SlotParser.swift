import Foundation

/// Turns an utterance into an intent, using the current gap as context.
///
/// This is the payoff of directed dialogue. Because the app just asked a narrow
/// question, the expected answer is narrow too: after "how many?" the utterance is
/// almost always a bare number. Parsing per-slot is far more tractable than
/// extracting four fields from one unstructured sentence, and each parser is small
/// enough to unit test exhaustively.
struct SlotParser {
    /// Recognised for any gap, checked before slot-specific parsing.
    private static let finishWords = ["save it", "go ahead", "send it"]
    private static let undoWords = ["scratch that", "remove that", "delete that", "undo",
                                    "no", "nope", "wrong", "not right"]
    private static let cancelWords = ["cancel", "stop", "forget it", "never mind", "nevermind"]
    private static let repeatWords = ["repeat", "say again", "read it back", "what was that"]
    private static let skipWords = ["skip", "skip it", "skip that", "leave it", "leave that",
                                    "not sure", "not sure yet", "don't know", "dont know",
                                    "come back to it", "later", "pass"]
    private static let noMoreWords = ["that's it", "thats it", "that's all", "thats all",
                                      "nothing else", "no more", "no thanks", "that's everything",
                                      "thats everything", "done", "finished"]
    private static let affirmWords = ["yes", "yep", "yeah", "correct", "right", "that's right",
                                      "thats right", "sure", "ok", "okay", "fine"]

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

    func parse(_ utterance: String, gap: InvoiceDraft.Gap, isConfirming: Bool) -> VoiceIntent {
        let text = utterance.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return .unclear }
        let lower = text.lowercased()

        // Global commands win over slot parsing, in priority order. Cancel before
        // undo because "stop" should never be read as a correction.
        if Self.cancelWords.contains(where: { lower == $0 || lower.hasPrefix($0 + " ") }) { return .cancel }
        if Self.repeatWords.contains(where: { lower.contains($0) }) { return .repeatLast }
        if Self.skipWords.contains(where: { lower == $0 }) { return .skip }
        if Self.undoWords.contains(where: { lower == $0 }) { return .undo }

        // Explicit overrides work at any point in the conversation.
        if lower.contains("tax") || lower.contains("vat") {
            if let rate = firstNumber(in: text), rate >= 0, rate <= 100 {
                return .setTax(rate)
            }
        }
        if let note = noteText(in: text) {
            return .addNote(note)
        }

        // Confirming the whole invoice: only yes-shaped answers finish. Anything
        // else falls through to the slot parsers so a correction still lands.
        if isConfirming, Self.affirmWords.contains(lower) || Self.finishWords.contains(where: { lower.hasPrefix($0) }) {
            return .finish
        }

        // Switching on the outer enum first, then the slot. Nested patterns like
        // `case .slot(.customer)` are not reliably proven exhaustive by the
        // compiler, and this reads better anyway.
        switch gap {
        case .slot(let slot):
            return parse(text, lower: lower, for: slot)

        case .anythingElse:
            if Self.noMoreWords.contains(where: { lower == $0 || lower.hasPrefix($0) }) {
                return .noMoreItems
            }
            if Self.affirmWords.contains(lower) { return .unclear }
            if let item = fullItem(in: text) { return item }
            let more = cleanDescription(text)
            return more.isEmpty ? .unclear : .itemDescription(more)

        case .readyToConfirm:
            if Self.affirmWords.contains(lower) { return .finish }
            if let item = fullItem(in: text) { return item }
            return .unclear
        }
    }

    private func parse(_ text: String, lower: String, for slot: SlotID) -> VoiceIntent {
        switch slot {
        case .customer:
            return .setCustomer(text)

        case .itemDescription:
            if Self.noMoreWords.contains(where: { lower == $0 }) { return .noMoreItems }
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
            if Self.affirmWords.contains(lower) { return .confirmTax }
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

    /// Converts spoken number words to digits, handling "twenty five" as 25 rather
    /// than 20 then 5. Speech recognition sometimes returns words, sometimes digits.
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

        // Only strip filler from the front; "a" mid-phrase is often meaningful.
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
