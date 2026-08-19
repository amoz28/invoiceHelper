import Foundation

/// Soft, phrase-tolerant matching for spoken yes/no/commands.
///
/// Speech recognition rarely returns the exact catalog string. Matching on
/// normalised tokens and short synonym groups keeps the dialogue moving when the
/// user says "sounds good", "that'll do", or "one more please".
enum VoiceMeaning {
    // MARK: - Public intents

    static func isAffirmative(_ text: String) -> Bool {
        let t = tokens(text)
        guard !t.isEmpty else { return false }
        if matchesAnyPhrase(t, phrases: affirmPhrases) { return true }
        // Single-token yes-shaped answers.
        if t.count == 1, affirmTokens.contains(t[0]) { return true }
        // "yes please", "yeah that's fine"
        if t.contains(where: { affirmTokens.contains($0) }) {
            // Avoid treating "right" inside unrelated phrases as yes when many tokens.
            if t.count <= 4 { return true }
            if t.contains(where: { ["yes", "yeah", "yep", "yup", "ok", "okay", "sure"].contains($0) }) {
                return true
            }
        }
        return false
    }

    /// "No" / "nope" alone — used when a prompt's polarity makes bare no mean "not yet".
    static func isBareNegative(_ text: String) -> Bool {
        let t = tokens(text)
        return t.count == 1 && ["no", "nope", "nah"].contains(t[0])
    }

    /// Description is finished ("that's all", "move on") — not bare "no".
    static func isDescriptionComplete(_ text: String) -> Bool {
        let t = tokens(text)
        guard !t.isEmpty else { return false }
        if matchesAnyPhrase(t, phrases: descriptionCompletePhrases) { return true }
        if t.count == 1, ["done", "finished", "enough"].contains(t[0]) { return true }
        return false
    }

    /// "No more items" / done adding — not a hard cancel.
    static func isDoneOrNoMore(_ text: String) -> Bool {
        let t = tokens(text)
        guard !t.isEmpty else { return false }
        if matchesAnyPhrase(t, phrases: donePhrases) { return true }
        if t.count == 1, ["no", "nope", "nah", "none", "nothing", "done", "finished"].contains(t[0]) {
            return true
        }
        // "no thanks", "no more", "nothing else"
        if t.contains("no") || t.contains("nope") || t.contains("nah") {
            if t.contains(where: { ["more", "thanks", "thank", "else", "items", "item"].contains($0) }) {
                return true
            }
            if t.count <= 2 { return true }
        }
        return false
    }

    static func wantsAnotherItem(_ text: String) -> Bool {
        let t = tokens(text)
        guard !t.isEmpty else { return false }
        if matchesAnyPhrase(t, phrases: moreItemPhrases) { return true }
        // Affirmative alone when asked "anything else?" is handled by the caller
        // via isAffirmative — here catch explicit add-another language.
        if t.contains("another") || t.contains("more") {
            if t.contains(where: { ["add", "item", "one", "please", "yes", "yeah"].contains($0) }) {
                return true
            }
            if t.count <= 2 { return true }
        }
        return false
    }

    static func isSkip(_ text: String) -> Bool {
        matchesAnyPhrase(tokens(text), phrases: skipPhrases)
            || (tokens(text).count == 1 && ["skip", "pass", "later"].contains(tokens(text)[0]))
    }

    static func isCancel(_ text: String) -> Bool {
        matchesAnyPhrase(tokens(text), phrases: cancelPhrases)
    }

    static func isRepeat(_ text: String) -> Bool {
        matchesAnyPhrase(tokens(text), phrases: repeatPhrases)
    }

    static func isUndo(_ text: String) -> Bool {
        matchesAnyPhrase(tokens(text), phrases: undoPhrases)
    }

    static func isFinish(_ text: String) -> Bool {
        matchesAnyPhrase(tokens(text), phrases: finishPhrases) || isAffirmative(text)
    }

    /// "it's for Acme" / "customer Acme Ltd" → "Acme Ltd" (original casing kept).
    static func stripCustomerFiller(_ text: String) -> String {
        let raw = text
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        let fillers: Set<String> = [
            "it", "its", "is", "for", "the", "customer", "client", "company",
            "invoice", "under", "name", "called", "please", "put", "this",
        ]
        var kept = raw
        while let first = kept.first, fillers.contains(first.lowercased()) { kept.removeFirst() }
        while let last = kept.last, fillers.contains(last.lowercased()) { kept.removeLast() }
        return kept.joined(separator: " ")
    }

    // MARK: - Matching

    private static func tokens(_ text: String) -> [String] {
        text
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    private static func matchesAnyPhrase(_ textTokens: [String], phrases: [[String]]) -> Bool {
        for phrase in phrases {
            if containsSequence(textTokens, phrase) { return true }
        }
        return false
    }

    private static func containsSequence(_ haystack: [String], _ needle: [String]) -> Bool {
        guard !needle.isEmpty else { return false }
        guard haystack.count >= needle.count else {
            return haystack == needle
        }
        if haystack == needle { return true }
        let last = haystack.count - needle.count
        for i in 0...last {
            if Array(haystack[i..<(i + needle.count)]) == needle { return true }
        }
        return false
    }

    // MARK: - Phrase tables (tokenised)

    private static let affirmTokens: Set<String> = [
        "yes", "yeah", "yep", "yup", "ok", "okay", "sure", "correct", "fine",
        "absolutely", "definitely", "aye",
    ]

    private static let affirmPhrases: [[String]] = [
        ["yes"], ["yeah"], ["yep"], ["yup"], ["ok"], ["okay"], ["sure"],
        ["correct"], ["right"], ["fine"], ["please"],
        ["thats", "right"], ["that", "is", "right"],
        ["sounds", "good"], ["sounds", "right"], ["thats", "fine"], ["that", "is", "fine"],
        ["yes", "please"], ["yeah", "please"], ["go", "ahead"], ["move", "on"],
        ["thats", "it"], ["that", "is", "it"], // when confirming description / tax
        ["go", "for", "it"], ["do", "it"], ["looks", "good"], ["thats", "ok"],
        ["thats", "okay"], ["all", "good"], ["perfect"], ["great"],
    ]

    private static let descriptionCompletePhrases: [[String]] = [
        ["thats", "all"], ["that", "is", "all"], ["thats", "it"], ["that", "is", "it"],
        ["thats", "everything"], ["that", "is", "everything"], ["move", "on"],
        ["thats", "the", "lot"], ["full", "description"], ["nothing", "more"],
        ["no", "more"], ["im", "done"], ["i", "am", "done"], ["thatll", "do"],
        ["that", "will", "do"],
    ]

    private static let donePhrases: [[String]] = [
        ["no"], ["nope"], ["nah"], ["nothing"], ["none"], ["done"], ["finished"],
        ["thats", "it"], ["thats", "all"], ["that", "is", "it"], ["that", "is", "all"],
        ["nothing", "else"], ["no", "more"], ["no", "thanks"], ["thats", "everything"],
        ["that", "is", "everything"], ["im", "done"], ["i", "am", "done"],
        ["thatll", "do"], ["that", "will", "do"], ["no", "thats", "it"],
        ["no", "thats", "all"], ["enough"], ["stop", "there"],
    ]

    private static let moreItemPhrases: [[String]] = [
        ["add", "another"], ["another", "one"], ["one", "more"], ["add", "one", "more"],
        ["another", "item"], ["add", "more"], ["yes", "another"], ["yeah", "another"],
        ["add", "an", "item"], ["new", "item"], ["plus", "one"],
    ]

    private static let skipPhrases: [[String]] = [
        ["skip"], ["skip", "it"], ["skip", "that"], ["leave", "it"], ["leave", "that"],
        ["not", "sure"], ["not", "sure", "yet"], ["dont", "know"], ["do", "not", "know"],
        ["come", "back", "to", "it"], ["later"], ["pass"], ["next"],
    ]

    private static let cancelPhrases: [[String]] = [
        ["cancel"], ["stop"], ["forget", "it"], ["never", "mind"], ["nevermind"],
        ["abort"], ["quit"],
    ]

    private static let repeatPhrases: [[String]] = [
        ["repeat"], ["say", "again"], ["read", "it", "back"], ["what", "was", "that"],
        ["pardon"], ["come", "again"],
    ]

    private static let undoPhrases: [[String]] = [
        ["scratch", "that"], ["remove", "that"], ["delete", "that"], ["undo"],
        ["wrong"], ["not", "right"], ["go", "back"],
    ]

    private static let finishPhrases: [[String]] = [
        ["save", "it"], ["save"], ["go", "ahead"], ["send", "it"], ["create", "it"],
        ["finish"], ["confirm"], ["yes", "save"],
    ]
}
