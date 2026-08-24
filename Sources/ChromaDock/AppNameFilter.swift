import Foundation

enum AppNameFilter {
    static func containsName(_ label: String, query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return false }
        return label.lowercased().contains(q)
    }
}
