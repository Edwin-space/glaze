import GlazeCore
import SwiftUI
import UIKit

/// A tvOS-native playback scrubber.
///
/// SwiftUI's `Slider` is unavailable on tvOS. This focused UIView receives the Siri
/// Remote touch surface as a pan gesture, while arrow presses and VoiceOver adjustable
/// actions move in ten-second steps.
struct TVScrubber: UIViewRepresentable {
    @Binding var value: TimeInterval
    let range: ClosedRange<TimeInterval>
    let onEditingChanged: (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(value: $value, onEditingChanged: onEditingChanged)
    }

    func makeUIView(context: Context) -> ScrubberView {
        let view = ScrubberView()
        view.onValueChanged = { context.coordinator.value.wrappedValue = $0 }
        view.onEditingChanged = context.coordinator.onEditingChanged
        view.accessibilityLabel = L10n.string("tv.player.timeline")
        return view
    }

    func updateUIView(_ uiView: ScrubberView, context: Context) {
        uiView.range = range
        uiView.value = value
        uiView.accessibilityValue = timecode(value)
    }

    final class Coordinator {
        let value: Binding<TimeInterval>
        let onEditingChanged: (Bool) -> Void

        init(value: Binding<TimeInterval>, onEditingChanged: @escaping (Bool) -> Void) {
            self.value = value
            self.onEditingChanged = onEditingChanged
        }
    }

    private func timecode(_ seconds: TimeInterval) -> String {
        let total = max(Int(seconds), 0)
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
        let secs = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%d:%02d", minutes, secs)
    }
}

final class ScrubberView: UIView {
    var range: ClosedRange<TimeInterval> = 0...1 {
        didSet { updateLayers() }
    }
    var value: TimeInterval = 0 {
        didSet { updateLayers() }
    }
    var onValueChanged: ((TimeInterval) -> Void)?
    var onEditingChanged: ((Bool) -> Void)?

    private let trackLayer = CALayer()
    private let progressLayer = CALayer()
    private let thumbLayer = CALayer()
    private var gestureStartValue: TimeInterval = 0

    override var canBecomeFocused: Bool { true }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isAccessibilityElement = true
        accessibilityTraits = [.adjustable]

        trackLayer.backgroundColor = UIColor.white.withAlphaComponent(0.28).cgColor
        progressLayer.backgroundColor = UIColor(red: 0.91, green: 0.59, blue: 0.24, alpha: 1).cgColor
        thumbLayer.backgroundColor = UIColor.white.cgColor
        layer.addSublayer(trackLayer)
        layer.addSublayer(progressLayer)
        layer.addSublayer(thumbLayer)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        addGestureRecognizer(pan)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: 48)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateLayers()
    }

    override func didUpdateFocus(
        in context: UIFocusUpdateContext,
        with coordinator: UIFocusAnimationCoordinator
    ) {
        super.didUpdateFocus(in: context, with: coordinator)
        coordinator.addCoordinatedAnimations {
            self.transform = self.isFocused ? CGAffineTransform(scaleX: 1.015, y: 1.08) : .identity
            self.thumbLayer.opacity = self.isFocused ? 1 : 0.78
        }
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        guard let type = presses.first?.type else {
            super.pressesBegan(presses, with: event)
            return
        }

        switch type {
        case .leftArrow:
            setValue(value - 10, announceEditing: true)
        case .rightArrow:
            setValue(value + 10, announceEditing: true)
        default:
            super.pressesBegan(presses, with: event)
        }
    }

    override func accessibilityIncrement() {
        setValue(value + 10, announceEditing: true)
    }

    override func accessibilityDecrement() {
        setValue(value - 10, announceEditing: true)
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .began:
            gestureStartValue = value
            onEditingChanged?(true)
        case .changed:
            let width = max(bounds.width, 1)
            let fraction = Double(gesture.translation(in: self).x / width)
            let span = range.upperBound - range.lowerBound
            setValue(gestureStartValue + fraction * span, announceEditing: false)
        case .ended, .cancelled, .failed:
            onEditingChanged?(false)
        default:
            break
        }
    }

    private func setValue(_ proposedValue: TimeInterval, announceEditing: Bool) {
        if announceEditing { onEditingChanged?(true) }
        value = min(max(proposedValue, range.lowerBound), range.upperBound)
        onValueChanged?(value)
        if announceEditing { onEditingChanged?(false) }
    }

    private func updateLayers() {
        let trackHeight: CGFloat = isFocused ? 8 : 6
        let thumbSize: CGFloat = isFocused ? 28 : 22
        let trackFrame = CGRect(
            x: 0,
            y: (bounds.height - trackHeight) / 2,
            width: bounds.width,
            height: trackHeight
        )
        let span = max(range.upperBound - range.lowerBound, 1)
        let fraction = CGFloat(min(max((value - range.lowerBound) / span, 0), 1))

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        trackLayer.frame = trackFrame
        trackLayer.cornerRadius = trackHeight / 2
        progressLayer.frame = CGRect(
            x: trackFrame.minX,
            y: trackFrame.minY,
            width: trackFrame.width * fraction,
            height: trackHeight
        )
        progressLayer.cornerRadius = trackHeight / 2
        thumbLayer.frame = CGRect(
            x: max(trackFrame.width * fraction - thumbSize / 2, 0),
            y: (bounds.height - thumbSize) / 2,
            width: thumbSize,
            height: thumbSize
        )
        thumbLayer.cornerRadius = thumbSize / 2
        thumbLayer.shadowColor = UIColor.black.cgColor
        thumbLayer.shadowOpacity = 0.38
        thumbLayer.shadowRadius = 8
        CATransaction.commit()
    }
}
