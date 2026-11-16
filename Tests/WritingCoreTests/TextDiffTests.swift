import Foundation
import Testing
@testable import WritingCore

func apply(_ e: [TextEdit], to s: String) -> String { e.reduce(s) { ($0 as NSString).replacingCharacters(in: $1.range, with: $1.replacement) } }
@Test func editsRoundTrip() { let a = "hey team, can yu chek teh deploymnet", b = "Hey team, can you check the deployment"; #expect(apply(wordEdits(from: a, to: b), to: a) == b) }
@Test func mentionUntouched() { let e = wordEdits(from: "@maya teh build", to: "@maya the build"); #expect(e == [TextEdit(range: NSRange(location: 6, length: 3), replacement: "the")]) }
@Test func descendingOrder() { let e = wordEdits(from: "teh a teh", to: "the a the"); #expect(e.map(\.range.location) == [6, 0]) }
@Test func identicalNoEdits() { #expect(wordEdits(from: "same text", to: "same text").isEmpty) }
@Test func highlightRanges() { #expect(changedRanges(from: "can yu go", to: "can you go") == [NSRange(location: 4, length: 3)]) }
@Test func insertionAndDeletionRoundTrip() { let a = "i think there going to need it", b = "They need it before the demo."; #expect(apply(wordEdits(from: a, to: b), to: a) == b) }
@Test func emojiRoundTrip() { let a = "👍 teh 🎉 deal", b = "👍 the 🎉 deal"; #expect(apply(wordEdits(from: a, to: b), to: a) == b) }
@Test func noEmptyRangeEdits() {
    let a = "can yu chek teh deploymnet ", b = "Can you check the deployment?"
    let e = wordEdits(from: a, to: b)
    #expect(e.allSatisfy { $0.range.length > 0 })
    #expect(apply(e, to: a) == b)
}
@Test func insertionAtStartHasRange() {
    let e = wordEdits(from: "go now", to: "Please go now")
    #expect(e.allSatisfy { $0.range.length > 0 })
    #expect(apply(e, to: "go now") == "Please go now")
}
@Test func mergesIntoOneEdit() {
    let a = "can yu chek teh deploymnet ", b = "Can you check the deployment?"
    let e = mergedEdits(wordEdits(from: a, to: b), in: a)
    #expect(e.count == 1)
    #expect(apply(e, to: a) == b)
}
@Test func mentionStaysOutsideMergedEdits() {
    let a = "hi teh @maya chek it", b = "hi the @maya check it"
    let e = mergedEdits(wordEdits(from: a, to: b), in: a)
    #expect(e.count == 2)
    #expect(e.allSatisfy { !(a as NSString).substring(with: $0.range).contains("@maya") })
    #expect(apply(e, to: a) == b)
}
@Test func emojiAndCodeStayOutside() {
    let a = "teh :tada: and `teh` chek", b = "the :tada: and `teh` check"
    let e = mergedEdits(wordEdits(from: a, to: b), in: a)
    #expect(e.count == 2)
    #expect(apply(e, to: a) == b)
}
@Test func overlappingEditsDoNotCrash() {
    let a = "we could of done it"
    let e = mergedEdits([TextEdit(range: NSRange(location: 9, length: 2), replacement: "have"), TextEdit(range: NSRange(location: 3, length: 8), replacement: "could have")], in: a)
    #expect(e.count == 1)
    #expect(apply(e, to: a) == "we could have done it")
}
@Test func doesNotMergeAcrossFormattingBoundary() {
    let a = "teh *bold* chek", b = "the *bold* check"
    let e = mergedEdits(wordEdits(from: a, to: b), in: a, splitAt: [4, 10])
    #expect(e.count == 2)
    #expect(apply(e, to: a) == b)
}
