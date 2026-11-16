import CoreGraphics

/// The dot gets one point heavier per mistake, from 8 pt (one) to 11 pt (four or more).
public func dotDiameter(mistakes: Int) -> CGFloat {
    8 + CGFloat(min(max(mistakes - 1, 0), 3))
}

/// Under the pointer the dot keeps its size and hollows into a ring.
public let dotHoverScale: CGFloat = 1

/// One breath takes about 4 s, varied by ±10% so it never ticks like a metronome. `random` is 0...1.
public func breathingPeriod(random: Double) -> Double {
    4 * (0.9 + 0.2 * random)
}
