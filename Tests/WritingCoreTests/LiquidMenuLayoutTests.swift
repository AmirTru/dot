import CoreGraphics
import Testing
@testable import WritingCore

private let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
private let size = CGSize(width: 220, height: 100)

@Test func opensUpWhenRoomAbove() {
    let input = CGRect(x: 100, y: 300, width: 400, height: 80)
    let dot = CGRect(x: 108, y: 360, width: 9, height: 9)
    let l = liquidLayout(dot: dot, input: input, menuSize: size, screen: screen)
    #expect(l.opensUp)
    #expect(l.menu == CGRect(x: 108, y: 386, width: 220, height: 100))
}

@Test func opensDownWhenNoRoomAbove() {
    let input = CGRect(x: 100, y: 650, width: 400, height: 80)
    let dot = CGRect(x: 108, y: 710, width: 9, height: 9)
    let l = liquidLayout(dot: dot, input: input, menuSize: size, screen: screen)
    #expect(!l.opensUp)
    #expect(l.menu == CGRect(x: 108, y: 604, width: 220, height: 100))
}

@Test func menuStaysInsideScreenHorizontally() {
    let input = CGRect(x: 700, y: 300, width: 290, height: 80)
    let dot = CGRect(x: 900, y: 360, width: 9, height: 9)
    let l = liquidLayout(dot: dot, input: input, menuSize: size, screen: screen)
    #expect(l.menu.maxX == 992)
}

@Test func panelCoversDotAndMenu() {
    let input = CGRect(x: 100, y: 300, width: 400, height: 80)
    let dot = CGRect(x: 108, y: 360, width: 9, height: 9)
    let l = liquidLayout(dot: dot, input: input, menuSize: size, screen: screen)
    #expect(l.panel.contains(l.menu.insetBy(dx: -15, dy: -15)))
    #expect(l.panel.contains(dot.insetBy(dx: -15, dy: -15)))
}

@Test func arrowsSkipDisabledItems() {
    let enabled = [false, true, true]
    #expect(nextEnabledIndex(from: nil, step: 1, enabled: enabled) == 1)
    #expect(nextEnabledIndex(from: 1, step: -1, enabled: enabled) == 2)
    #expect(nextEnabledIndex(from: nil, step: -1, enabled: enabled) == 2)
}

@Test func arrowsWrapAround() {
    #expect(nextEnabledIndex(from: 2, step: 1, enabled: [true, true, true]) == 0)
}

@Test func noEnabledItems() {
    #expect(nextEnabledIndex(from: nil, step: 1, enabled: [false, false]) == nil)
}

@Test func cornerIsCircleWhenSmallAndCappedWhenLarge() {
    #expect(liquidCornerRadius(width: 9, height: 9) == 4.5)
    #expect(liquidCornerRadius(width: 220, height: 100) == 12)
}
