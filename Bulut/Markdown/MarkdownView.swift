import SwiftUI
import UIKit

/// Renders a model reply: headings, lists, quotes, tables and code blocks, with inline Markdown inside them.
struct MarkdownView: View {
    let text: String

    var body: some View {
        let blocks = MarkdownParser.parse(text)
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownBlock) -> some View {
        switch block {
        case .paragraph(let text):
            InlineText(text)

        case .heading(let level, let text):
            InlineText(text)
                .font(Self.headingFont(level))
                .padding(.top, level <= 2 ? 6 : 2)

        case .code(let language, let code):
            CodeBlockView(language: language, code: code)

        case .listItem(let indent, let marker, let text):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(marker)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                InlineText(text)
            }
            .padding(.leading, CGFloat(indent) * 18)

        case .quote(let text):
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.secondary.opacity(0.5))
                    .frame(width: 3)
                InlineText(text)
                    .foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)

        case .table(let header, let rows):
            TableBlockView(header: header, rows: rows)

        case .rule:
            Divider().padding(.vertical, 4)
        }
    }

    private static func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: return .title2.bold()
        case 2: return .title3.bold()
        case 3: return .headline
        default: return .subheadline.bold()
        }
    }
}

/// Inline Markdown (bold, italic, `code`, links, ~~strike~~) via Foundation's parser.
struct InlineText: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(Self.attributed(text))
            .fixedSize(horizontal: false, vertical: true)
    }

    static func attributed(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            allowsExtendedAttributes: false,
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}

struct CodeBlockView: View {
    let language: String?
    let code: String
    @State private var copied = false
    /// Each tap restarts the "Kopyalandı" timer; the previous one is cancelled with its task.
    @State private var copyCount = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(language ?? "kod")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    UIPasteboard.general.string = code
                    copyCount += 1
                } label: {
                    Label(copied ? "Kopyalandı" : "Kopyala", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(.tertiarySystemFill))

            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(.callout, design: .monospaced))
                    .fixedSize(horizontal: true, vertical: true)
                    .padding(12)
            }
        }
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color(.separator).opacity(0.5), lineWidth: 0.5)
        }
        .task(id: copyCount) {
            guard copyCount > 0 else { return }
            copied = true
            do {
                try await Task.sleep(for: .seconds(1.5))
            } catch {
                return  // A newer tap took over.
            }
            copied = false
        }
    }
}

struct TableBlockView: View {
    let header: [String]
    let rows: [[String]]

    var body: some View {
        let widths = columnWidths
        ScrollView(.horizontal, showsIndicators: false) {
            Grid(alignment: .topLeading, horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    ForEach(Array(header.enumerated()), id: \.offset) { column, cell in
                        InlineText(cell)
                            .font(.subheadline.bold())
                            .padding(8)
                            .frame(width: widths[column], alignment: .leading)
                    }
                }

                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    Divider()
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { column, cell in
                            InlineText(cell)
                                .font(.subheadline)
                                .padding(8)
                                .frame(width: widths[min(column, widths.count - 1)], alignment: .leading)
                        }
                    }
                }
            }
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color(.separator).opacity(0.6), lineWidth: 0.5)
            }
        }
    }

    /// Rough column widths from the longest cell, so long cells wrap instead of stretching forever.
    private var columnWidths: [CGFloat] {
        (0..<max(header.count, 1)).map { column in
            let cells = [column < header.count ? header[column] : ""] + rows.map { column < $0.count ? $0[column] : "" }
            let longest = cells.map(\.count).max() ?? 0
            return min(max(CGFloat(longest) * 7.5 + 16, 64), 240)
        }
    }
}

#if DEBUG
#Preview("Markdown") {
    ScrollView {
        MarkdownView(text: PreviewData.markdownReply)
            .padding()
    }
}
#endif
