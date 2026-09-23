import Foundation

/// What to do when the sound stops coming out of the thing it was coming out of.
///
/// Taking an AirPod out, or pulling a cable, moves playback to the phone's own
/// speaker. Carrying on is never what anyone means by that: the film keeps running
/// into a room, or a carriage, and by the time the headphones are back in place
/// minutes have gone by. Every player on the platform pauses, and so should this one.
public enum AudioRouteChange {
    /// The outputs that mean "someone was listening privately".
    ///
    /// Written as strings because the port types are UIKit's and this package is
    /// shared with the Mac; the caller passes what the system reported.
    public static let privateOutputs: Set<String> = [
        "Headphones", "BluetoothA2DPOutput", "BluetoothHFP", "BluetoothLE", "USBAudio"
    ]

    /// - Parameters:
    ///   - reasonIsDeviceUnavailable: true when the route changed because the old
    ///     output went away, rather than because something new arrived or the user
    ///     chose a different one.
    ///   - previousOutputs: the port types the sound was going to a moment ago.
    /// - Returns: whether playback should stop.
    public static func shouldPause(
        reasonIsDeviceUnavailable: Bool,
        previousOutputs: [String]
    ) -> Bool {
        guard reasonIsDeviceUnavailable else { return false }
        return previousOutputs.contains { privateOutputs.contains($0) }
    }
}
