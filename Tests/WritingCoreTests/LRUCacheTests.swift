import Testing
@testable import WritingCore

@Test func lruEvictsOldest() { let c = LRUCache<String, Int>(capacity: 2); c["a"] = 1; c["b"] = 2; _ = c["a"]; c["c"] = 3; #expect(c["b"] == nil && c["a"] == 1) }
