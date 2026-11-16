import Foundation

public enum MarkKind: Equatable, Sendable { case spelling, wordChoice }

public struct Mark: Equatable, Sendable {
    public let range: NSRange
    public let fix: String
    public let kind: MarkKind
    public init(range: NSRange, fix: String, kind: MarkKind) {
        self.range = range; self.fix = fix; self.kind = kind
    }
}
