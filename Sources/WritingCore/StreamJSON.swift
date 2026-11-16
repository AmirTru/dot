import Foundation

public enum StreamEvent: Equatable, Sendable {
    case result(text: String, isError: Bool, tokens: Int)
    case other
}

public func userMessageLine(_ text: String) -> String {
    let content = String(decoding: try! JSONEncoder().encode(text), as: UTF8.self)
    return #"{"type":"user","message":{"role":"user","content":"# + content + "}}\n"
}

public func parseStreamLine(_ line: String) -> StreamEvent {
    guard let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
          obj["type"] as? String == "result"
    else { return .other }
    let usage = obj["usage"] as? [String: Any] ?? [:]
    let tokens = ["input_tokens", "cache_creation_input_tokens", "cache_read_input_tokens", "output_tokens"]
        .reduce(0) { $0 + (usage[$1] as? Int ?? 0) }
    return .result(text: obj["result"] as? String ?? "", isError: obj["is_error"] as? Bool ?? false, tokens: tokens)
}

/// Flags for a warm Haiku process. The isolation flags keep the user's own Claude Code
/// setup (CLAUDE.md, MCP servers, skills) out of the context: measured 327,553 vs 615
/// input tokens per call.
public func claudeArguments(systemPrompt: String) -> [String] {
    ["-p", "--model", "haiku",
     "--input-format", "stream-json", "--output-format", "stream-json", "--verbose",
     "--tools", "", "--no-session-persistence",
     "--setting-sources", "project", "--strict-mcp-config", "--disable-slash-commands",
     "--system-prompt", systemPrompt]
}
