import GlazeBooks
import GlazeCore
import PDFKit
import SwiftUI
import UIKit

/// A PDF book. PDFKit already knows how to page, zoom and lay out two pages at a
/// time, so this is a wrapper rather than a reader — the work is telling it which of
/// those the viewer asked for.
struct IOSPDFReader: UIViewRepresentable {
    let url: URL
    @Binding var page: Int
    let pageCount: (Int) -> Void
    let direction: ReadingDirection
    let doublePage: Bool
    let onTap: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.backgroundColor = .black
        view.autoScales = true
        view.document = PDFDocument(url: url)
        apply(to: view)

        if let document = view.document {
            let count = document.pageCount
            let report = pageCount
            // Reported on the next turn of the runloop: this runs while SwiftUI is
            // building the view, and writing state from inside that is what leaves
            // the spinner sitting on top of a book that has already opened.
            DispatchQueue.main.async { report(count) }
            if let target = document.page(at: min(page, count - 1)) {
                view.go(to: target)
            }
        }

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap))
        // PDFKit puts a double-tap zoom on its own view; a single tap has to wait for
        // that to fail or zooming also toggles the controls.
        tap.numberOfTapsRequired = 1
        view.addGestureRecognizer(tap)
        context.coordinator.observe(view)
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        context.coordinator.parent = self
        apply(to: view)

        guard let document = view.document else { return }
        let current = view.currentPage.map { document.index(for: $0) } ?? 0
        guard current != page, let target = document.page(at: min(max(0, page), document.pageCount - 1)) else { return }
        view.go(to: target)
    }

    private func apply(to view: PDFView) {
        guard direction != .vertical else {
            // The same choice the strip offers a comic: one continuous run, scrolled.
            // PDFKit does it natively, so this is a mode rather than another reader.
            view.usePageViewController(false)
            view.displayDirection = .vertical
            view.displayMode = .singlePageContinuous
            view.displaysRTL = false
            view.displaysAsBook = false
            return
        }

        view.usePageViewController(true)
        view.displayDirection = .horizontal
        view.displayMode = doublePage ? .twoUp : .singlePage
        view.displaysRTL = direction == .rightToLeft
        view.displaysAsBook = doublePage
    }

    @MainActor
    final class Coordinator: NSObject {
        var parent: IOSPDFReader
        private weak var view: PDFView?

        init(_ parent: IOSPDFReader) {
            self.parent = parent
        }

        func observe(_ view: PDFView) {
            self.view = view
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(pageChanged),
                name: .PDFViewPageChanged,
                object: view
            )
        }

        @objc func handleTap() { parent.onTap() }

        @objc func pageChanged() {
            guard let view, let document = view.document, let current = view.currentPage else { return }
            parent.page = document.index(for: current)
        }
    }
}
