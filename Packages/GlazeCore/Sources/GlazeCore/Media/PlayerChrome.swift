import Foundation

/// When the controls over a film should be on screen.
///
/// Written as a decision rather than as a pile of flags in a view because the rule is
/// easy to get subtly wrong: a tap while the bar is already up used to restart its
/// five-second timer, so the bar someone was trying to dismiss stayed for another five
/// seconds. A tap is a request either way — show me, or get out of my way.
public enum PlayerChromeIntent: Equatable, Sendable {
    /// Put the controls up and start the clock that takes them down again.
    case reveal
    /// Take them down now.
    case hide
    /// Put them up and leave them there: nothing is moving, so nothing is in the way.
    case revealAndHold

    /// - Parameters:
    ///   - visible: whether the controls are on screen now.
    ///   - isPlaying: a paused film has nothing to get out of the way of.
    public static func forTap(visible: Bool, isPlaying: Bool) -> PlayerChromeIntent {
        if visible { return .hide }
        return isPlaying ? .reveal : .revealAndHold
    }

    /// After a button is used, or a scrub ends: the viewer is working with the
    /// controls, so they stay a while longer rather than being toggled away.
    public static func afterUse(isPlaying: Bool) -> PlayerChromeIntent {
        isPlaying ? .reveal : .revealAndHold
    }

    public var showsControls: Bool { self != .hide }
    public var startsHideTimer: Bool { self == .reveal }
}
