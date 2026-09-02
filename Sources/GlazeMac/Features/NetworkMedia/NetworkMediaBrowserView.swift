import Foundation
import GlazeCore
import SwiftUI

struct NetworkMediaBrowserView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model = NetworkMediaBrowserModel()
    @State private var webDAVConnections = WebDAVConnectionStore()
    @State private var webDAVModel = WebDAVBrowserModel()
    @State private var selectedWebDAV: WebDAVConnection?

    let onOpen: (NetworkMediaResource, MediaLibrarySource) -> Void

    var body: some View {
        NavigationStack {
            Group {
                if selectedWebDAV != nil {
                    webDAVMediaList
                } else if model.selectedServer == nil {
                    serverList
                } else {
                    mediaList
                }
            }
            .navigationTitle(navigationTitle)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.string("network.browser.close")) { dismiss() }
                }
                // DLNA/UPnP is the one concept a viewer has to understand before this
                // sheet can do anything for them, so the explanation lives in it.
                ToolbarItem(placement: .automatic) {
                    GlazeHelpButton(
                        titleKey: "network.browser.title",
                        bodyKey: "help.network.browser"
                    )
                }
                if canNavigateBack {
                    ToolbarItem(placement: .navigation) {
                        Button(action: navigateBack) {
                            Label(L10n.string("network.browser.back"), systemImage: "chevron.left")
                        }
                    }
                } else {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            Task { await model.discover() }
                        } label: {
                            Label(L10n.string("network.browser.refresh"), systemImage: "arrow.clockwise")
                        }
                        .disabled(model.phase != .idle)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .toolbarBackground(.hidden, for: .windowToolbar)
        .frame(minWidth: 620, minHeight: 460)
        // Replaces the sheet's own chrome rather than painting inside it, so the
        // backdrop runs edge to edge instead of leaving opaque bands top and bottom.
        .presentationBackground { GlazeAmbientBackdrop(isAnimated: false) }
        .preferredColorScheme(.dark)
        .task { await model.discoverIfNeeded() }
    }

    @ViewBuilder
    private var serverList: some View {
        if model.phase == .discovering, webDAVConnections.connections.isEmpty {
            ContentUnavailableView {
                Label(L10n.string("network.browser.discovering"), systemImage: "externaldrive.badge.wifi")
            } description: {
                ProgressView()
            }
        } else if let errorMessage = model.errorMessage, webDAVConnections.connections.isEmpty {
            issueView(message: errorMessage)
        } else if model.servers.isEmpty, webDAVConnections.connections.isEmpty {
            ContentUnavailableView {
                Label(L10n.string("network.browser.empty"), systemImage: "externaldrive.badge.questionmark")
            } description: {
                Text(L10n.string("network.browser.empty_hint"))
            } actions: {
                HStack {
                    Button(L10n.string("network.browser.retry")) {
                        Task { await model.discover() }
                    }
                    SettingsLink {
                        Text(L10n.string("settings.title"))
                    }
                }
            }
        } else {
            List {
                if !model.servers.isEmpty {
                    Section(L10n.string("settings.network.dlna.title")) {
                        ForEach(model.servers) { server in
                            Button {
                                Task { await model.select(server) }
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "dot.radiowaves.left.and.right")
                                        .foregroundStyle(.tint)
                                    Text(server.friendlyName)
                                    Spacer()
                                    Image(systemName: "chevron.forward").foregroundStyle(.tertiary)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .glazeGlassRow()
                        }
                    }
                }

                if !webDAVConnections.connections.isEmpty {
                    Section(L10n.string("webdav.section.title")) {
                        ForEach(webDAVConnections.connections) { connection in
                            Button {
                                selectedWebDAV = connection
                                Task { await webDAVModel.open(connection) }
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "externaldrive.connected.to.line.below")
                                        .foregroundStyle(.tint)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(connection.name)
                                        Text(connection.rootURL.host ?? connection.rootURL.absoluteString)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.forward").foregroundStyle(.tertiary)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .glazeGlassRow()
                        }
                    }
                }
            }
            .listStyle(.inset)
        }
    }

    @ViewBuilder
    private var webDAVMediaList: some View {
        if webDAVModel.phase == .loading {
            ContentUnavailableView {
                Label(L10n.string("network.browser.loading"), systemImage: "folder")
            } description: {
                ProgressView()
            }
        } else if let errorMessage = webDAVModel.errorMessage {
            ContentUnavailableView {
                Label(L10n.string("network.browser.error"), systemImage: "exclamationmark.triangle")
            } description: {
                Text(errorMessage)
            } actions: {
                if let selectedWebDAV {
                    Button(L10n.string("network.browser.retry")) {
                        Task { await webDAVModel.open(selectedWebDAV) }
                    }
                }
            }
        } else if webDAVModel.folders.isEmpty, webDAVModel.videos.isEmpty {
            ContentUnavailableView(L10n.string("network.browser.folder_empty"), systemImage: "folder")
        } else {
            List {
                ForEach(webDAVModel.folders) { entry in
                    Button {
                        Task { await webDAVModel.open(entry) }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "folder").foregroundStyle(.tint)
                            Text(entry.name).lineLimit(2)
                            Spacer()
                            Image(systemName: "chevron.forward").foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .glazeGlassRow()
                }

                ForEach(webDAVModel.videos) { entry in
                    Button { openWebDAVVideo(entry) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "film").foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(entry.name).lineLimit(2)
                                if let byteCount = entry.byteCount {
                                    Text(ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .glazeGlassRow()
                }
            }
            .listStyle(.inset)
        }
    }

    @ViewBuilder
    private var mediaList: some View {
        if model.phase == .browsing {
            ContentUnavailableView {
                Label(L10n.string("network.browser.loading"), systemImage: "folder")
            } description: {
                ProgressView()
            }
        } else if let errorMessage = model.errorMessage {
            issueView(message: errorMessage)
        } else if model.currentNodes.isEmpty {
            ContentUnavailableView(L10n.string("network.browser.folder_empty"), systemImage: "folder")
        } else {
            List(model.currentNodes) { node in
                Button {
                    select(node)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: iconName(for: node))
                            .foregroundStyle(isContainer(node) ? Color.accentColor : Color.secondary)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(node.title).lineLimit(2)
                            if case .video(let resource) = node.kind, let detail = mediaDetail(resource) {
                                Text(detail).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if isContainer(node) {
                            Image(systemName: "chevron.forward").foregroundStyle(.tertiary)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .glazeGlassRow()
            }
            .listStyle(.inset)
        }
    }

    private func issueView(message: String) -> some View {
        ContentUnavailableView {
            Label(L10n.string("network.browser.error"), systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button(L10n.string("network.browser.retry")) {
                Task { await model.retryCurrentLocation() }
            }
        }
    }

    private func select(_ node: NetworkMediaNode) {
        switch node.kind {
        case .container:
            Task { await model.open(node) }
        case .video(let resource):
            guard let server = model.selectedServer else { return }
            onOpen(resource, .dlna(serverID: server.id, serverName: server.friendlyName))
            dismiss()
        case .unsupported:
            break
        }
    }

    private var navigationTitle: String {
        if selectedWebDAV != nil {
            return webDAVModel.title
        }
        return model.navigationTitle
    }

    private var canNavigateBack: Bool {
        if selectedWebDAV != nil { return true }
        return model.canNavigateBack
    }

    private func navigateBack() {
        if selectedWebDAV != nil {
            if webDAVModel.canNavigateBack {
                webDAVModel.navigateBack()
            } else {
                selectedWebDAV = nil
            }
        } else {
            model.navigateBack()
        }
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

    /// Keeps credentials transient: they are inserted only into the in-memory URL
    /// handed to libVLC and are never encoded in the saved connection record.
    private func authenticatedURL(_ url: URL, username: String, password: String?) -> URL {
        guard !username.isEmpty, let password,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }
        components.user = username
        components.password = password
        return components.url ?? url
    }

    private func isContainer(_ node: NetworkMediaNode) -> Bool {
        if case .container = node.kind { return true }
        return false
    }

    private func iconName(for node: NetworkMediaNode) -> String {
        switch node.kind {
        case .container: "folder"
        case .video: "film"
        case .unsupported: "questionmark.square.dashed"
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
