import Foundation

private func isHebrew(_ s: Unicode.Scalar) -> Bool { (0x0590...0x05FF).contains(s.value) || (0xFB1D...0xFB4F).contains(s.value) }

/// Spell-check language for one word: Hebrew letters → "he", anything else → "en".
public func spellLanguage(for word: String) -> String {
    word.unicodeScalars.contains(where: isHebrew) ? "he" : "en"
}

/// Direction of the text, from its first letter (digits, spaces and punctuation are skipped).
public func isRightToLeft(_ text: String) -> Bool {
    guard let first = text.unicodeScalars.first(where: { $0.properties.isAlphabetic }) else { return false }
    return isHebrew(first)
}

/// The macOS Hebrew dictionary flags many correct spellings (such as הטעתי), so Hebrew words wait for Haiku when it is available.
public func trustsLocalSpelling(of word: String, connected: Bool) -> Bool {
    !connected || spellLanguage(for: word) != "he"
}
