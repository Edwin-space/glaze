import GlazeCore
import SwiftUI

/// The notice the LGPL requires: what is in here that we did not write, under which
/// licence, and where its source can be had.
struct MacLicensesView: View {
    @State private var selection: OpenSourceNotice.ID?

    private var notices: [OpenSourceNotice] { OpenSourceNotices.all }

    var body: some View {
        NavigationSplitView {
            List(notices, selection: $selection) { notice in
                VStack(alignment: .leading, spacing: 2) {
                    Text(notice.name).font(.body)
                    Text(notice.license.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .tag(notice.id)
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 250)
        } detail: {
            if let notice = notices.first(where: { $0.id == selection }) {
                detail(for: notice)
            } else {
                ContentUnavailableView(
                    L10n.string("legal.title"),
                    systemImage: "doc.text",
                    description: Text(L10n.string("legal.detail"))
                )
            }
        }
        .navigationTitle(L10n.string("legal.title"))
        .frame(minWidth: 720, minHeight: 480)
        .onAppear { selection = selection ?? notices.first?.id }
    }

    private func detail(for notice: OpenSourceNotice) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(notice.name).font(.title2.weight(.semibold))
                Text(notice.copyright).foregroundStyle(.secondary)
                Text(notice.usage)

                HStack(spacing: 16) {
                    Link(notice.license.displayName, destination: notice.license.url)
                    Link(L10n.string("legal.source"), destination: notice.sourceURL)
                }
                .font(.callout)

                if let text = notice.license.bundledText {
                    Divider()
                    Text(L10n.string("legal.license_text")).font(.headline)
                    Text(text)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
    }
}
