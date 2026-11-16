import AppKit
import WritingCore

enum Slack {
    static let slackFlag = "--force-renderer-accessibility"

    /// Slack only exposes its message box to accessibility when started with this flag.
    static func slackHasAccessibility(_ app: NSRunningApplication) -> Bool {
        let ps = Process()
        let out = Pipe()
        ps.executableURL = URL(fileURLWithPath: "/bin/ps")
        ps.arguments = ["-o", "command=", "-p", String(app.processIdentifier)]
        ps.standardOutput = out
        guard (try? ps.run()) != nil else { return false }
        ps.waitUntilExit()
        return String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).contains(slackFlag)
    }

    static let bundleID = "com.tinyspeck.slackmacgap"

    static func restartSlackWithAccessibility() {
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        running.forEach { $0.terminate() }
        Task { @MainActor in
            for _ in 0..<50 where running.contains(where: { !$0.isTerminated }) {
                try? await Task.sleep(for: .milliseconds(200))
            }
            let open = Process()
            open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            open.arguments = ["-b", bundleID, "--args", slackFlag]
            try? open.run()
        }
    }
}
