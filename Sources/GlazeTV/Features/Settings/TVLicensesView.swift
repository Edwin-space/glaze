import GlazeCore
import SwiftUI

/// The notice the LGPL requires, at a distance a television is read from.
///
/// A remote cannot follow a link, so the source addresses are printed rather than
/// made tappable — a viewer types them somewhere else.
struct TVLicensesView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 40) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(L10n.string("legal.title"))
                        .font(.system(size: 54, weight: .bold))
                    Text(L10n.string("legal.detail"))
                        .font(.system(size: 24))
                        .foregroundStyle(TVTheme.dim)
                        .frame(maxWidth: 1200, alignment: .leading)
                }

                ForEach(OpenSourceNotices.all) { notice in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(notice.name).font(.system(size: 32, weight: .semibold))
                        Text("\(notice.copyright) · \(notice.license.displayName)")
                            .font(.system(size: 22))
                            .foregroundStyle(TVTheme.amber)
                        Text(notice.usage)
                            .font(.system(size: 22))
                            .foregroundStyle(TVTheme.dim)
                            .frame(maxWidth: 1200, alignment: .leading)
                        Text(notice.sourceURL.absoluteString)
                            .font(.system(size: 20).monospaced())
                            .foregroundStyle(.white.opacity(0.45))
                    }
                }

                if let text = OpenSourceLicense.lgpl21.bundledText {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(L10n.string("legal.license_text"))
                            .font(.system(size: 32, weight: .semibold))
                        Text(text)
                            .font(.system(size: 17).monospaced())
                            .foregroundStyle(.white.opacity(0.6))
                            .frame(maxWidth: 1400, alignment: .leading)
                    }
                }
            }
            .padding(.horizontal, 84)
            .padding(.vertical, 70)
        }
        .background(TVTheme.ground)
        .onExitCommand { dismiss() }
    }
}
