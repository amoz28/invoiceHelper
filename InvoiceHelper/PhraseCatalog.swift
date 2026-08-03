import Foundation

/// Every line the app can say, in one place. Swapping this out is how a second
/// language gets added: the dialogue manager itself has no words in it.
///
/// Lines vary slightly where they repeat often, so a long session does not sound
/// like a phone menu.
struct PhraseCatalog {
    private func pick(_ options: [String]) -> String {
        options.randomElement() ?? options[0]
    }

    func askCustomer() -> String {
        pick(["Who's this invoice for?", "Which customer is this for?"])
    }

    func customerNotFound(_ spoken: String) -> String {
        "I couldn't find \(spoken) in your customers. Who's it for?"
    }

    func askFirstItem() -> String {
        pick(["What did you do for them?", "What's the work?"])
    }

    func askNextItem() -> String {
        pick(["What else?", "Anything else on there?"])
    }

    func askQuantity() -> String {
        pick(["How many?", "How many of those?"])
    }

    func askPrice() -> String {
        pick(["At what price?", "What's the rate?"])
    }

    func askAnythingElse() -> String {
        pick(["Anything else, or shall I read it back?", "Is that everything?"])
    }

    func taxSet(_ rate: Double) -> String {
        "Tax set to \(number(rate)) percent."
    }

    func noteAdded() -> String {
        "Note added."
    }

    func removedLastItem() -> String {
        "Removed the last item."
    }

    func cancelled() -> String {
        "Alright, I've stopped. Nothing was saved."
    }

    func whatShouldChange() -> String {
        "What should I change?"
    }

    func saving() -> String {
        "Saving it now."
    }

    func didNotCatch(_ retry: String?) -> String {
        let opener = pick(["Sorry, I didn't catch that.", "I missed that."])
        guard let retry else { return opener }
        return opener + " " + retry
    }

    /// The read-back before saving. Always includes customer, every line, and the
    /// total, because this is the user's only chance to catch a misheard amount.
    func confirmSummary(_ draft: InvoiceDraft) -> String {
        var parts: [String] = []
        if let customer = draft.customerName {
            parts.append("This is for \(customer).")
        }

        for item in draft.completeItems {
            let quantity = number(item.quantity ?? 0)
            let price = number(item.unitPrice ?? 0)
            parts.append("\(quantity) \(item.description) at \(price).")
        }

        if let rate = draft.taxRate, rate > 0 {
            parts.append("With \(number(rate)) percent tax, the total is \(number(draft.total)).")
        } else {
            parts.append("The total is \(number(draft.total)).")
        }

        parts.append("Shall I save it?")
        return parts.joined(separator: " ")
    }

    /// Speech synthesis reads "50.00" awkwardly, so trailing zeros are dropped.
    private func number(_ value: Double) -> String {
        value == value.rounded()
            ? String(format: "%.0f", value)
            : String(format: "%.2f", value)
    }
}
