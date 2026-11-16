import Foundation
import WritingCore

/// Sends each changed sentence to Haiku after a 700 ms pause. Results are cached by sentence
/// text, so a sentence is never sent twice.
@MainActor
final class SentenceChecker {
    var onChange: (() -> Void)?
    var onAuthError: (() -> Void)?
    var enabled = true
    private(set) var isChecking = false

    private let lane: ClaudeLane
    private let cache = LRUCache<String, [HaikuIssue]>(capacity: 500)
    private var debounce: Task<Void, Never>?
    private var runID = 0

    init(lane: ClaudeLane) { self.lane = lane }

    func textChanged(_ text: String) {
        debounce?.cancel()
        guard enabled else { return }
        debounce = Task {
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            await run(text)
        }
    }

    func marks(for text: String) -> [Mark] {
        sentences(in: text).flatMap { s in cache[s.text].map { mapIssues($0, sentence: s, in: text) } ?? [] }
    }

    private func run(_ text: String) async {
        let pending = sentences(in: text).filter { $0.isCheckable && cache[$0.text] == nil }
        guard !pending.isEmpty else { return }
        runID += 1
        let mine = runID
        isChecking = true
        onChange?()
        defer {
            if mine == runID { isChecking = false; onChange?() }
        }
        for sentence in pending {
            if Task.isCancelled { return }
            do {
                let raw = try await lane.send(sentence.text, timeout: .seconds(4))
                cache[sentence.text] = parseIssues(raw) ?? []
                onChange?()
            } catch ClaudeError.errorResult {
                onAuthError?()
                return
            } catch {
                return
            }
        }
    }
}
