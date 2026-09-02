import Foundation
import GlazeCore
import SwiftUI

private enum NetworkBrowserViewMode: String, CaseIterable, Identifiable {
    case icons, list, columns, gallery

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .icons: "square.grid.2x2"
        case .list: "list.bullet"
        case .columns: "rectangle.split.3x1"
        case .gallery: "rectangle.on.rectangle"
        }
    }

    var localizationKey: String { "network.browser.view.\(rawValue)" }
}

private struct NetworkBrowserItem: Identifiable {
    enum Source {
        case webDAV(WebDAVEntry, parentLevelID: String)
        case dlna(NetworkMediaNode, parentLevelID: String)
    }

    let id: String
    let name: String
    let isFolder: Bool
    let detail: String?
    let source: Source
}

private struct NetworkBrowserLevel: Identifiable {
    let id: String
    let title: String
    let items: [NetworkBrowserItem]
}

struct NetworkMediaBrowserView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("network.browser.viewMode") private var viewModeRaw = NetworkBrowserViewMode.list.rawValue

    @State private var model = NetworkMediaBrowserModel()
    @State private var webDAVConnections = WebDAVConnectionStore()
    @State private var webDAVFavorites = WebDAVFavoriteStore()
    @State private var webDAVModel = WebDAVBrowserModel()
    @State private var selectedWebDAV: WebDAVConnection?
    @State private var gallerySelectionID: String?

    let onOpen: (NetworkMediaResource, MediaLibrarySource) -> Void

    var body: some View {
        NavigationSplitView {
            sourceSidebar
                .navigationSplitViewColumnWidth(min: 210, ideal: 240, max: 300)
        } detail: {
            VStack(spacing: 0) {
                browserToolbar
                Divider().opacity(0.45)
                detailContent
            }
            // NavigationSplitView centers an intrinsically sized detail column.
            // A browser toolbar must instead stay attached to the top edge like
            // Finder's, with the content taking the remaining height.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(L10n.string("network.browser.close")) { dismiss() }
            }
            ToolbarItem(placement: .automatic) {
                GlazeHelpButton(titleKey: "network.browser.title", bodyKey: "help.network.browser")
            }
        }
        .scrollContentBackground(.hidden)
        .toolbarBackground(.hidden, for: .windowToolbar)
        .frame(minWidth: 900, minHeight: 600)
        .presentationBackground { GlazeAmbientBackdrop(isAnimated: false) }
        .preferredColorScheme(.dark)
        .task { await model.discoverIfNeeded() }
    }

    private var viewMode: NetworkBrowserViewMode {
        get { NetworkBrowserViewMode(rawValue: viewModeRaw) ?? .list }
        nonmutating set { viewModeRaw = newValue.rawValue }
    }

    private var sourceSidebar: some View {
        List {
            if !availableFavorites.isEmpty {
                Section(L10n.string("network.browser.favorites")) {
                    ForEach(availableFavorites) { favorite in
                        sidebarButton(
                            title: favorite.name,
                            subtitle: connection(for: favorite.connectionID)?.name,
                            symbol: "star.fill",
                            isSelected: selectedWebDAV?.id == favorite.connectionID
                                && webDAVModel.levels.first?.url == favorite.url
                        ) { open(favorite) }
                    }
                }
            }

            if !model.servers.isEmpty {
                Section(L10n.string("settings.network.dlna.title")) {
                    ForEach(model.servers) { server in
                        sidebarButton(
                            title: server.friendlyName,
                            symbol: "dot.radiowaves.left.and.right",
                            isSelected: selectedWebDAV == nil && model.selectedServer?.id == server.id
                        ) {
                            selectedWebDAV = nil
                            gallerySelectionID = nil
                            Task { await model.select(server) }
                        }
                    }
                }
            }

            if !webDAVConnections.connections.isEmpty {
                Section(L10n.string("webdav.section.title")) {
                    ForEach(webDAVConnections.connections) { connection in
                        sidebarButton(
                            title: connection.name,
                            subtitle: connection.rootURL.host,
                            symbol: "externaldrive.connected.to.line.below",
                            isSelected: selectedWebDAV?.id == connection.id
                                && webDAVModel.levels.first?.url == connection.rootURL
                        ) { open(connection) }
                    }
                }
            }

            if model.phase == .discovering {
                Section {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(L10n.string("network.browser.discovering"))
                            .foregroundStyle(.secondary)
                    }
                }
            } else if let errorMessage = model.errorMessage, !webDAVConnections.connections.isEmpty {
                Section {
                    Label(errorMessage, systemImage: "wifi.exclamationmark")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle(L10n.string("network.browser.locations"))
        .safeAreaInset(edge: .bottom) {
            HStack {
                SettingsLink {
                    Label(L10n.string("settings.title"), systemImage: "gearshape")
                }
                .buttonStyle(.plain)
                Spacer()
                Button { Task { await model.discover() } } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .help(L10n.string("network.browser.refresh"))
                .disabled(model.phase == .discovering)
            }
            .padding(12)
            .background(.ultraThinMaterial)
        }
    }

    private func sidebarButton(
        title: String,
        subtitle: String? = nil,
        symbol: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .frame(width: 18)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).lineLimit(1)
                    if let subtitle {
                        Text(subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(isSelected ? Color.accentColor.opacity(0.16) : Color.clear)
    }

    private var browserToolbar: some View {
        HStack(spacing: 10) {
            Button(action: navigateBack) { Image(systemName: "chevron.left") }
                .buttonStyle(.borderless)
                .disabled(!hasSelectedSource)
                .help(L10n.string("network.browser.back"))
                .keyboardShortcut("[", modifiers: .command)

            pathBar
            Spacer(minLength: 12)

            if let selectedWebDAV, let level = webDAVModel.levels.last {
                Button {
                    webDAVFavorites.toggle(
                        connectionID: selectedWebDAV.id,
                        name: level.title,
                        url: level.url
                    )
                } label: {
                    Image(systemName: isCurrentWebDAVFolderFavorite ? "star.fill" : "star")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(isCurrentWebDAVFolderFavorite ? Color.accentColor : Color.secondary)
                .help(L10n.string(isCurrentWebDAVFolderFavorite
                                  ? "network.browser.favorite.remove"
                                  : "network.browser.favorite.add"))
            }

            viewModePicker

            Button(action: refreshCurrentLocation) { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.borderless)
                .help(L10n.string("network.browser.refresh"))
                .disabled(isLoading || !hasSelectedSource)
        }
        .controlSize(.large)
        .padding(.horizontal, 16)
        .frame(height: 52)
        .background(.ultraThinMaterial)
    }

    private var pathBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                Image(systemName: selectedWebDAV == nil ? "play.tv" : "externaldrive")
                    .foregroundStyle(.secondary)
                ForEach(browserLevels) { level in
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Button(level.title) { navigate(to: level.id) }
                        .buttonStyle(.plain)
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: 420, alignment: .leading)
        .accessibilityLabel(L10n.string("network.browser.path"))
    }

    private var viewModePicker: some View {
        HStack(spacing: 0) {
            ForEach(NetworkBrowserViewMode.allCases) { mode in
                Button { viewMode = mode } label: {
                    Image(systemName: mode.symbolName)
                        .frame(width: 26, height: 24)
                        .background(viewMode == mode ? Color.white.opacity(0.12) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                }
                .buttonStyle(.borderless)
                .help(L10n.string(mode.localizationKey))
                .accessibilityLabel(L10n.string(mode.localizationKey))
                .accessibilityAddTraits(viewMode == mode ? .isSelected : [])
            }
        }
        .padding(3)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    @ViewBuilder private var detailContent: some View {
        if !hasSelectedSource {
            sourceOverview
        } else if let currentErrorMessage {
            issueView(message: currentErrorMessage)
        } else if currentItems.isEmpty, isLoading {
            ContentUnavailableView {
                Label(L10n.string("network.browser.loading"), systemImage: "folder")
            } description: { ProgressView() }
        } else if currentItems.isEmpty {
            ContentUnavailableView(L10n.string("network.browser.folder_empty"), systemImage: "folder")
        } else {
            browserContent
                .overlay(alignment: .topTrailing) {
                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                            .padding(10)
                            .background(.thinMaterial, in: Capsule())
                            .padding(12)
                    }
                }
        }
    }

    @ViewBuilder private var sourceOverview: some View {
        if model.phase == .discovering, webDAVConnections.connections.isEmpty {
            ContentUnavailableView {
                Label(L10n.string("network.browser.discovering"), systemImage: "externaldrive.badge.wifi")
            } description: { ProgressView() }
        } else if let errorMessage = model.errorMessage, webDAVConnections.connections.isEmpty {
            issueView(message: errorMessage)
        } else if model.servers.isEmpty, webDAVConnections.connections.isEmpty {
            ContentUnavailableView {
                Label(L10n.string("network.browser.empty"), systemImage: "externaldrive.badge.questionmark")
            } description: {
                Text(L10n.string("network.browser.empty_hint"))
            } actions: {
                Button(L10n.string("network.browser.retry")) { Task { await model.discover() } }
                SettingsLink { Text(L10n.string("settings.title")) }
            }
        } else {
            ContentUnavailableView {
                Label(L10n.string("network.browser.choose_location"), systemImage: "sidebar.left")
            } description: {
                Text(L10n.string("network.browser.choose_location_hint"))
            }
        }
    }

    @ViewBuilder private var browserContent: some View {
        switch viewMode {
        case .icons: iconGrid
        case .list: listView
        case .columns: columnView
        case .gallery: galleryView
        }
    }

    private var iconGrid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 128), spacing: 14)], spacing: 18) {
                ForEach(currentItems) { item in
                    Button { open(item) } label: {
                        VStack(spacing: 10) {
                            Image(systemName: item.isFolder ? "folder.fill" : "film.fill")
                                .font(.system(size: 42, weight: .light))
                                .foregroundStyle(item.isFolder ? Color.accentColor : Color.secondary)
                                .frame(height: 52)
                            Text(item.name)
                                .font(.callout)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                            if let detail = item.detail {
                                Text(detail).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 118)
                        .padding(12)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(20)
        }
    }

    private var listView: some View {
        List(currentItems) { item in
            Button { open(item) } label: {
                HStack(spacing: 12) {
                    Image(systemName: item.isFolder ? "folder" : "film")
                        .foregroundStyle(item.isFolder ? Color.accentColor : Color.secondary)
                        .frame(width: 20)
                    Text(item.name).lineLimit(2)
                    Spacer()
                    if let detail = item.detail {
                        Text(detail).font(.caption).foregroundStyle(.secondary)
                    }
                    if item.isFolder { Image(systemName: "chevron.forward").foregroundStyle(.tertiary) }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .glazeGlassRow()
        }
        .listStyle(.inset)
    }

    private var columnView: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 0) {
                ForEach(browserLevels) { level in
                    List(level.items) { item in
                        Button { open(item) } label: {
                            HStack(spacing: 8) {
                                Image(systemName: item.isFolder ? "folder" : "film")
                                    .foregroundStyle(item.isFolder ? Color.accentColor : Color.secondary)
                                Text(item.name).lineLimit(1)
                                Spacer()
                                if item.isFolder { Image(systemName: "chevron.forward").foregroundStyle(.tertiary) }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .listStyle(.inset)
                    .frame(width: 260)
                    Divider()
                }
            }
        }
    }

    private var galleryView: some View {
        VStack(spacing: 0) {
            if let item = galleryItem {
                VStack(spacing: 16) {
                    Image(systemName: item.isFolder ? "folder.fill" : "film.fill")
                        .font(.system(size: 86, weight: .ultraLight))
                        .foregroundStyle(item.isFolder ? Color.accentColor : Color.secondary)
                    Text(item.name).font(.title2).lineLimit(2).multilineTextAlignment(.center)
                    if let detail = item.detail { Text(detail).foregroundStyle(.secondary) }
                    Button(item.isFolder
                           ? L10n.string("network.browser.open_folder")
                           : L10n.string("network.browser.play")) { open(item) }
                        .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(24)
            }
            Divider()
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(currentItems) { item in
                        Button { gallerySelectionID = item.id } label: {
                            VStack(spacing: 6) {
                                Image(systemName: item.isFolder ? "folder.fill" : "film.fill")
                                    .font(.title)
                                    .foregroundStyle(item.isFolder ? Color.accentColor : Color.secondary)
                                Text(item.name).font(.caption).lineLimit(1)
                            }
                            .frame(width: 112, height: 72)
                            .background(
                                gallerySelectionID == item.id ? Color.accentColor.opacity(0.18) : Color.white.opacity(0.04),
                                in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(12)
            }
            .frame(height: 98)
        }
        .onAppear { synchronizeGallerySelection() }
        .onChange(of: currentItems.map(\.id)) { _, _ in synchronizeGallerySelection() }
    }

    private var browserLevels: [NetworkBrowserLevel] {
        if selectedWebDAV != nil {
            return webDAVModel.levels.map { level in
                NetworkBrowserLevel(
                    id: level.id,
                    title: level.title,
                    items: level.entries.compactMap { makeItem($0, parentLevelID: level.id) }
                )
            }
        }
        return model.levels.map { level in
            NetworkBrowserLevel(
                id: level.id,
                title: level.title,
                items: level.nodes.map { makeItem($0, parentLevelID: level.id) }
            )
        }
    }

    private var currentItems: [NetworkBrowserItem] { browserLevels.last?.items ?? [] }
    private var galleryItem: NetworkBrowserItem? {
        currentItems.first(where: { $0.id == gallerySelectionID }) ?? currentItems.first
    }
    private var availableFavorites: [WebDAVFavorite] {
        let connectionIDs = Set(webDAVConnections.connections.map(\.id))
        return webDAVFavorites.favorites.filter { connectionIDs.contains($0.connectionID) }
    }
    private var hasSelectedSource: Bool { selectedWebDAV != nil || model.selectedServer != nil }
    private var isLoading: Bool {
        selectedWebDAV != nil ? webDAVModel.phase == .loading : model.phase == .browsing
    }
    private var currentErrorMessage: String? {
        selectedWebDAV != nil ? webDAVModel.errorMessage : model.errorMessage
    }
    private var isCurrentWebDAVFolderFavorite: Bool {
        guard let selectedWebDAV, let level = webDAVModel.levels.last else { return false }
        return webDAVFavorites.contains(connectionID: selectedWebDAV.id, url: level.url)
    }

    private func connection(for id: String) -> WebDAVConnection? {
        webDAVConnections.connections.first { $0.id == id }
    }

    private func open(_ connection: WebDAVConnection) {
        selectedWebDAV = connection
        gallerySelectionID = nil
        Task { await webDAVModel.open(connection) }
    }

    private func open(_ favorite: WebDAVFavorite) {
        guard let connection = connection(for: favorite.connectionID) else { return }
        selectedWebDAV = connection
        gallerySelectionID = nil
        Task { await webDAVModel.open(connection, at: favorite.url, title: favorite.name) }
    }

    private func open(_ item: NetworkBrowserItem) {
        gallerySelectionID = nil
        switch item.source {
        case .webDAV(let entry, let parentLevelID):
            if entry.isDirectory {
                webDAVModel.navigate(to: parentLevelID)
                Task { await webDAVModel.open(entry) }
            } else {
                openWebDAVVideo(entry)
            }
        case .dlna(let node, let parentLevelID):
            switch node.kind {
            case .container:
                Task { await model.open(node, from: parentLevelID) }
            case .video(let resource):
                guard let server = model.selectedServer else { return }
                onOpen(resource, .dlna(serverID: server.id, serverName: server.friendlyName))
                dismiss()
            case .unsupported:
                break
            }
        }
    }

    private func navigateBack() {
        gallerySelectionID = nil
        if selectedWebDAV != nil {
            if webDAVModel.canNavigateBack { webDAVModel.navigateBack() } else { selectedWebDAV = nil }
        } else if model.selectedServer != nil {
            model.navigateBack()
        }
    }

    private func navigate(to levelID: String) {
        gallerySelectionID = nil
        if selectedWebDAV != nil { webDAVModel.navigate(to: levelID) } else { model.navigate(to: levelID) }
    }

    private func refreshCurrentLocation() {
        if selectedWebDAV != nil {
            Task { await webDAVModel.reloadCurrent() }
        } else {
            Task { await model.retryCurrentLocation() }
        }
    }

    private func synchronizeGallerySelection() {
        if !currentItems.contains(where: { $0.id == gallerySelectionID }) {
            gallerySelectionID = currentItems.first?.id
        }
    }

    private func makeItem(_ entry: WebDAVEntry, parentLevelID: String) -> NetworkBrowserItem? {
        guard entry.isDirectory || entry.isVideo else { return nil }
        return NetworkBrowserItem(
            id: entry.url.absoluteString,
            name: entry.name,
            isFolder: entry.isDirectory,
            detail: entry.byteCount.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) },
            source: .webDAV(entry, parentLevelID: parentLevelID)
        )
    }

    private func makeItem(_ node: NetworkMediaNode, parentLevelID: String) -> NetworkBrowserItem {
        let isFolder: Bool
        let detail: String?
        switch node.kind {
        case .container:
            isFolder = true
            detail = nil
        case .video(let resource):
            isFolder = false
            detail = mediaDetail(resource)
        case .unsupported:
            isFolder = false
            detail = nil
        }
        return NetworkBrowserItem(
            id: node.id,
            name: node.title,
            isFolder: isFolder,
            detail: detail,
            source: .dlna(node, parentLevelID: parentLevelID)
        )
    }

    private func openWebDAVVideo(_ entry: WebDAVEntry) {
        guard let connection = selectedWebDAV else { return }
        let playbackURL = authenticatedURL(
            entry.url,
            username: connection.username,
            password: webDAVConnections.password(for: connection)
        )
        let resource = NetworkMediaResource(
            serverID: connection.id,
            objectID: entry.url.absoluteString,
            playbackURL: playbackURL,
            byteCount: entry.byteCount,
            dateAdded: entry.lastModified
        )
        onOpen(resource, .nas)
        dismiss()
    }

    private func authenticatedURL(_ url: URL, username: String, password: String?) -> URL {
        guard !username.isEmpty, let password,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        components.user = username
        components.password = password
        return components.url ?? url
    }

    private func issueView(message: String) -> some View {
        ContentUnavailableView {
            Label(L10n.string("network.browser.error"), systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button(L10n.string("network.browser.retry")) { refreshCurrentLocation() }
        }
    }

    private func mediaDetail(_ resource: NetworkMediaResource) -> String? {
        let size = resource.byteCount.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) }
        let duration = resource.duration.map(formatDuration)
        let detail = [duration, size].compactMap { $0 }.joined(separator: " · ")
        return detail.isEmpty ? nil : detail
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let seconds = max(Int(duration.rounded()), 0)
        let hours = seconds / 3_600
        let minutes = (seconds % 3_600) / 60
        let remainder = seconds % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, remainder)
            : String(format: "%d:%02d", minutes, remainder)
    }
}
