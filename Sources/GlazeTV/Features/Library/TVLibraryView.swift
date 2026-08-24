import GlazeCore
import SwiftUI

/// Finding something to watch, from the sofa.
///
/// The Mac browser is a sheet inside a working session; this is the whole app. There is
/// no pointer, no keyboard, and the screen is across a room, so everything here is a
/// focusable row big enough to read from the sofa and reachable with a d-pad.
struct TVLibraryView: View {
    @State private var model = NetworkMediaBrowserModel()
    @State private var playing: NetworkMediaResource?

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(model.navigationTitle)
        }
        .task { await model.discoverIfNeeded() }
        .fullScreenCover(item: $playing) { resource in
            TVPlayerView(resource: resource)
        }
        .onExitCommand { model.navigateBack() }
    }

    /// Driven by what there is to show, not by the phase alone. `discover()` leaves the
    /// model in `.idle` when it succeeds, so treating `.idle` as "still looking" left
    /// the spinner up forever with the servers sitting right there behind it.
    @ViewBuilder
    private var content: some View {
        if model.phase == .discovering {
            waiting(L10n.string("network.browser.discovering"))
        } else if model.selectedServer == nil {
            serverList
        } else if model.phase == .browsing, model.currentNodes.isEmpty {
            waiting(L10n.string("network.browser.loading"))
        } else {
            nodeList
        }
    }

    private func waiting(_ message: String) -> some View {
        VStack(spacing: 28) {
            ProgressView()
                .controlSize(.large)
            Text(message)
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }

    private var serverList: some View {
        Group {
            if model.servers.isEmpty {
                emptyState(
                    title: L10n.string("network.browser.empty"),
                    detail: L10n.string("network.browser.empty_hint")
                )
            } else {
                List(model.servers) { server in
                    Button {
                        Task { await model.select(server) }
                    } label: {
                        Label(server.friendlyName, systemImage: "externaldrive.connected.to.line.below")
                    }
                }
            }
        }
    }

    private var nodeList: some View {
        Group {
            if model.currentNodes.isEmpty {
                emptyState(title: L10n.string("network.browser.folder_empty"), detail: nil)
            } else {
                List(model.currentNodes) { node in
                    row(for: node)
                }
            }
        }
    }

    @ViewBuilder
    private func row(for node: NetworkMediaNode) -> some View {
        switch node.kind {
        case .container:
            Button {
                Task { await model.open(node) }
            } label: {
                Label(node.title, systemImage: "folder")
            }
        case .video(let resource):
            Button {
                playing = resource
            } label: {
                Label(node.title, systemImage: "play.rectangle")
            }
        case .unsupported:
            // Shown rather than hidden: a file missing from a folder the viewer can see
            // on their NAS reads as a bug in Glaze.
            Label(node.title, systemImage: "questionmark.square.dashed")
                .foregroundStyle(.secondary)
        }
    }

    private func emptyState(title: String, detail: String?) -> some View {
        VStack(spacing: 18) {
            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            Text(title).font(.title2)
            if let detail {
                Text(detail)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 720)
            }
            Button(L10n.string("network.browser.refresh")) {
                Task { await model.discover() }
            }
            .padding(.top, 12)
        }
    }
}

extension NetworkMediaResource: @retroactive Identifiable {
    public var id: String { "\(serverID)#\(objectID)" }
}
