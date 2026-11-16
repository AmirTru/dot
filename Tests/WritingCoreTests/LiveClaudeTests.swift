import Foundation
import Testing
@testable import WritingCore

/// Talks to the real Claude Code. Run with: WH_LIVE=1 scripts/test.sh --filter Live
@Test(.enabled(if: ProcessInfo.processInfo.environment["WH_LIVE"] == "1"))
func LiveSentenceCheck() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("wh-live")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let lane = ClaudeLane(executable: findClaude(home: NSHomeDirectory())!, systemPrompt: Prompts.check, workingDirectory: dir)
    let first = try await lane.send("can yu chek teh deploymnet", timeout: .seconds(10))
    #expect((parseIssues(first)?.count ?? 0) >= 3)
    let start = ContinuousClock.now
    let second = try await lane.send("i think there going to be late", timeout: .seconds(10))
    let elapsed = ContinuousClock.now - start
    print("LIVE second:", second, elapsed)
    #expect(parseIssues(second)?.contains { $0.fix.lowercased() == "they're" } == true)
    #expect(elapsed < .seconds(2))
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["WH_LIVE"] == "1"))
func LiveHebrewCheck() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("wh-live")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let lane = ClaudeLane(executable: findClaude(home: NSHomeDirectory())!, systemPrompt: Prompts.check, workingDirectory: dir)
    let raw = try await lane.send("אני רוצה לבדוק את הדיפלוי מחר בבוקער", timeout: .seconds(10))
    print("LIVE hebrew:", raw)
    #expect(parseIssues(raw)?.contains { $0.wrong == "בבוקער" } == true)
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["WH_LIVE"] == "1"))
func LiveMixedFix() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("wh-live")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let lane = ClaudeLane(executable: findClaude(home: NSHomeDirectory())!, systemPrompt: Prompts.action(.fixEverything), workingDirectory: dir)
    let out = try await lane.send("teh build תבדוק את", timeout: .seconds(10))
    print("LIVE mixed fix:", out.debugDescription)
    #expect(out.contains("the build") && !out.contains("\n"))
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["WH_LIVE"] == "1"))
func LiveRephraseAndShorten() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("wh-live")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let exe = findClaude(home: NSHomeDirectory())!
    let text = "hey so i think we shoud probaly look at the deploymnet tomorow becuase the stagin enviroment is kind of broken and nobody realy knows why it happend"
    let words = { (s: String) in s.split(whereSeparator: \.isWhitespace).count }
    let rephrased = try await ClaudeLane(executable: exe, systemPrompt: Prompts.action(.rephrase), workingDirectory: dir).send(text, timeout: .seconds(15))
    let shortened = try await ClaudeLane(executable: exe, systemPrompt: Prompts.action(.shorten), workingDirectory: dir).send(text, timeout: .seconds(15))
    print("LIVE rephrase:", rephrased)
    print("LIVE shorten:", shortened, words(shortened), "vs", words(text))
    #expect(changedRanges(from: fixAllTypos(text), to: rephrased).count >= 3)
    #expect(Double(words(shortened)) <= Double(words(text)) * 0.75)
    #expect(!rephrased.contains("—") && !shortened.contains("—"))
}

private func fixAllTypos(_ s: String) -> String {
    ["shoud": "should", "probaly": "probably", "deploymnet": "deployment", "tomorow": "tomorrow", "becuase": "because",
     "stagin": "staging", "enviroment": "environment", "realy": "really", "happend": "happened"]
        .reduce(s) { $0.replacingOccurrences(of: $1.key, with: $1.value) }
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["WH_LIVE"] == "1"))
func LiveShortenKeepsReason() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("wh-live")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let exe = findClaude(home: NSHomeDirectory())!
    let cases = [
        "we need to push the release to next week because the migration isnt tested yet and qa is out",
        "can you restart the worker pods since they keep crashing after the config change",
        "אני חושב שצריך לדחות את הדיפלוי כי הסטייג׳ינג שבור ואף אחד לא יודע למה",
    ]
    var kept = 0
    for text in cases {
        let out = try await ClaudeLane(executable: exe, systemPrompt: Prompts.action(.shorten), workingDirectory: dir).send(text, timeout: .seconds(15))
        let ok = ["because", "since", "so ", "כי", "בגלל"].contains { out.lowercased().contains($0) }
        if ok { kept += 1 }
        print("LIVE shorten reason:", ok, "|", out)
    }
    #expect(kept == cases.count)
}
