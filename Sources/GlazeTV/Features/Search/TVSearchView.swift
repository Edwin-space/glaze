import GlazeCore
import SwiftUI

struct TVSearchView: View {
    let model: NetworkMediaBrowserModel

    @State private var query = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 30) {
            Text(L10n.string("tv.navigation.search"))
                .font(.system(size: 58, weight: .bold))

            TextField(L10n.string("tv.search.placeholder"), text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 34))
                .padding(.horizontal, 28)
                .frame(height: 76)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))

            if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                searchEmpty(
                    symbol: "magnifyingglass",
                    title: L10n.string("tv.search.start"),
                    detail: L10n.string("tv.search.start.detail")
                )
            } else if results.isEmpty {
                searchEmpty(
                    symbol: "film.stack",
                    title: L10n.string("tv.search.empty"),
                    detail: L10n.string("tv.search.empty.detail")
                )
            } else {
                TVShelf(title: String(format: L10n.string("tv.search.results_format"), results.count)) {
                    ForEach(results) { item in
                        TVMediaCard(item: item, progress: nil)
                    }
                }
                .padding(.horizontal, -60)
            }

            Spacer()
        }
        .padding(.horizontal, 84)
        .padding(.top, 70)
        .background(TVTheme.ground)
    }

    private var results: [PlayableItem] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return [] }
        return model.currentNodes.compactMap { node in
            guard case .video(let resource) = node.kind,
                  node.title.localizedCaseInsensitiveContains(needle) else { return nil }
            return PlayableItem(resource: resource, title: node.title)
        }
    }

    private func searchEmpty(symbol: String, title: String, detail: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: symbol)
                .font(.system(size: 62))
                .foregroundStyle(TVTheme.dim)
            Text(title).font(.system(size: 32, weight: .semibold))
            Text(detail)
                .font(.system(size: 23))
                .foregroundStyle(TVTheme.dim)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
