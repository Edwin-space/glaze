import GlazeCore
import SwiftUI

/// Connection management lives here instead of competing with films on Home.
struct TVMediaSourcesView: View {
    let model: NetworkMediaBrowserModel
    let library: TVLibraryModel
    @Bindable var preferences: TVUserPreferences
    /// Choosing a NAS here makes it the library, rather than opening a file browser
    /// beside the one the rest of the app reads.
    let onOpenPairing: () -> Void
    let onUseWebDAV: (WebDAVConnection) -> Void
    /// A media server picked by hand. Opened for browsing straight away — not after a
    /// catalogue of it has been built, which on a real NAS never finished (`docs/42`).
    var onUseDLNA: (NetworkMediaServer) -> Void = { _ in }

    /// Servers typed in by hand, kept across launches.
    let savedServers: SavedMediaServerStore

    @State private var webdav = TVWebDAVConnections()
    @State private var isAddingWebDAV = false
    @State private var isAddingServer = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 44) {
                header
                pairingSection
                automaticDiscovery
                webDAVSection
            }
            .padding(.horizontal, 84)
            .padding(.top, 70)
            .padding(.bottom, 90)
        }
        .background(TVTheme.ground)
        .task { await model.discoverIfNeeded() }
        .fullScreenCover(isPresented: $isAddingServer) {
            TVAddMediaServerView { server in
                model.add(server)
                savedServers.save(SavedMediaServer(server))
                preferences.preferredServerID = server.id
                onUseDLNA(server)
                Task { await model.select(server) }
            }
        }
        .fullScreenCover(isPresented: $isAddingWebDAV) {
            TVWebDAVSetupView { connection, password in
                webdav.save(connection, password: password)
                onUseWebDAV(connection)
            }
        }
    }

    /// The easy way in, put before the ways that involve typing.
    private var pairingSection: some View {
        HStack(spacing: 26) {
            Image(systemName: "qrcode")
                .font(.system(size: 44))
                .foregroundStyle(TVTheme.amber)
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.string("tv.pairing.open"))
                    .font(.system(size: 31, weight: .semibold))
                Text(L10n.string("tv.pairing.detail"))
                    .font(.system(size: 21))
                    .foregroundStyle(TVTheme.dim)
                    .frame(maxWidth: 900, alignment: .leading)
            }
            Spacer()
            Button(L10n.string("tv.settings.start")) { onOpenPairing() }
        }
        .padding(30)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
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
                Button { isAddingServer = true } label: {
                    Label(L10n.string("network.manual.add"), systemImage: "plus")
                }
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
                // An Apple TV cannot send the multicast search without Apple's
                // entitlement (`docs/34`), so "nothing found" here is the normal
                // result even when the NAS is running perfectly. Saying only "no
                // servers" sent people looking for a fault in the NAS.
                sourceStatus(
                    symbol: "externaldrive.badge.questionmark",
                    title: L10n.string("network.browser.empty"),
                    detail: model.errorMessage ?? L10n.string("network.manual.discovery_note")
                )
                Button { isAddingServer = true } label: {
                    Label(L10n.string("network.manual.add"), systemImage: "plus")
                }
            } else {
                VStack(spacing: 14) {
                    ForEach(model.servers) { server in
                        Button {
                            preferences.preferredServerID = server.id
                            onUseDLNA(server)
                            Task { await model.select(server) }
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
