import GlazeCore
import Testing

@Suite("Deciding whether the controls belong on screen")
struct PlayerChromeTests {
    @Test("A tap while they are up puts them away at once")
    func tapHidesWhenVisible() {
        let intent = PlayerChromeIntent.forTap(visible: true, isPlaying: true)
        #expect(intent == .hide)
        #expect(intent.showsControls == false)
    }

    @Test("A tap while they are hidden brings them back, on a timer")
    func tapRevealsWhenHidden() {
        let intent = PlayerChromeIntent.forTap(visible: false, isPlaying: true)
        #expect(intent == .reveal)
        #expect(intent.startsHideTimer)
    }

    @Test("Paused, they stay put rather than timing out")
    func pausedControlsHold() {
        let intent = PlayerChromeIntent.forTap(visible: false, isPlaying: false)
        #expect(intent == .revealAndHold)
        #expect(intent.showsControls)
        #expect(intent.startsHideTimer == false)
    }

    @Test("Using a control keeps them up instead of toggling them away")
    func usingAControlKeepsThem() {
        #expect(PlayerChromeIntent.afterUse(isPlaying: true) == .reveal)
        #expect(PlayerChromeIntent.afterUse(isPlaying: false) == .revealAndHold)
    }
}
