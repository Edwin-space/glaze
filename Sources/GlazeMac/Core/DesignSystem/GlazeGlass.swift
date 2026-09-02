import SwiftUI

/// Glassmorphism design system.
///
/// Glass only reads as glass when there is something colored behind it, so this
/// file ships two halves that depend on each other: `GlazeAmbientBackdrop` paints
/// the light the glass refracts, and the `glazeGlass*` modifiers paint the panes.
/// Using a pane without a backdrop behind it produces flat grey — that is the one
/// mistake to avoid when extending this.
enum GlazeGlass {
    // Brand light sources. Amber is the product accent; celadon is its cool
    // counterweight so the backdrop has a temperature range rather than one hue.
    static let amber = Color(red: 0.878, green: 0.584, blue: 0.290)
    static let amberDeep = Color(red: 0.659, green: 0.388, blue: 0.122)
    static let celadon = Color(red: 0.478, green: 0.608, blue: 0.557)
    static let plum = Color(red: 0.286, green: 0.212, blue: 0.322)
    static let ground = Color(red: 0.055, green: 0.047, blue: 0.043)

    enum Radius {
        static let field: CGFloat = 10
        static let card: CGFloat = 16
        static let panel: CGFloat = 22
        static let stage: CGFloat = 28
    }

    /// Pane weight. Floating controls sit over video and need to stay legible, so
    /// they get more opacity than structural panels resting on the backdrop.
    enum Depth {
        case pane      // structural surfaces: inspector, sheets
        case card      // grouped content inside a surface
        case floating  // chrome over video: scrubber bar, notices
        case transport // transport discs: the picture should read through them

        var material: Material {
            switch self {
            case .pane: .ultraThinMaterial
            case .card: .ultraThinMaterial
            case .floating: .thinMaterial
            case .transport: .ultraThinMaterial
            }
        }

        var fillOpacity: Double {
            switch self {
            case .pane: 0.10
            case .card: 0.14
            case .floating: 0.18
            case .transport: 0.08
            }
        }

        var shadowRadius: CGFloat {
            switch self {
            case .pane: 24
            case .card: 10
            case .floating: 26
            case .transport: 20
            }
        }

        var shadowOpacity: Double {
            switch self {
            case .pane: 0.34
            case .card: 0.18
            case .floating: 0.42
            // A deeper shadow is what lifts a near-transparent disc off the footage.
            case .transport: 0.52
            }
        }
    }
}

private struct GlazeGlassSurface: ViewModifier {
    let shape: AnyShape
    let depth: GlazeGlass.Depth
    let tint: Color?
    let isStroked: Bool

    func body(content: Content) -> some View {
        content
            .background {
                shape
                    .fill(depth.material)
                    .overlay {
                        // Diagonal sheen: brighter at the top-left edge, as if a
                        // light source sits off-screen above the window.
                        shape.fill(
                            LinearGradient(
                                colors: [
                                    .white.opacity(depth.fillOpacity),
                                    .white.opacity(depth.fillOpacity * 0.28)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    }
                    .overlay {
                        if let tint {
                            shape.fill(
                                LinearGradient(
                                    colors: [tint.opacity(0.26), tint.opacity(0.05)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        }
                    }
                    .overlay {
                        if isStroked {
                            // Hairline that catches light on the top edge and fades
                            // out at the bottom — the detail that sells an edge of glass.
                            shape.stroke(
                                LinearGradient(
                                    colors: [
                                        .white.opacity(0.42),
                                        .white.opacity(0.10),
                                        .white.opacity(0.04)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 1
                            )
                        }
                    }
                    .compositingGroup()
                    .shadow(
                        color: .black.opacity(depth.shadowOpacity),
                        radius: depth.shadowRadius,
                        y: depth.shadowRadius * 0.34
                    )
            }
    }
}

extension View {
    /// Applies a glass pane behind the content.
    func glazeGlass(
        _ depth: GlazeGlass.Depth = .card,
        cornerRadius: CGFloat = GlazeGlass.Radius.card,
        tint: Color? = nil,
        stroked: Bool = true
    ) -> some View {
        modifier(
            GlazeGlassSurface(
                shape: AnyShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)),
                depth: depth,
                tint: tint,
                isStroked: stroked
            )
        )
    }

    /// Circular glass, for the round transport buttons over video.
    func glazeGlassCircle(
        _ depth: GlazeGlass.Depth = .floating,
        tint: Color? = nil
    ) -> some View {
        modifier(
            GlazeGlassSurface(
                shape: AnyShape(Circle()),
                depth: depth,
                tint: tint,
                isStroked: true
            )
        )
    }

    /// Grouped-row treatment used inside inspector panels, replacing the opaque
    /// default `Form` row background so the backdrop stays visible through it.
    func glazeGlassRow() -> some View {
        listRowBackground(
            RoundedRectangle(cornerRadius: GlazeGlass.Radius.field, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: GlazeGlass.Radius.field, style: .continuous)
                        .fill(.white.opacity(0.06))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: GlazeGlass.Radius.field, style: .continuous)
                        .strokeBorder(.white.opacity(0.10), lineWidth: 1)
                }
        )
    }
}

/// The light behind the glass: slow-drifting colour fields on a near-black ground.
///
/// Deliberately low contrast — it has to survive being looked at for hours behind
/// a subtitle panel without competing with the video beside it.
struct GlazeAmbientBackdrop: View {
    var isAnimated = true
    /// Structural surfaces need the brand light without letting it compete with
    /// dense settings or inspector copy. Keep the launch stage unscreened and add
    /// a controlled dark scrim only where the foreground carries information.
    var scrimOpacity: Double = 0

    @State private var drift = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var shouldAnimate: Bool { isAnimated && !reduceMotion }

    var body: some View {
        GeometryReader { geo in
            let size = max(geo.size.width, geo.size.height)

            ZStack {
                GlazeGlass.ground

                // Positioned proportionally so the light reaches the window's
                // corners at any size — fixed offsets collapse into the middle
                // on a wide window and leave the edges dead.
                blob(GlazeGlass.amber, opacity: 0.95, diameter: size * 0.95)
                    .position(x: geo.size.width * (drift ? 0.20 : 0.28),
                              y: geo.size.height * (drift ? 0.14 : 0.24))

                blob(GlazeGlass.amberDeep, opacity: 0.90, diameter: size * 0.85)
                    .position(x: geo.size.width * (drift ? 0.86 : 0.76),
                              y: geo.size.height * (drift ? 0.80 : 0.90))

                blob(GlazeGlass.celadon, opacity: 0.62, diameter: size * 0.72)
                    .position(x: geo.size.width * (drift ? 0.88 : 0.96),
                              y: geo.size.height * (drift ? 0.18 : 0.10))

                blob(GlazeGlass.plum, opacity: 0.85, diameter: size * 0.90)
                    .position(x: geo.size.width * (drift ? 0.12 : 0.06),
                              y: geo.size.height * (drift ? 0.88 : 0.78))

                if scrimOpacity > 0 {
                    Color.black.opacity(scrimOpacity)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
            // Four large blurs are expensive to composite on the CPU every frame.
            // Rasterising the whole backdrop moves the work to Metal and keeps the
            // drift animation off the main thread's critical path.
            .drawingGroup()
        }
        .ignoresSafeArea()
        .onAppear {
            guard shouldAnimate else { return }
            withAnimation(.easeInOut(duration: 14).repeatForever(autoreverses: true)) {
                drift = true
            }
        }
    }

    private func blob(_ color: Color, opacity: Double, diameter: CGFloat) -> some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [color.opacity(opacity), color.opacity(opacity * 0.35), color.opacity(0)],
                    center: .center,
                    startRadius: 0,
                    endRadius: diameter * 0.5
                )
            )
            .frame(width: diameter, height: diameter)
            .blur(radius: 60)
    }
}
