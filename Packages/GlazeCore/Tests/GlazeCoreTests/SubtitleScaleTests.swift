import Testing
@testable import GlazeCore

@Suite("Subtitle size crosses into VLC's units")
struct SubtitleScaleTests {
    @Test("Normal size is one, not one hundred")
    func normalSizeIsOne() {
        #expect(SubtitleScale.fraction(fromPercent: 100) == 1)
    }

    @Test("Every size the interface offers lands inside what VLC accepts")
    func offeredSizesAreAccepted() {
        // The assertion inside libVLC is `scale >= 10 && scale <= 500` on the
        // percentage it derives, so anything outside 0.1...5 crashes a debug build.
        for percent in [SubtitleScale.minimumPercent, 85, 100, 125, 150, SubtitleScale.maximumPercent] {
            let fraction = SubtitleScale.fraction(fromPercent: percent)
            #expect(fraction >= SubtitleScale.minimumFraction)
            #expect(fraction <= SubtitleScale.maximumFraction)
        }
    }

    @Test("A wild value is clamped rather than passed on")
    func wildValuesAreClamped() {
        #expect(SubtitleScale.fraction(fromPercent: 100_000) == SubtitleScale.maximumFraction)
        #expect(SubtitleScale.fraction(fromPercent: 0) == SubtitleScale.minimumFraction)
    }

    @Test("What VLC reports back reads as a percentage again")
    func roundTrips() {
        let percent: Float = 125
        #expect(SubtitleScale.percent(fromFraction: SubtitleScale.fraction(fromPercent: percent)) == percent)
    }

    @Test("The interface's own limits hold")
    func interfaceLimitsHold() {
        #expect(SubtitleScale.clampPercent(10) == SubtitleScale.minimumPercent)
        #expect(SubtitleScale.clampPercent(400) == SubtitleScale.maximumPercent)
        #expect(SubtitleScale.clampPercent(125) == 125)
    }
}
