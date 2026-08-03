import Foundation

/// Drives the conversation. Given an intent, it mutates the draft and decides what to
/// say next.
///
/// Deliberately deterministic and free of any speech or ML dependency: it operates on
/// slots, not words, which is what keeps it testable and makes a second language a
/// matter of swapping the phrase catalog rather than rewriting the logic.
@MainActor
final class DialogueManager: ObservableObject {
    @Published private(set) var draft = InvoiceDraft()
    @Published private(set) var isAwaitingConfirmation = false
    /// Set when the user has confirmed and the invoice should be written.
    @Published private(set) var isComplete = false

    private let phrases: PhraseCatalog
    /// Looks up a spoken name against the customer list. Injected so the manager
    /// stays free of AppStore.
    private let resolveCustomer: (String) -> (id: String, name: String)?

    init(
        phrases: PhraseCatalog = PhraseCatalog(),
        defaultTaxRate: Double,
        resolveCustomer: @escaping (String) -> (id: String, name: String)?
    ) {
        self.phrases = phrases
        self.resolveCustomer = resolveCustomer
        self.draft.taxRate = defaultTaxRate
    }

    /// The line to open the conversation with.
    func opening() -> String {
        phrases.askCustomer()
    }

    /// Applies an intent and returns what to say next, or nil to keep listening.
    func handle(_ intent: VoiceIntent) -> String? {
        if isAwaitingConfirmation {
            return handleWhileConfirming(intent)
        }

        switch intent {
        case .setCustomer(let spoken):
            guard let match = resolveCustomer(spoken) else {
                return phrases.customerNotFound(spoken)
            }
            draft.customerId = match.id
            draft.customerName = match.name
            return prompt(for: draft.nextGap)

        case .itemDescription(let text):
            draft.startItem(description: text)
            return prompt(for: draft.nextGap)

        case .quantity(let value):
            draft.setQuantity(value)
            return prompt(for: draft.nextGap)

        case .price(let value):
            draft.setUnitPrice(value)
            return prompt(for: draft.nextGap)

        case .fullItem(let description, let quantity, let price):
            draft.startItem(description: description)
            draft.setQuantity(quantity)
            draft.setUnitPrice(price)
            return prompt(for: draft.nextGap)

        case .setTax(let rate):
            draft.taxRate = rate
            return phrases.taxSet(rate)

        case .addNote(let text):
            draft.notes = [draft.notes, text].compactMap { $0 }.joined(separator: "\n")
            return phrases.noteAdded()

        case .finish:
            guard draft.isReadyToConfirm else {
                return prompt(for: draft.nextGap)
            }
            isAwaitingConfirmation = true
            return phrases.confirmSummary(draft)

        case .undo:
            draft.removeLastItem()
            return phrases.removedLastItem()

        case .cancel:
            return phrases.cancelled()

        case .repeatLast:
            return phrases.confirmSummary(draft)

        case .unclear:
            return phrases.didNotCatch(prompt(for: draft.nextGap))
        }
    }

    private func handleWhileConfirming(_ intent: VoiceIntent) -> String? {
        switch intent {
        case .finish:
            isAwaitingConfirmation = false
            isComplete = true
            return phrases.saving()

        case .cancel, .undo:
            isAwaitingConfirmation = false
            return phrases.whatShouldChange()

        case .repeatLast:
            return phrases.confirmSummary(draft)

        default:
            // Anything substantive means they want to keep editing.
            isAwaitingConfirmation = false
            return handle(intent)
        }
    }

    private func prompt(for gap: InvoiceDraft.Gap) -> String {
        switch gap {
        case .customer:
            return phrases.askCustomer()
        case .itemDescription:
            return draft.completeItems.isEmpty ? phrases.askFirstItem() : phrases.askNextItem()
        case .itemQuantity:
            return phrases.askQuantity()
        case .itemPrice:
            return phrases.askPrice()
        case .anythingElse:
            return phrases.askAnythingElse()
        }
    }
}
