import GlazeCore
import SwiftUI

struct TVRootView: View {
    @State private var preferences = TVUserPreferences()
    @State private var media = NetworkMediaBrowserModel()

    var body: some View {
        Group {
            if preferences.onboardingCompleted {
                TVAppShell(media: media, preferences: preferences)
            } else {
                TVOnboardingView(model: media, preferences: preferences)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: preferences.onboardingCompleted)
    }
}

private struct TVAppShell: View {
    let media: NetworkMediaBrowserModel
    @Bindable var preferences: TVUserPreferences

    @State private var destination: TVDestination = .home
    @State private var isSidebarVisible = true

    var body: some View {
        ZStack(alignment: .leading) {
            TVTheme.ground.ignoresSafeArea()
            destinationView

            if isSidebarVisible {
                Color.black.opacity(0.22)
                    .ignoresSafeArea()
                    .transition(.opacity)

                TVSidebar(selection: $destination) {
                    withAnimation(.easeOut(duration: 0.2)) {
                        isSidebarVisible = false
                    }
                }
                .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .task {
            await media.discoverIfNeeded()
            guard media.selectedServer == nil,
                  let preferredID = preferences.preferredServerID,
                  let server = media.servers.first(where: { $0.id == preferredID }) else { return }
            await media.select(server)
        }
        .onExitCommand {
            if isSidebarVisible {
                isSidebarVisible = false
            } else if media.canNavigateBack, destination == .library {
                media.navigateBack()
            } else {
                withAnimation(.easeOut(duration: 0.2)) {
                    isSidebarVisible = true
                }
            }
        }
        .onChange(of: destination) { _, _ in
            withAnimation(.easeOut(duration: 0.2)) {
                isSidebarVisible = false
            }
        }
        .animation(.easeOut(duration: 0.2), value: isSidebarVisible)
    }

    @ViewBuilder
    private var destinationView: some View {
        switch destination {
        case .search:
            TVSearchView(model: media)
        case .home:
            TVHomeView(model: media, preferences: preferences) {
                destination = .sources
                isSidebarVisible = true
            }
        case .library:
            TVLibraryView(model: media, preferences: preferences)
        case .sources:
            TVMediaSourcesView(model: media, preferences: preferences)
        case .settings:
            TVSettingsView(preferences: preferences)
        }
    }
}

private enum TVDestination: String, CaseIterable, Identifiable {
    case search
    case home
    case library
    case sources
    case settings

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .search: "tv.navigation.search"
        case .home: "tv.navigation.home"
        case .library: "tv.navigation.library"
        case .sources: "tv.navigation.sources"
        case .settings: "settings.title"
        }
    }

    var symbol: String {
        switch self {
        case .search: "magnifyingglass"
        case .home: "house.fill"
        case .library: "rectangle.stack.fill"
        case .sources: "externaldrive.connected.to.line.below.fill"
        case .settings: "gearshape.fill"
        }
    }
}

private struct TVSidebar: View {
    @Binding var selection: TVDestination
    let onSelect: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 16) {
                Image(systemName: "play.tv.fill")
                    .foregroundStyle(TVTheme.amber)
                Text("Glaze")
                    .font(.system(size: 34, weight: .bold))
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 20)

            VStack(spacing: 14) {
                ForEach(TVDestination.allCases) { destination in
                    Button {
                        selection = destination
                        onSelect()
                    } label: {
                        TVSidebarLabel(destination: destination, isSelected: selection == destination)
                    }
                    .buttonStyle(.plain)
                    .focusEffectDisabled()
                }
            }
            .focusSection()

            Spacer()

            Text(L10n.string("tv.navigation.hint"))
                .font(.system(size: 19))
                .foregroundStyle(TVTheme.dim)
                .padding(.horizontal, 28)
        }
        .padding(.vertical, 52)
        .padding(.horizontal, 28)
        .frame(width: 440)
        .background(.ultraThinMaterial)
        .overlay(alignment: .trailing) {
            Rectangle().fill(.white.opacity(0.12)).frame(width: 1)
        }
        .ignoresSafeArea()
    }
}

private struct TVSidebarLabel: View {
    let destination: TVDestination
    let isSelected: Bool

    @Environment(\.isFocused) private var isFocused

    var body: some View {
        Label(L10n.string(destination.titleKey), systemImage: destination.symbol)
            .font(.system(size: 27, weight: .semibold))
            .foregroundStyle(isFocused ? .black : (isSelected ? TVTheme.amber : .white))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .frame(height: 58)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isFocused ? .white : (isSelected ? TVTheme.amber.opacity(0.14) : .clear))
            )
            .scaleEffect(isFocused ? 1.035 : 1)
            .shadow(color: .black.opacity(isFocused ? 0.35 : 0), radius: 18, y: 10)
            .animation(.easeOut(duration: 0.16), value: isFocused)
    }
}
