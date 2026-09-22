import GlazeCore
import SwiftUI

/// The timeline under a film, as a bar rather than a slider.
///
/// SwiftUI's `Slider` only moves when the little knob itself is dragged, so touching
/// the bar anywhere else did nothing at all — no seek, and no still of the scene
/// being pointed at, because nothing told the player a scrub had begun. A film's
/// timeline is a place you put your thumb, not a knob you have to find.
struct IOSTimelineBar: View {
    let duration: TimeInterval
    @Binding var value: TimeInterval
    /// True while a thumb is on the bar.
    let onScrubbingChanged: (Bool) -> Void

    @State private var isDragging = false

    private var trackHeight: CGFloat { isDragging ? 8 : 5 }
    private var knobDiameter: CGFloat { isDragging ? 22 : 14 }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let fraction = duration > 0 ? min(max(value / duration, 0), 1) : 0

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.25))
                    .frame(height: trackHeight)
                Capsule()
                    .fill(IOSTheme.amber)
                    .frame(width: max(width * fraction, trackHeight), height: trackHeight)
                Circle()
                    .fill(.white)
                    .frame(width: knobDiameter, height: knobDiameter)
                    .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
                    .offset(x: min(max(width * fraction - knobDiameter / 2, 0), max(width - knobDiameter, 0)))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            // The whole strip takes the touch, not just the knob.
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        if !isDragging {
                            isDragging = true
                            onScrubbingChanged(true)
                        }
                        value = time(at: drag.location.x, width: width)
                    }
                    .onEnded { drag in
                        value = time(at: drag.location.x, width: width)
                        isDragging = false
                        onScrubbingChanged(false)
                    }
            )
            .animation(.easeOut(duration: 0.12), value: isDragging)
        }
        .frame(height: 44)
        .accessibilityElement()
        .accessibilityLabel(L10n.string("ios.player.a11y.timeline"))
        .accessibilityValue(IOSPlayerView.timecode(value))
        .accessibilityAdjustableAction { direction in
            let step: TimeInterval = 10
            switch direction {
            case .increment: value = min(value + step, duration)
            case .decrement: value = max(value - step, 0)
            @unknown default: break
            }
            onScrubbingChanged(true)
            onScrubbingChanged(false)
        }
    }

    private func time(at x: CGFloat, width: CGFloat) -> TimeInterval {
        guard width > 0, duration > 0 else { return 0 }
        return min(max(Double(x / width), 0), 1) * duration
    }
}
