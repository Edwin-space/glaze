import AVFoundation
import MediaPlayer
import UIKit

/// Moves the system volume from a swipe.
///
/// There is no public setter for the output volume; `MPVolumeView` owns the only
/// control that can move it, so one is parked off-screen in the window and driven
/// directly. The view has to be in a real hierarchy or its slider never exists — if it
/// does not, `adjust` reports the current level and changes nothing rather than failing.
@MainActor
enum SystemVolume {
    private static let host = MPVolumeView(frame: CGRect(x: -2_000, y: -2_000, width: 1, height: 1))

    private static func slider() -> UISlider? {
        if host.superview == nil {
            guard let window = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .flatMap(\.windows)
                .first(where: \.isKeyWindow)
            else { return nil }
            host.alpha = 0.001
            window.addSubview(host)
        }
        return host.subviews.compactMap { $0 as? UISlider }.first
    }

    /// What the system is playing at now, 0...1.
    static var level: Float { AVAudioSession.sharedInstance().outputVolume }

    /// Moves the volume to a level, rather than by a step.
    ///
    /// A swipe reads as a position on the screen, and stepping from wherever the
    /// volume happens to be compounds: each event moves the level the next one starts
    /// from, so a short flick ran to the end of the scale.
    /// - Returns: the resulting volume, 0...1.
    @discardableResult
    static func set(_ level: Float) -> Float {
        let wanted = min(max(level, 0), 1)
        guard let slider = slider() else { return self.level }
        slider.value = wanted
        // Setting `value` alone moves the knob without telling the system.
        slider.sendActions(for: .valueChanged)
        return wanted
    }
}
