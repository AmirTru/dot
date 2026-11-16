import Foundation

/// Where each accessibility text piece (e.g. Slack's static-text children) starts in the full
/// input text. Pieces are searched in order, each after the previous match; nil if not found.
public func pieceOffsets(_ pieces: [String], in text: String) -> [Int?] {
    let ns = text as NSString
    var cursor = 0
    return pieces.map { piece in
        guard !piece.isEmpty else { return nil }
        let found = ns.range(of: piece, range: NSRange(location: cursor, length: ns.length - cursor))
        guard found.location != NSNotFound else { return nil }
        cursor = NSMaxRange(found)
        return found.location
    }
}

/// The piece fully containing `range`, and the range relative to that piece.
public func locate(_ range: NSRange, pieces: [NSRange]) -> (index: Int, local: NSRange)? {
    guard let i = pieces.firstIndex(where: { $0.location <= range.location && NSMaxRange(range) <= NSMaxRange($0) }) else { return nil }
    return (i, NSRange(location: range.location - pieces[i].location, length: range.length))
}
