import Foundation

/// Model output to what goes on the clipboard. The model writes tables as OTSL tokens
/// (<fcel> cell, <ecel> empty, <lcel>/<ucel>/<xcel> merged left/up/both, <nl> row end);
/// tables become Markdown in text, and tab-separated cells plus an HTML grid in table mode,
/// so a paste into Numbers, Excel, Pages or Notes keeps the grid.
struct Shaped {
    var text: String
    var html: String?
}

enum Shape {
    private typealias Cell = (tok: String, text: String)
    private static let cellTokens: Set<String> = ["fcel", "ecel", "lcel", "ucel", "xcel", "ched", "rhed", "srow"]
    private static let otslToken = try! NSRegularExpression(pattern: "<(fcel|ecel|lcel|ucel|xcel|nl|ched|rhed|srow)>")
    private static let otslBlock = try! NSRegularExpression(
        pattern: "(?:<otsl>)?\\s*((?:<(?:fcel|ecel|lcel|ucel|xcel|ched|rhed|srow)>[^<]*(?:<nl>\\s*)?)+)\\s*(?:</otsl>)?")
    private static let tokenWithText = try! NSRegularExpression(pattern: "<(fcel|ecel|lcel|ucel|xcel|ched|rhed|srow|nl)>([^<]*)")
    /// Inline math the model uses for plain things like \(1.5\%\); real formulas (with commands) stay.
    private static let simpleMath = try! NSRegularExpression(pattern: "\\\\\\(\\s*((?:[\\w\\s.,:+\\-/=]|\\\\[%$&#_])+?)\\s*\\\\\\)")

    static func apply(_ raw: String, mode: Mode) -> Shaped {
        if mode == .formula { return Shaped(text: stripMath(raw)) }
        var s = raw
        if mode == .text {
            s = replace(simpleMath, in: s) { m in
                m[1].replacingOccurrences(of: "\\\\([%$&#_])", with: "$1", options: .regularExpression)
                    .trimmingCharacters(in: .whitespaces)
            }
        }
        guard has(otslToken, s) else { return Shaped(text: s) }
        let grids = matches(otslBlock, s).map { grid($0[0]) }
        let html = grids.map(gridHTML).joined()
        if mode == .table, grids.count == 1 { return Shaped(text: gridTSV(grids[0]), html: html) }
        let text = replace(otslBlock, in: s) { "\n\n" + gridMarkdown(grid($0[1])) + "\n\n" }
        return Shaped(text: text.trimmingCharacters(in: .whitespacesAndNewlines), html: html)
    }

    /// For the live preview: OTSL shown as rows of cells while it streams in.
    static func preview(_ raw: String, mode: Mode) -> String {
        // A tag still arriving token by token ("<fc") is not shown until it is complete.
        let raw = raw.replacingOccurrences(of: "<[a-z/]*$", with: "", options: .regularExpression)
        guard has(otslToken, raw) else { return mode == .formula ? stripMath(raw) : raw }
        return raw.replacingOccurrences(of: "<nl>", with: "\n")
            .replacingOccurrences(of: "<(fcel|ched|rhed|srow)>", with: "\t", options: .regularExpression)
            .replacingOccurrences(of: "<(ecel|lcel|ucel|xcel)>", with: "\t", options: .regularExpression)
            .replacingOccurrences(of: "</?otsl>", with: "", options: .regularExpression)
            .split(separator: "\n").map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "\t ")) }.joined(separator: "\n")
    }

    static func stripMath(_ t: String) -> String {
        let t = t.trimmingCharacters(in: .whitespacesAndNewlines)
        for (a, b) in [("$$", "$$"), ("\\[", "\\]"), ("\\(", "\\)"), ("$", "$")]
        where t.hasPrefix(a) && t.hasSuffix(b) && t.count > a.count + b.count {
            return String(t.dropFirst(a.count).dropLast(b.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return t
    }

    // MARK: grids

    private static func grid(_ s: String) -> [[Cell]] {
        var rows: [[Cell]] = [], row: [Cell] = []
        for m in matches(tokenWithText, s) {
            if m[0] == "nl" { rows.append(row); row = [] } else { row.append((m[0], m[1].trimmingCharacters(in: .whitespaces))) }
        }
        if !row.isEmpty { rows.append(row) }
        let width = rows.map(\.count).max() ?? 0
        return rows.map { $0 + Array(repeating: ("ecel", ""), count: width - $0.count) }
    }

    private static func merged(_ c: Cell) -> Bool { ["lcel", "ucel", "xcel"].contains(c.tok) }

    /// Merged cells stay blank, which is what spreadsheets expect on paste.
    private static func cells(_ g: [[Cell]]) -> [[String]] { g.map { $0.map { merged($0) ? "" : $0.text } } }

    private static func gridTSV(_ g: [[Cell]]) -> String {
        cells(g).map { $0.map { $0.replacingOccurrences(of: "\t", with: " ") }.joined(separator: "\t") }.joined(separator: "\n")
    }

    private static func gridMarkdown(_ g: [[Cell]]) -> String {
        let c = cells(g)
        guard let head = c.first else { return "" }
        let fix = { (t: String) in t.replacingOccurrences(of: "|", with: "\\|").replacingOccurrences(of: "\n", with: " ") }
        var lines = ["| " + head.map(fix).joined(separator: " | ") + " |", "|" + String(repeating: "---|", count: head.count)]
        lines += c.dropFirst().map { "| " + $0.map(fix).joined(separator: " | ") + " |" }
        return lines.joined(separator: "\n")
    }

    private static func gridHTML(_ g: [[Cell]]) -> String {
        var out = "<table>"
        for (i, r) in g.enumerated() {
            out += "<tr>"
            for (j, c) in r.enumerated() where !merged(c) {
                var cs = 1, rs = 1
                while j + cs < r.count, ["lcel", "xcel"].contains(g[i][j + cs].tok) { cs += 1 }
                while i + rs < g.count, ["ucel", "xcel"].contains(g[i + rs][j].tok) { rs += 1 }
                let tag = i == 0 ? "th" : "td"
                let attr = (cs > 1 ? " colspan=\"\(cs)\"" : "") + (rs > 1 ? " rowspan=\"\(rs)\"" : "")
                let esc = c.text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
                    .replacingOccurrences(of: ">", with: "&gt;")
                out += "<\(tag)\(attr)>\(esc)</\(tag)>"
            }
            out += "</tr>"
        }
        return out + "</table>"
    }

    // MARK: regex helpers

    private static func has(_ re: NSRegularExpression, _ s: String) -> Bool {
        re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
    }

    private static func groups(_ m: NSTextCheckingResult, _ s: String) -> [String] {
        (1..<max(m.numberOfRanges, 2)).map { i in
            guard i < m.numberOfRanges, let r = Range(m.range(at: i), in: s) else { return "" }
            return String(s[r])
        }
    }

    /// Capture groups of every match (index 0 is group 1).
    private static func matches(_ re: NSRegularExpression, _ s: String) -> [[String]] {
        re.matches(in: s, range: NSRange(s.startIndex..., in: s)).map { groups($0, s) }
    }

    /// Replace each match; the closure gets group 0 at index 0 and group n at index n.
    private static func replace(_ re: NSRegularExpression, in s: String, with f: ([String]) -> String) -> String {
        var out = "", last = s.startIndex
        for m in re.matches(in: s, range: NSRange(s.startIndex..., in: s)) {
            guard let r = Range(m.range, in: s) else { continue }
            out += s[last..<r.lowerBound]
            out += f([String(s[r])] + groups(m, s))
            last = r.upperBound
        }
        return out + s[last...]
    }
}
