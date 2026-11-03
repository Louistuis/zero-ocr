#if arch(x86_64)
import SwiftUI

/// The Intel edition draws results with SwiftUI instead of a web view, which saves the WebKit
/// processes (about 100 MB) on Macs with 4 GB. Headings, lists, paragraphs, emphasis and links come
/// from the Markdown; tables become a grid; LaTeX stays as clean source, which is also what is copied.
struct RichText: View {
    let text: String
    let mode: Mode
    var html: String?
    var maxHeight: CGFloat = 280
    @State private var height: CGFloat = 18

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 9) {
                ForEach(Array(Block.parse(text, mode: mode).enumerated()), id: \.offset) { _, block in
                    block.view
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        }
        .scrollIndicators(.automatic)
        .frame(height: min(max(height, 18), maxHeight))
    }
}

private enum Block {
    case heading(Int, AttributedString)
    case paragraph(AttributedString)
    case item(String, AttributedString)
    case math(String)
    case table([[String]])

    static func parse(_ text: String, mode: Mode) -> [Block] {
        switch mode {
        case .formula: return [.math(Shape.stripMath(text))]
        case .table: return [.table(text.split(separator: "\n").map { $0.components(separatedBy: "\t") })]
        case .text, .doc: break
        }
        var out: [Block] = [], para: [String] = [], rows: [[String]] = [], math: [String]?
        func endParagraph() {
            guard !para.isEmpty else { return }
            // Markdown joins the lines of a paragraph; plain text keeps the lines it was read with.
            out.append(.paragraph(inline(para.joined(separator: mode == .doc ? " " : "\n"))))
            para = []
        }
        func endTable() {
            if !rows.isEmpty { out.append(.table(rows)); rows = [] }
        }
        for raw in text.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if var m = math {   // inside a $$ … $$ block
                if line.hasSuffix("$$") || line.hasSuffix("\\]") {
                    m.append(String(line.dropLast(2)))
                    out.append(.math(m.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)))
                    math = nil
                } else {
                    m.append(line)
                    math = m
                }
                continue
            }
            if line.hasPrefix("|") {
                endParagraph()
                let cells = line.trimmingCharacters(in: CharacterSet(charactersIn: "| ")).components(separatedBy: "|")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                if !cells.allSatisfy({ !$0.isEmpty && $0.allSatisfy { "-: ".contains($0) } }) { rows.append(cells) }
                continue
            }
            endTable()
            if line.hasPrefix("$$") || line.hasPrefix("\\[") {
                endParagraph()
                let body = String(line.dropFirst(2))
                if body.count >= 2, body.hasSuffix("$$") || body.hasSuffix("\\]") {
                    out.append(.math(String(body.dropLast(2)).trimmingCharacters(in: .whitespaces)))
                } else {
                    math = [body]
                }
            } else if line.isEmpty {
                endParagraph()
            } else if let h = heading(line) {
                endParagraph()
                out.append(h)
            } else if let i = item(line) {
                endParagraph()
                out.append(i)
            } else {
                para.append(line)
            }
        }
        if let m = math { out.append(.math(m.joined(separator: "\n"))) }
        endParagraph()
        endTable()
        return out
    }

    private static func heading(_ line: String) -> Block? {
        let level = line.prefix(while: { $0 == "#" }).count
        guard (1...6).contains(level), line.dropFirst(level).first == " " else { return nil }
        return .heading(level, inline(String(line.dropFirst(level + 1))))
    }

    private static func item(_ line: String) -> Block? {
        for b in ["- ", "* ", "+ "] where line.hasPrefix(b) { return .item("•", inline(String(line.dropFirst(2)))) }
        let digits = line.prefix(while: \.isNumber)
        if !digits.isEmpty, line.dropFirst(digits.count).hasPrefix(". ") {
            return .item(digits + ".", inline(String(line.dropFirst(digits.count + 2))))
        }
        return nil
    }

    private static let mathSpan = try! NSRegularExpression(pattern: #"\$(?!\s)[^$\n]+?\$|\\\(.+?\\\)"#)

    /// Emphasis, code and links from Markdown. Inline math is kept away from the Markdown parser (it eats
    /// backslashes and underscores) and shown as monospaced source.
    private static func inline(_ s: String) -> AttributedString {
        var out = AttributedString()
        var last = s.startIndex
        let ns = s as NSString
        func markdown(_ part: Substring) {
            guard !part.isEmpty else { return }
            out += (try? AttributedString(markdown: String(part), options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
                ?? AttributedString(String(part))
        }
        for m in mathSpan.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            guard let r = Range(m.range, in: s) else { continue }
            markdown(s[last..<r.lowerBound])
            var math = AttributedString(Shape.stripMath(String(s[r])))
            math.font = .system(size: 12, design: .monospaced)
            out += math
            last = r.upperBound
        }
        markdown(s[last...])
        return out
    }

    @ViewBuilder
    var view: some View {
        switch self {
        case .heading(let level, let t):
            Text(t).font(.system(size: level == 1 ? 17 : level == 2 ? 15 : 13.5, weight: .semibold))
                .padding(.top, level <= 2 ? 3 : 0)
        case .paragraph(let t):
            Text(t).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
        case .item(let mark, let t):
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text(mark).foregroundStyle(.secondary).frame(minWidth: 10, alignment: .trailing)
                Text(t).fixedSize(horizontal: false, vertical: true)
            }
            .font(.system(size: 13))
        case .math(let src):
            // Wrapped, so the whole formula is visible on the card.
            Text(src).font(.system(size: 12.5, design: .monospaced)).fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        case .table(let rows):
            ScrollView(.horizontal) {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
                        GridRow {
                            ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                                Text(cell).font(.system(size: 12, weight: i == 0 ? .semibold : .regular))
                            }
                        }
                        if i == 0 && rows.count > 1 { Divider().gridCellUnsizedAxes(.horizontal) }
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.never)
        }
    }
}
#endif
