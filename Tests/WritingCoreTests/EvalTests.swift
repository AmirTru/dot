import Foundation
import Testing
@testable import WritingCore

/// Runs every eval case against the real Haiku and grades it. Costs one model call per case (~62).
/// Run with: WH_EVAL=1 scripts/test.sh --filter EvalPrompts
/// WH_EVAL_ONLY=check,fixEverything,rephrase,shorten limits the prompts; WH_EVAL_OUT=<file> saves the results as JSON.
@Test(.enabled(if: ProcessInfo.processInfo.environment["WH_EVAL"] == "1"))
func EvalPrompts() async throws {
    let env = ProcessInfo.processInfo.environment
    let only = env["WH_EVAL_ONLY"].map { Set($0.split(separator: ",").map(String.init)) }
    let wanted = { (name: String) in only?.contains(name) ?? true }
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("wh-eval")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let exe = findClaude(home: NSHomeDirectory())!

    // One lane per prompt, cases in order, like the app: history carries over between requests.
    let results = await withTaskGroup(of: [EvalResult].self) { group in
        if wanted("check") {
            group.addTask {
                let lane = ClaudeLane(executable: exe, systemPrompt: Prompts.check, workingDirectory: dir)
                var out: [EvalResult] = []
                for c in checkCases {
                    let raw = (try? await lane.send(c.text, timeout: .seconds(30))) ?? "<error>"
                    out.append(EvalResult(prompt: "check", id: c.id, input: c.text, output: raw, failures: gradeCheck(c, raw)))
                }
                return out
            }
        }
        for (name, action) in [("fixEverything", WritingAction.fixEverything), ("rephrase", .rephrase), ("shorten", .shorten)] where wanted(name) {
            group.addTask {
                let lane = ClaudeLane(executable: exe, systemPrompt: Prompts.action(action), workingDirectory: dir)
                var out: [EvalResult] = []
                for c in actionCases where c.action == action {
                    let raw = (try? await lane.send(c.text, timeout: .seconds(30))) ?? "<error>"
                    let cleaned = cleanResult(raw, original: c.text)
                    out.append(EvalResult(prompt: name, id: c.id, input: c.text, output: cleaned, failures: gradeAction(c, cleaned)))
                }
                return out
            }
        }
        var all: [EvalResult] = []
        for await r in group { all += r }
        return all
    }

    for prompt in ["check", "fixEverything", "rephrase", "shorten"] {
        let rs = results.filter { $0.prompt == prompt }
        guard !rs.isEmpty else { continue }
        print("EVAL \(prompt): \(rs.filter(\.failures.isEmpty).count)/\(rs.count) passed")
        for r in rs {
            print("  [\(r.failures.isEmpty ? "PASS" : "FAIL")] \(r.id): \(r.output)")
            for f in r.failures { print("      - \(f)") }
        }
    }
    if let path = env["WH_EVAL_OUT"] {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        try enc.encode(results).write(to: URL(fileURLWithPath: path))
    }
}

struct EvalResult: Codable {
    let prompt, id, input, output: String
    let failures: [String]
}

func hasHebrew(_ s: String) -> Bool { s.unicodeScalars.contains { (0x0590...0x05FF).contains($0.value) } }
func hasLatin(_ s: String) -> Bool { s.unicodeScalars.contains { ("a"..."z").contains($0) || ("A"..."Z").contains($0) } }

/// Whole word or phrase, case-insensitive. A Hebrew word may carry up to two prefix letters (ה, ל, ב, ו, ש, מ, כ).
private func containsWord(_ text: String, _ word: String) -> Bool {
    let prefix = hasHebrew(word) ? "(?:[והבלמשכ]{0,2}-?)" : ""
    let pattern = "(?<![\\p{L}\\p{N}])" + prefix + NSRegularExpression.escapedPattern(for: word) + "(?![\\p{L}\\p{N}])"
    let regex = try! NSRegularExpression(pattern: pattern, options: .caseInsensitive)
    return regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
}

func words(_ s: String) -> [String] {
    s.lowercased().split(whereSeparator: \.isWhitespace)
        .map { $0.trimmingCharacters(in: .punctuationCharacters) }
        .filter { !$0.isEmpty }
}

private func lcs(_ a: [String], _ b: [String]) -> Int {
    var row = Array(repeating: 0, count: b.count + 1)
    for x in a {
        var prev = 0
        for (j, y) in b.enumerated() {
            let saved = row[j + 1]
            row[j + 1] = x == y ? prev + 1 : max(row[j + 1], row[j])
            prev = saved
        }
    }
    return row[b.count]
}

func gradeCheck(_ c: CheckCase, _ raw: String) -> [String] {
    guard let issues = parseIssues(raw) else { return ["not valid issues JSON"] }
    var failures: [String] = []
    let matches = { (issue: HaikuIssue, alts: [String]) in
        alts.contains { issue.wrong.lowercased() == $0.lowercased() || containsWord(issue.wrong, $0) }
    }
    for (i, alts) in c.expect.enumerated() {
        guard let hit = issues.first(where: { matches($0, alts) }) else { failures.append("missed \(alts[0])"); continue }
        let fixes = i < c.fixes.count ? c.fixes[i] : []
        if !fixes.isEmpty, !fixes.contains(where: { hit.fix.lowercased().contains($0.lowercased()) }) {
            failures.append("wrong fix for \(hit.wrong): \(hit.fix)")
        }
    }
    for issue in issues {
        if !containsWord(c.text, issue.wrong) { failures.append("flagged text not in sentence: \(issue.wrong)") }
        if !c.expect.contains(where: { matches(issue, $0) }) && !c.allow.contains(where: { $0.lowercased() == issue.wrong.lowercased() }) {
            failures.append("false positive: \(issue.wrong) → \(issue.fix)")
        }
        if hasHebrew(issue.wrong) != hasHebrew(issue.fix) { failures.append("fix changed language: \(issue.wrong) → \(issue.fix)") }
        if !["spelling", "word_choice"].contains(issue.kind) { failures.append("bad kind: \(issue.kind)") }
    }
    return failures
}

private let tells = ["—", "–", "hope this helps", "feel free", "great question", "here's the thing", "quick note",
                     "crucial", "pivotal", "seamless", "delve", "leverage", "robust", "showcase", "additionally", "not just"]

func gradeAction(_ c: ActionCase, _ out: String) -> [String] {
    if out == "<error>" || out.isEmpty { return ["no answer"] }
    var failures: [String] = []
    if ["ok", "ok.", "done", "done."].contains(out.lowercased()) { failures.append("followed embedded instruction") }
    for alts in c.contains where !alts.contains(where: { containsWord(out, $0) }) { failures.append("lost \(alts[0])") }
    for a in c.absent where out.lowercased().contains(a.lowercased()) { failures.append("contains \(a)") }
    for t in c.exact where !out.contains(t) { failures.append("changed \(t)") }
    let invisible = { (s: String) in s.unicodeScalars.filter { $0.properties.generalCategory == .format }.count }
    if invisible(out) > invisible(c.text) { failures.append("invisible character added") }
    if out.filter({ $0 == "\n" }).count != c.text.filter({ $0 == "\n" }).count { failures.append("line breaks changed") }
    if hasHebrew(out) != hasHebrew(c.text) || hasLatin(out) != hasLatin(c.text) { failures.append("language mix changed") }
    let ratio = Double(words(out).count) / Double(words(c.text).count)
    if let r = c.ratio, !r.contains(ratio) { failures.append(String(format: "length ratio %.2f outside %.2f...%.2f", ratio, r.lowerBound, r.upperBound)) }
    if c.action != .fixEverything {
        if c.text.contains("?") && !out.contains("?") { failures.append("question became a statement") }
        for t in tells where out.lowercased().contains(t) { failures.append("AI tell: \(t)") }
        if out.range(of: "\\bnot\\b[^.]{1,40}\\bbut\\b", options: [.regularExpression, .caseInsensitive]) != nil { failures.append("AI tell: not X but Y") }
    }
    if c.action == .rephrase, let fixed = c.fixed {
        let same = Double(lcs(words(fixed), words(out))) / Double(words(fixed).count)
        if same > 0.8 { failures.append(String(format: "barely reworded (%.0f%% of words kept in order)", same * 100)) }
    }
    return failures
}
