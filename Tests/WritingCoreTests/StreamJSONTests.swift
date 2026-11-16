import Foundation
import Testing
@testable import WritingCore

@Test func encodesUserLine() throws {
    let line = userMessageLine("a\"b")
    #expect(line.hasSuffix("\n") && !line.dropLast().contains("\n"))
    let obj = try JSONSerialization.jsonObject(with: Data(line.utf8)) as! [String: Any]
    #expect((obj["message"] as! [String: Any])["content"] as? String == "a\"b")
}
@Test func parsesResult() { #expect(parseStreamLine(#"{"type":"result","result":"hi","is_error":false}"#) == .result(text: "hi", isError: false, tokens: 0)) }
@Test func parsesErrorResult() { #expect(parseStreamLine(#"{"type":"result","result":"Not logged in","is_error":true}"#) == .result(text: "Not logged in", isError: true, tokens: 0)) }
@Test func ignoresOther() { #expect(parseStreamLine(#"{"type":"system"}"#) == .other) }
@Test func ignoresGarbage() { #expect(parseStreamLine("not json") == .other) }
@Test func recycleAfter20() { #expect(RecyclePolicy().shouldRecycle(requests: 20, idleFor: 0)); #expect(!RecyclePolicy().shouldRecycle(requests: 19, idleFor: 599)) }
@Test func recycleWhenIdle() { #expect(RecyclePolicy().shouldRecycle(requests: 1, idleFor: 600)) }
@Test func argumentsIsolateUserConfig() {
    let args = claudeArguments(systemPrompt: "P")
    #expect(args.contains("--strict-mcp-config") && args.contains("--disable-slash-commands"))
    #expect(Array(args.suffix(2)) == ["--system-prompt", "P"])
}

@Test func countsAllTokensOfOneTurn() {
    let line = #"{"type":"result","result":"hi","is_error":false,"usage":{"input_tokens":2,"cache_creation_input_tokens":596,"cache_read_input_tokens":10,"output_tokens":6}}"#
    #expect(parseStreamLine(line) == .result(text: "hi", isError: false, tokens: 614))
}
