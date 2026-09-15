import GlazeBooks
import GlazeCore
import SwiftUI
import UIKit

/// Decodes comic pages away from the main thread and keeps a handful in memory.
///
/// A scanned page is often three thousand pixels tall, which is twenty-odd megabytes
/// once decoded. Holding the whole volume is how a reader gets killed for memory
/// halfway through; holding the few pages around where the viewer is, is enough.
actor ComicPageStore {
    /// How the pages are being shown, because it changes what "too big" means.
    enum Layout: Sendable {
        /// One page filling the screen.
        case page
        /// A continuous strip. A webtoon page is a narrow ribbon thousands of pixels
        /// tall; shrinking it by its longest side — which is what a page-shaped cap
        /// does — would reduce it to an unreadable sliver.
        case strip
    }

    /// Beyond this a page is bigger than any screen it will be drawn on, and the
    /// extra detail costs only memory.
    private static let maximumPixels = 2_600
    /// A strip page is capped by width instead, with a ceiling on total pixels so a
    /// ten-thousand-pixel ribbon cannot take the app down on its own.
    private static let maximumStripWidth: CGFloat = 1_400
    private static let maximumStripPixels: CGFloat = 6_000_000

    private let source: any ComicPages
    private let sizes: [CGSize?]
    private let layout: Layout
    private var cache: [Int: UIImage] = [:]
    private var order: [Int] = []

    /// - Parameter sizes: each page's pixel dimensions, index-aligned, when known.
    ///   The strip needs them to lay out and reuses them to decide how far to shrink.
    init(source: any ComicPages, layout: Layout = .page, sizes: [CGSize?] = []) {
        self.source = source
        self.layout = layout
        self.sizes = sizes
    }

    nonisolated var pageCount: Int { source.pageCount }

    private var cacheLimit: Int { layout == .strip ? 3 : 5 }

    func image(at index: Int) -> UIImage? {
        if let cached = cache[index] { return cached }
        guard let data = try? source.imageData(at: index),
              let image = Self.decode(data, maximumPixels: maximumPixels(for: index)) else { return nil }

        cache[index] = image
        order.append(index)
        while order.count > cacheLimit, let oldest = order.first {
            order.removeFirst()
            cache[oldest] = nil
        }
        return image
    }

    private func maximumPixels(for index: Int) -> Int {
        guard layout == .strip,
              index < sizes.count, let size = sizes[index],
              size.width > 0, size.height > 0
        else { return Self.maximumPixels }

        let byWidth = Self.maximumStripWidth / size.width
        let byArea = (Self.maximumStripPixels / (size.width * size.height)).squareRoot()
        // Never enlarge: a small page drawn bigger is only blur.
        let scale = min(1, byWidth, byArea)
        return Int((max(size.width, size.height) * scale).rounded())
    }

    /// Decoded to a bounded size up front rather than lazily at draw time, so the
    /// cost lands here and not as a stutter on the page turn.
    private static func decode(_ data: Data, maximumPixels: Int) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixels
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: image)
    }
}

/// One screenful of comic — a page, or two side by side.
@MainActor
final class ComicSpreadController: UIViewController, UIScrollViewDelegate {
    let spreadIndex: Int
    private let pages: [Int]
    private let store: ComicPageStore
    private let onTap: () -> Void

    private let scrollView = UIScrollView()
    private let content = UIStackView()
    private var imageViews: [UIImageView] = []

    init(spreadIndex: Int, pages: [Int], store: ComicPageStore, onTap: @escaping () -> Void) {
        self.spreadIndex = spreadIndex
        self.pages = pages
        self.store = store
        self.onTap = onTap
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        scrollView.delegate = self
        scrollView.maximumZoomScale = 4
        scrollView.minimumZoomScale = 1
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        content.axis = .horizontal
        content.distribution = .fillEqually
        content.spacing = 0
        content.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(content)

        for _ in pages {
            let imageView = UIImageView()
            imageView.contentMode = .scaleAspectFit
            imageView.backgroundColor = .black
            imageViews.append(imageView)
            content.addArrangedSubview(imageView)
        }

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            content.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            content.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            content.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            content.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            content.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor)
        ])

        addGestures()
        loadPages()
    }

    private func addGestures() {
        let double = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap))
        double.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(double)

        let single = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap))
        // Without this a single tap fires before the second tap of a zoom arrives,
        // so zooming in also flashes the controls up.
        single.require(toFail: double)
        scrollView.addGestureRecognizer(single)
    }

    private func loadPages() {
        for (slot, page) in pages.enumerated() {
            Task { [weak self] in
                guard let self else { return }
                let image = await store.image(at: page)
                guard imageViews.indices.contains(slot) else { return }
                imageViews[slot].image = image
            }
        }
    }

    @objc private func handleSingleTap() { onTap() }

    @objc private func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
        guard scrollView.zoomScale <= scrollView.minimumZoomScale else {
            scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
            return
        }
        let point = recognizer.location(in: content)
        let scale: CGFloat = 2.5
        let size = CGSize(width: scrollView.bounds.width / scale, height: scrollView.bounds.height / scale)
        scrollView.zoom(
            to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height),
            animated: true
        )
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { content }
}

/// The comic itself: pages that turn with a swipe, in whichever direction the book
/// is meant to be read.
struct IOSComicPager: UIViewControllerRepresentable {
    let store: ComicPageStore
    let spreads: ComicSpreads
    let direction: ReadingDirection
    @Binding var page: Int
    let onTap: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIPageViewController {
        let controller = UIPageViewController(
            transitionStyle: .scroll,
            navigationOrientation: .horizontal
        )
        controller.dataSource = context.coordinator
        controller.delegate = context.coordinator
        controller.view.backgroundColor = .black

        let index = spreads.index(containing: page)
        controller.setViewControllers([context.coordinator.spread(at: index)], direction: .forward, animated: false)
        context.coordinator.currentIndex = index
        return controller
    }

    func updateUIViewController(_ controller: UIPageViewController, context: Context) {
        context.coordinator.parent = self

        // Only act on a jump that came from outside — the slider, or reopening the
        // book. A swipe has already moved the view, and re-setting it here would
        // fight the animation that is still running.
        let target = spreads.index(containing: page)
        guard target != context.coordinator.currentIndex else { return }
        let forward = target > context.coordinator.currentIndex
        let animatedDirection: UIPageViewController.NavigationDirection =
            (forward == (direction == .leftToRight)) ? .forward : .reverse
        controller.setViewControllers(
            [context.coordinator.spread(at: target)],
            direction: animatedDirection,
            animated: false
        )
        context.coordinator.currentIndex = target
    }

    @MainActor
    final class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
        var parent: IOSComicPager
        var currentIndex = 0

        init(_ parent: IOSComicPager) {
            self.parent = parent
        }

        func spread(at index: Int) -> ComicSpreadController {
            var pages = parent.spreads.pages(at: index)
            // A right-to-left book puts the lower page number on the right, which is
            // the whole difference between reading manga and reading it backwards.
            if parent.direction == .rightToLeft { pages.reverse() }
            return ComicSpreadController(
                spreadIndex: index,
                pages: pages,
                store: parent.store,
                onTap: parent.onTap
            )
        }

        /// In a right-to-left book the gestures swap: turning the page forward is a
        /// swipe the other way, so "after" is the lower index.
        private func step(from index: Int, forward: Bool) -> ComicSpreadController? {
            let delta = (parent.direction == .leftToRight) == forward ? 1 : -1
            let next = index + delta
            guard next >= 0, next < parent.spreads.count else { return nil }
            return spread(at: next)
        }

        func pageViewController(
            _ controller: UIPageViewController,
            viewControllerBefore viewController: UIViewController
        ) -> UIViewController? {
            guard let current = viewController as? ComicSpreadController else { return nil }
            return step(from: current.spreadIndex, forward: false)
        }

        func pageViewController(
            _ controller: UIPageViewController,
            viewControllerAfter viewController: UIViewController
        ) -> UIViewController? {
            guard let current = viewController as? ComicSpreadController else { return nil }
            return step(from: current.spreadIndex, forward: true)
        }

        func pageViewController(
            _ controller: UIPageViewController,
            didFinishAnimating finished: Bool,
            previousViewControllers: [UIViewController],
            transitionCompleted completed: Bool
        ) {
            guard completed, let current = controller.viewControllers?.first as? ComicSpreadController else { return }
            currentIndex = current.spreadIndex
            parent.page = parent.spreads.pages(at: current.spreadIndex).min() ?? 0
        }
    }
}
