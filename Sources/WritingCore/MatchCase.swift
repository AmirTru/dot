/// Capitalizes the fix when the replaced word was capitalized. Never lowers a fix, so "i" → "I" stays.
public func matchCase(of word: String, _ fix: String) -> String {
    guard let w = word.first, w.isUppercase, let f = fix.first else { return fix }
    return String(f).uppercased() + fix.dropFirst()
}
