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
        pick([
            "Who's this invoice for?",
            "Which customer should I put this under?",
            "Alright — who's it for?",
        ])
    }

    func customerNotFound(_ spoken: String) -> String {
        pick([
            "Hmm, I couldn't find \(spoken) in your customers. Who's it for?",
            "I don't have anyone called \(spoken). Can you say the customer name again?",
        ])
    }

    func customerAmbiguous(_ names: [String]) -> String {
        let list = names.joined(separator: ", or ")
        return pick([
            "Did you mean \(list)?",
            "Just to check — \(list)?",
        ])
    }

    func askDescription(isFirst: Bool) -> String {
        isFirst
            ? pick([
                "What work should I put down?",
                "What did you do for them?",
                "Okay — what's the first item?",
            ])
            : pick([
                "What's next?",
                "What else should I add?",
                "Alright, what's the next item?",
            ])
    }

    /// Asked after a description so a pause mid-sentence does not steal the turn.
    /// All variants share the same yes/no polarity: yes / "that's all" means move on.
    func confirmDescriptionDone() -> String {
        pick([
            "Got it. Is that all for the description?",
            "Okay. Is that the full description?",
            "Thanks. Shall I move on with that description?",
        ])
    }

    func askQuantity() -> String {
        pick([
            "How many?",
            "And how many of those?",
            "Quantity?",
        ])
    }

    func askPrice() -> String {
        pick([
            "And the price?",
            "What's the unit price?",
            "At what rate?",
        ])
    }

    func askAnythingElse() -> String {
        pick([
            "Anything else on this invoice?",
            "Want to add another item?",
            "Is that everything, or one more item?",
        ])
    }

    func confirmTaxDefault(_ rate: Double) -> String {
        pick([
            "Tax is \(number(rate)) percent — does that sound right?",
            "I'll use \(number(rate)) percent tax, okay?",
        ])
    }

    // MARK: - Acknowledgements

    func ack() -> String {
        pick(["Got it.", "Okay.", "Nice.", "Perfect.", "Alright."])
    }

    func skipped(_ what: String) -> String {
        pick([
            "No problem — I'll come back to the \(what).",
            "Okay, skipping the \(what) for now.",
        ])
    }

    func quantityAssumed() -> String {
        pick([
            "I'll put that down as one for now.",
            "Okay, quantity one.",
        ])
    }

    func revisiting(_ what: String, prompt: String) -> String {
        "Just circling back to the \(what). " + prompt
    }

    func taxSet(_ rate: Double) -> String {
        "Okay, tax set to \(number(rate)) percent."
    }

    func noteAdded() -> String {
        pick(["Note added.", "Okay, I've added that note."])
    }

    func removedLastItem() -> String {
        pick(["Removed the last item.", "Okay, that last item's gone."])
    }

    func cancelled() -> String {
        "Alright, I've stopped. Nothing was saved."
    }

    func whatShouldChange() -> String {
        pick([
            "No problem — what should I change?",
            "Okay, what needs changing?",
        ])
    }

    func saving() -> String {
        pick(["Saving it now.", "Okay, saving that for you."])
    }

    func startingNextItem() -> String {
        pick([
            "Sure — what's the next item?",
            "Alright, what should I add?",
            "Okay. What work is next?",
        ])
    }

    func didNotCatch(_ retry: String?) -> String {
        let opener = pick([
            "Sorry, I didn't catch that.",
            "I missed that — one more time?",
            "Hmm, I didn't quite get that.",
        ])
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
    @MainActor
    func confirmSummary(_ draft: InvoiceDraft) -> String {
        var parts: [String] = []
        if let customer = draft.customerName {
            parts.append("So this is for \(customer).")
        }
        for item in draft.completeItems {
            parts.append("\(number(item.quantity ?? 0)) \(item.description) at \(number(item.unitPrice ?? 0)).")
        }
        if draft.taxRate > 0 {
            parts.append("With \(number(draft.taxRate)) percent tax, that comes to \(number(draft.total)).")
        } else {
            parts.append("That comes to \(number(draft.total)).")
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
