import Foundation
import Testing
@testable import WritingCore

private let cal: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; c.firstWeekday = 1; return c }()
private func day(_ s: String) -> Date { ISO8601DateFormatter().date(from: s + "T12:00:00Z")! }

@Test func totalsTodayWeekMonth() {
    var ledger = TokenLedger()
    ledger.add(100, on: day("2026-10-31"), calendar: cal)   // last month
    ledger.add(10, on: day("2026-11-02"), calendar: cal)    // this month, earlier week
    ledger.add(20, on: day("2026-11-15"), calendar: cal)    // Sunday, this week
    ledger.add(5, on: day("2026-11-16"), calendar: cal)
    ledger.add(5, on: day("2026-11-16"), calendar: cal)
    let t = ledger.totals(now: day("2026-11-16"), calendar: cal)
    #expect(t.today == 10)
    #expect(t.week == 30)
    #expect(t.month == 40)
}

@Test func dropsDaysOlderThanTwoMonths() {
    var ledger = TokenLedger()
    ledger.add(1, on: day("2026-08-01"), calendar: cal)
    ledger.add(1, on: day("2026-11-16"), calendar: cal)
    #expect(ledger.days.count == 1)
}

@Test func ledgerRoundTripsAsJSON() throws {
    var ledger = TokenLedger()
    ledger.add(7, on: day("2026-11-16"), calendar: cal)
    let back = try JSONDecoder().decode(TokenLedger.self, from: JSONEncoder().encode(ledger))
    #expect(back == ledger)
}

@Test func shortTokenCounts() {
    #expect(shortCount(950) == "950")
    #expect(shortCount(12_340) == "12.3K")
    #expect(shortCount(2_500_000) == "2.5M")
}
