import Foundation

/// A warm Claude Code process for one kind of request. Recycles the process per
/// RecyclePolicy so history (and tokens) stay bounded, and the newest request wins:
/// a request still waiting when a newer one arrives is dropped.
public actor ClaudeLane {
    private let executable: URL
    private let arguments: [String]
    private let policy: RecyclePolicy
    private let workingDirectory: URL?
    private let onTokens: (@Sendable (Int) -> Void)?
    private var current: ClaudeSession?
    private var spare: ClaudeSession?
    private var busy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var generation = 0

    public init(executable: URL, systemPrompt: String, policy: RecyclePolicy = .init(), workingDirectory: URL? = nil,
                onTokens: (@Sendable (Int) -> Void)? = nil) {
        self.onTokens = onTokens
        self.executable = executable
        self.arguments = claudeArguments(systemPrompt: systemPrompt)
        self.policy = policy
        self.workingDirectory = workingDirectory
    }

    public func send(_ text: String, timeout: Duration) async throws -> String {
        generation += 1
        let mine = generation
        while busy { await withCheckedContinuation { waiters.append($0) } }
        guard mine == generation else { wakeNext(); throw ClaudeError.superseded }
        busy = true
        defer { busy = false; wakeNext() }
        do {
            return try await attempt(text, timeout: timeout)
        } catch ClaudeError.processExited {
            current = nil
            return try await attempt(text, timeout: timeout)
        }
    }

    public var isRunning: Bool { current != nil || spare != nil }

    /// Ends the warm processes when unused for `seconds`, so idle lanes don't hold ~400 MB each.
    /// The next `send` starts a fresh one.
    public func shutDownIfIdle(for seconds: TimeInterval) async {
        guard !busy, let c = current, -(await c.lastUsed).timeIntervalSinceNow >= seconds else { return }
        await c.terminate()
        await spare?.terminate()
        current = nil
        spare = nil
    }

    public func warmUp() async {
        if current == nil { current = launch() }
    }

    private func attempt(_ text: String, timeout: Duration) async throws -> String {
        guard let session = await ready() else { throw ClaudeError.processExited }
        do {
            let reply = try await session.send(text, timeout: timeout)
            if await session.requestCount >= policy.maxRequests - 1, spare == nil { spare = launch() }
            return reply
        } catch ClaudeError.timeout {
            current = launch()
            throw ClaudeError.timeout
        }
    }

    private func ready() async -> ClaudeSession? {
        if let c = current, await c.isAlive,
           !policy.shouldRecycle(requests: await c.requestCount, idleFor: -(await c.lastUsed).timeIntervalSinceNow) {
            return c
        }
        await current?.terminate()
        if let s = spare, await s.isAlive { current = s } else { current = launch() }
        spare = nil
        return current
    }

    private func launch() -> ClaudeSession? {
        try? ClaudeSession(executable: executable, arguments: arguments, workingDirectory: workingDirectory, onTokens: onTokens)
    }

    private func wakeNext() {
        if !waiters.isEmpty { waiters.removeFirst().resume() }
    }
}
