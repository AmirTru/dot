import AppKit
import Combine
import WritingCore

@MainActor
final class AuthMonitor: ObservableObject {
    @Published private(set) var state: ConnectionState = .connected(expiresSoon: false)
    private var timer: Timer?
    private var connectTask: Task<Void, Never>?

    func start() {
        Task { await refresh() }
        timer = Timer.scheduledTimer(withTimeInterval: 30 * 60, repeats: true) { _ in
            Task { @MainActor in await self.refresh() }
        }
    }

    func refresh() async {
        state = await readAuthStatus(executable: ClaudePaths.executable)
    }

    func disconnect() async {
        connectTask?.cancel()
        await logOut(executable: ClaudePaths.executable)
        await refresh()
    }

    /// Signs in without a Terminal window: `claude auth login` opens the browser itself and waits for the
    /// browser to hand the login back. Only installing Claude Code runs in Terminal, where the person can watch it.
    func startConnectFlow() {
        connectTask?.cancel()
        if !ClaudePaths.isInstalled { NSAppleScript(source: terminalInstallScript)?.executeAndReturnError(nil) }
        connectTask = Task {
            // Installing and signing in can take a few minutes.
            for _ in 0..<300 where !ClaudePaths.isInstalled {
                try? await Task.sleep(for: .seconds(2))
                if Task.isCancelled { return }
            }
            let login = Process()
            login.executableURL = ClaudePaths.executable
            login.arguments = ["auth", "login"]
            login.standardInput = Pipe()
            login.standardOutput = FileHandle.nullDevice
            login.standardError = FileHandle.nullDevice
            guard (try? login.run()) != nil else { return }
            defer { if login.isRunning { login.terminate() } }
            for _ in 0..<150 {
                try? await Task.sleep(for: .seconds(2))
                if Task.isCancelled { return }
                await refresh()
                if case .connected = state { return }
            }
        }
    }
}
