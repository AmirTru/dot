import Foundation

/// Debug log at ~/Library/Logs/WritingHelper.log. Records lengths and offsets, never the typed text.
enum Log {
    private static let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/WritingHelper.log")
    private static let handle: FileHandle? = {
        FileManager.default.createFile(atPath: url.path, contents: nil)
        return try? FileHandle(forWritingTo: url)
    }()
    private static let time: DateFormatter = { let f = DateFormatter(); f.dateFormat = "HH:mm:ss.SSS"; return f }()

    static func write(_ message: String) {
        handle?.write(Data("\(time.string(from: Date())) \(message)\n".utf8))
    }
}
