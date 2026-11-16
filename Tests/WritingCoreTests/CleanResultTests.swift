import Testing
@testable import WritingCore

@Test func removesAddedLineBreaks() { #expect(cleanResult("the build\nתבדוק את", original: "teh build תבדוק את") == "the build תבדוק את") }
@Test func keepsRealLineBreaks() { #expect(cleanResult("hi\nthere", original: "hi\nthere") == "hi\nthere") }
@Test func stripsWrappingQuotes() { #expect(cleanResult("\"the build\"", original: "teh build") == "the build") }
@Test func keepsQuotesTheWriterUsed() { #expect(cleanResult("\"ok\"", original: "\"ok\"") == "\"ok\"") }
@Test func trimsWhitespace() { #expect(cleanResult("  the build \n", original: "teh build") == "the build") }
