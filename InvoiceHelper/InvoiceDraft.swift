import Foundation

/// A partially built invoice. The dialogue manager fills slots as the user speaks.
/// Deliberately holds no view state and knows nothing about speech.
struct InvoiceDraft: Equatable {
    struct DraftItem: Identifiable, Equatable {
        let id = UUID()
        var description: String
        var quantity: Double?
        var unitPrice: Double?

        var isComplete: Bool {
            !description.trimmingCharacters(in: .whitespaces).isEmpty
                && (quantity ?? 0) > 0
                && (unitPrice ?? 0) > 0
        }

        var amount: Double {
            (quantity ?? 0) * (unitPrice ?? 0)
        }
    }

    var customerId: String?
    var customerName: String?
    var items: [DraftItem] = []
    var taxRate: Double?
    var notes: String?

    /// The item currently being built, which is the last incomplete one.
    var pendingItemIndex: Int? {
        items.indices.last { !items[$0].isComplete }
    }

    var completeItems: [DraftItem] {
        items.filter(\.isComplete)
    }

    var subtotal: Double {
        completeItems.reduce(0) { $0 + $1.amount }
    }

    var total: Double {
        subtotal * (1 + (taxRate ?? 0) / 100)
    }

    /// What the manager still needs before it can offer to save.
    enum Gap: Equatable {
        case customer
        case itemDescription
        case itemQuantity(itemIndex: Int)
        case itemPrice(itemIndex: Int)
        case anythingElse
    }

    /// Ordered by what to ask about next. Customer first, then finish the item in
    /// progress, then offer to wrap up. Tax is never asked about: it defaults from
    /// the company profile and the user can override it by saying so.
    var nextGap: Gap {
        if customerId == nil { return .customer }

        if let index = pendingItemIndex {
            let item = items[index]
            if item.description.trimmingCharacters(in: .whitespaces).isEmpty {
                return .itemDescription
            }
            if (item.quantity ?? 0) <= 0 {
                return .itemQuantity(itemIndex: index)
            }
            if (item.unitPrice ?? 0) <= 0 {
                return .itemPrice(itemIndex: index)
            }
        }

        if completeItems.isEmpty { return .itemDescription }
        return .anythingElse
    }

    var isReadyToConfirm: Bool {
        customerId != nil && !completeItems.isEmpty
    }

    // MARK: - Mutation

    mutating func startItem(description: String) {
        items.append(DraftItem(description: description, quantity: nil, unitPrice: nil))
    }

    /// Applies a value to the item in progress, or to the last complete item when
    /// the user is correcting something they already said.
    mutating func setQuantity(_ value: Double, itemIndex: Int? = nil) {
        guard let index = itemIndex ?? pendingItemIndex ?? items.indices.last else { return }
        guard items.indices.contains(index) else { return }
        items[index].quantity = value
    }

    mutating func setUnitPrice(_ value: Double, itemIndex: Int? = nil) {
        guard let index = itemIndex ?? pendingItemIndex ?? items.indices.last else { return }
        guard items.indices.contains(index) else { return }
        items[index].unitPrice = value
    }

    mutating func removeLastItem() {
        guard !items.isEmpty else { return }
        items.removeLast()
    }
}
