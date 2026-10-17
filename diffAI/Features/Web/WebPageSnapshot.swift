import Foundation

/// A structured picture of a web page, produced by WebPageAnalyzer. Password values are never included.
struct WebPageSnapshot: Codable, Equatable {
    struct Element: Codable, Equatable {
        let index: Int
        /// "link", "button" or "field"
        let kind: String
        let label: String
        let type: String
        let value: String
        let href: String
        var inForm: Bool = false

        /// Sign-in and payment steps are never pressed automatically.
        var isSensitive: Bool {
            if type == "password" { return true }
            let text = " \(label.lowercased()) "
            let keywords = ["pay", "payment", "checkout", "check out", "card", "password", "log in", "login", "sign in", "signin", "sign up", "register", "buy", "order", "purchase", "bank", "transfer", "delete", "unsubscribe", "confirm purchase", "place order"]
            return keywords.contains { text.contains(" \($0) ") || text.contains(" \($0)s ") }
        }

        /// A button that submits a form. Pressing it is the same as submitting, so it needs approval.
        var submitsForm: Bool {
            kind == "button" && inForm && (type == "submit" || label.lowercased().contains("submit"))
        }
    }

    let title: String
    let url: String
    let headings: [String]
    let landmarks: [String]
    let elements: [Element]
    let mainText: String
    let formCount: Int
    let hasPasswordField: Bool

    var links: [Element] {
        elements.filter { $0.kind == "link" }
    }

    /// Finds an element by its number ("number 4", "4") or by words in its label ("search").
    /// Exact label matches win over partial ones.
    func element(matching target: String) -> Element? {
        let clean = target.lowercased().trimmingCharacters(in: .whitespaces)
        let digits = clean.filter(\.isNumber)
        if !digits.isEmpty, clean == digits || clean.hasPrefix("number ") || clean.hasPrefix("link ") || clean.hasPrefix("button "),
           let number = Int(digits) {
            return elements.first { $0.index == number }
        }
        if let exact = elements.first(where: { $0.label.lowercased() == clean }) {
            return exact
        }
        if let wordMatch = elements.first(where: { " \($0.label.lowercased()) ".contains(" \(clean) ") }) {
            return wordMatch
        }
        return elements.first { $0.label.lowercased().contains(clean) }
    }
}
