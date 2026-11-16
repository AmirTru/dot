import Foundation

/// Text that is not prose and must never be underlined: code, links, emails, @mentions, #channels,
/// :emoji: and file paths.
private let protectedPattern = try! NSRegularExpression(pattern: [
    "```[\\s\\S]*?(?:```|$)",
    "`[^`\\n]*`",
    "\\b(?:https?://|www\\.)\\S+",
    "[\\w.+-]+@[\\w-]+\\.[\\w.-]+",
    "(?<![\\w])@[\\w.-]+",
    "(?<![\\w&])#[\\w-]+",
    ":[\\w+-]+:",
    "\\S*[/\\\\]\\S+",
    "\\b[\\w-]+\\.(?:swift|go|ts|tsx|js|jsx|py|md|json|ya?ml|tf|sh|txt|rb|java|kt|rs|toml|lock|env|sql)\\b",
].joined(separator: "|"))

public func protectedRanges(in text: String) -> [NSRange] {
    protectedPattern.matches(in: text, range: NSRange(location: 0, length: (text as NSString).length)).map(\.range)
}

public func isProtected(_ range: NSRange, in text: String) -> Bool {
    protectedRanges(in: text).contains { NSIntersectionRange($0, range).length > 0 }
}

/// Finished words that are prose, i.e. not inside code, links, mentions or similar.
public func checkableWords(in text: String, caret: Int?, focused: Bool) -> [NSRange] {
    let skip = protectedRanges(in: text)
    return finishedWords(in: text, caret: caret, focused: focused).filter { word in
        !skip.contains { NSIntersectionRange($0, word).length > 0 }
    }
}
