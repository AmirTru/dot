import Testing
@testable import WritingCore

@Test func waitReturnsTrueWhenConditionTurnsTrue() async {
    var n = 0
    #expect(await waitUntil(timeout: .milliseconds(500)) { n += 1; return n >= 3 })
}
@Test func waitTimesOut() async {
    let start = ContinuousClock.now
    #expect(await waitUntil(timeout: .milliseconds(60)) { false } == false)
    #expect(ContinuousClock.now - start >= .milliseconds(60))
}
