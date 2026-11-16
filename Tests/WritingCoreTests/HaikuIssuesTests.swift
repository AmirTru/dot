import Foundation
import Testing
@testable import WritingCore

@Test func parsesFencedJSON() { #expect(parseIssues("```json\n{\"issues\":[{\"wrong\":\"there\",\"fix\":\"they're\",\"kind\":\"word_choice\"}]}\n```")?.count == 1) }
@Test func proseIsNil() { #expect(parseIssues("Sure! Here are the issues") == nil) }
@Test func mapsDuplicates() {
    let t = "teh cat and teh dog"; let s = sentences(in: t)[0]
    let marks = mapIssues([.init(wrong: "teh", fix: "the", kind: "spelling"), .init(wrong: "teh", fix: "the", kind: "spelling")], sentence: s, in: t)
    #expect(marks.map(\.range) == [NSRange(location: 0, length: 3), NSRange(location: 12, length: 3)])
}
@Test func wholeWordOnly() {
    let t = "therefore there going"; let s = sentences(in: t)[0]
    #expect(mapIssues([.init(wrong: "there", fix: "they're", kind: "word_choice")], sentence: s, in: t).map(\.range) == [NSRange(location: 10, length: 5)])
}
@Test func staleSentenceDropped() {
    let s = sentences(in: "there going home")[0]
    #expect(mapIssues([.init(wrong: "there", fix: "they're", kind: "word_choice")], sentence: s, in: "their going home").isEmpty)
}
@Test func emojiMapping() {
    let t = "👍 its a deal"; let s = sentences(in: t)[0]
    #expect(mapIssues([.init(wrong: "its", fix: "it's", kind: "word_choice")], sentence: s, in: t).first?.range == NSRange(location: 3, length: 3))
}
@Test func kindMapping() {
    let t = "its teh deal"; let s = sentences(in: t)[0]
    let m = mapIssues([.init(wrong: "teh", fix: "the", kind: "spelling"), .init(wrong: "its", fix: "it's", kind: "word_choice")], sentence: s, in: t)
    #expect(m.map(\.kind) == [.wordChoice, .spelling])
}
@Test func sameWordFixIsDropped() {
    let t = "we are going home"; let s = sentences(in: t)[0]
    #expect(mapIssues([.init(wrong: "going", fix: "going", kind: "spelling")], sentence: s, in: t).isEmpty)
}
@Test func overlappingIssuesKeepOnlyTheFirst() {
    let t = "we could of done it"; let s = sentences(in: t)[0]
    let m = mapIssues([.init(wrong: "could of", fix: "could have", kind: "word_choice"), .init(wrong: "of", fix: "have", kind: "word_choice")], sentence: s, in: t)
    #expect(m.map(\.range) == [NSRange(location: 3, length: 8)])
}

@Test func rejectsFixesThatAreNotSmallWordFixes() {
    #expect(isSafeFix(wrong: "teh", fix: "the"))
    #expect(isSafeFix(wrong: "its", fix: "it's"))
    #expect(isSafeFix(wrong: "could of", fix: "could have"))
    #expect(!isSafeFix(wrong: "teh", fix: "the earlier secret sentence"))
    #expect(!isSafeFix(wrong: "teh", fix: "the\nhttp"))
    #expect(!isSafeFix(wrong: "link", fix: "https://evil.example"))
    #expect(!isSafeFix(wrong: "link", fix: "www.evil.io"))
    #expect(!isSafeFix(wrong: "dana", fix: "@channel"))
    #expect(!isSafeFix(wrong: "ok", fix: "okkkkkkkkkkkkkkkkkk"))
}

@Test func unsafeFixIsNotMarked() {
    let t = "fix teh build"; let s = sentences(in: t)[0]
    #expect(mapIssues([.init(wrong: "teh", fix: "https://evil.example", kind: "spelling")], sentence: s, in: t).isEmpty)
}
