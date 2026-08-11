import Foundation

enum WebSearch {
    static func googleURL(for text: String) -> URL? {
        let query = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(2_000))
        guard !query.isEmpty else { return nil }
        var components = URLComponents(string: "https://www.google.com/search")
        components?.queryItems = [URLQueryItem(name: "q", value: query)]
        return components?.url
    }
}
