import Foundation
import Testing
@testable import WritingCore

private func checkable(_ t: String) -> [String] {
    let ns = t as NSString
    return checkableWords(in: t, caret: nil, focused: false).map { ns.substring(with: $0) }
}

@Test func skipsURL() { #expect(checkable("see https://github.com/acme/teh-api/pull/88 teh") == ["see", "teh"]) }
@Test func skipsWWW() { #expect(checkable("go to www.exmaple.com now") == ["go", "to", "now"]) }
@Test func skipsEmail() { #expect(checkable("mail dana@example.com plz") == ["mail", "plz"]) }
@Test func skipsMentionAndChannel() { #expect(checkable("@yossii check #infra-teh") == ["check"]) }
@Test func skipsEmoji() { #expect(checkable("nice :tada: :partyparot:") == ["nice"]) }
@Test func skipsInlineCode() { #expect(checkable("run `kubctl get pods` agian") == ["run", "agian"]) }
@Test func skipsCodeBlock() { #expect(checkable("fails:\n```\nnpm run biuld\n```\nwhy") == ["fails", "why"]) }
@Test func skipsPath() { #expect(checkable("edit src/WritngHelper/main.swift pls") == ["edit", "pls"]) }
@Test func haikuMarkInLinkDropped() {
    let t = "look at https://teh.io ok"; let s = sentences(in: t)
    let marks = s.flatMap { mapIssues([.init(wrong: "teh", fix: "the", kind: "spelling")], sentence: $0, in: t) }
    #expect(marks.filter { !isProtected($0.range, in: t) }.isEmpty)
}
