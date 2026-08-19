import Foundation
import Combine

/// Drives the conversation. Given an intent it mutates the draft and decides what to
/// say next.
///
/// Deterministic and free of any speech or ML dependency: it operates on slots, not
/// words. That is what makes it unit testable and what keeps a second language to a
/// phrase catalog swap.
@MainActor
final class DialogueManager: ObservableObject {
    /// Shared with the on-screen form. Both paths mutate this one instance.
    let draft: InvoiceDraft

    /// The slot the conversation is currently on. The form highlights it, and tapping
    /// a field writes back here so the next thing said lands in the right place.
    @Published var focusedSlot: SlotID?
    @Published private(set) var isAwaitingConfirmation = false
    /// After a description is captured, wait for "yes / that's all" before quantity.
    @Published private(set) var isAwaitingDescriptionConfirm = false
    @Published private(set) var isComplete = false

    /// True once the user has filled several fields by hand in a row. The manager
    /// keeps tracking focus and updating the draft, it just stops talking: someone
    /// working through the form with a keyboard does not want to be narrated at.
    @Published private(set) var isQuiet = false

    /// Consecutive manual fills. Any spoken input resets it.
    private var manualStreak = 0
    /// Chosen by feel rather than principle: one typed field is often a correction
    /// mid-conversation, three is a decision to use the keyboard.
    private let quietThreshold = 3

    private let phrases: PhraseCatalog
    private let resolveCustomer: (String) -> (id: String, name: String)?
    private let customerCandidates: (String) -> [String]

    /// SwiftUI does not observe an ObservableObject nested inside another one, so
    /// the draft's changes are republished through this object. Without it the form
    /// would not redraw when speech filled a field.
    private var draftObserver: AnyCancellable?

    init(
        draft: InvoiceDraft,
        phrases: PhraseCatalog = PhraseCatalog(),
        resolveCustomer: @escaping (String) -> (id: String, name: String)?,
        customerCandidates: @escaping (String) -> [String] = { _ in [] }
    ) {
        self.draft = draft
        self.phrases = phrases
        self.resolveCustomer = resolveCustomer
        self.customerCandidates = customerCandidates

        draftObserver = draft.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
    }

    func opening() -> String {
        focusedSlot = .customer
        return phrases.askCustomer()
    }

    /// Applies an intent and returns the line to speak, or nil to keep listening.
    ///
    /// Spoken input ends any quiet spell: talking to the app is an unambiguous
    /// signal that being talked back to is welcome again.
    func handle(_ intent: VoiceIntent) -> String? {
        manualStreak = 0
        isQuiet = false

        if isAwaitingConfirmation {
            return handleWhileConfirming(intent)
        }

        if isAwaitingDescriptionConfirm {
            return handleDescriptionConfirm(intent)
        }

        switch intent {
        case .setCustomer(let spoken):
            guard let match = resolveCustomer(spoken) else {
                let candidates = customerCandidates(spoken)
                return candidates.isEmpty
                    ? phrases.customerNotFound(spoken)
                    : phrases.customerAmbiguous(candidates)
            }
            draft.setCustomer(id: match.id, name: match.name)
            return advance(prefix: phrases.ack())

        case .itemDescription(let text):
            let index = targetItemIndex(for: .itemDescription(0))
            draft.setDescription(text, at: index)
            isAwaitingDescriptionConfirm = true
            focusedSlot = .itemDescription(index)
            return phrases.confirmDescriptionDone()

        case .confirmDescription:
            // Should only arrive while awaiting description confirm.
            isAwaitingDescriptionConfirm = false
            return advance(prefix: phrases.ack())

        case .quantity(let value):
            draft.setQuantity(value, at: targetItemIndex(for: .itemQuantity(0)))
            return advance(prefix: phrases.ack())

        case .price(let value):
            draft.setUnitPrice(value, at: targetItemIndex(for: .itemPrice(0)))
            return advance(prefix: phrases.ack())

        case .fullItem(let description, let quantity, let price):
            let index = targetItemIndex(for: .itemDescription(0))
            isAwaitingDescriptionConfirm = false
            draft.setDescription(description, at: index)
            draft.setQuantity(quantity, at: index)
            draft.setUnitPrice(price, at: index)
            return advance(prefix: phrases.ack())

        case .setTax(let rate):
            draft.setTaxRate(rate)
            return advance(prefix: phrases.taxSet(rate))

        case .confirmTax:
            draft.setTaxRate(draft.taxRate)
            return advance(prefix: phrases.ack())

        case .addNote(let text):
            draft.notes = [draft.notes, text].compactMap { $0 }.joined(separator: "\n")
            return advance(prefix: phrases.noteAdded())

        case .skip:
            return skipCurrent()

        case .noMoreItems:
            draft.itemsFinished = true
            return advance(prefix: phrases.ack())

        case .moreItems:
            draft.itemsFinished = false
            draft.appendItem()
            let index = draft.items.count - 1
            focusedSlot = .itemDescription(index)
            return phrases.startingNextItem()

        case .finish:
            guard draft.canSave else {
                let reason = draft.saveBlockedReason ?? ""
                return phrases.cannotSaveYet(reason) + " " + (advance() ?? "")
            }
            isAwaitingConfirmation = true
            return phrases.confirmSummary(draft)

        case .undo:
            isAwaitingDescriptionConfirm = false
            draft.removeItem(at: max(draft.items.count - 1, 0))
            return advance(prefix: phrases.removedLastItem())

        case .cancel:
            return phrases.cancelled()

        case .repeatLast:
            return draft.canSave ? phrases.confirmSummary(draft) : advance()

        case .unclear:
            return phrases.didNotCatch(promptForCurrentGap())
        }
    }

    /// "Is that all for the description?" — yes moves on; more words extend it.
    private func handleDescriptionConfirm(_ intent: VoiceIntent) -> String? {
        switch intent {
        case .confirmDescription, .noMoreItems, .finish, .confirmTax:
            isAwaitingDescriptionConfirm = false
            return advance(prefix: phrases.ack())

        case .itemDescription(let text):
            let index = focusedSlot?.itemIndex
                ?? targetItemIndex(for: .itemDescription(0))
            let existing: String
            if draft.items.indices.contains(index) {
                existing = draft.items[index].description.trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                existing = ""
            }
            let combined = existing.isEmpty ? text : existing + " " + text
            draft.setDescription(combined, at: index)
            focusedSlot = .itemDescription(index)
            return phrases.confirmDescriptionDone()

        case .fullItem(let description, let quantity, let price):
            let index = focusedSlot?.itemIndex
                ?? targetItemIndex(for: .itemDescription(0))
            isAwaitingDescriptionConfirm = false
            draft.setDescription(description, at: index)
            draft.setQuantity(quantity, at: index)
            draft.setUnitPrice(price, at: index)
            return advance(prefix: phrases.ack())

        case .skip:
            isAwaitingDescriptionConfirm = false
            return skipCurrent()

        case .unclear:
            return phrases.didNotCatch(phrases.confirmDescriptionDone())

        default:
            // Unexpected slot answers while confirming description: treat as more description text when possible.
            isAwaitingDescriptionConfirm = false
            return handle(intent)
        }
    }

    /// Called when the user taps a field, so speech retargets to what they're looking at.
    func focus(_ slot: SlotID) {
        focusedSlot = slot
    }

    /// Called when a field has been filled by hand rather than spoken. Advances focus
    /// exactly as a spoken answer would, so the form and the conversation stay in
    /// step, and returns the next prompt only if the app is still talking.
    @discardableResult
    func recordManualFill(of slot: SlotID) -> String? {
        guard draft.state(of: slot) != .empty else { return nil }

        manualStreak += 1
        if manualStreak >= quietThreshold { isQuiet = true }

        focusedSlot = slot
        let line = advance()
        return isQuiet ? nil : line
    }

    /// Turns speech back on without needing a spoken word first, for the unmute
    /// control in the mic bar.
    func resumeSpeaking() {
        manualStreak = 0
        isQuiet = false
    }

    // MARK: - Advancing

    /// Moves to the next gap and returns the prompt, optionally prefixed with an
    /// acknowledgement of what just happened.
    private func advance(prefix: String? = nil) -> String? {
        let wasSkipped = focusedSlot.map { draft.state(of: $0) == .skipped } ?? false
        let gap = draft.nextGap

        switch gap {
        case .slot(let slot):
            focusedSlot = slot
            var prompt = promptFor(slot)
            // Name the slot when doubling back, so the user knows where they are.
            if !wasSkipped, draft.state(of: slot) == .skipped {
                prompt = phrases.revisiting(phrases.slotName(slot), prompt: prompt)
            }
            return [prefix, prompt].compactMap { $0 }.joined(separator: " ")

        case .anythingElse:
            focusedSlot = nil
            return [prefix, phrases.askAnythingElse()].compactMap { $0 }.joined(separator: " ")

        case .readyToConfirm:
            guard draft.canSave else {
                focusedSlot = draft.customerId == nil ? .customer : nil
                return [prefix, draft.saveBlockedReason].compactMap { $0 }.joined(separator: " ")
            }
            isAwaitingConfirmation = true
            return [prefix, phrases.confirmSummary(draft)].compactMap { $0 }.joined(separator: " ")
        }
    }

    private func skipCurrent() -> String? {
        isAwaitingDescriptionConfirm = false
        guard let slot = focusedSlot else {
            draft.itemsFinished = true
            return advance()
        }

        draft.skip(slot)
        let acknowledgement: String
        if case .itemQuantity = slot {
            acknowledgement = phrases.quantityAssumed()
        } else {
            acknowledgement = phrases.skipped(phrases.slotName(slot))
        }
        return advance(prefix: acknowledgement)
    }

    private func promptForCurrentGap() -> String? {
        if isAwaitingDescriptionConfirm {
            return phrases.confirmDescriptionDone()
        }
        switch draft.nextGap {
        case .slot(let slot): return promptFor(slot)
        case .anythingElse: return phrases.askAnythingElse()
        case .readyToConfirm: return nil
        }
    }

    private func promptFor(_ slot: SlotID) -> String {
        switch slot {
        case .customer:
            return phrases.askCustomer()
        case .itemDescription(let index):
            return phrases.askDescription(isFirst: index == 0)
        case .itemQuantity:
            return phrases.askQuantity()
        case .itemPrice:
            return phrases.askPrice()
        case .taxRate:
            return phrases.confirmTaxDefault(draft.taxRate)
        }
    }

    /// A bare value ("three", "forty") belongs to whichever item the user is on.
    /// Falls back to the first row still needing that kind of value.
    private func targetItemIndex(for kind: SlotID) -> Int {
        if let focused = focusedSlot, let index = focused.itemIndex {
            return index
        }
        switch kind {
        case .itemDescription:
            return draft.items.firstIndex { !$0.hasDescription } ?? appendedIndex()
        case .itemQuantity:
            return draft.items.firstIndex { ($0.quantity ?? 0) <= 0 } ?? max(draft.items.count - 1, 0)
        case .itemPrice:
            return draft.items.firstIndex { ($0.unitPrice ?? 0) <= 0 } ?? max(draft.items.count - 1, 0)
        case .customer, .taxRate:
            return 0
        }
    }

    private func appendedIndex() -> Int {
        draft.appendItem()
        return draft.items.count - 1
    }

    // MARK: - Confirmation

    private func handleWhileConfirming(_ intent: VoiceIntent) -> String? {
        switch intent {
        case .finish:
            isAwaitingConfirmation = false
            isComplete = true
            return phrases.saving()

        case .cancel, .undo, .skip:
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
}
