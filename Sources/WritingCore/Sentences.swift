import Foundation

public struct Sentence: Hashable, Sendable {
    public let range: NSRange
    public let text: String
    public var isCheckable: Bool { text.split(whereSeparator: \.isWhitespace).count >= 2 }
}

public func sentences(in text: String) -> [Sentence] {
    let regex = try! NSRegularExpression(pattern: "[^.!?\\n]+[.!?]*")
    let ns = text as NSString
    return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap { m in
        let trimmed = ns.substring(with: m.range).trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : Sentence(range: m.range, text: trimmed)
    }
}
