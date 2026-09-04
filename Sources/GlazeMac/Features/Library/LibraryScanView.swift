import GlazeCore
import SwiftUI

/// Fills in what a library is, and asks about the films it cannot settle on its own.
struct LibraryScanView: View {
    let connection: WebDAVConnection
    /// The folder being described — the share root, or whatever the viewer had open.
    let root: URL
    let password: String?
    @Bindable var preferences: GlazePreferences

    private var controller: LibraryScanController { .shared }
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 760, height: 560)
        // Closing the window does not stop the work; reopening shows where it got to.
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.string("library.scan.title"))
                .font(.title2.weight(.semibold))
            Text(String(format: L10n.string("library.scan.subtitle_format"), scopeName))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
    }

    private var scopeName: String {
        guard root != connection.rootURL else { return connection.name }
        let folder = root.lastPathComponent
        return folder.isEmpty ? connection.name : "\(connection.name) › \(folder)"
    }

    @ViewBuilder
    private var content: some View {
        switch controller.phase {
        case .idle:
            intro
        case .scanning(let foldersRead):
            working(
                title: L10n.string("library.scan.reading"),
                detail: foldersRead == 0
                    ? L10n.string("library.scan.reading.detail")
                    : String(format: L10n.string("library.scan.folders_format"), foldersRead),
                fraction: nil
            )
        case .describing(let completed, let total, let title):
            working(
                title: L10n.string("library.scan.describing"),
                detail: title.isEmpty ? String(format: "%d / %d", completed, total) : title,
                fraction: total > 0 ? Double(completed) / Double(total) : nil
            )
        case .reviewing:
            if let question = controller.currentQuestion {
                review(question)
            } else {
                summaryView
            }
        case .finished:
            summaryView
        case .failed(let text):
            failure(text)
        }
    }

    private var intro: some View {
        VStack(spacing: 14) {
            Image(systemName: "film.stack")
                .font(.system(size: 42))
                .foregroundStyle(.secondary)
            Text(L10n.string("library.scan.intro"))
                .font(.headline)
            Text(L10n.string("library.scan.intro.detail"))
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func working(title: String, detail: String, fraction: Double?) -> some View {
        VStack(spacing: 14) {
            if let fraction {
                ProgressView(value: fraction).frame(width: 320)
            } else {
                ProgressView().controlSize(.large)
            }
            Text(title).font(.headline)
            Text(detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 520)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The question. The filename is shown in full because it is the evidence the
    /// viewer is judging the candidates against.
    private func review(_ question: LibraryScanController.Question) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.string(question.isSeries ? "library.scan.which_series" : "library.scan.which_film"))
                    .font(.headline)
                if question.isSeries {
                    Text(String(
                        format: L10n.string("library.scan.series_scope_format"),
                        question.subject,
                        question.episodeCount
                    ))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }
                Text(question.item.sourceName)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(2)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            ScrollView {
                VStack(spacing: 10) {
                    ForEach(question.candidates) { candidate in
                        Button { controller.choose(candidate) } label: {
                            CandidateRow(candidate: candidate)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }
        }
    }

    private var summaryView: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 42))
                .foregroundStyle(.green)
            Text(L10n.string("library.scan.done")).font(.headline)

            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 6) {
                summaryRow("library.scan.summary.described", controller.summary.described)
                summaryRow("library.scan.summary.already", controller.summary.alreadyDescribed)
                summaryRow("library.scan.summary.poster_added", controller.summary.postersAdded)
                summaryRow("library.scan.summary.answered", controller.summary.answered)
                summaryRow("library.scan.summary.skipped", controller.summary.skipped)
                summaryRow("library.scan.summary.not_found", controller.summary.notFound)
                summaryRow("library.scan.summary.failed", controller.summary.failed)
            }
            .font(.callout)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func summaryRow(_ key: String, _ count: Int) -> some View {
        if count > 0 {
            GridRow {
                Text(L10n.string(key)).foregroundStyle(.secondary)
                Text("\(count)").monospacedDigit()
            }
        }
    }

    private func failure(_ text: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 38))
                .foregroundStyle(.orange)
            Text(text)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        HStack {
            if case .reviewing = controller.phase, controller.currentQuestion != nil {
                Button(L10n.string("library.scan.skip")) { controller.skipCurrentQuestion() }
                Text(String(format: L10n.string("library.scan.remaining_format"), controller.questions.count))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if controller.isRunning {
                Button(L10n.string("common.cancel")) { controller.cancel() }
            } else {
                Button(L10n.string("common.close")) { dismiss() }
                Button(startTitle) {
                    controller.start(connection, root: root, password: password, apiKey: preferences.tmdbAPIKey)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
    }

    private var startTitle: String {
        switch controller.phase {
        case .idle: L10n.string("library.scan.start")
        default: L10n.string("library.scan.again")
        }
    }
}

/// One candidate, with the reasons it is where it is.
private struct CandidateRow: View {
    let candidate: RankedMetadataMatch

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            poster

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(candidate.match.title)
                        .font(.headline)
                    if let year = candidate.match.year {
                        Text(String(year))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                if let original = candidate.match.originalTitle, original != candidate.match.title {
                    Text(original)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if let overview = candidate.match.overview, !overview.isEmpty {
                    Text(overview)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                HStack(spacing: 6) {
                    ForEach(candidate.reasons, id: \.self) { reason in
                        Text(L10n.string("library.scan.reason.\(reason.rawValue)"))
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(reasonTint(reason), in: Capsule())
                    }
                }
                .padding(.top, 2)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
        .contentShape(RoundedRectangle(cornerRadius: 10))
    }

    private var poster: some View {
        AsyncImage(url: candidate.match.posterURL) { image in
            image.resizable().aspectRatio(contentMode: .fill)
        } placeholder: {
            RoundedRectangle(cornerRadius: 6).fill(.quaternary)
        }
        .frame(width: 60, height: 90)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func reasonTint(_ reason: MetadataMatchReason) -> Color {
        switch reason {
        case .titleExact, .yearExact: .green.opacity(0.22)
        case .yearMismatch: .red.opacity(0.18)
        case .yearUnknown: .orange.opacity(0.18)
        default: .secondary.opacity(0.18)
        }
    }
}
