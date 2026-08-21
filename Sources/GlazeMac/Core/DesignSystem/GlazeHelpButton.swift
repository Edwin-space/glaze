import GlazeCore
import SwiftUI

/// A small `?` beside a setting that opens a plain-language explanation.
///
/// Several controls in the inspector name things the app does rather than things the
/// viewer already knows — a transcription model, a container format, a translation
/// quality. Naming them is unavoidable, so the explanation has to sit next to the
/// control. A `.help()` tooltip is not enough: it only appears on hover, gives no
/// hint that it exists, and is unreachable by keyboard.
struct GlazeHelpButton: View {
    /// Reused as the popover's heading, so a row needs one string, not two.
    let titleKey: String
    let bodyKey: String

    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Image(systemName: "questionmark.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            String(format: L10n.string("help.accessibility_format"), L10n.string(titleKey))
        )
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 7) {
                Text(L10n.string(titleKey))
                    .font(.headline)
                Text(L10n.string(bodyKey))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .multilineTextAlignment(.leading)
            .padding(15)
            .frame(width: 290)
        }
    }
}

/// A row label with its `?` attached. Use in place of a bare `Text` label on any
/// control whose name does not explain itself.
struct GlazeHelpLabel: View {
    let textKey: String
    let helpKey: String

    init(_ textKey: String, help helpKey: String) {
        self.textKey = textKey
        self.helpKey = helpKey
    }

    var body: some View {
        HStack(spacing: 5) {
            Text(L10n.string(textKey))
            GlazeHelpButton(titleKey: textKey, bodyKey: helpKey)
        }
    }
}
