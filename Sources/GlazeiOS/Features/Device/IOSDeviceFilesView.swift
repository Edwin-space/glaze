import GlazeCore
import SwiftUI
import UniformTypeIdentifiers

/// The films kept on the phone itself, and how they got there.
///
/// A server is not always reachable — a train, a plane, someone else's wifi. Films
/// copied into the app play with nothing else involved, and the subtitle the Mac
/// wrote comes along if it was copied beside them.
struct IOSDeviceFilesView: View {
    let library: IOSLibraryModel
    let onOpenLibrary: () -> Void

    @State private var model = IOSDeviceFilesModel()
    @State private var isImporting = false

    var body: some View {
        List {
            if model.isEmpty {
                howToGetFilmsOn
            } else {
                summary
                files
            }
            importSection
        }
        .glazeListBackground()
        .navigationTitle(L10n.string("ios.device.title"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { model.reload() }
        .refreshable { model.reload() }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.movie, .video, .mpeg4Movie, .quickTimeMovie, .data],
            allowsMultipleSelection: true
        ) { result in
            guard case .success(let urls) = result else { return }
            for url in urls { model.importFile(from: url) }
        }
        .alert(
            L10n.string("ios.device.import_failed"),
            isPresented: Binding(get: { model.failure != nil }, set: { if !$0 { model.clearFailure() } })
        ) {
            Button(L10n.string("common.close"), role: .cancel) { model.clearFailure() }
        } message: {
            Text(model.failure ?? "")
        }
    }

    /// The empty state has a job: nobody guesses the USB route on their own.
    private var howToGetFilmsOn: some View {
        Section {
            VStack(alignment: .leading, spacing: IOSTheme.Spacing.medium) {
                Image(systemName: "iphone.and.arrow.forward")
                    .font(.largeTitle)
                    .foregroundStyle(IOSTheme.amber)
                Text(L10n.string("ios.device.empty.title")).font(.headline)
                Text(L10n.string("ios.device.empty.usb"))
                    .font(.footnote)
                    .foregroundStyle(IOSTheme.dim)
                Text(L10n.string("ios.device.empty.files"))
                    .font(.footnote)
                    .foregroundStyle(IOSTheme.dim)
                Text(L10n.string("ios.device.empty.subtitles"))
                    .font(.footnote)
                    .foregroundStyle(IOSTheme.dim)
            }
            .padding(.vertical, IOSTheme.Spacing.tight)
        }
    }

    private var summary: some View {
        Section {
            Button(action: onOpenLibrary) {
                Label(L10n.string("ios.device.open_library"), systemImage: "rectangle.stack")
            }
        } footer: {
            Text(
                String(
                    format: L10n.string("ios.device.summary_format"),
                    model.files.count,
                    ByteCountFormatter.string(fromByteCount: model.totalByteCount, countStyle: .file)
                )
            )
        }
    }

    private var files: some View {
        Section(L10n.string("ios.device.files")) {
            ForEach(model.files) { file in
                VStack(alignment: .leading, spacing: IOSTheme.Spacing.hair) {
                    Text(file.name).font(.callout).lineLimit(2)
                    HStack(spacing: IOSTheme.Spacing.tight) {
                        Text(ByteCountFormatter.string(fromByteCount: file.byteCount, countStyle: .file))
                        if file.subtitleCount > 0 {
                            Label(
                                String(format: L10n.string("ios.device.subtitle_count_format"), file.subtitleCount),
                                systemImage: "captions.bubble"
                            )
                            .foregroundStyle(IOSTheme.amber)
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(IOSTheme.dim)
                }
                .accessibilityElement(children: .combine)
                .swipeActions {
                    Button(L10n.string("common.delete"), role: .destructive) {
                        model.delete(file)
                    }
                }
            }
        }
    }

    private var importSection: some View {
        Section {
            Button { isImporting = true } label: {
                Label(L10n.string("ios.device.import"), systemImage: "square.and.arrow.down")
            }
        } footer: {
            Text(L10n.string("ios.device.import.hint"))
        }
    }
}
