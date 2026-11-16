import Foundation
import Testing
@testable import WritingCore

@Test func hebrewWordUsesHebrew() { #expect(spellLanguage(for: "שלוום") == "he") }
@Test func englishWordUsesEnglish() { #expect(spellLanguage(for: "teh") == "en") }
@Test func hebrewTextIsRightToLeft() { #expect(isRightToLeft("שלום team")) }
@Test func englishTextIsLeftToRight() { #expect(!isRightToLeft("hi שלום")) }
@Test func leadingDigitsAndSpaceSkipped() { #expect(isRightToLeft("  12 מחר")) }
@Test func emptyIsLeftToRight() { #expect(!isRightToLeft("")) }
@Test func hebrewWordsFound() { #expect(finishedWords(in: "שלוום לך ", caret: 9, focused: true) == [NSRange(location: 0, length: 5), NSRange(location: 6, length: 2)]) }
@Test func niqqudStaysInsideWord() { #expect(finishedWords(in: "שָׁלוֹם ", caret: 8, focused: true) == [NSRange(location: 0, length: 7)]) }
@Test func mixedSentenceMapping() {
    let t = "תבדוק את teh build"; let s = sentences(in: t)[0]
    #expect(mapIssues([.init(wrong: "teh", fix: "the", kind: "spelling"), .init(wrong: "תבדוק", fix: "תבדק", kind: "spelling")], sentence: s, in: t).map(\.range)
            == [NSRange(location: 0, length: 5), NSRange(location: 9, length: 3)])
}
@Test func hebrewEditsRoundTrip() { let a = "שלוום חברים, מה נישמע", b = "שלום חברים, מה נשמע"; #expect(apply(mergedEdits(wordEdits(from: a, to: b), in: a), to: a) == b) }

@Test func hebrewSpellingIsLeftToHaikuWhenConnected() {
    #expect(!trustsLocalSpelling(of: "הטעתי", connected: true))
    #expect(trustsLocalSpelling(of: "הטעתי", connected: false))
    #expect(trustsLocalSpelling(of: "teh", connected: true))
}
