import GlazeCore
import SwiftUI

/// The Mac's amber on near-black, sized for a phone held at arm's length rather than
/// a television across a room. Same product, closer eyes: type is smaller, spacing
/// tighter, and the focus plate the television needs is replaced by touch feedback.
enum IOSTheme {
    static let ground = Color(red: 0.055, green: 0.055, blue: 0.063)
    static let amber = Color(red: 0.91, green: 0.59, blue: 0.24)
    static let dim = Color.white.opacity(0.55)

    /// Gaps come from here rather than from whatever number felt right.
    ///
    /// The screens had grown nineteen different spacings — 3 and 22 and 26 each used
    /// once — which is how a layout stops looking deliberate. Six steps cover
    /// everything the app actually does.
    enum Spacing {
        /// Between two lines of the same thought: a title and its caption.
        static let hair: CGFloat = 2
        /// Between things that belong together in a row.
        static let tight: CGFloat = 6
        static let small: CGFloat = 10
        /// The usual gap between a row's icon and its text.
        static let medium: CGFloat = 14
        static let large: CGFloat = 20
        /// Between sections of a screen.
        static let section: CGFloat = 28
    }

    enum Radius {
        static let card: CGFloat = 10
        /// Panels that sit over video, which need a softer edge to read as a surface.
        static let panel: CGFloat = 18
    }

    /// The smallest a control may be and still be reliably hit with a thumb.
    ///
    /// The player's chrome was 34pt, which is a miss in a dark room with one hand.
    /// Glyphs can stay small; the thing that takes the tap cannot.
    static let minimumTouchTarget: CGFloat = 44

    /// Chrome that sits over video.
    ///
    /// The approved player contract asks for clear glass or a translucent material on
    /// each control, never merged into one bar (`docs/17`). The Mac keeps that in
    /// `GlazeGlass.Depth.transport`; the phone had drifted to a flat black disc, which
    /// blots out the frame it is sitting on instead of letting the picture read
    /// through. These are the phone's numbers for the same idea — a little heavier
    /// than the Mac's, because a thumb-sized glyph in daylight has less room to be
    /// subtle than a pointer-sized one indoors.
    enum Transport {
        static let fill = Color.black.opacity(0.22)
        static let edge = Color.white.opacity(0.14)
        static let material: Material = .ultraThinMaterial
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
            .padding(.horizontal, IOSTheme.Spacing.tight)
            .padding(.vertical, IOSTheme.Spacing.hair)
            .background(.white.opacity(emphasized ? 0.14 : 0.08), in: Capsule())
    }
}

/// A row of the shape the whole app uses for a thing you can pick: a symbol, a name,
/// and a line underneath saying what it is.
///
/// The sources list and the add-a-server sheet had each grown their own copy, down to
/// the same 14 and 2 point gaps. One of them would eventually have been changed alone.
struct IOSListRow: View {
    let symbol: String
    let title: String
    let detail: String?
    /// For a film: whether it is new, part-watched or watched. Nil for anything that is
    /// not played — a folder, a book.
    var watch: WatchState?
    /// Read out in place of the two labels, when they only make sense together.
    var accessibilityDescription: String?

    var body: some View {
        HStack(spacing: IOSTheme.Spacing.medium) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(watch == .watched ? IOSTheme.dim : IOSTheme.amber)
                .frame(width: 30)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: IOSTheme.Spacing.hair) {
                HStack(spacing: IOSTheme.Spacing.tight) {
                    Text(title)
                        // Watched films step back rather than disappear: they are still
                        // there to rewatch, just no longer what the eye should land on.
                        .foregroundStyle(watch == .watched ? AnyShapeStyle(IOSTheme.dim) : AnyShapeStyle(.primary))
                        .lineLimit(1)
                    if watch == .new {
                        IOSNewBadge()
                    }
                }
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(IOSTheme.dim)
                        .lineLimit(2)
                }
                if case .inProgress(let fraction) = watch, fraction > 0 {
                    ProgressView(value: fraction)
                        .tint(IOSTheme.amber)
                        .frame(maxWidth: 160)
                        .padding(.top, IOSTheme.Spacing.hair)
                }
            }

            if watch == .watched {
                Spacer(minLength: 0)
                Image(systemName: "checkmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(IOSTheme.dim)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(spokenLabel)
    }

    private var spokenLabel: String {
        var parts = [accessibilityDescription ?? [title, detail].compactMap { $0 }.joined(separator: ", ")]
        switch watch {
        case .new: parts.append(L10n.string("ios.watch.new"))
        case .watched: parts.append(L10n.string("ios.watch.watched"))
        case .inProgress(let fraction):
            parts.append(String(format: L10n.string("ios.watch.progress_format"), Int(fraction * 100)))
        case nil: break
        }
        return parts.joined(separator: ", ")
    }
}

/// "NEW", beside a film nobody has started.
///
/// In a folder of forty episodes the unwatched ones are what a person scans for, and a
/// small mark beside the name is how every player people already use says so.
struct IOSNewBadge: View {
    var body: some View {
        Text(L10n.string("ios.watch.new_badge"))
            .font(.system(size: 9, weight: .heavy))
            .tracking(0.4)
            .foregroundStyle(.black)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(IOSTheme.amber, in: Capsule())
            .accessibilityHidden(true)
    }
}

/// Puts a comfortable target under a small glyph.
///
/// The player's controls are drawn small on purpose — a bar across a film should be
/// quiet — but what takes the tap has to be the size of a thumb.
struct TouchTarget: ViewModifier {
    var diameter: CGFloat = IOSTheme.minimumTouchTarget

    func body(content: Content) -> some View {
        content
            .frame(minWidth: diameter, minHeight: diameter)
            .contentShape(Rectangle())
    }
}

extension View {
    func touchTarget(_ diameter: CGFloat = IOSTheme.minimumTouchTarget) -> some View {
        modifier(TouchTarget(diameter: diameter))
    }

    /// Lets the app's ground show through a `List` or `Form`.
    ///
    /// The library painted `ground` and every list took the system's own backdrop
    /// instead, so moving between tabs shifted the darkness slightly. Both are dark,
    /// which is why it read as sloppiness rather than as a bug.
    ///
    /// Only the hiding happens here. Painting the ground behind *each* list as well
    /// crashed SwiftUI outright — a segmentation fault instantiating generic metadata
    /// for the list's style context — so the colour is laid down once, under the whole
    /// tab view, and the lists simply get out of its way.

    func glazeListBackground() -> some View {
        scrollContentBackground(.hidden)
    }
}


extension View {
    /// One control over the film: material, a light darkening for glyph contrast, and
    /// a hairline so the edge reads against a bright frame. Never a capsule holding
    /// several — the contract is explicit that the discs stay separate.
    func glazeTransportDisc(_ shape: some Shape = Circle()) -> some View {
        background(IOSTheme.Transport.material, in: shape)
            .background(IOSTheme.Transport.fill, in: shape)
            .overlay { shape.stroke(IOSTheme.Transport.edge, lineWidth: 0.5) }
    }
}
