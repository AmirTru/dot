import Foundation
import Testing
@testable import WritingCore

let fakeURL = Bundle.module.url(forResource: "fake-claude", withExtension: "sh", subdirectory: "Fixtures")!

@Test func laneRoundTrip() async throws {
    let lane = ClaudeLane(executable: fakeURL, systemPrompt: "x")
    #expect(try await lane.send("hi", timeout: .seconds(4)) == "ECHO:hi")
}
@Test func laneRecoversAfterCrash() async throws {
    let lane = ClaudeLane(executable: fakeURL, systemPrompt: "exit-after-1")
    _ = try await lane.send("one", timeout: .seconds(4))
    #expect(try await lane.send("two", timeout: .seconds(4)) == "ECHO:two")
}
@Test func laneRecyclesAt20() async throws {
    let lane = ClaudeLane(executable: fakeURL, systemPrompt: "x", policy: .init(maxRequests: 2))
    for i in 0..<5 { #expect(try await lane.send("\(i)", timeout: .seconds(4)) == "ECHO:\(i)") }
}
@Test func newerSendCancelsQueuedOlder() async throws {
    let lane = ClaudeLane(executable: fakeURL, systemPrompt: "slow")
    async let first = lane.send("a", timeout: .seconds(4))
    try await Task.sleep(for: .milliseconds(5))
    async let second = lane.send("b", timeout: .seconds(4))
    try await Task.sleep(for: .milliseconds(5))
    async let third = lane.send("c", timeout: .seconds(4))
    let r1 = try? await first, r2 = try? await second, r3 = try await third
    #expect(r1 == "ECHO:a" && r2 == nil && r3 == "ECHO:c")
}
@Test func laneWorksAfterIdleShutdown() async throws {
    let lane = ClaudeLane(executable: fakeURL, systemPrompt: "x")
    _ = try await lane.send("a", timeout: .seconds(4))
    await lane.shutDownIfIdle(for: 0)
    #expect(await lane.isRunning == false)
    #expect(try await lane.send("b", timeout: .seconds(4)) == "ECHO:b")
}
