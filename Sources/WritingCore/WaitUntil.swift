/// Polls `condition` every 15 ms until it is true or `timeout` passes. Accessibility writes
/// in Slack and Zen land asynchronously, so every step waits for its effect.
@MainActor
public func waitUntil(timeout: Duration, _ condition: () -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(15))
    }
    return condition()
}
