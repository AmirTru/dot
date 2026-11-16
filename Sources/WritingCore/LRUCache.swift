public final class LRUCache<Key: Hashable, Value> {
    private let capacity: Int
    private var values: [Key: Value] = [:]
    private var order: [Key] = []

    public init(capacity: Int) { self.capacity = capacity }

    public subscript(key: Key) -> Value? {
        get {
            guard let v = values[key] else { return nil }
            touch(key)
            return v
        }
        set {
            guard let newValue else { values[key] = nil; order.removeAll { $0 == key }; return }
            values[key] = newValue
            touch(key)
            if order.count > capacity { values[order.removeFirst()] = nil }
        }
    }

    private func touch(_ key: Key) {
        order.removeAll { $0 == key }
        order.append(key)
    }
}
