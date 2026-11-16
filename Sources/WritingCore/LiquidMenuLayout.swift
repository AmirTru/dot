import CoreGraphics

/// Where the liquid menu sits. All rects are screen coordinates with y up (AppKit).
public struct LiquidLayout: Equatable, Sendable {
    /// The transparent window, big enough for the dot, the open menu, and spring overshoot.
    public let panel: CGRect
    public let dot: CGRect
    /// The menu's final open frame.
    public let menu: CGRect
    public let opensUp: Bool

    public init(panel: CGRect, dot: CGRect, menu: CGRect, opensUp: Bool) {
        self.panel = panel; self.dot = dot; self.menu = menu; self.opensUp = opensUp
    }
}

/// The menu opens above the text box when it fits, else below the dot's line; it never covers the text.
public func liquidLayout(dot: CGRect, input: CGRect, menuSize: CGSize, screen: CGRect,
                         gap: CGFloat = 6, margin: CGFloat = 16) -> LiquidLayout {
    let opensUp = input.maxY + gap + menuSize.height + margin <= screen.maxY
    let y = opensUp ? input.maxY + gap : dot.minY - gap - menuSize.height
    let x = min(dot.minX, screen.maxX - 8 - menuSize.width)
    let menu = CGRect(x: x, y: y, width: menuSize.width, height: menuSize.height)
    return LiquidLayout(panel: menu.union(dot).insetBy(dx: -margin, dy: -margin), dot: dot, menu: menu, opensUp: opensUp)
}

/// The next selectable row for an arrow key, wrapping around and skipping disabled rows.
public func nextEnabledIndex(from: Int?, step: Int, enabled: [Bool]) -> Int? {
    guard enabled.contains(true) else { return nil }
    let n = enabled.count
    var i = from ?? (step > 0 ? -1 : n)
    repeat { i = ((i + step) % n + n) % n } while !enabled[i]
    return i
}

/// A circle at dot size, a rounded menu when open.
public func liquidCornerRadius(width: CGFloat, height: CGFloat, cap: CGFloat = 12) -> CGFloat {
    min(min(width, height) / 2, cap)
}
