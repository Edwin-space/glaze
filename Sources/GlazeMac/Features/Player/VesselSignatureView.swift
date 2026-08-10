import SwiftUI

/// The empty-state signature mark: a vessel silhouette that visually "glazes" (fills)
/// as a slow ambient pour, standing in for a generic loading ring. Read literally: 자막
/// 없는 영상에 유약을 입힌다 — the app coats an unprepared video before it's watched.
struct VesselShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * w, y: rect.minY + y * h)
        }

        path.move(to: pt(0.25, 0.1875))
        path.addCurve(to: pt(0.75, 0.1875), control1: pt(0.25, 0.1375), control2: pt(0.75, 0.1375))
        path.addCurve(to: pt(0.7625, 0.625), control1: pt(0.76875, 0.3), control2: pt(0.8125, 0.4625))
        path.addCurve(to: pt(0.5, 0.8875), control1: pt(0.73125, 0.8), control2: pt(0.6125, 0.8875))
        path.addCurve(to: pt(0.2375, 0.625), control1: pt(0.3875, 0.8875), control2: pt(0.26875, 0.8))
        path.addCurve(to: pt(0.25, 0.1875), control1: pt(0.1875, 0.4625), control2: pt(0.23125, 0.3))
        path.closeSubpath()
        return path
    }
}

struct VesselSignatureView: View {
    /// When set, the vessel fills to this level and stops (subtitle prep genuinely in
    /// progress/done). When nil, it plays a slow idle pour as an ambient "waiting" cue.
    var progress: CGFloat?

    @State private var idleFill: CGFloat = 0.1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var fillLevel: CGFloat {
        progress ?? idleFill
    }

    var body: some View {
        ZStack {
            // Ambient glow behind the vessel — the mockup's single flat shape read as
            // small/plain without this; the glow gives it presence against the dark stage.
            VesselShape()
                .fill(GlazeColors.glaze.opacity(0.35))
                .blur(radius: 28)
                .opacity(0.6)

            VesselShape()
                .fill(
                    LinearGradient(
                        colors: [GlazeColors.glazeHoney, GlazeColors.glaze, GlazeColors.glazeDeep],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .mask(alignment: .bottom) {
                    GeometryReader { geo in
                        Rectangle()
                            .frame(height: max(0, geo.size.height * fillLevel))
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    }
                }

            // Sheen line at the glaze's leading edge, like a wet surface catching light.
            VesselShape()
                .fill(GlazeColors.porcelain.opacity(0.5))
                .mask(alignment: .bottom) {
                    GeometryReader { geo in
                        Rectangle()
                            .frame(height: 3)
                            .frame(maxWidth: .infinity, alignment: .bottom)
                            .offset(y: -max(0, geo.size.height * fillLevel) + 1.5)
                    }
                }
                .blur(radius: 1)

            VesselShape()
                .stroke(GlazeColors.porcelain.opacity(0.32), lineWidth: 1.8)

            Image(systemName: "play.fill")
                .font(.system(size: 30, weight: .regular))
                .foregroundStyle(GlazeColors.porcelain)
                .shadow(color: .black.opacity(0.55), radius: 4, y: 1)
        }
        .frame(width: 196, height: 196)
        .onAppear {
            guard progress == nil, !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.7).repeatForever(autoreverses: true)) {
                idleFill = 0.72
            }
        }
    }
}
