import Foundation

/// Romanian to English translation. Tries a free online endpoint first, then falls back to a
/// small built in glossary so the feature still works with no network.
@MainActor
final class TranslationService: ObservableObject {
    @Published var isTranslating = false
    @Published var usedOfflineFallback = false

    private static let glossary: [String: String] = [
        // Numbers
        "unu": "1", "una": "1", "doi": "2", "doua": "2", "două": "2", "trei": "3",
        "patru": "4", "cinci": "5", "sase": "6", "șase": "6", "sapte": "7", "șapte": "7",
        "opt": "8", "noua": "9", "nouă": "9", "zece": "10",
        "douazeci": "20", "douăzeci": "20", "treizeci": "30", "patruzeci": "40",
        "cincizeci": "50", "saizeci": "60", "șaizeci": "60", "suta": "100", "sută": "100",

        // Invoice vocabulary
        "factura": "invoice", "factură": "invoice", "articol": "item", "articole": "items",
        "descriere": "description", "cantitate": "quantity", "bucata": "unit", "bucată": "unit",
        "pret": "price", "preț": "price", "taxa": "tax", "taxă": "tax", "tva": "tax",
        "total": "total", "subtotal": "subtotal", "client": "customer", "clientul": "customer",
        "data": "date", "scadenta": "due", "scadență": "due", "plata": "payment", "plată": "payment",
        "platit": "paid", "plătit": "paid", "nota": "note", "notă": "note", "note": "note",
        "observatii": "note", "observații": "note", "termeni": "terms", "moneda": "currency",

        // Actions
        "adauga": "add", "adaugă": "add", "seteaza": "set", "setează": "set",
        "sterge": "delete", "șterge": "delete", "salveaza": "save", "salvează": "save",

        // Units and joining words
        "ora": "hour", "oră": "hour", "ore": "hours", "zi": "day", "zile": "days",
        "la": "at", "pentru": "for", "de": "of", "si": "and", "și": "and",
        "procente": "percent", "procent": "percent", "la suta": "percent",

        // Common work descriptions
        "serviciu": "service", "servicii": "services", "produs": "product", "produse": "products",
        "munca": "work", "muncă": "work", "lucru": "work", "consultanta": "consulting",
        "consultanță": "consulting", "design": "design", "dezvoltare": "development",
        "reparatie": "repair", "reparație": "repair", "instalare": "installation",
        "curatenie": "cleaning", "curățenie": "cleaning", "transport": "transport",
        "materiale": "materials", "manopera": "labour", "manoperă": "labour",
        "euro": "euro", "lei": "lei", "leu": "lei",
    ]

    func translateRomanianToEnglish(_ text: String) async -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        isTranslating = true
        usedOfflineFallback = false
        defer { isTranslating = false }

        if let online = await translateOnline(trimmed), !online.isEmpty {
            return online
        }

        usedOfflineFallback = true
        return offlineTranslate(trimmed)
    }

    /// MyMemory is a free endpoint with no API key. Any failure falls through to the glossary.
    private func translateOnline(_ text: String) async -> String? {
        guard let encoded = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://api.mymemory.translated.net/get?q=\(encoded)&langpair=ro|en")
        else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = 4

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let responseData = json["responseData"] as? [String: Any],
                  let translated = responseData["translatedText"] as? String
            else { return nil }
            return translated.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }

    /// Word by word substitution. Crude, but enough for the short command phrases we expect.
    func offlineTranslate(_ text: String) -> String {
        let words = text.split(separator: " ").map(String.init)
        let mapped = words.map { word -> String in
            let key = word
                .trimmingCharacters(in: .punctuationCharacters)
                .lowercased()
            return Self.glossary[key] ?? word
        }
        return mapped.joined(separator: " ")
    }
}
