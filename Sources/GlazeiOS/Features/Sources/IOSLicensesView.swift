import GlazeCore
import SwiftUI

/// The notice the LGPL requires: what is in here that we did not write, under which
/// licence, and where its source can be had.
struct IOSLicensesView: View {
    var body: some View {
        List {
            Section {
                Text(L10n.string("legal.detail"))
                    .font(.footnote)
                    .foregroundStyle(IOSTheme.dim)
            }

            ForEach(OpenSourceNotices.all) { notice in
                Section(notice.name) {
                    Text(notice.copyright)
                        .font(.caption)
                        .foregroundStyle(IOSTheme.dim)
                    Text(notice.usage)
                        .font(.caption)

                    if notice.license.bundledText != nil {
                        NavigationLink(notice.license.displayName) {
                            LicenseTextView(notice: notice)
                        }
                    } else {
                        Link(destination: notice.license.url) {
                            LabeledContent(notice.license.displayName) {
                                Image(systemName: "arrow.up.right")
                            }
                        }
                    }

                    Link(L10n.string("legal.source"), destination: notice.sourceURL)
                }
            }
        }
        .glazeListBackground()
        .navigationTitle(L10n.string("legal.title"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// The licence itself. The LGPL says a copy must accompany the app, so it is carried
/// in the bundle rather than linked to a site the reader may not be able to reach.
struct LicenseTextView: View {
    let notice: OpenSourceNotice

    var body: some View {
        ScrollView {
            Text(notice.license.bundledText ?? "")
                .font(.caption.monospaced())
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(IOSTheme.Spacing.medium)
        }
        .navigationTitle(notice.license.displayName)
        .navigationBarTitleDisplayMode(.inline)
    }
}
