import Testing
@testable import WritingCore

@Test func splitsSentences() { #expect(sentences(in: "hi there. ok?").map(\.text) == ["hi there.", "ok?"]) }
@Test func oneWordNotCheckable() { #expect(sentences(in: "ok.")[0].isCheckable == false) }
