import Foundation

/// Matches spoken names against real records, and supplies the vocabulary that
/// biases speech recognition.
///
/// Proper nouns are where recognition fails hardest: "Ionescu" comes back as
/// "you nescu" unless the recognizer has been told the name exists. Seeding
/// contextualStrings with the actual customer list is the single cheapest
/// accuracy win available here, which is why this type serves both jobs.
struct VoiceEntityResolver {
    let customers: [Customer]
    let savedItems: [SavedItem]

    /// Fed to SFSpeechAudioBufferRecognitionRequest.contextualStrings.
    var recognitionVocabulary: [String] {
        let names = customers.flatMap { [$0.name, $0.displayName].compactMap { $0 } }
        let items = savedItems.map(\.name)
        return Array(Set(names + items)).filter { !$0.isEmpty }
    }

    // MARK: - Customers

    /// Returns a confident match, or nil. Deliberately conservative: a wrong
    /// customer means the invoice goes to the wrong person, so an unmatched name
    /// and a re-ask is much cheaper than a confident mistake.
    func resolveCustomer(_ spoken: String) -> (id: String, name: String)? {
        let stripped = VoiceMeaning.stripCustomerFiller(spoken)
        let query = normalise(stripped.isEmpty ? spoken : stripped)
        guard !query.isEmpty else { return nil }

        var scored: [(customer: Customer, score: Double)] = []
        for customer in customers {
            let candidates = [customer.name, customer.displayName].compactMap { $0 }
            let best = candidates.map { score(query: query, candidate: normalise($0)) }.max() ?? 0
            if best > 0 { scored.append((customer, best)) }
        }

        let ranked = scored.sorted { $0.score > $1.score }
        // Slightly softer than before so near-miss dictation ("Acme" / "Ack me") still lands.
        guard let top = ranked.first, top.score >= 0.62 else { return nil }

        // Reject when the runner-up is nearly as good: "Anderson" against both
        // Anderson and Andersen should ask rather than guess.
        if ranked.count > 1, ranked[1].score >= top.score - 0.06, ranked[1].score >= 0.55 {
            return nil
        }

        return (top.customer.id, CustomerHeader.primary(top.customer))
    }

    /// Names close enough to be worth offering when resolveCustomer declines.
    func customerCandidates(_ spoken: String, limit: Int = 3) -> [Customer] {
        let query = normalise(spoken)
        guard !query.isEmpty else { return [] }
        return customers
            .map { ($0, score(query: query, candidate: normalise(CustomerHeader.primary($0)))) }
            .filter { $0.1 >= 0.45 }
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map(\.0)
    }

    // MARK: - Saved items

    /// Lets "add the usual callout charge" resolve to a real price.
    func resolveSavedItem(_ spoken: String) -> SavedItem? {
        let query = normalise(spoken)
        guard !query.isEmpty else { return nil }
        let best = savedItems
            .map { ($0, score(query: query, candidate: normalise($0.name))) }
            .max { $0.1 < $1.1 }
        guard let best, best.1 >= 0.7 else { return nil }
        return best.0
    }

    // MARK: - Scoring

    private func normalise(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// 1.0 exact, 0.9 prefix or contained, otherwise token overlap blended with
    /// edit distance. Good enough for lists of tens to low hundreds of names.
    private func score(query: String, candidate: String) -> Double {
        guard !candidate.isEmpty else { return 0 }
        if query == candidate { return 1.0 }
        if candidate.hasPrefix(query) || query.hasPrefix(candidate) { return 0.9 }
        if candidate.contains(query) || query.contains(candidate) { return 0.85 }

        let queryTokens = Set(query.split(separator: " ").map(String.init))
        let candidateTokens = Set(candidate.split(separator: " ").map(String.init))
        let shared = queryTokens.intersection(candidateTokens).count
        let overlap = Double(shared) / Double(max(queryTokens.count, candidateTokens.count))

        let distance = levenshtein(query, candidate)
        let similarity = 1.0 - Double(distance) / Double(max(query.count, candidate.count))

        return max(overlap, similarity * 0.95)
    }

    private func levenshtein(_ a: String, _ b: String) -> Int {
        let x = Array(a), y = Array(b)
        if x.isEmpty { return y.count }
        if y.isEmpty { return x.count }

        var previous = Array(0...y.count)
        var current = [Int](repeating: 0, count: y.count + 1)

        for i in 1...x.count {
            current[0] = i
            for j in 1...y.count {
                let cost = x[i - 1] == y[j - 1] ? 0 : 1
                current[j] = min(current[j - 1] + 1, previous[j] + 1, previous[j - 1] + cost)
            }
            previous = current
        }
        return previous[y.count]
    }
}
