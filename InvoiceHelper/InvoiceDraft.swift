import Foundation

/// Identifies one answerable field. Item slots carry their index because items repeat.
enum SlotID: Hashable {
    case customer
    case itemDescription(Int)
    case itemQuantity(Int)
    case itemPrice(Int)
    case taxRate

    var itemIndex: Int? {
        switch self {
        case .itemDescription(let i), .itemQuantity(let i), .itemPrice(let i): return i
        case .customer, .taxRate: return nil
        }
    }
}

/// Derived, never stored, so a slot's state can't drift out of sync with its value.
enum SlotState: Equatable {
    case empty
    case filled
    /// Value was inferred rather than given, e.g. a skipped quantity defaulting to 1.
    case assumed
    /// Skipped once. Will be asked again on the revisit pass.
    case skipped
    /// Skipped twice. Never asked again, but still editable by tapping.
    case skippedFinal
}

/// A partially built invoice. Holds no view state and knows nothing about speech.
///
/// ObservableObject rather than a struct because the conversation and the on-screen
/// form both mutate the same instance. Two sources of truth cannot support filling a
/// field by voice and then correcting it by hand.
@MainActor
final class InvoiceDraft: ObservableObject {
    struct DraftItem: Identifiable, Equatable {
        let id = UUID()
        var description: String = ""
        var quantity: Double?
        var unitPrice: Double?

        var hasDescription: Bool {
            !description.trimmingCharacters(in: .whitespaces).isEmpty
        }
        var isComplete: Bool {
            hasDescription && (quantity ?? 0) > 0 && (unitPrice ?? 0) > 0
        }
        var amount: Double { (quantity ?? 0) * (unitPrice ?? 0) }
    }

    @Published var customerId: String?
    @Published var customerName: String?
    @Published var items: [DraftItem] = [DraftItem()]
    /// Pre-filled rather than empty: tax is confirmed, not asked from scratch.
    @Published var taxRate: Double = 20
    @Published var notes: String?

    /// Skipped once, awaiting the revisit pass.
    @Published private(set) var skipped: Set<SlotID> = []
    /// Skipped twice, left alone.
    @Published private(set) var skippedFinal: Set<SlotID> = []
    /// Values the app inferred rather than heard, shown differently in the form.
    @Published private(set) var assumed: Set<SlotID> = []
    /// Set once the user says there is nothing more to add.
    @Published var itemsFinished = false
    /// Set once the 20% default has been accepted or overridden.
    @Published var taxConfirmed = false

    // MARK: - Slot state

    func state(of slot: SlotID) -> SlotState {
        if hasValue(slot) {
            return assumed.contains(slot) ? .assumed : .filled
        }
        if skippedFinal.contains(slot) { return .skippedFinal }
        if skipped.contains(slot) { return .skipped }
        return .empty
    }

    private func hasValue(_ slot: SlotID) -> Bool {
        switch slot {
        case .customer:
            return customerId != nil
        case .taxRate:
            return taxConfirmed
        case .itemDescription(let i):
            return items.indices.contains(i) && items[i].hasDescription
        case .itemQuantity(let i):
            return items.indices.contains(i) && (items[i].quantity ?? 0) > 0
        case .itemPrice(let i):
            return items.indices.contains(i) && (items[i].unitPrice ?? 0) > 0
        }
    }

    /// Every slot in the order they are asked about. Tax sits last because it applies
    /// to the whole invoice, so asking it once beats asking it per item.
    var orderedSlots: [SlotID] {
        var slots: [SlotID] = [.customer]
        for index in items.indices {
            slots.append(.itemDescription(index))
            slots.append(.itemQuantity(index))
            slots.append(.itemPrice(index))
        }
        slots.append(.taxRate)
        return slots
    }

    enum Gap: Equatable {
        case slot(SlotID)
        case anythingElse
        case readyToConfirm
    }

    /// First empty slot, then a chance to add more items, then anything skipped, then
    /// tax, then done. One rule gives "come back to it" with no special-case logic.
    var nextGap: Gap {
        let itemSlots = orderedSlots.filter { $0 != .taxRate }

        if let empty = itemSlots.first(where: { state(of: $0) == .empty }) {
            return .slot(empty)
        }
        if !itemsFinished, hasAnyCompleteItem {
            return .anythingElse
        }
        if let revisit = itemSlots.first(where: { state(of: $0) == .skipped }) {
            return .slot(revisit)
        }
        if !taxConfirmed {
            return .slot(.taxRate)
        }
        return .readyToConfirm
    }

    // MARK: - Saving

    var hasAnyCompleteItem: Bool {
        items.contains(\.isComplete)
    }

    var completeItems: [DraftItem] {
        items.filter(\.isComplete)
    }

    /// Saving needs a customer and at least one complete item. Tax never blocks,
    /// since it always has a value.
    var canSave: Bool {
        customerId != nil && hasAnyCompleteItem
    }

    /// Why saving is blocked, for the form's footer and the spoken prompt.
    var saveBlockedReason: String? {
        if customerId == nil { return "Choose a customer before saving." }
        if !hasAnyCompleteItem { return "Add at least one item with a description and a price." }
        return nil
    }

    var subtotal: Double { completeItems.reduce(0) { $0 + $1.amount } }
    var tax: Double { subtotal * taxRate / 100 }
    var total: Double { subtotal + tax }

    // MARK: - Mutation

    func setCustomer(id: String, name: String) {
        customerId = id
        customerName = name
        clearSkip(.customer)
    }

    func setDescription(_ text: String, at index: Int) {
        guard items.indices.contains(index) else { return }
        items[index].description = text
        clearSkip(.itemDescription(index))
    }

    func setQuantity(_ value: Double, at index: Int, assumed isAssumed: Bool = false) {
        guard items.indices.contains(index) else { return }
        items[index].quantity = value
        let slot = SlotID.itemQuantity(index)
        clearSkip(slot)
        if isAssumed { assumed.insert(slot) } else { assumed.remove(slot) }
    }

    func setUnitPrice(_ value: Double, at index: Int) {
        guard items.indices.contains(index) else { return }
        items[index].unitPrice = value
        clearSkip(.itemPrice(index))
    }

    func setTaxRate(_ value: Double) {
        taxRate = value
        taxConfirmed = true
        clearSkip(.taxRate)
    }

    /// Skipping a quantity fills it with 1 rather than leaving a hole, because an
    /// unquantified line is almost always one of something.
    func skip(_ slot: SlotID) {
        if case .itemQuantity(let index) = slot {
            setQuantity(1, at: index, assumed: true)
            return
        }
        if case .taxRate = slot {
            taxConfirmed = true
            assumed.insert(.taxRate)
            return
        }

        if skipped.contains(slot) {
            skipped.remove(slot)
            skippedFinal.insert(slot)
        } else {
            skipped.insert(slot)
        }
    }

    private func clearSkip(_ slot: SlotID) {
        skipped.remove(slot)
        skippedFinal.remove(slot)
    }

    func appendItem() {
        items.append(DraftItem())
        itemsFinished = false
    }

    func removeItem(at index: Int) {
        guard items.indices.contains(index), items.count > 1 else { return }
        items.remove(at: index)
        // Slot IDs carry indices, so any skip state past the removed row is stale.
        skipped = skipped.filter { ($0.itemIndex ?? -1) < index }
        skippedFinal = skippedFinal.filter { ($0.itemIndex ?? -1) < index }
        assumed = assumed.filter { ($0.itemIndex ?? -1) < index }
    }
}
