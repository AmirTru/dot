import Foundation

/// Tokens used per calendar day, for the menu's today / week / month counts. Only counts, never text.
public struct TokenLedger: Codable, Equatable, Sendable {
    public private(set) var days: [String: Int] = [:]
    public init() {}

    public mutating func add(_ tokens: Int, on date: Date, calendar: Calendar = .current) {
        days[key(date, calendar), default: 0] += tokens
        let cutoff = key(calendar.date(byAdding: .day, value: -62, to: date)!, calendar)
        days = days.filter { $0.key >= cutoff }
    }

    public func totals(now: Date, calendar: Calendar = .current) -> (today: Int, week: Int, month: Int) {
        func since(_ unit: Calendar.Component) -> Int {
            let start = key(calendar.dateInterval(of: unit, for: now)!.start, calendar)
            return days.filter { $0.key >= start }.values.reduce(0, +)
        }
        return (days[key(now, calendar)] ?? 0, since(.weekOfYear), since(.month))
    }

    private func key(_ date: Date, _ calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }
}

/// 950 → "950", 12,340 → "12.3K", 2,500,000 → "2.5M".
public func shortCount(_ n: Int) -> String {
    switch n {
    case ..<1_000: "\(n)"
    case ..<1_000_000: String(format: "%.1fK", Double(n) / 1_000)
    default: String(format: "%.1fM", Double(n) / 1_000_000)
    }
}
