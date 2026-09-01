import GlazeCore
import SwiftUI

/// One-time setup that makes the first launch about the viewer, not a failed scan.
struct TVOnboardingView: View {
    let model: NetworkMediaBrowserModel
    @Bindable var preferences: TVUserPreferences

    @State private var step: Step = .welcome
    @State private var selectedServerID: String?
    @State private var isFinishing = false
    @State private var isAddingWebDAV = false
    @State private var webdav = TVWebDAVConnections()
    @FocusState private var focusedControl: FocusControl?

    private enum Step: Int, CaseIterable {
        case welcome
        case language
        case sources
    }

    private enum FocusControl: Hashable {
        case welcomeContinue
        case language(String)
        case languageBack
        case languageContinue
        case source(String)
        case sourceRefresh
        case sourceBack
        case sourceWebDAV
        case sourceFinish
    }

    var body: some View {
        ZStack {
            TVTheme.ground.ignoresSafeArea()
            ambientBackdrop

            VStack(spacing: 0) {
                progress
                    .padding(.top, 54)

                Group {
                    switch step {
                    case .welcome: welcome
                    case .language: language
                    case .sources: sources
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task { await model.discoverIfNeeded() }
        .fullScreenCover(isPresented: $isAddingWebDAV) {
            TVWebDAVSetupView { connection, password in
                webdav.save(connection, password: password)
            }
        }
    }

    private var ambientBackdrop: some View {
        ZStack {
            RadialGradient(
                colors: [TVTheme.amber.opacity(0.16), .clear],
                center: .topTrailing,
                startRadius: 20,
                endRadius: 900
            )
            LinearGradient(
                colors: [.clear, .black.opacity(0.38)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
    }

    private var progress: some View {
        HStack(spacing: 12) {
            ForEach(Step.allCases, id: \.rawValue) { item in
                Capsule()
                    .fill(item.rawValue <= step.rawValue ? TVTheme.amber : .white.opacity(0.18))
                    .frame(width: item == step ? 58 : 24, height: 7)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: step)
    }

    private var welcome: some View {
        VStack(spacing: 30) {
            Image(systemName: "play.tv.fill")
                .font(.system(size: 92, weight: .medium))
                .foregroundStyle(TVTheme.amber)

            Text(L10n.string("tv.onboarding.welcome.title"))
                .font(.system(size: 68, weight: .bold))

            Text(L10n.string("tv.onboarding.welcome.detail"))
                .font(.system(size: 28))
                .foregroundStyle(TVTheme.dim)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 940)

            Button(L10n.string("tv.onboarding.continue")) { step = .language }
                .buttonStyle(.borderedProminent)
                .tint(TVTheme.amber)
                .padding(.top, 18)
                .focused($focusedControl, equals: .welcomeContinue)
        }
    }

    private var language: some View {
        VStack(spacing: 30) {
            Text(L10n.string("tv.onboarding.language.title"))
                .font(.system(size: 58, weight: .bold))

            Text(L10n.string("tv.onboarding.language.detail"))
                .font(.system(size: 27))
                .foregroundStyle(TVTheme.dim)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 900)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 22) {
                    ForEach(TVSubtitleLanguage.supported) { language in
                        Button {
                            preferences.defaultSubtitleLanguageCode = language.id
                        } label: {
                            VStack(spacing: 12) {
                                Text(language.localizedName)
                                    .font(.system(size: 30, weight: .semibold))
                                if language.id == preferences.defaultSubtitleLanguageCode {
                                    Label(L10n.string("tv.settings.default"), systemImage: "checkmark.circle.fill")
                                        .font(.system(size: 20, weight: .medium))
                                        .foregroundStyle(TVTheme.amber)
                                }
                            }
                            .frame(width: 250, height: 132)
                        }
                        .buttonStyle(.card)
                        .focused($focusedControl, equals: .language(language.id))
                        .onMoveCommand { direction in
                            if direction == .down {
                                focusedControl = .languageContinue
                            }
                        }
                    }
                }
                .padding(.horizontal, 80)
                .padding(.vertical, 28)
            }
            .focusSection()

            HStack(spacing: 22) {
                Button(L10n.string("network.browser.back")) { step = .welcome }
                    .focused($focusedControl, equals: .languageBack)
                Button(L10n.string("tv.onboarding.continue")) { step = .sources }
                    .buttonStyle(.borderedProminent)
                    .tint(TVTheme.amber)
                    .focused($focusedControl, equals: .languageContinue)
                    .onMoveCommand { direction in
                        if direction == .up {
                            focusedControl = .language(preferences.defaultSubtitleLanguageCode)
                        }
                    }
            }
            .focusSection()
        }
    }

    private var sources: some View {
        VStack(spacing: 26) {
            Text(L10n.string("tv.onboarding.sources.title"))
                .font(.system(size: 58, weight: .bold))

            Text(L10n.string("tv.onboarding.sources.detail"))
                .font(.system(size: 27))
                .foregroundStyle(TVTheme.dim)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 980)

            sourceChoices
                .frame(maxWidth: 1100, maxHeight: 350)

            HStack(spacing: 22) {
                Button(L10n.string("network.browser.back")) { step = .language }
                    .focused($focusedControl, equals: .sourceBack)
                Button(L10n.string("webdav.add")) { isAddingWebDAV = true }
                    .focused($focusedControl, equals: .sourceWebDAV)
                Button {
                    Task { await finish() }
                } label: {
                    if isFinishing {
                        ProgressView()
                    } else {
                        Text(L10n.string("tv.onboarding.finish"))
                    }
                }
                    .buttonStyle(.borderedProminent)
                    .tint(TVTheme.amber)
                    .disabled(isFinishing)
                    .focused($focusedControl, equals: .sourceFinish)
            }
            .focusSection()
        }
    }

    @ViewBuilder
    private var sourceChoices: some View {
        if model.phase == .discovering {
            VStack(spacing: 18) {
                ProgressView().controlSize(.large)
                Text(L10n.string("network.browser.discovering"))
                    .foregroundStyle(TVTheme.dim)
            }
        } else if model.servers.isEmpty {
            VStack(spacing: 18) {
                Image(systemName: "externaldrive.badge.questionmark")
                    .font(.system(size: 58))
                    .foregroundStyle(TVTheme.dim)
                Text(L10n.string("network.browser.empty"))
                    .font(.system(size: 30, weight: .semibold))
                Text(L10n.string("tv.onboarding.sources.optional"))
                    .font(.system(size: 22))
                    .foregroundStyle(TVTheme.dim)
                Button(L10n.string("network.browser.refresh")) {
                    Task { await model.discover() }
                }
                .focused($focusedControl, equals: .sourceRefresh)
            }
        } else {
            ScrollView {
                VStack(spacing: 16) {
                    ForEach(model.servers) { server in
                        Button {
                            selectedServerID = server.id
                        } label: {
                            HStack(spacing: 22) {
                                Image(systemName: "externaldrive.connected.to.line.below.fill")
                                    .foregroundStyle(TVTheme.amber)
                                Text(server.friendlyName)
                                    .font(.system(size: 30, weight: .medium))
                                Spacer()
                                if selectedServerID == server.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(TVTheme.amber)
                                }
                            }
                            .padding(.horizontal, 28)
                            .frame(maxWidth: .infinity, minHeight: 82)
                        }
                        .buttonStyle(.card)
                        .focused($focusedControl, equals: .source(server.id))
                        .onMoveCommand { direction in
                            if direction == .down {
                                focusedControl = .sourceFinish
                            }
                        }
                    }
                }
                .padding(20)
            }
        }
    }

    private func finish() async {
        guard !isFinishing else { return }
        isFinishing = true
        defer { isFinishing = false }

        let serverID = selectedServerID ?? model.servers.first?.id
        if let server = model.servers.first(where: { $0.id == serverID }) {
            await model.select(server)
        }
        preferences.finishOnboarding(serverID: serverID)
    }
}
