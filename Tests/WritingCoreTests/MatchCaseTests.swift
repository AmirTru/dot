import Testing
@testable import WritingCore

@Test func keepsCapital() { #expect(matchCase(of: "Teh", "the") == "The") }
@Test func neverLowersFix() { #expect(matchCase(of: "i", "I") == "I") }
@Test func lowerStaysLower() { #expect(matchCase(of: "teh", "the") == "the") }
@Test func emptyFix() { #expect(matchCase(of: "Teh", "") == "") }
