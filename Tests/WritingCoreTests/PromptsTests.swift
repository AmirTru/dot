import Testing
@testable import WritingCore

@Test func rephraseUsesHumanizerRules() {
    let p = Prompts.action(.rephrase)
    #expect(p.contains("em dash") && p.contains("Not X but Y") && p.contains("different words"))
}
@Test func shortenUsesHumanizerRules() {
    let p = Prompts.action(.shorten)
    #expect(p.contains("em dash") && p.contains("at least a third"))
}
@Test func fixEverythingStaysMinimal() { #expect(Prompts.action(.fixEverything).contains("Change as little as possible")) }
