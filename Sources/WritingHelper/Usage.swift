import Foundation
import WritingCore

/// Saves the token counts after every Claude answer, so the menu can show today / week / month.
@MainActor
final class Usage {
    static let shared = Usage()
    private(set) var ledger: TokenLedger
    private let file: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Dot")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("usage.json")
    }()

    private init() {
        ledger = (try? JSONDecoder().decode(TokenLedger.self, from: Data(contentsOf: file))) ?? TokenLedger()
    }

    func add(_ tokens: Int) {
        guard tokens > 0 else { return }
        ledger.add(tokens, on: Date())
        try? JSONEncoder().encode(ledger).write(to: file, options: .atomic)
    }

    nonisolated static func record(_ tokens: Int) {
        Task { @MainActor in shared.add(tokens) }
    }
}
