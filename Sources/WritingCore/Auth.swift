import Foundation

public enum ConnectionState: Equatable, Sendable {
    case connected(expiresSoon: Bool)
    case disconnected
}

private struct AuthStatus: Decodable {
    let loggedIn: Bool
    let loginExpiresAt: String?
}

public func connectionState(fromStatusJSON data: Data, now: Date) -> ConnectionState {
    guard let status = try? JSONDecoder().decode(AuthStatus.self, from: data), status.loggedIn else { return .disconnected }
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    guard let raw = status.loginExpiresAt, let expiry = formatter.date(from: raw) else { return .connected(expiresSoon: false) }
    return .connected(expiresSoon: expiry.timeIntervalSince(now) < 24 * 3600)
}

public func readAuthStatus(executable: URL) async -> ConnectionState {
    await withCheckedContinuation { done in
        let process = Process()
        let output = Pipe()
        process.executableURL = executable
        process.arguments = ["auth", "status"]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { _ in
            let data = output.fileHandleForReading.readDataToEndOfFile()
            done.resume(returning: connectionState(fromStatusJSON: data, now: Date()))
        }
        do { try process.run() } catch { done.resume(returning: .disconnected) }
    }
}

/// Where the Claude Code installers put `claude`. A fixed list instead of a PATH search,
/// so a folder earlier in PATH can't swap in a different program.
public func findClaude(home: String, exists: (String) -> Bool = FileManager.default.isExecutableFile(atPath:)) -> URL? {
    ["\(home)/.local/bin/claude", "\(home)/.claude/local/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude"]
        .first(where: exists).map { URL(fileURLWithPath: $0) }
}

/// AppleScript that runs Anthropic's official Claude Code installer in Terminal, where the person can watch it.
public let terminalInstallScript = """
tell application "Terminal"
activate
do script "curl -fsSL https://claude.ai/install.sh | bash"
end tell
"""

/// Signs Claude Code out on this Mac (`claude auth logout`). Returns when the command has finished.
public func logOut(executable: URL) async {
    await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
        let process = Process()
        process.executableURL = executable
        process.arguments = ["auth", "logout"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { _ in done.resume() }
        do { try process.run() } catch { done.resume() }
    }
}
