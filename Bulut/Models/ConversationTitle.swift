import Foundation

enum ConversationTitle {
    /// The placeholder title taken from the first message until the model names the conversation.
    static func fromFirstMessage(_ text: String) -> String {
        let singleLine = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces)
        guard singleLine.count > 48 else { return singleLine }
        return String(singleLine.prefix(48)).trimmingCharacters(in: .whitespaces) + "…"
    }

    /// First non-empty line of a model-written title, without the quotes, Markdown or
    /// "Başlık:" label some models still add. Nil when nothing usable is left.
    static func clean(_ raw: String) -> String? {
        let markup = CharacterSet(charactersIn: "#*_`\"'“”‘’«».").union(.whitespaces)
        var line = raw
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? ""
        // Markup first, so "**Başlık:** …" and "# Title: …" expose the label.
        line = line.trimmingCharacters(in: markup)
        for label in ["Başlık:", "Title:"] where line.lowercased().hasPrefix(label.lowercased()) {
            line = String(line.dropFirst(label.count))
        }
        line = line.trimmingCharacters(in: markup)
        guard !line.isEmpty else { return nil }
        guard line.count > 60 else { return line }
        return String(line.prefix(60)).trimmingCharacters(in: .whitespaces) + "…"
    }
}
