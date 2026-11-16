import Foundation

/// Tidies Haiku's rewrite: no line breaks the writer didn't have, no quotes wrapped around the whole reply.
public func cleanResult(_ output: String, original: String) -> String {
    var s = output.trimmingCharacters(in: .whitespacesAndNewlines)
    if !original.contains("\n") {
        s = s.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: " ")
    }
    let trimmedOriginal = original.trimmingCharacters(in: .whitespacesAndNewlines)
    if s.count >= 2, s.first == "\"", s.last == "\"", !(trimmedOriginal.first == "\"" && trimmedOriginal.last == "\"") {
        s = String(s.dropFirst().dropLast())
    }
    return s
}
