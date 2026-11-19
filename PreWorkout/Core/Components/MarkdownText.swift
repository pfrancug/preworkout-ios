import SwiftUI

/// Minimal block Markdown renderer for AI reports (headings, lists, paragraphs);
/// inline styles (bold, italics, code, links) come from `AttributedString`.
struct MarkdownText: View {
    let text: String

    private enum Block: Hashable {
        case heading(Int, String)
        case bullet(String)
        case numbered(String, String)
        case paragraph(String)
        case rule
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .heading(let level, let value):
                    Text(inline(value))
                        .font(level <= 1 ? .title2.bold() : level == 2 ? .title3.bold() : .headline)
                        .padding(.top, 4)
                case .bullet(let value):
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•")
                        Text(inline(value))
                    }
                case .numbered(let number, let value):
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(verbatim: number).monospacedDigit()
                        Text(inline(value))
                    }
                case .paragraph(let value):
                    Text(inline(value))
                case .rule:
                    Divider()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }

    private var blocks: [Block] {
        var result: [Block] = []
        var paragraph: [String] = []
        func flush() {
            if !paragraph.isEmpty {
                result.append(.paragraph(paragraph.joined(separator: "\n")))
                paragraph = []
            }
        }
        for rawLine in text.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                flush()
            } else if line.hasPrefix("#") {
                flush()
                let level = line.prefix(while: { $0 == "#" }).count
                result.append(.heading(level, line.dropFirst(level).trimmingCharacters(in: .whitespaces)))
            } else if line == "---" || line == "***" {
                flush()
                result.append(.rule)
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("• ") {
                flush()
                result.append(.bullet(String(line.dropFirst(2))))
            } else if let dot = line.firstIndex(of: "."), line[..<dot].allSatisfy(\.isNumber),
                      !line[..<dot].isEmpty, line[line.index(after: dot)...].hasPrefix(" ") {
                flush()
                result.append(.numbered(String(line[...dot]), line[line.index(after: dot)...].trimmingCharacters(in: .whitespaces)))
            } else {
                paragraph.append(line)
            }
        }
        flush()
        return result
    }

    private func inline(_ value: String) -> AttributedString {
        (try? AttributedString(
            markdown: value,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(value)
    }
}
