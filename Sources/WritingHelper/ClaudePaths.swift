import Foundation
import WritingCore

enum ClaudePaths {
    static var executable: URL { found ?? URL(fileURLWithPath: NSHomeDirectory() + "/.local/bin/claude") }
    static var isInstalled: Bool { found != nil }
    private static var found: URL? { findClaude(home: NSHomeDirectory()) }

    /// An empty folder to run Claude Code in, so no project settings or CLAUDE.md get picked up.
    static let workingDirectory: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WritingHelper/claude-cwd")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()
}
