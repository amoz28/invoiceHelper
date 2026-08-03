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
    case addNote(String)
    /// "Skip", "leave it", "not sure yet".
    case skip
    /// "That's it", "nothing else" when asked whether to add more.
    case noMoreItems
    /// "Save it", "yes" when asked to confirm the whole invoice.
    case finish
    case undo
    case cancel
    case repeatLast
    case unclear
}
