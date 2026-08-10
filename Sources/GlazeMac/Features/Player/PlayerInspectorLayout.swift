import GlazeCore
import SwiftUI

struct PlayerInspectorLayout<Content: View, Footer: View>: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let onClose: () -> Void
    @ViewBuilder let content: Content
    @ViewBuilder let footer: Footer

    init(
        title: String,
        subtitle: String,
        systemImage: String,
        onClose: @escaping () -> Void,
        @ViewBuilder content: () -> Content,
        @ViewBuilder footer: () -> Footer
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.onClose = onClose
        self.content = content()
        self.footer = footer()
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: GlazeSpacing.md) {
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 7))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: GlazeSpacing.sm)

                Button(action: onClose) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .help(L10n.string("player.inspector.close"))
            }
            .padding(GlazeSpacing.lg)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: GlazeSpacing.lg) {
                    content
                }
                .padding(GlazeSpacing.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if Footer.self != EmptyView.self {
                Divider()
                VStack(spacing: GlazeSpacing.sm) {
                    footer
                }
                .padding(GlazeSpacing.lg)
            }
        }
        .frame(width: 360)
        .background(.regularMaterial)
    }
}

struct InspectorSection<Content: View>: View {
    let title: String?
    @ViewBuilder let content: Content

    init(_ title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: GlazeSpacing.md) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, GlazeSpacing.xs)
        } label: {
            if let title {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .groupBoxStyle(.automatic)
    }
}

struct InspectorEmptyMessage: View {
    let text: String
    let systemImage: String

    var body: some View {
        ContentUnavailableView {
            Label(text, systemImage: systemImage)
                .font(.callout)
        }
        .frame(maxWidth: .infinity, minHeight: 150)
    }
}
