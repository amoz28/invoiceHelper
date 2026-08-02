import Foundation

@MainActor
final class TranslationService: ObservableObject {
    @Published var isTranslating = false
    @Published var error: String?

    /// Simple offline translation dictionary for common invoice terms (Romanian to English)
    private let offlineTranslations: [String: String] = [
        // Numbers
        "unu": "one",
        "doi": "two",
        "trei": "three",
        "patru": "four",
        "cinci": "five",
        "sase": "six",
        "sapte": "seven",
        "opt": "eight",
        "noua": "nine",
        "zece": "ten",
        "douazeci": "twenty",
        "treizeci": "thirty",
        "patruzeci": "forty",
        "cincizeci": "fifty",
        "suta": "hundred",
        "mie": "thousand",

        // Common invoice terms
        "articol": "item",
        "descriere": "description",
        "cantitate": "quantity",
        "pret": "price",
        "taxa": "tax",
        "total": "total",
        "subtotal": "subtotal",
        "client": "customer",
        "factura": "invoice",
        "data": "date",
        "scadenta": "due date",
        "plata": "payment",
        "platit": "paid",
        "neplătit": "unpaid",
        "parțial": "partial",
        "note": "notes",
        "termeni": "terms",
        "adresa": "address",
        "telefon": "phone",
        "email": "email",
        "moneda": "currency",

        // Common actions
        "adauga": "add",
        "sterge": "delete",
        "salveaza": "save",
        "trimite": "send",
        "anuleaza": "cancel",
        "inchide": "close",

        // Common descriptors
        "serviciu": "service",
        "produs": "product",
        "munca": "work",
        "consultanta": "consulting",
        "design": "design",
        "dezvoltare": "development",
        "euro": "euro",
        "leu": "lei",
        "lei": "lei",
    ]

    /// Translates text from Romanian to English using online service with offline fallback
    func translateRomanianToEnglish(_ text: String) async -> String {
        isTranslating = true
        defer { isTranslating = false }

        // First try online translation
        if let translated = await translateOnline(text, from: "ro", to: "en") {
            return translated
        }

        // Fallback to offline translation
        return offlineTranslate(text)
    }

    /// Online translation using Google Translate API (optional fallback)
    private func translateOnline(_ text: String, from: String, to: String) async -> String? {
        let encoded = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? text
        let urlString = "https://api.mymemory.translated.net/get?q=\(encoded)&langpair=\(from)|\(to)"

        guard let url = URL(string: urlString) else {
            error = "Invalid URL"
            return nil
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                error = "Translation service unavailable"
                return nil
            }

            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let responseData = json["responseData"] as? [String: Any],
               let translatedText = responseData["translatedText"] as? String {
                return translatedText
            }
        } catch {
            self.error = "Translation failed: \(error.localizedDescription)"
        }

        return nil
    }

    /// Offline translation using local dictionary
    private func offlineTranslate(_ text: String) -> String {
        let words = text.lowercased()
            .split(separator: " ")
            .map(String.init)

        let translated = words.map { word -> String in
            let cleanWord = word.trimmingCharacters(in: CharacterSet.punctuationCharacters)
            return offlineTranslations[cleanWord] ?? word
        }

        return translated.joined(separator: " ")
    }
}
