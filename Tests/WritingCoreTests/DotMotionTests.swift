import CoreGraphics
import Testing
@testable import WritingCore

@Test func dotGrowsOneStepPerMistakeUpToFour() {
    #expect(dotDiameter(mistakes: 0) == 8)
    #expect(dotDiameter(mistakes: 1) == 8)
    #expect(dotDiameter(mistakes: 2) == 9)
    #expect(dotDiameter(mistakes: 3) == 10)
    #expect(dotDiameter(mistakes: 4) == 11)
    #expect(dotDiameter(mistakes: 40) == 11)
}

@Test func hoverKeepsTheSizeAndHollowsIntoARing() {
    #expect(dotHoverScale == 1)
}

@Test func breathingIsNeverAMetronome() {
    #expect(breathingPeriod(random: 0) == 3.6)
    #expect(abs(breathingPeriod(random: 1) - 4.4) < 0.0001)
}
