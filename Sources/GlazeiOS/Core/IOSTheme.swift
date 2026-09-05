import SwiftUI

/// The Mac's amber on near-black, sized for a phone held at arm's length rather than
/// a television across a room. Same product, closer eyes: type is smaller, spacing
/// tighter, and the focus plate the television needs is replaced by touch feedback.
enum IOSTheme {
    static let ground = Color(red: 0.055, green: 0.055, blue: 0.063)
    static let amber = Color(red: 0.91, green: 0.59, blue: 0.24)
    static let dim = Color.white.opacity(0.55)

    enum Radius {
        static let card: CGFloat = 10
    }

    /// A stable colour per title, for the many films that have no artwork yet.
    static func signature(for title: String) -> LinearGradient {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in title.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        let hue = Double(hash % 360) / 360
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

/// A short mark next to a title — 4K, HDR, an episode number.
struct IOSChip: View {
    let text: String
    var emphasized = false

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(emphasized ? IOSTheme.amber : IOSTheme.dim)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.white.opacity(emphasized ? 0.14 : 0.08), in: Capsule())
    }
}
