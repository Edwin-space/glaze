import GlazeBooks
import GlazeCore
import SwiftUI

/// Reading one book, full screen.
///
/// The two kinds of book are read by two very different engines — PDFKit for a
/// document, a page controller over a zip for a comic — but they are one screen to
/// the viewer, so the chrome, the resume point and the reading direction live here
/// rather than being built twice.
/// What comes back while a book is being opened.
private enum OpenEvent: Sendable {
    case progress(Int, Int)
    case opened((any ComicPages)?)
}

struct IOSBookReaderView: View {
    let book: BookItem

    @Environment(\.dismiss) private var dismiss
    @Environment(IOSUserPreferences.self) private var preferences

    @State private var page = 0
    @State private var pageCount = 0
    @State private var source: (any ComicPages)?
    @State private var unpacking: (done: Int, total: Int)?
    @State private var comic: ComicPageStore?
    /// Each page's pixel dimensions. Only needed for the strip, which cannot place
    /// anything until it knows every page's height, so only measured for it.
    @State private var sizes: [CGSize?] = []
    @State private var measured = 0
    @State private var isMeasuring = false
    @State private var epub: IOSOpenedEPUB?
    @State private var chapterOffset: Double = 0
    @State private var isOpening = true
    @State private var failed = false
    @State private var showsChrome = true
    @State private var direction: ReadingDirection = .leftToRight

    @Environment(ReadingProgressStore.self) private var positions
    private let options = ReadingOptionsStore()

    var body: some View {
        GeometryReader { geometry in
            let isWide = geometry.size.width > geometry.size.height
            let doublePage = preferences.doublePageSpreads && isWide && direction.supportsSpreads
            let insets = (
                top: geometry.safeAreaInsets.top + 52,
                bottom: geometry.safeAreaInsets.bottom + 168
            )

            ZStack {
                Color.black.ignoresSafeArea()
                content(doublePage: doublePage, insets: insets)
                if showsChrome { chrome }
            }
        }
        .statusBarHidden(!showsChrome)
        .persistentSystemOverlays(showsChrome ? .automatic : .hidden)
        .preferredColorScheme(.dark)
        .task { await open() }
        .onChange(of: direction) { _, newValue in
            Task { await prepare(for: newValue) }
        }
        .onChange(of: page) { _, newValue in
            if book.kind == .ebook {
                chapterOffset = options.scrollOffset(for: book.id, chapter: newValue)
            }
            remember()
        }
        .onDisappear { remember() }
    }

    // MARK: - The book

    @ViewBuilder
    private func content(doublePage: Bool, insets: (top: CGFloat, bottom: CGFloat)) -> some View {
        if failed {
            unreadable
        } else if let comic, direction == .vertical {
            IOSComicStrip(
                store: comic,
                sizes: sizes,
                page: $page,
                onTap: toggleChrome
            )
            .ignoresSafeArea()
        } else if let comic {
            IOSComicPager(
                store: comic,
                spreads: ComicSpreads(pageCount: pageCount, isDouble: doublePage),
                direction: direction,
                page: $page,
                onTap: toggleChrome
            )
            .ignoresSafeArea()
        } else if let epub {
            IOSEPUBReader(
                root: epub.root,
                spine: epub.spine,
                chapter: $page,
                theme: preferences.readingTheme,
                fontScale: preferences.readingFontScale,
                startOffset: chapterOffset,
                contentInsets: insets,
                onScroll: { offset in
                    options.setScrollOffset(offset, for: book.id, chapter: page)
                },
                onTap: toggleChrome
            )
            .ignoresSafeArea()
        } else if book.kind == .document {
            IOSPDFReader(
                url: book.url,
                page: $page,
                pageCount: { count in
                    pageCount = count
                    isOpening = false
                },
                direction: direction,
                doublePage: doublePage,
                onTap: toggleChrome
            )
            .ignoresSafeArea()
        }

        if let unpacking {
            unpackingNote(unpacking)
        } else if isMeasuring {
            measuring
        } else if isOpening, !failed {
            ProgressView()
                .controlSize(.large)
                .tint(IOSTheme.amber)
        }
    }

    /// Switching a long volume to the strip has to read every page's header first.
    /// Saying so, with a count, is better than a spinner that looks like a hang.
    private var measuring: some View {
        VStack(spacing: IOSTheme.Spacing.small) {
            ProgressView()
                .controlSize(.large)
                .tint(IOSTheme.amber)
            Text(
                pageCount > 0
                    ? String(format: L10n.string("book.reader.measuring_format"), measured, pageCount)
                    : L10n.string("book.reader.measuring")
            )
            .font(.caption.monospacedDigit())
            .foregroundStyle(IOSTheme.dim)
        }
        .padding(IOSTheme.Spacing.large)
        .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: IOSTheme.Radius.panel))
    }

    /// 7-Zip packs everything into one stream, so there is no reading a page without
    /// unpacking what came before it. Once is enough — after this the pages sit on
    /// disk — but the first time is a wait, and silence would read as a hang.
    private func unpackingNote(_ progress: (done: Int, total: Int)) -> some View {
        VStack(spacing: IOSTheme.Spacing.small) {
            ProgressView()
                .controlSize(.large)
                .tint(IOSTheme.amber)
            Text(
                progress.total > 0
                    ? String(format: L10n.string("book.reader.unpacking_format"), progress.done, progress.total)
                    : L10n.string("book.reader.unpacking")
            )
            .font(.caption.monospacedDigit())
            .foregroundStyle(IOSTheme.dim)
        }
        .padding(IOSTheme.Spacing.large)
        .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: IOSTheme.Radius.panel))
    }

    private var unreadable: some View {
        VStack(spacing: IOSTheme.Spacing.medium) {
            Image(systemName: "book.closed")
                .font(.largeTitle)
                .foregroundStyle(IOSTheme.dim)
            Text(L10n.string("book.reader.failed"))
                .font(.callout)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            Text(book.fileName)
                .font(.caption)
                .foregroundStyle(IOSTheme.dim)
            Button(L10n.string("common.close")) { dismiss() }
                .buttonStyle(.borderedProminent)
                .tint(IOSTheme.amber)
        }
        .padding(IOSTheme.Spacing.large)
    }

    // MARK: - Chrome

    private var chrome: some View {
        VStack(spacing: 0) {
            topBar
            Spacer()
            if pageCount > 1 { bottomBar }
        }
        .transition(.opacity)
    }

    private var topBar: some View {
        HStack(spacing: IOSTheme.Spacing.medium) {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
            }
            .touchTarget()
            .accessibilityLabel(L10n.string("common.close"))

            Text(book.displayTitle)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
                .frame(maxWidth: .infinity)

            restartButton
        }
        .foregroundStyle(.white)
        .padding(.horizontal, IOSTheme.Spacing.medium)
        .padding(.vertical, IOSTheme.Spacing.small)
        .background(Color.black)
    }

    private var restartButton: some View {
        Button { page = 0 } label: {
            Image(systemName: "arrow.counterclockwise")
        }
        .touchTarget()
        .accessibilityLabel(L10n.string("book.reader.restart"))
    }

    /// The reading mode sits in the bar rather than behind a menu or a sheet.
    ///
    /// Both of those were tried and neither survived: presenting anything from here
    /// takes this view out of the hierarchy and puts it back, which resets its state
    /// and takes the presentation down with it. A control that is simply on screen
    /// has nothing to be dismissed. It is also the better place for it — the mode is
    /// a thing you change once, while looking at the page it applies to.
    private var directionPicker: some View {
        Picker(L10n.string("book.reader.direction"), selection: directionBinding) {
            ForEach(ReadingDirection.allCases, id: \.self) { option in
                Text(option.shortName).tag(option)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    /// Reflowable text has no reading direction to pick — it has paper and type size.
    private var themePicker: some View {
        @Bindable var preferences = preferences
        return Picker(L10n.string("book.reader.theme"), selection: $preferences.readingTheme) {
            ForEach(ReadingTheme.allCases, id: \.self) { option in
                Text(option.localizedName).tag(option)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    private var fontSizeButtons: some View {
        HStack(spacing: IOSTheme.Spacing.large) {
            Button { changeFontScale(by: -ReadingFontScale.step) } label: {
                Image(systemName: "textformat.size.smaller")
            }
            .touchTarget()
            .disabled(preferences.readingFontScale <= ReadingFontScale.minimum)
            .accessibilityLabel(L10n.string("book.reader.text_smaller"))

            Text(String(format: "%.0f%%", preferences.readingFontScale * 100))
                .font(.caption.monospacedDigit())
                .foregroundStyle(IOSTheme.dim)
                .frame(minWidth: 52)

            Button { changeFontScale(by: ReadingFontScale.step) } label: {
                Image(systemName: "textformat.size.larger")
            }
            .touchTarget()
            .disabled(preferences.readingFontScale >= ReadingFontScale.maximum)
            .accessibilityLabel(L10n.string("book.reader.text_larger"))
        }
        .foregroundStyle(.white)
    }

    private func changeFontScale(by amount: Double) {
        preferences.readingFontScale = ReadingFontScale.clamp(preferences.readingFontScale + amount)
    }

    private var bottomBar: some View {
        VStack(spacing: IOSTheme.Spacing.tight) {
            if book.kind == .ebook {
                themePicker
                fontSizeButtons
            } else {
                directionPicker
            }

            Text(
                String(
                    format: L10n.string(
                        book.kind == .ebook ? "book.reader.chapter_format" : "book.reader.page_format"
                    ),
                    page + 1,
                    pageCount
                )
            )
                .font(.caption.monospacedDigit())
                .foregroundStyle(IOSTheme.dim)

            Slider(
                value: Binding(
                    get: { Double(page) },
                    set: { page = Int($0.rounded()) }
                ),
                in: 0...Double(max(1, pageCount - 1)),
                step: 1
            )
            .tint(IOSTheme.amber)
            .accessibilityLabel(L10n.string("book.reader.page"))
        }
        .padding(.horizontal, IOSTheme.Spacing.large)
        .padding(.vertical, IOSTheme.Spacing.small)
        .background(Color.black)
    }

    // MARK: - Settings that stick

    /// Saved against this book, not against the app: a manga scan and the PDF manual
    /// beside it want opposite answers.
    private var directionBinding: Binding<ReadingDirection> {
        Binding(
            get: { direction },
            set: { newValue in
                direction = newValue
                options.setDirection(newValue, for: book.id)
            }
        )
    }

    private var doublePageBinding: Binding<Bool> {
        @Bindable var preferences = preferences
        return $preferences.doublePageSpreads
    }

    // MARK: - Opening and remembering

    private func open() async {
        direction = options.direction(
            for: book.id,
            // A comic is the thing people read right to left; a PDF almost never is.
            fallback: book.kind == .comic ? preferences.readingDirection : .leftToRight
        )
        let resume = positions.page(for: book.id) ?? 0

        let url = book.url

        // A PDF is opened by the reader view itself, which reports its own page count
        // back; there is nothing to prepare here.
        guard book.kind != .document else {
            page = resume
            return
        }

        if book.kind == .ebook {
            let identifier = book.id
            let unpacked = await Task.detached(priority: .userInitiated) { () -> IOSOpenedEPUB? in
                IOSEPUBUnpacker.open(url, identifier: identifier)
            }.value

            guard let unpacked else {
                failed = true
                isOpening = false
                return
            }
            epub = unpacked
            pageCount = unpacked.spine.count
            page = min(resume, max(0, unpacked.spine.count - 1))
            chapterOffset = options.scrollOffset(for: book.id, chapter: page)
            isOpening = false
            return
        }

        let item = book
        // A `.7z` has to be unpacked before a single page can be drawn, and that is a
        // wait worth explaining rather than a spinner that looks like a hang.
        if IOSComicSource.needsUnpacking(item) { unpacking = (0, 0) }

        var opened: (any ComicPages)?
        let stream = AsyncStream<OpenEvent> { continuation in
            Task.detached(priority: .userInitiated) {
                let source = IOSComicSource.open(item) { done, total in
                    // Every tenth page: a thousand-page archive reporting each one
                    // spends more time on the message than on the work.
                    if done % 10 == 0 || done == total { continuation.yield(.progress(done, total)) }
                }
                continuation.yield(.opened(source))
                continuation.finish()
            }
        }
        for await event in stream {
            switch event {
            case .progress(let done, let total): unpacking = (done, total)
            case .opened(let source): opened = source
            }
        }
        unpacking = nil

        guard let opened else {
            failed = true
            isOpening = false
            return
        }

        source = opened
        pageCount = opened.pageCount
        page = min(resume, max(0, opened.pageCount - 1))
        await prepare(for: direction)
        isOpening = false
    }

    /// Builds the page store the current mode needs. The strip decodes pages
    /// differently — capped by width rather than by their longest side — so switching
    /// mode is not something the existing store can be asked to do.
    private func prepare(for direction: ReadingDirection) async {
        guard let source else { return }

        guard direction == .vertical else {
            comic = ComicPageStore(source: source)
            return
        }

        if sizes.count != source.pageCount {
            await measureSizes(of: source)
        }
        comic = ComicPageStore(source: source, layout: .strip, sizes: sizes)
    }

    private func measureSizes(of source: any ComicPages) async {
        isMeasuring = true
        measured = 0
        defer { isMeasuring = false }

        let count = source.pageCount
        let stream = AsyncStream<(Int, [CGSize?])> { continuation in
            Task.detached(priority: .userInitiated) {
                var found: [CGSize?] = []
                found.reserveCapacity(count)
                for index in 0..<count {
                    found.append(source.pageSize(at: index))
                    // Reported in batches: a per-page hop to the main actor for a
                    // four-hundred-page volume costs more than the measuring does.
                    if found.count % 20 == 0 { continuation.yield((found.count, [])) }
                }
                continuation.yield((count, found))
                continuation.finish()
            }
        }

        for await (progress, found) in stream {
            measured = progress
            if !found.isEmpty { sizes = found }
        }
    }

    private func remember() {
        guard pageCount > 0 else { return }
        positions.record(page: page, of: pageCount, for: book.id)
    }

    private func toggleChrome() {
        withAnimation(.easeInOut(duration: 0.2)) { showsChrome.toggle() }
    }
}
