import Foundation

/// What the user meant. The dialogue manager consumes these; nothing downstream
/// ever sees raw transcript text.
enum VoiceIntent: Equatable {
    case setCustomer(String)
    case itemDescription(String)
    case quantity(Double)
    case price(Double)
    /// A whole item in one breath: "two hours of joinery at forty".
    case fullItem(description: String, quantity: Double, price: Double)
    case setTax(Double)
    /// "Yes", "that's right" when asked to confirm the 20% default.
    case confirmTax
    /// "Yes" / "that's all" after the description confirm question.
    case confirmDescription
    case addNote(String)
    /// "Skip", "leave it", "not sure yet".
    case skip
    /// "That's it", "nothing else" when asked whether to add more.
    case noMoreItems
    /// "Yes" / "add another" when asked "anything else on this invoice?".
    case moreItems
    /// "Save it", "yes" when asked to confirm the whole invoice.
    case finish
    case undo
    case cancel
    case repeatLast
    case unclear
}
