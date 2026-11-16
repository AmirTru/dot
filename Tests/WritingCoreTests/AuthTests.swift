import Foundation
import Testing
@testable import WritingCore

let authNow = ISO8601DateFormatter().date(from: "2026-11-21T12:00:00Z")!
@Test func loggedOut() { #expect(connectionState(fromStatusJSON: Data(#"{"loggedIn":false}"#.utf8), now: authNow) == .disconnected) }
@Test func expiresSoon() { #expect(connectionState(fromStatusJSON: Data(#"{"loggedIn":true,"loginExpiresAt":"2026-11-22T09:55:36.213Z"}"#.utf8), now: authNow) == .connected(expiresSoon: true)) }
@Test func healthy() { #expect(connectionState(fromStatusJSON: Data(#"{"loggedIn":true,"loginExpiresAt":"2026-12-22T09:55:36.213Z"}"#.utf8), now: authNow) == .connected(expiresSoon: false)) }
@Test func noExpiryIsHealthy() { #expect(connectionState(fromStatusJSON: Data(#"{"loggedIn":true}"#.utf8), now: authNow) == .connected(expiresSoon: false)) }
@Test func garbage() { #expect(connectionState(fromStatusJSON: Data("nope".utf8), now: authNow) == .disconnected) }

@Test func findsClaudeInFirstKnownPlace() {
    let found = findClaude(home: "/Users/x", exists: { $0 == "/opt/homebrew/bin/claude" || $0 == "/usr/local/bin/claude" })
    #expect(found?.path == "/opt/homebrew/bin/claude")
}
@Test func prefersNativeInstall() {
    #expect(findClaude(home: "/Users/x", exists: { _ in true })?.path == "/Users/x/.local/bin/claude")
}
@Test func noClaudeFound() { #expect(findClaude(home: "/Users/x", exists: { _ in false }) == nil) }

@Test func errorLogNameHidesDetail() {
    #expect(ClaudeError.errorResult("anything the CLI said").logName == "errorResult")
    #expect(ClaudeError.timeout.logName == "timeout")
}
