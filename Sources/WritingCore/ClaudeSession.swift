import Foundation

public enum ClaudeError: Error, Equatable {
    case timeout, processExited, superseded
    case errorResult(String)

    /// The case without its text, for the log.
    public var logName: String {
        switch self {
        case .timeout: "timeout"
        case .processExited: "processExited"
        case .superseded: "superseded"
        case .errorResult: "errorResult"
        }
    }
}

public struct RecyclePolicy: Sendable {
    public var maxRequests = 20
    public var maxIdle: TimeInterval = 600
    public init(maxRequests: Int = 20, maxIdle: TimeInterval = 600) {
        self.maxRequests = maxRequests; self.maxIdle = maxIdle
    }
    public func shouldRecycle(requests: Int, idleFor: TimeInterval) -> Bool {
        requests >= maxRequests || idleFor >= maxIdle
    }
}

private final class LineSplitter: @unchecked Sendable {
    private var buffer = Data()
    private let lock = NSLock()

    func feed(_ data: Data) -> [String] {
        lock.lock(); defer { lock.unlock() }
        buffer.append(data)
        var lines: [String] = []
        while let nl = buffer.firstIndex(of: 10) {
            lines.append(String(decoding: buffer[buffer.startIndex..<nl], as: UTF8.self))
            buffer.removeSubrange(buffer.startIndex...nl)
        }
        return lines
    }
}

/// One long-running `claude -p` process speaking stream-json. One request at a time.
public actor ClaudeSession {
    private let process = Process()
    private let input = Pipe()
    private var pending: CheckedContinuation<String, Error>?
    private var exited = false
    public private(set) var requestCount = 0
    public private(set) var lastUsed = Date()
    public var isAlive: Bool { !exited }

    private let onTokens: (@Sendable (Int) -> Void)?

    public init(executable: URL, arguments: [String], workingDirectory: URL? = nil, onTokens: (@Sendable (Int) -> Void)? = nil) throws {
        self.onTokens = onTokens
        signal(SIGPIPE, SIG_IGN)
        let output = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        if let workingDirectory { process.currentDirectoryURL = workingDirectory }
        let (lines, sink) = AsyncStream<String>.makeStream()
        let splitter = LineSplitter()
        output.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil; sink.finish(); return }
            for line in splitter.feed(data) { sink.yield(line) }
        }
        try process.run()
        Task { await self.consume(lines) }
    }

    private func consume(_ lines: AsyncStream<String>) async {
        for await line in lines {
            if case let .result(text, isError, tokens) = parseStreamLine(line) {
                onTokens?(tokens)
                resolve(isError ? .failure(ClaudeError.errorResult(text)) : .success(text))
            }
        }
        exited = true
        resolve(.failure(ClaudeError.processExited))
    }

    private func resolve(_ result: Result<String, Error>) {
        pending?.resume(with: result)
        pending = nil
    }

    public func send(_ text: String, timeout: Duration) async throws -> String {
        guard !exited, pending == nil else { throw ClaudeError.processExited }
        requestCount += 1
        lastUsed = Date()
        do {
            try input.fileHandleForWriting.write(contentsOf: Data(userMessageLine(text).utf8))
        } catch {
            exited = true
            throw ClaudeError.processExited
        }
        let timer = Task { [weak self] in
            try await Task.sleep(for: timeout)
            await self?.timedOut()
        }
        defer { timer.cancel() }
        return try await withCheckedThrowingContinuation { pending = $0 }
    }

    private func timedOut() {
        guard pending != nil else { return }
        resolve(.failure(ClaudeError.timeout))
        terminate()
    }

    public func terminate() {
        exited = true
        if process.isRunning { process.terminate() }
    }
}
