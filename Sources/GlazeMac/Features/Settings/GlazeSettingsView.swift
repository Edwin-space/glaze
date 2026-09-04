import GlazeCore
import SwiftUI

/// A single, discoverable home for choices that outlive the current video.
///
/// Settings are grouped by the viewer's task rather than by implementation layer.
/// The player inspector remains contextual to one film; this window owns defaults,
/// appearance, and reusable network locations.
struct GlazeSettingsView: View {
    private enum Page: String, CaseIterable, Identifiable {
        case subtitles
        case translation
        case network
        case metadata

        var id: Self { self }

        var titleKey: String {
            switch self {
            case .subtitles: "settings.tab.subtitles"
            case .translation: "settings.tab.translation"
            case .network: "settings.tab.network"
            case .metadata: "settings.tab.metadata"
            }
        }

        var symbolName: String {
            switch self {
            case .subtitles: "captions.bubble"
            case .translation: "character.bubble"
            case .network: "externaldrive.connected.to.line.below"
            case .metadata: "film"
            }
        }
    }

    @State private var preferences = GlazePreferences.shared
    @State private var connections = WebDAVConnectionStore()
    @State private var selection: Page? = .subtitles
    @State private var editingConnection: WebDAVConnection?
    @State private var isAddingConnection = false
    @State private var connectionPendingRemoval: WebDAVConnection?
    @State private var connectionTestStates: [String: ConnectionTestState] = [:]

    var body: some View {
        NavigationSplitView {
            List(Page.allCases, selection: $selection) { page in
                Label(L10n.string(page.titleKey), systemImage: page.symbolName)
                    .tag(page)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 172, ideal: 188, max: 220)
        } detail: {
            ZStack {
                GlazeAmbientBackdrop(isAnimated: false, scrimOpacity: 0.18)
                selectedPage
            }
        }
        .frame(minWidth: 780, idealWidth: 820, minHeight: 570, idealHeight: 620)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $isAddingConnection) {
            WebDAVConnectionEditorView { connection, password in
                connections.save(connection, password: password)
            }
        }
        .sheet(item: $editingConnection) { connection in
            WebDAVConnectionEditorView(
                connection: connection,
                storedPassword: connections.password(for: connection)
            ) { updated, password in
                connections.save(updated, password: password)
            }
        }
        .alert(
            L10n.string("settings.network.remove_title"),
            isPresented: removalAlertPresentation,
            presenting: connectionPendingRemoval
        ) { connection in
            Button(L10n.string("webdav.remove"), role: .destructive) {
                connections.remove(connection)
                connectionTestStates[connection.id] = nil
                connectionPendingRemoval = nil
            }
            Button(L10n.string("settings.cancel"), role: .cancel) {
                connectionPendingRemoval = nil
            }
        } message: { connection in
            Text(String(format: L10n.string("settings.network.remove_message"), connection.name))
        }
    }

    private var removalAlertPresentation: Binding<Bool> {
        Binding(
            get: { connectionPendingRemoval != nil },
            set: { if !$0 { connectionPendingRemoval = nil } }
        )
    }

    @ViewBuilder
    private var selectedPage: some View {
        switch selection ?? .subtitles {
        case .subtitles: subtitleSettings
        case .translation: translationSettings
        case .network: networkSettings
        case .metadata: metadataSettings
        }
    }

    private var subtitleSettings: some View {
        SettingsPage(
            titleKey: "settings.tab.subtitles",
            descriptionKey: "settings.subtitle.description"
        ) {
            SubtitleAppearancePreview(preferences: preferences)

            SettingsCard(titleKey: "settings.section.appearance") {
                settingsRow(labelKey: "subtitle.appearance.size") {
                    HStack(spacing: 12) {
                        Slider(value: $preferences.fontSize, in: 14...48, step: 1)
                            .frame(maxWidth: 260)
                        Text(String(format: L10n.string("subtitle.appearance.points_format"), Int(preferences.fontSize)))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 52, alignment: .trailing)
                    }
                }

                settingsRow(labelKey: "subtitle.appearance.position") {
                    Picker("", selection: $preferences.position) {
                        ForEach(SubtitlePosition.allCases, id: \.self) { position in
                            Text(L10n.string(position.labelKey)).tag(position)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 360)
                }

                settingsRow(labelKey: "subtitle.appearance.offset") {
                    HStack(spacing: 12) {
                        Slider(value: $preferences.positionOffset, in: 0...120, step: 4)
                            .frame(maxWidth: 260)
                        Text(String(format: L10n.string("subtitle.appearance.offset_format"), Int(preferences.positionOffset)))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 52, alignment: .trailing)
                    }
                }

                settingsRow(labelKey: "subtitle.appearance.background") {
                    Picker("", selection: $preferences.background) {
                        ForEach(SubtitleBackground.allCases, id: \.self) { background in
                            Text(L10n.string(background.labelKey)).tag(background)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 360)
                }

                if preferences.background == .plate {
                    settingsRow(labelKey: "subtitle.appearance.opacity") {
                        HStack(spacing: 12) {
                            Slider(value: $preferences.backgroundOpacity, in: 0.2...0.8, step: 0.05)
                                .frame(maxWidth: 260)
                            Text(preferences.backgroundOpacity, format: .percent.precision(.fractionLength(0)))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .frame(width: 52, alignment: .trailing)
                        }
                    }
                }

                HStack {
                    Spacer()
                    Button(L10n.string("settings.restore_defaults")) {
                        preferences.textSize = .default
                        preferences.position = .default
                        preferences.positionOffset = 0
                        preferences.background = .default
                        preferences.backgroundOpacity = 0.48
                    }
                }
            }

            SettingsCard(titleKey: "settings.section.generation") {
                settingsRow(labelKey: "subtitle.model.tier") {
                    Picker("", selection: $preferences.transcriptionTier) {
                        ForEach(TranscriptionModelTier.allCases, id: \.self) { tier in
                            Text(L10n.string(tier.labelKey)).tag(tier)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 240)
                }

                Text(
                    String(
                        format: L10n.string("subtitle.model.download_format"),
                        preferences.transcriptionTier.approximateDownloadMegabytes
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                settingsRow(labelKey: "subtitle.panel.storage") {
                    Picker("", selection: $preferences.storageLocation) {
                        ForEach(SubtitleStorageLocation.allCases, id: \.self) { location in
                            Text(L10n.string(location.labelKey)).tag(location)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 240)
                }
            }
        }
    }

    private var translationSettings: some View {
        SettingsPage(
            titleKey: "settings.tab.translation",
            descriptionKey: "settings.translation.description"
        ) {
            SettingsCard(titleKey: "settings.section.translation") {
                settingsRow(labelKey: "subtitle.translate.engine") {
                    Picker("", selection: $preferences.translationEngineID) {
                        Text(L10n.string(SubtitleTranslationEngineID.appleTranslation.labelKey))
                            .tag(SubtitleTranslationEngineID.appleTranslation)
                        Text(L10n.string(SubtitleTranslationEngineID.appleFoundationModel.labelKey))
                            .tag(SubtitleTranslationEngineID.appleFoundationModel)
                    }
                    .labelsHidden()
                    .frame(maxWidth: 280)
                }

                if preferences.translationEngineID == .appleFoundationModel {
                    Label(
                        L10n.string("subtitle.translate.engine.on_device_ai_hint"),
                        systemImage: "lock.shield"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                } else {
                    settingsRow(labelKey: "subtitle.translate.quality") {
                        Picker("", selection: $preferences.translationQuality) {
                            ForEach(SubtitleTranslationQuality.allCases, id: \.self) { quality in
                                Text(L10n.string(quality.labelKey)).tag(quality)
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: 240)
                    }
                }

                settingsRow(labelKey: "subtitle.translate.output") {
                    Picker("", selection: $preferences.translationOutput) {
                        ForEach(SubtitleTranslationOutput.allCases, id: \.self) { output in
                            Text(L10n.string(output.labelKey)).tag(output)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 240)
                }
            }
        }
    }

    private var networkSettings: some View {
        SettingsPage(
            titleKey: "settings.tab.network",
            descriptionKey: "settings.network.description"
        ) {
            SettingsCard(titleKey: "settings.network.discovery.title") {
                protocolRow(
                    systemImage: "dot.radiowaves.left.and.right",
                    titleKey: "settings.network.dlna.title",
                    detailKey: "settings.network.dlna.detail",
                    statusKey: "settings.network.automatic"
                )
            }

            SettingsCard(titleKey: "webdav.section.title") {
                if connections.connections.isEmpty {
                    HStack(spacing: 14) {
                        Image(systemName: "externaldrive.badge.plus")
                            .font(.system(size: 24, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 30)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(L10n.string("settings.network.webdav.empty"))
                                .font(.headline)
                            Text(L10n.string("settings.network.webdav.empty_detail"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer(minLength: 18)

                        Button {
                            isAddingConnection = true
                        } label: {
                            Label(L10n.string("webdav.add"), systemImage: "plus")
                        }
                        .buttonStyle(.glassProminent)
                    }
                } else {
                    ForEach(connections.connections) { connection in
                        WebDAVConnectionRow(
                            connection: connection,
                            testState: connectionTestStates[connection.id] ?? .idle,
                            onTest: { test(connection) },
                            onEdit: { editingConnection = connection },
                            onRemove: { connectionPendingRemoval = connection }
                        )

                        if connection.id != connections.connections.last?.id {
                            Divider()
                        }
                    }

                    HStack {
                        Spacer()
                        Button {
                            isAddingConnection = true
                        } label: {
                            Label(L10n.string("webdav.add"), systemImage: "plus")
                        }
                        .buttonStyle(.glassProminent)
                    }
                }
            }

            SettingsCard(titleKey: "settings.network.other_locations.title") {
                protocolRow(
                    systemImage: "externaldrive",
                    titleKey: "settings.network.smb.title",
                    detailKey: "settings.network.smb.detail",
                    statusKey: "settings.network.finder_managed"
                )

                Divider()

                protocolRow(
                    systemImage: "network.slash",
                    titleKey: "settings.network.ftp.title",
                    detailKey: "settings.network.ftp.detail",
                    statusKey: "settings.network.not_supported"
                )
            }
        }
    }

    private var metadataSettings: some View {
        SettingsPage(
            titleKey: "settings.tab.metadata",
            descriptionKey: "settings.metadata.description"
        ) {
            SettingsCard(titleKey: "settings.section.metadata") {
                settingsRow(labelKey: "metadata.settings.key") {
                    SecureField("", text: $preferences.tmdbAPIKey)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 340)
                }

                Text(L10n.string("help.metadata.key"))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Link(
                    L10n.string("metadata.attribution"),
                    destination: URL(string: "https://www.themoviedb.org")!
                )
                .font(.caption)
            }
        }
    }

    private func settingsRow<Content: View>(
        labelKey: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        LabeledContent {
            content()
        } label: {
            Text(L10n.string(labelKey))
        }
    }

    private func protocolRow(
        systemImage: String,
        titleKey: String,
        detailKey: String,
        statusKey: String
    ) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.tint)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.string(titleKey)).font(.headline)
                Text(L10n.string(detailKey))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 20)

            Text(L10n.string(statusKey))
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(.quaternary, in: Capsule())
        }
    }

    private func test(_ connection: WebDAVConnection) {
        connectionTestStates[connection.id] = .testing
        let password = connections.password(for: connection)
        Task {
            do {
                _ = try await WebDAVClient().list(
                    connection.rootURL,
                    credentials: credentialPair(username: connection.username, password: password)
                )
                connectionTestStates[connection.id] = .success
            } catch {
                connectionTestStates[connection.id] = .failure(webDAVMessage(for: error))
            }
        }
    }
}

private struct SettingsPage<Content: View>: View {
    let titleKey: String
    let descriptionKey: String
    let content: Content

    init(titleKey: String, descriptionKey: String, @ViewBuilder content: () -> Content) {
        self.titleKey = titleKey
        self.descriptionKey = descriptionKey
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(L10n.string(titleKey))
                        .font(.title2.weight(.semibold))
                    Text(L10n.string(descriptionKey))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                content
            }
            .padding(.horizontal, 30)
            .padding(.vertical, 28)
            .frame(maxWidth: 680, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .scrollContentBackground(.hidden)
    }
}

private struct SettingsCard<Content: View>: View {
    let titleKey: String
    let content: Content

    init(titleKey: String, @ViewBuilder content: () -> Content) {
        self.titleKey = titleKey
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.string(titleKey)).font(.headline)
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: GlazeGlass.Radius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: GlazeGlass.Radius.card, style: .continuous)
                .strokeBorder(.white.opacity(0.10), lineWidth: 1)
        }
    }
}

private struct SubtitleAppearancePreview: View {
    @Bindable var preferences: GlazePreferences

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.10, green: 0.16, blue: 0.19),
                    Color(red: 0.18, green: 0.24, blue: 0.20),
                    Color.black.opacity(0.92)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack {
                if preferences.position != .top { Spacer() }
                subtitleSample
                    .padding(.top, preferences.position == .top ? 18 + CGFloat(preferences.positionOffset * 0.35) : 0)
                    .padding(.bottom, preferences.position == .top ? 0 : 18 + previewBottomOffset)
                if preferences.position == .top { Spacer() }
            }
            .padding(.horizontal, 24)
        }
        .frame(height: 220)
        .clipShape(RoundedRectangle(cornerRadius: GlazeGlass.Radius.panel, style: .continuous))
        .overlay(alignment: .topLeading) {
            Label(L10n.string("subtitle.appearance.preview"), systemImage: "eye")
                .font(.caption.weight(.medium))
                .foregroundStyle(.white.opacity(0.72))
                .padding(14)
        }
        .overlay {
            RoundedRectangle(cornerRadius: GlazeGlass.Radius.panel, style: .continuous)
                .strokeBorder(.white.opacity(0.13), lineWidth: 1)
        }
    }

    @ViewBuilder
    private var subtitleSample: some View {
        let text = Text(L10n.string("subtitle.appearance.preview_text"))
            .font(.system(size: min(preferences.fontSize * 0.72, 30), weight: .semibold))
            .multilineTextAlignment(.center)
            .foregroundStyle(.white)

        if preferences.background == .plate {
            text
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(.black.opacity(preferences.backgroundOpacity))
                        }
                }
        } else {
            text
                .shadow(color: .black.opacity(0.95), radius: 1, y: 1)
                .shadow(color: .black.opacity(0.6), radius: 5)
        }
    }

    private var previewBottomOffset: CGFloat {
        let preset: CGFloat = preferences.position == .raised ? 42 : 0
        return preset + CGFloat(preferences.positionOffset * 0.35)
    }
}

private enum ConnectionTestState: Equatable {
    case idle
    case testing
    case success
    case failure(String)
}

private struct WebDAVConnectionRow: View {
    let connection: WebDAVConnection
    let testState: ConnectionTestState
    let onTest: () -> Void
    let onEdit: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "externaldrive.connected.to.line.below")
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(.tint)
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 3) {
                Text(connection.name).font(.headline)
                Text(connection.rootURL.absoluteString)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 16)
            connectionStatus

            Button(L10n.string("webdav.test"), action: onTest)
                .disabled(testState == .testing)

            Menu {
                Button(L10n.string("settings.edit"), action: onEdit)
                Divider()
                Button(L10n.string("webdav.remove"), role: .destructive, action: onRemove)
            } label: {
                Label(L10n.string("settings.more"), systemImage: "ellipsis.circle")
                    .labelStyle(.iconOnly)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }

    @ViewBuilder
    private var connectionStatus: some View {
        switch testState {
        case .idle:
            EmptyView()
        case .testing:
            ProgressView().controlSize(.small)
        case .success:
            Label(L10n.string("webdav.test.success"), systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        case .failure(let message):
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
                .help(message)
        }
    }
}

private struct WebDAVConnectionEditorView: View {
    @Environment(\.dismiss) private var dismiss

    private let connectionID: String
    private let storedPassword: String?
    private let onSave: (WebDAVConnection, String?) -> Void

    @State private var name: String
    @State private var address: String
    @State private var username: String
    @State private var password = ""
    @State private var testState: ConnectionTestState = .idle

    init(
        connection: WebDAVConnection? = nil,
        storedPassword: String? = nil,
        onSave: @escaping (WebDAVConnection, String?) -> Void
    ) {
        connectionID = connection?.id ?? UUID().uuidString
        self.storedPassword = storedPassword
        self.onSave = onSave
        _name = State(initialValue: connection?.name ?? "")
        _address = State(initialValue: connection?.rootURL.absoluteString ?? "")
        _username = State(initialValue: connection?.username ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(L10n.string("webdav.field.name"), text: $name)
                    TextField(L10n.string("webdav.field.url"), text: $address)
                    TextField(L10n.string("webdav.field.username"), text: $username)
                    SecureField(L10n.string("webdav.field.password"), text: $password)
                } header: {
                    Text(L10n.string("webdav.section.title"))
                } footer: {
                    Text(L10n.string("help.webdav.url"))
                }

                if resolvedURL?.scheme?.lowercased() == "http" {
                    Section {
                        Label(L10n.string("webdav.http_warning"), systemImage: "exclamationmark.shield")
                            .foregroundStyle(.yellow)
                    }
                }

                if case .failure(let message) = testState {
                    Section {
                        Label(message, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(L10n.string(name.isEmpty ? "webdav.add" : "webdav.edit"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.string("settings.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .automatic) {
                    Button {
                        test()
                    } label: {
                        if testState == .testing {
                            ProgressView().controlSize(.small)
                        } else {
                            Text(L10n.string("webdav.test"))
                        }
                    }
                    .disabled(resolvedURL == nil || testState == .testing)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.string("settings.save")) { save() }
                        .disabled(resolvedURL == nil)
                }
            }
        }
        .frame(width: 520, height: 430)
        .preferredColorScheme(.dark)
    }

    private var resolvedURL: URL? {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let withScheme = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let url = URL(string: withScheme),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host != nil else {
            return nil
        }
        return url
    }

    private var connection: WebDAVConnection? {
        guard let resolvedURL else { return nil }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return WebDAVConnection(
            id: connectionID,
            name: trimmedName.isEmpty ? (resolvedURL.host ?? resolvedURL.absoluteString) : trimmedName,
            rootURL: resolvedURL,
            username: username.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private func test() {
        guard let connection else { return }
        testState = .testing
        let candidatePassword = password.isEmpty ? storedPassword : password
        Task {
            do {
                _ = try await WebDAVClient().list(
                    connection.rootURL,
                    credentials: credentialPair(username: connection.username, password: candidatePassword)
                )
                testState = .success
            } catch {
                testState = .failure(webDAVMessage(for: error))
            }
        }
    }

    private func save() {
        guard let connection else { return }
        onSave(connection, password.isEmpty ? nil : password)
        dismiss()
    }
}

private func credentialPair(username: String, password: String?) -> (String, String)? {
    guard !username.isEmpty, let password else { return nil }
    return (username, password)
}

private func webDAVMessage(for error: Error) -> String {
    guard let webdav = error as? WebDAVError else {
        return L10n.string("webdav.error.network")
    }

    return switch webdav {
    case .unauthorized: L10n.string("webdav.error.unauthorized")
    case .notFound: L10n.string("webdav.error.not_found")
    case .notWebDAV: L10n.string("webdav.error.not_webdav")
    case .certificateMismatch: L10n.string("webdav.error.certificate")
    case .network: L10n.string("webdav.error.network")
    }
}
