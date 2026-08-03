import Foundation

/// Every line the app can say, in one place. The dialogue manager itself has no
/// words in it, so a second language is a catalog swap rather than a rewrite.
///
/// English only for now, by product decision. The dictation sheet keeps Romanian.
struct PhraseCatalog {
    private func pick(_ options: [String]) -> String {
        options.randomElement() ?? options[0]
    }

    // MARK: - Prompts

    func askCustomer() -> String {
        pick(["Who's this invoice for?", "Which customer is this for?"])
    }

    func customerNotFound(_ spoken: String) -> String {
        "I couldn't find \(spoken) in your customers. Who's it for?"
    }

    func customerAmbiguous(_ names: [String]) -> String {
        let list = names.joined(separator: ", or ")
        return "Did you mean \(list)?"
    }

    func askDescription(isFirst: Bool) -> String {
        isFirst
            ? pick(["What did you do for them?", "What's the work?"])
            : pick(["What's the next item?", "What else did you do?"])
    }

    func askQuantity() -> String {
        pick(["How many?", "How many of those?"])
    }

    func askPrice() -> String {
        pick(["At what price?", "What's the rate?"])
    }

    func askAnythingElse() -> String {
        pick(["Anything else on this invoice?", "Is that everything?"])
    }

    func confirmTaxDefault(_ rate: Double) -> String {
        "Tax is \(number(rate)) percent, is that right?"
    }

    // MARK: - Acknowledgements

    func skipped(_ what: String) -> String {
        "Alright, I'll come back to the \(what)."
    }

    func quantityAssumed() -> String {
        "I'll put it down as one for now."
    }

    func revisiting(_ what: String, prompt: String) -> String {
        "Back to the \(what). " + prompt
    }

    func taxSet(_ rate: Double) -> String {
        "Tax set to \(number(rate)) percent."
    }

    func noteAdded() -> String { "Note added." }
    func removedLastItem() -> String { "Removed the last item." }
    func cancelled() -> String { "Alright, I've stopped. Nothing was saved." }
    func whatShouldChange() -> String { "What should I change?" }
    func saving() -> String { "Saving it now." }

    func didNotCatch(_ retry: String?) -> String {
        let opener = pick(["Sorry, I didn't catch that.", "I missed that."])
        guard let retry else { return opener }
        return opener + " " + retry
    }

    /// Spoken when the user tries to finish but a required slot is still empty.
    func cannotSaveYet(_ reason: String) -> String {
        reason
    }

    // MARK: - Read-back

    /// Always names the customer, every line, and the total. This is the user's one
    /// chance to catch a misheard amount before a wrong invoice reaches a client.
    func confirmSummary(_ draft: InvoiceDraft) -> String {
        var parts: [String] = []
        if let customer = draft.customerName {
            parts.append("This is for \(customer).")
        }
        for item in draft.completeItems {
            parts.append("\(number(item.quantity ?? 0)) \(item.description) at \(number(item.unitPrice ?? 0)).")
        }
        if draft.taxRate > 0 {
            parts.append("With \(number(draft.taxRate)) percent tax, the total is \(number(draft.total)).")
        } else {
            parts.append("The total is \(number(draft.total)).")
        }
        parts.append("Shall I save it?")
        return parts.joined(separator: " ")
    }

    /// Human name for a slot, used in skip and revisit lines.
    func slotName(_ slot: SlotID) -> String {
        switch slot {
        case .customer: return "customer"
        case .itemDescription: return "description"
        case .itemQuantity: return "quantity"
        case .itemPrice: return "price"
        case .taxRate: return "tax rate"
        }
    }

    /// Trailing zeros are dropped: synthesis reads "fifty point zero zero" otherwise.
    private func number(_ value: Double) -> String {
        value == value.rounded() ? String(format: "%.0f", value) : String(format: "%.2f", value)
    }
}
