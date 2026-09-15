import GlazeBooks
import GlazeCore
import SwiftUI
import UIKit

/// A webtoon: one continuous strip, scrolled rather than turned.
///
/// Most of what is read in Korea is drawn this way — a tall ribbon meant to run past
/// the eye without a break. Cutting it into screen-sized pages puts a fold through
/// the middle of panels the artist drew to be read continuously, which is why this is
/// a different view rather than a setting on the pager.
///
/// A collection view rather than a scroll view full of image views: a chapter can be
/// two hundred ribbons, and only the two on screen should be decoded.
struct IOSComicStrip: UIViewControllerRepresentable {
    let store: ComicPageStore
    /// Each page's pixel dimensions, index-aligned. Measured before this view is made,
    /// because a strip cannot place anything until it knows every page's height.
    let sizes: [CGSize?]
    @Binding var page: Int
    let onTap: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> ComicStripController {
        let controller = ComicStripController(
            store: store,
            sizes: sizes,
            onTap: onTap,
            onPageChanged: { context.coordinator.report($0) }
        )
        controller.startingPage = page
        return controller
    }

    func updateUIViewController(_ controller: ComicStripController, context: Context) {
        context.coordinator.parent = self
        // Only a jump from outside — the slider, or reopening the book. Following the
        // scroll back into the view it came from would fight the finger.
        guard page != context.coordinator.reported else { return }
        controller.show(page: page)
        context.coordinator.reported = page
    }

    @MainActor
    final class Coordinator {
        var parent: IOSComicStrip
        var reported: Int

        init(_ parent: IOSComicStrip) {
            self.parent = parent
            reported = parent.page
        }

        func report(_ page: Int) {
            guard page != reported else { return }
            reported = page
            parent.page = page
        }
    }
}

@MainActor
final class ComicStripController: UIViewController {
    /// Where to open. Read once, when the collection view first has a width to lay
    /// out against.
    var startingPage = 0

    private let store: ComicPageStore
    private let sizes: [CGSize?]
    private let onTap: () -> Void
    private let onPageChanged: (Int) -> Void

    private var collectionView: UICollectionView!
    private var hasRestored = false
    /// Kept across a rotation: the layout is rebuilt at the new width and the reader
    /// should still be on the page they were reading.
    private var pageBeforeResize: Int?

    /// Nothing measured, and nothing to measure from. A page-and-a-half tall is a
    /// reasonable guess for a strip and is only ever seen for a moment.
    private static let unknownAspect: CGFloat = 1.5

    init(
        store: ComicPageStore,
        sizes: [CGSize?],
        onTap: @escaping () -> Void,
        onPageChanged: @escaping (Int) -> Void
    ) {
        self.store = store
        self.sizes = sizes
        self.onTap = onTap
        self.onPageChanged = onPageChanged
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        // No gaps anywhere: the whole point is that the strip has no seams.
        layout.minimumLineSpacing = 0
        layout.minimumInteritemSpacing = 0
        layout.sectionInset = .zero

        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = .black
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.prefetchDataSource = self
        collectionView.contentInsetAdjustmentBehavior = .never
        collectionView.showsVerticalScrollIndicator = false
        collectionView.register(ComicStripCell.self, forCellWithReuseIdentifier: ComicStripCell.identifier)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(collectionView)

        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        collectionView.addGestureRecognizer(tap)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard collectionView.bounds.width > 0 else { return }

        if !hasRestored {
            hasRestored = true
            show(page: startingPage)
        } else if let page = pageBeforeResize {
            pageBeforeResize = nil
            show(page: page)
        }
    }

    override func viewWillTransition(
        to size: CGSize,
        with coordinator: any UIViewControllerTransitionCoordinator
    ) {
        pageBeforeResize = topmostVisiblePage()
        collectionView.collectionViewLayout.invalidateLayout()
        super.viewWillTransition(to: size, with: coordinator)
    }

    func show(page: Int) {
        let count = store.pageCount
        guard count > 0 else { return }
        let target = min(max(0, page), count - 1)
        collectionView.scrollToItem(at: IndexPath(item: target, section: 0), at: .top, animated: false)
    }

    @objc private func handleTap() { onTap() }

    /// Which page the reader is on: whichever one the top of the screen is inside.
    private func topmostVisiblePage() -> Int {
        let top = collectionView.contentOffset.y + 1
        let indexPaths = collectionView.indexPathsForVisibleItems.sorted()
        for indexPath in indexPaths {
            guard let attributes = collectionView.layoutAttributesForItem(at: indexPath) else { continue }
            if attributes.frame.maxY > top { return indexPath.item }
        }
        return indexPaths.first?.item ?? 0
    }

    private func height(forItemAt index: Int, width: CGFloat) -> CGFloat {
        guard index < sizes.count, let size = sizes[index], size.width > 0, size.height > 0 else {
            return width * Self.unknownAspect
        }
        return (width * size.height / size.width).rounded()
    }
}

extension ComicStripController: UICollectionViewDataSource {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        store.pageCount
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: ComicStripCell.identifier,
            for: indexPath
        ) as! ComicStripCell
        cell.load(page: indexPath.item, from: store)
        return cell
    }
}

extension ComicStripController: UICollectionViewDelegateFlowLayout {
    func collectionView(
        _ collectionView: UICollectionView,
        layout: UICollectionViewLayout,
        sizeForItemAt indexPath: IndexPath
    ) -> CGSize {
        let width = collectionView.bounds.width
        return CGSize(width: width, height: height(forItemAt: indexPath.item, width: width))
    }
}

extension ComicStripController: UICollectionViewDataSourcePrefetching {
    func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
        // Warming the store rather than the cell: a ribbon takes long enough to
        // inflate and decode that arriving at it cold shows a black gap.
        for indexPath in indexPaths {
            Task { _ = await store.image(at: indexPath.item) }
        }
    }
}

extension ComicStripController: UIScrollViewDelegate {
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard hasRestored else { return }
        onPageChanged(topmostVisiblePage())
    }
}

/// One ribbon.
@MainActor
final class ComicStripCell: UICollectionViewCell {
    static let identifier = "ComicStripCell"

    private let imageView = UIImageView()
    private var loading: Task<Void, Never>?

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = .black
        // The cell's height was computed from this image's own proportions, so
        // filling it exactly is right and nothing is cropped.
        imageView.contentMode = .scaleToFill
        imageView.clipsToBounds = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(imageView)

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override func prepareForReuse() {
        super.prepareForReuse()
        loading?.cancel()
        loading = nil
        imageView.image = nil
    }

    func load(page: Int, from store: ComicPageStore) {
        loading?.cancel()
        loading = Task { [weak self] in
            let image = await store.image(at: page)
            guard !Task.isCancelled else { return }
            self?.imageView.image = image
        }
    }
}
