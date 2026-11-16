import CoreGraphics
import Testing
@testable import WritingCore

@Test func flipsY() { #expect(axRectToAppKit(CGRect(x: 10, y: 100, width: 50, height: 20), primaryScreenHeight: 1000) == CGRect(x: 10, y: 880, width: 50, height: 20)) }
