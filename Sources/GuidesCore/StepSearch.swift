import Foundation

/// Presentation-only query. It never adds metadata or changes guide/export contents.
public enum StepSearch {
    public static func matchingIDs(in document: GuideDocument, query: String) -> [UUID] {
        let q = fold(query.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !q.isEmpty else { return document.steps.map(\.id) }
        return document.steps.filter { fold($0.title).contains(q) || fold($0.body).contains(q) }.map(\.id)
    }
    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_GB"))
    }
}
