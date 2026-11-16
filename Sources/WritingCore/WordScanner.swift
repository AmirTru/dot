import Foundation

/// Words (letters and apostrophes) that are complete: followed by a non-word
/// character, or at the end of text in an unfocused input. A word touching the
/// caret is still being typed or edited, so it is skipped.
public func finishedWords(in text: String, caret: Int?, focused: Bool) -> [NSRange] {
    let ns = text as NSString
    let regex = try! NSRegularExpression(pattern: "[\\p{L}\\p{M}'’]+")
    return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap { m in
        let r = m.range
        let end = r.location + r.length
        let finished = end < ns.length || !focused
        guard finished else { return nil }
        if focused, let caret, caret >= r.location, caret <= end { return nil }
        return r
    }
}

/// Someone is typing if the text changed in the last 1.5 s. Only then is the word at the caret (and the last
/// word) left unmarked; a caret placed in a word to look at it must not hide that word's mistake.
public func isTyping(lastEdit: Date?, now: Date, window: TimeInterval = 1.5) -> Bool {
    guard let lastEdit else { return false }
    return now.timeIntervalSince(lastEdit) < window
}
