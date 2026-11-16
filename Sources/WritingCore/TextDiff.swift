import Foundation

public struct TextEdit: Equatable, Sendable {
    public let range: NSRange
    public let replacement: String
    public init(range: NSRange, replacement: String) {
        self.range = range; self.replacement = replacement
    }
}

private struct Token { let text: String; let range: NSRange }

private func tokens(_ s: String) -> [Token] {
    let regex = try! NSRegularExpression(pattern: "\\s+|\\S+")
    let ns = s as NSString
    return regex.matches(in: s, range: NSRange(location: 0, length: ns.length)).map {
        Token(text: ns.substring(with: $0.range), range: $0.range)
    }
}

/// Index pairs (old, new) of the longest common token subsequence.
private func lcsPairs(_ a: [Token], _ b: [Token]) -> [(Int, Int)] {
    let n = a.count, m = b.count
    var table = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
    for i in stride(from: n - 1, through: 0, by: -1) {
        for j in stride(from: m - 1, through: 0, by: -1) {
            table[i][j] = a[i].text == b[j].text ? table[i + 1][j + 1] + 1 : max(table[i + 1][j], table[i][j + 1])
        }
    }
    var pairs: [(Int, Int)] = []
    var i = 0, j = 0
    while i < n && j < m {
        if a[i].text == b[j].text { pairs.append((i, j)); i += 1; j += 1 }
        else if table[i + 1][j] >= table[i][j + 1] { i += 1 }
        else { j += 1 }
    }
    return pairs
}

/// Minimal edits turning `old` into `new`, last first so applying them in order keeps offsets valid.
public func wordEdits(from old: String, to new: String) -> [TextEdit] {
    let a = tokens(old), b = tokens(new)
    var edits: [TextEdit] = []
    var i = 0, j = 0, oldPos = 0
    for (pi, pj) in lcsPairs(a, b) + [(a.count, b.count)] {
        if i < pi || j < pj {
            let location = i < pi ? a[i].range.location : oldPos
            let length = i < pi ? NSMaxRange(a[pi - 1].range) - location : 0
            edits.append(TextEdit(range: NSRange(location: location, length: length),
                                  replacement: b[j..<pj].map(\.text).joined()))
        }
        if pi < a.count { oldPos = NSMaxRange(a[pi].range) }
        i = pi + 1; j = pj + 1
    }
    return edits.map { widenInsertion($0, tokens: a) }.reversed()
}

/// Apps ignore writes into an empty selection, so a pure insertion also replaces the
/// unchanged token before it (or after it, at the very start).
private func widenInsertion(_ edit: TextEdit, tokens: [Token]) -> TextEdit {
    guard edit.range.length == 0 else { return edit }
    if let before = tokens.last(where: { NSMaxRange($0.range) == edit.range.location }) {
        return TextEdit(range: NSRange(location: before.range.location, length: before.range.length), replacement: before.text + edit.replacement)
    }
    if let after = tokens.first(where: { $0.range.location == edit.range.location }) {
        return TextEdit(range: after.range, replacement: edit.replacement + after.text)
    }
    return edit
}

/// Non-whitespace ranges in `new` that were not in `old`, for the green highlight.
public func changedRanges(from old: String, to new: String) -> [NSRange] {
    let a = tokens(old), b = tokens(new)
    let kept = Set(lcsPairs(a, b).map(\.1))
    return b.indices.filter { !kept.contains($0) && !b[$0].text.allSatisfy(\.isWhitespace) }.map { b[$0].range }
}

/// Joins neighbouring edits into one, so the app writes once instead of once per word.
/// Never joins across an @mention, :emoji:, `code` or link, or across a `splitAt` offset (where Slack's
/// formatting changes), so those are never rewritten. Overlapping edits keep the first. Last-first in and out.
public func mergedEdits(_ edits: [TextEdit], in old: String, splitAt: Set<Int> = []) -> [TextEdit] {
    let ns = old as NSString
    let protected = try! NSRegularExpression(pattern: "@[\\w.-]+|:[\\w+-]+:|`|https?://")
    var merged: [TextEdit] = []
    for edit in edits.sorted(by: { $0.range.location < $1.range.location }) {
        guard let last = merged.last else { merged.append(edit); continue }
        if edit.range.location < NSMaxRange(last.range) { continue }
        let gap = NSRange(location: NSMaxRange(last.range), length: edit.range.location - NSMaxRange(last.range))
        let between = ns.substring(with: gap)
        let crossesFormatting = splitAt.contains { $0 > gap.location && $0 <= NSMaxRange(gap) }
        if !crossesFormatting, protected.firstMatch(in: between, range: NSRange(location: 0, length: gap.length)) == nil {
            merged[merged.count - 1] = TextEdit(range: NSUnionRange(last.range, edit.range), replacement: last.replacement + between + edit.replacement)
        } else {
            merged.append(edit)
        }
    }
    return merged.reversed()
}
