import AppKit
import WritingCore

/// Instant, offline spelling marks from the macOS spell checker, in English or Hebrew per word. Cached per word.
@MainActor
final class LocalChecker {
    private var cache: [String: String?] = [:]

    func marks(text: String, caret: Int?, focused: Bool) -> [Mark] {
        let ns = text as NSString
        return checkableWords(in: text, caret: caret, focused: focused).compactMap { range in
            let word = ns.substring(with: range)
            guard let fix = fix(for: word) else { return nil }
            return Mark(range: range, fix: matchCase(of: word, fix), kind: .spelling)
        }
    }

    private func fix(for word: String) -> String? {
        if let cached = cache[word] { return cached }
        let checker = NSSpellChecker.shared
        let language = spellLanguage(for: word)
        var result: String?
        let miss = checker.checkSpelling(of: word, startingAt: 0, language: language, wrap: false, inSpellDocumentWithTag: 0, wordCount: nil)
        if miss.location != NSNotFound {
            let whole = NSRange(location: 0, length: (word as NSString).length)
            result = checker.correction(forWordRange: whole, in: word, language: language, inSpellDocumentWithTag: 0)
                ?? checker.guesses(forWordRange: whole, in: word, language: language, inSpellDocumentWithTag: 0)?.first
            if result == word { result = nil }
        }
        if cache.count > 5000 { cache.removeAll() }
        cache[word] = result
        return result
    }
}
