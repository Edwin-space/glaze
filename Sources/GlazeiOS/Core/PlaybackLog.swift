import GlazeCore

/// Compatibility for legacy call sites. Their free text included filenames and raw
/// errors, so it must never reach persistent storage. Operation boundaries now use
/// DiagnosticsCenter with fixed event names and numeric values.
enum PlaybackLog {
    static func begin(_ note: @autoclosure () -> String) {}
    static func write(_ note: @autoclosure () -> String) {}
}
