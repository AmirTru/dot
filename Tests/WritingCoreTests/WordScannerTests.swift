import Foundation
import Testing
@testable import WritingCore

@Test func unfinishedWordIgnored() { #expect(finishedWords(in: "teh", caret: 3, focused: true).isEmpty) }
@Test func wordEndsAtSpace() { #expect(finishedWords(in: "teh ", caret: 4, focused: true) == [NSRange(location: 0, length: 3)]) }
@Test func blurFinishesLastWord() { #expect(finishedWords(in: "teh", caret: nil, focused: false) == [NSRange(location: 0, length: 3)]) }
@Test func caretInsideWordSkipsIt() { #expect(finishedWords(in: "teh cat ", caret: 2, focused: true) == [NSRange(location: 4, length: 3)]) }
@Test func emojiOffsetsAreUTF16() { #expect(finishedWords(in: "👍 teh ", caret: 7, focused: true) == [NSRange(location: 3, length: 3)]) }
@Test func apostropheIsPartOfWord() { #expect(finishedWords(in: "dont'z ", caret: 7, focused: true) == [NSRange(location: 0, length: 6)]) }

@Test func typingMeansAKeyInTheLastSecondAndAHalf() {
    let now = Date(timeIntervalSince1970: 100)
    #expect(isTyping(lastEdit: Date(timeIntervalSince1970: 99), now: now))
    #expect(!isTyping(lastEdit: Date(timeIntervalSince1970: 98), now: now))
    #expect(!isTyping(lastEdit: nil, now: now))
}

@Test func afterTypingTheCaretWordAndLastWordCount() {
    #expect(finishedWords(in: "teh deploymnet", caret: 1, focused: false) == [NSRange(location: 0, length: 3), NSRange(location: 4, length: 10)])
}
