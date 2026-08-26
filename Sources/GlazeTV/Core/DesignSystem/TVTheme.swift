import SwiftUI

/// The look of the Apple TV app.
///
/// Carried over from the Mac's amber-on-near-black so the two read as one product, but
/// rebuilt for a television: everything is larger, contrast is higher, and the surfaces
/// are flatter. The Mac's glass depends on a bright desktop showing through; on a TV
/// there is nothing behind the app, and the same treatment turns to grey mud.
enum TVTheme {
    static let ground = Color(red: 0.039, green: 0.039, blue: 0.047)
    static let amber = Color(red: 0.91, green: 0.59, blue: 0.24)
    static let dim = Color.white.opacity(0.55)

    enum Radius {
        static let card: CGFloat = 14
        static let chip: CGFloat = 8
    }

    /// A stable colour for a title.
    ///
    /// DLNA sends no artwork, so a shelf of films would otherwise be a row of identical
    /// grey rectangles. Deriving a hue from the title gives every film a mark that is
    /// the same every time the viewer comes back, which is most of what a poster does
    /// on a shelf: let you find the one you were watching without reading.
    static func signature(for title: String) -> LinearGradient {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in title.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }

        let hue = Double(hash % 360) / 360
        // Kept dark and desaturated: this sits under white text and must never compete
        // with it, only distinguish one tile from its neighbour.
        return LinearGradient(
            colors: [
                Color(hue: hue, saturation: 0.42, brightness: 0.30),
                Color(hue: (hue + 0.08).truncatingRemainder(dividingBy: 1), saturation: 0.55, brightness: 0.14)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

/// A short mark next to a title — 4K, HDR, a runtime.
struct TVChip: View {
    let text: String
    var emphasized = false

    var body: some View {
        Text(text)
            .font(.system(size: 20, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(emphasized ? TVTheme.amber : TVTheme.dim)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: TVTheme.Radius.chip, style: .continuous)
                    .fill(.white.opacity(emphasized ? 0.14 : 0.08))
            )
    }
}
