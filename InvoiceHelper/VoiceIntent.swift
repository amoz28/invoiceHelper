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
    case addNote(String)
    /// "That's it", "done", "yes" when confirming.
    case finish
    /// "Scratch that", "no", "remove that".
    case undo
    case cancel
    case repeatLast
    case unclear
}
