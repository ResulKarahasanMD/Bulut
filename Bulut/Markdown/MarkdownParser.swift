import Foundation

/// A small block-level Markdown parser for chat replies. Inline syntax (bold, italic, `code`, links)
/// is left inside the text and rendered by `AttributedString(markdown:)`.
enum MarkdownBlock: Hashable, Sendable {
    case paragraph(String)
    case heading(level: Int, text: String)
    case code(language: String?, code: String)
    case listItem(indent: Int, marker: String, text: String)
    case quote(String)
    case table(header: [String], rows: [[String]])
    case rule
}

enum MarkdownParser {
    static func parse(_ text: String) -> [MarkdownBlock] {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        var quote: [String] = []
        var index = 0

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            blocks.append(.paragraph(paragraph.joined(separator: "\n")))
            paragraph.removeAll()
        }

        func flushQuote() {
            guard !quote.isEmpty else { return }
            blocks.append(.quote(quote.joined(separator: "\n")))
            quote.removeAll()
        }

        func flushAll() {
            flushParagraph()
            flushQuote()
        }

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Fenced code block (an unclosed fence while streaming runs to the end).
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                flushAll()
                let fence = String(trimmed.prefix(3))
                let language = trimmed.dropFirst(3).trimmingCharacters(in: .whitespaces)
                var code: [String] = []
                index += 1
                while index < lines.count {
                    if lines[index].trimmingCharacters(in: .whitespaces).hasPrefix(fence) { break }
                    code.append(lines[index])
                    index += 1
                }
                blocks.append(.code(language: language.isEmpty ? nil : language, code: code.joined(separator: "\n")))
                index += 1
                continue
            }

            if trimmed.isEmpty {
                flushAll()
                index += 1
                continue
            }

            if trimmed.hasPrefix(">") {
                flushParagraph()
                var content = trimmed.dropFirst()
                if content.hasPrefix(" ") { content = content.dropFirst() }
                quote.append(String(content))
                index += 1
                continue
            }
            flushQuote()

            if let heading = parseHeading(trimmed) {
                flushParagraph()
                blocks.append(heading)
                index += 1
                continue
            }

            if isRule(trimmed) {
                flushParagraph()
                blocks.append(.rule)
                index += 1
                continue
            }

            if trimmed.hasPrefix("|") {
                var tableLines: [String] = []
                var cursor = index
                while cursor < lines.count {
                    let candidate = lines[cursor].trimmingCharacters(in: .whitespaces)
                    guard candidate.hasPrefix("|") else { break }
                    tableLines.append(candidate)
                    cursor += 1
                }
                if let table = parseTable(tableLines) {
                    flushParagraph()
                    blocks.append(table)
                    index = cursor
                    continue
                }
            }

            if let item = parseListItem(line) {
                flushParagraph()
                blocks.append(item)
                index += 1
                continue
            }

            paragraph.append(trimmed)
            index += 1
        }

        flushAll()
        return blocks
    }

    // MARK: Pieces

    private static func parseHeading(_ trimmed: String) -> MarkdownBlock? {
        let hashes = trimmed.prefix { $0 == "#" }.count
        guard (1...6).contains(hashes) else { return nil }
        let rest = trimmed.dropFirst(hashes)
        guard rest.isEmpty || rest.hasPrefix(" ") else { return nil }
        let text = rest.trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
            .trimmingCharacters(in: .whitespaces)
        return .heading(level: hashes, text: text)
    }

    private static func isRule(_ trimmed: String) -> Bool {
        let compact = trimmed.replacingOccurrences(of: " ", with: "")
        guard compact.count >= 3, let first = compact.first, "-*_".contains(first) else { return false }
        return compact.allSatisfy { $0 == first }
    }

    private static func parseListItem(_ line: String) -> MarkdownBlock? {
        let leading = line.prefix { $0 == " " || $0 == "\t" }
        let spaces = leading.reduce(0) { $0 + ($1 == "\t" ? 4 : 1) }
        let indent = min(spaces / 2, 4)
        let body = line.dropFirst(leading.count)

        // Unordered: "- ", "* ", "+ "
        if let first = body.first, "-*+".contains(first), body.dropFirst().hasPrefix(" ") {
            var text = body.dropFirst(2).trimmingCharacters(in: .whitespaces)
            var marker = "•"
            if text.hasPrefix("[ ] ") {
                marker = "☐"
                text = String(text.dropFirst(4))
            } else if text.lowercased().hasPrefix("[x] ") {
                marker = "☑"
                text = String(text.dropFirst(4))
            }
            return .listItem(indent: indent, marker: marker, text: text)
        }

        // Ordered: "1. " or "1) "
        let digits = body.prefix { $0.isASCII && $0.isNumber }
        if !digits.isEmpty, digits.count <= 4 {
            let afterDigits = body.dropFirst(digits.count)
            if let separator = afterDigits.first, separator == "." || separator == ")",
               afterDigits.dropFirst().hasPrefix(" ") {
                let text = afterDigits.dropFirst(2).trimmingCharacters(in: .whitespaces)
                return .listItem(indent: indent, marker: "\(digits).", text: text)
            }
        }
        return nil
    }

    private static func parseTable(_ lines: [String]) -> MarkdownBlock? {
        guard lines.count >= 2 else { return nil }
        let rows = lines.map(splitRow)
        guard isSeparatorRow(rows[1]) else { return nil }
        let header = rows[0]
        let body = rows.dropFirst(2).map { row -> [String] in
            // Pad or trim every row to the header width so the grid lines up.
            if row.count >= header.count { return Array(row.prefix(header.count)) }
            return row + Array(repeating: "", count: header.count - row.count)
        }
        return .table(header: header, rows: Array(body))
    }

    private static func splitRow(_ line: String) -> [String] {
        var content = line.trimmingCharacters(in: .whitespaces)
        if content.hasPrefix("|") { content.removeFirst() }
        if content.hasSuffix("|") { content.removeLast() }
        return content.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func isSeparatorRow(_ cells: [String]) -> Bool {
        guard !cells.isEmpty else { return false }
        return cells.allSatisfy { cell in
            let core = cell.trimmingCharacters(in: CharacterSet(charactersIn: ":"))
            return !core.isEmpty && core.allSatisfy { $0 == "-" }
        }
    }
}
