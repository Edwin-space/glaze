import GlazeCore
import SwiftUI

/// Connection management lives here instead of competing with films on Home.
struct TVMediaSourcesView: View {
    let model: NetworkMediaBrowserModel
    let library: TVLibraryModel
    @Bindable var preferences: TVUserPreferences
    /// Choosing a NAS here makes it the library, rather than opening a file browser
    /// beside the one the rest of the app reads.
    let onUseWebDAV: (WebDAVConnection) -> Void

    @State private var webdav = TVWebDAVConnections()
    @State private var isAddingWebDAV = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 44) {
                header
                automaticDiscovery
                webDAVSection
            }
            .padding(.horizontal, 84)
            .padding(.top, 70)
            .padding(.bottom, 90)
        }
        .background(TVTheme.ground)
        .task { await model.discoverIfNeeded() }
        .fullScreenCover(isPresented: $isAddingWebDAV) {
            TVWebDAVSetupView { connection, password in
                webdav.save(connection, password: password)
                onUseWebDAV(connection)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.string("tv.navigation.sources"))
                .font(.system(size: 58, weight: .bold))
            Text(L10n.string("tv.sources.detail"))
                .font(.system(size: 25))
                .foregroundStyle(TVTheme.dim)
        }
    }

    private var automaticDiscovery: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(L10n.string("settings.network.discovery.title"))
                    .font(.system(size: 31, weight: .semibold))
                Spacer()
                Button {
                    Task {
                        await model.discover()
                        if let preferredID = preferences.preferredServerID {
                            await model.restorePreferredServer(id: preferredID)
                        }
                    }
                } label: {
                    Label(L10n.string("network.browser.refresh"), systemImage: "arrow.clockwise")
                }
            }

            if model.phase == .discovering {
                sourceStatus(
                    symbol: "antenna.radiowaves.left.and.right",
                    title: L10n.string("network.browser.discovering"),
                    detail: L10n.string("settings.network.dlna.detail")
                )
            } else if model.servers.isEmpty {
                sourceStatus(
                    symbol: "externaldrive.badge.questionmark",
                    title: L10n.string("network.browser.empty"),
                    detail: L10n.string("network.browser.empty_hint")
                )
            } else {
                VStack(spacing: 14) {
                    ForEach(model.servers) { server in
                        Button {
                            Task {
                                await model.select(server)
                                preferences.preferredServerID = server.id
                            }
                        } label: {
                            HStack(spacing: 22) {
                                Image(systemName: "externaldrive.connected.to.line.below.fill")
                                    .font(.system(size: 38))
                                    .foregroundStyle(TVTheme.amber)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(server.friendlyName)
                                        .font(.system(size: 30, weight: .semibold))
                                    Text(L10n.string("settings.network.dlna.title"))
                                        .font(.system(size: 21))
                                        .foregroundStyle(TVTheme.dim)
                                }
                                Spacer()
                                if preferences.preferredServerID == server.id {
                                    Label(L10n.string("tv.settings.default"), systemImage: "checkmark.circle.fill")
                                        .font(.system(size: 21, weight: .medium))
                                        .foregroundStyle(TVTheme.amber)
                                }
                            }
                            .padding(26)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.card)
                    }
                }
            }
        }
    }

    private var webDAVSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(L10n.string("webdav.section.title"))
                    .font(.system(size: 31, weight: .semibold))
                Spacer()
                Button {
                    isAddingWebDAV = true
                } label: {
                    Label(L10n.string("webdav.add"), systemImage: "plus")
                }
            }

            if webdav.connections.isEmpty {
                sourceStatus(
                    symbol: "folder.badge.plus",
                    title: L10n.string("settings.network.webdav.empty"),
                    detail: L10n.string("settings.network.webdav.empty_detail")
                )
            } else {
                VStack(spacing: 14) {
                    ForEach(webdav.connections) { connection in
                        Button { onUseWebDAV(connection) } label: {
                            HStack(spacing: 22) {
                                Image(systemName: "folder.badge.person.crop")
                                    .font(.system(size: 38))
                                    .foregroundStyle(TVTheme.amber)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(connection.name)
                                        .font(.system(size: 30, weight: .semibold))
                                    Text(connection.rootURL.absoluteString)
                                        .font(.system(size: 21))
                                        .foregroundStyle(TVTheme.dim)
                                        .lineLimit(1)
                                }
                                Spacer()
                                if case .webDAV(let active) = library.source, active == connection.name {
                                    Label(L10n.string("tv.settings.default"), systemImage: "checkmark.circle.fill")
                                        .font(.system(size: 21, weight: .medium))
                                        .foregroundStyle(TVTheme.amber)
                                } else {
                                    Image(systemName: "chevron.right")
                                        .foregroundStyle(TVTheme.dim)
                                }
                            }
                            .padding(26)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.card)
                    }
                }
            }
        }
    }

    private func sourceStatus(symbol: String, title: String, detail: String) -> some View {
        HStack(spacing: 24) {
            Image(systemName: symbol)
                .font(.system(size: 40))
                .foregroundStyle(TVTheme.amber)
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 29, weight: .semibold))
                Text(detail)
                    .font(.system(size: 21))
                    .foregroundStyle(TVTheme.dim)
                    .lineLimit(2)
            }
            Spacer()
        }
        .padding(28)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
