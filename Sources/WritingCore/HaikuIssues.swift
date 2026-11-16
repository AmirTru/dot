import Foundation

public struct HaikuIssue: Decodable, Equatable, Sendable {
    public let wrong: String
    public let fix: String
    public let kind: String
    public init(wrong: String, fix: String, kind: String) {
        self.wrong = wrong; self.fix = fix; self.kind = kind
    }
}

private struct IssueList: Decodable { let issues: [HaikuIssue] }

public func parseIssues(_ raw: String) -> [HaikuIssue]? {
    var body = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if body.hasPrefix("```") {
        body = body.split(separator: "\n", omittingEmptySubsequences: false).dropFirst().joined(separator: "\n")
        if body.hasSuffix("```") { body = String(body.dropLast(3)) }
    }
    return (try? JSONDecoder().decode(IssueList.self, from: Data(body.utf8)))?.issues
}

/// Maps Haiku's word-level issues onto ranges in the current text. Returns nothing
/// when the sentence was edited after it was sent, so stale results never mark new text.
public func mapIssues(_ issues: [HaikuIssue], sentence: Sentence, in text: String) -> [Mark] {
    let ns = text as NSString
    guard NSMaxRange(sentence.range) <= ns.length,
          ns.substring(with: sentence.range).trimmingCharacters(in: .whitespaces) == sentence.text
    else { return [] }
    var marks: [Mark] = []
    for issue in issues where !issue.wrong.isEmpty && issue.wrong != issue.fix && isSafeFix(wrong: issue.wrong, fix: issue.fix) {
        let pattern = "(?<![\\p{L}\\p{M}'’])" + NSRegularExpression.escapedPattern(for: issue.wrong) + "(?![\\p{L}\\p{M}'’])"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
        let hit = regex.matches(in: text, range: sentence.range).first { match in
            !marks.contains { NSIntersectionRange($0.range, match.range).length > 0 }
        }
        guard let hit else { continue }
        marks.append(Mark(range: hit.range, fix: issue.fix, kind: issue.kind == "spelling" ? .spelling : .wordChoice))
    }
    return marks.sorted { $0.range.location < $1.range.location }
}

/// A fix is a spelling or word-choice change, never new content. Text in a message can steer Haiku
/// (prompt injection), and Fix Everything pastes fixes without a preview, so anything bigger is dropped.
public func isSafeFix(wrong: String, fix: String) -> Bool {
    let words = { (s: String) in s.split(whereSeparator: \.isWhitespace).count }
    let lower = fix.lowercased()
    return !fix.contains(where: \.isNewline) && !lower.contains("://") && !lower.contains("www.") && !fix.contains("@")
        && words(fix) <= words(wrong) + 1 && fix.count <= wrong.count * 2 + 4
}
