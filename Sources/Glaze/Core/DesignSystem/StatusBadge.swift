import SwiftUI

struct StatusBadge: View {
    let title: String
    let systemImage: String
    let tint: Color

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.medium))
            .labelStyle(.titleAndIcon)
            .foregroundStyle(tint)
            .padding(.horizontal, GlazeSpacing.sm)
            .padding(.vertical, GlazeSpacing.xs)
            .background(tint.opacity(0.12), in: Capsule())
    }
}
