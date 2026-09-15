import GlazeBooks
import GlazeCore
import SwiftUI
import WebKit

/// A reflowable book, one chapter at a time.
///
/// Unlike a comic or a PDF, an EPUB has no pages of its own — it is text that lays
/// itself out at whatever size the reader asks for. So the unit here is the chapter,
/// and the web view scrolls within it.
struct IOSEPUBReader: UIViewRepresentable {
    /// The unpacked book on disk. The web view needs read access to the whole folder
    /// so a chapter can reach its own stylesheets and images.
    let root: URL
    /// Chapter paths, relative to `root`, in reading order.
    let spine: [String]
    @Binding var chapter: Int
    let theme: ReadingTheme
    let fontScale: Double
    /// Where in the chapter to resume, as a fraction of its height.
    let startOffset: Double
    /// Room for the bars. The web view fills the screen so text can scroll under
    /// them, but a chapter's first line has to start below the title, not behind it.
    let contentInsets: (top: CGFloat, bottom: CGFloat)
    let onScroll: (Double) -> Void
    let onTap: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let view = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        context.coordinator.installStyle(in: view)
        view.navigationDelegate = context.coordinator
        view.scrollView.delegate = context.coordinator
        view.scrollView.showsVerticalScrollIndicator = false
        paint(view)

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap))
        // Set loosely so links and text selection still work; this only listens.
        tap.cancelsTouchesInView = false
        tap.delegate = context.coordinator
        view.scrollView.addGestureRecognizer(tap)

        apply(insets: view)
        context.coordinator.load(chapter: chapter, into: view, restoring: startOffset)
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {
        context.coordinator.parent = self
        apply(insets: view)

        if context.coordinator.appearance != appearanceKey {
            context.coordinator.appearance = appearanceKey
            paint(view)
            // Both halves matter: the script styles the *next* document the web view
            // loads, and the evaluation styles the one already on screen. Updating
            // only the second meant changing to sepia and then turning a page put the
            // old colours straight back.
            context.coordinator.installStyle(in: view)
            context.coordinator.applyAppearance(to: view)
        }
        guard context.coordinator.loadedChapter != chapter else { return }
        context.coordinator.load(chapter: chapter, into: view, restoring: 0)
    }

    /// The paper colour goes on the web view too, not only in the document's CSS.
    /// The strip a content inset leaves above the first line is the web view's own
    /// background, and left clear it showed the black behind — a cream page with a
    /// black band across the top of every chapter.
    private func paint(_ view: WKWebView) {
        let components = theme.backgroundComponents
        let color = UIColor(
            red: components.red,
            green: components.green,
            blue: components.blue,
            alpha: 1
        )
        view.isOpaque = true
        view.backgroundColor = color
        view.scrollView.backgroundColor = color
    }

    private func apply(insets view: WKWebView) {
        let insets = UIEdgeInsets(top: contentInsets.top, left: 0, bottom: contentInsets.bottom, right: 0)
        guard view.scrollView.contentInset != insets else { return }
        view.scrollView.contentInset = insets
        view.scrollView.verticalScrollIndicatorInsets = insets
    }

    private var appearanceKey: String { "\(theme.rawValue)|\(fontScale)" }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, UIScrollViewDelegate, UIGestureRecognizerDelegate {
        var parent: IOSEPUBReader
        var loadedChapter = -1
        var appearance = ""
        private var pendingOffset: Double = 0
        private var isRestoring = false

        init(_ parent: IOSEPUBReader) {
            self.parent = parent
            appearance = "\(parent.theme.rawValue)|\(parent.fontScale)"
        }

        /// Injected before the document draws, so the page never flashes white first.
        func installStyle(in view: WKWebView) {
            let controller = view.configuration.userContentController
            controller.removeAllUserScripts()
            controller.addUserScript(
                WKUserScript(
                    source: Self.styleSource(theme: parent.theme, fontScale: parent.fontScale),
                    injectionTime: .atDocumentStart,
                    forMainFrameOnly: true
                )
            )
        }

        func load(chapter: Int, into view: WKWebView, restoring offset: Double) {
            guard parent.spine.indices.contains(chapter) else { return }
            loadedChapter = chapter
            pendingOffset = offset
            isRestoring = offset > 0

            let file = parent.root.appendingPathComponent(parent.spine[chapter])
            view.loadFileURL(file, allowingReadAccessTo: parent.root)
        }

        func applyAppearance(to view: WKWebView) {
            view.evaluateJavaScript(
                Self.styleSource(theme: parent.theme, fontScale: parent.fontScale),
                completionHandler: nil
            )
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard pendingOffset > 0 else {
                isRestoring = false
                return
            }
            let offset = pendingOffset
            pendingOffset = 0
            // After layout settles, or the content height is still zero and the
            // restore lands at the top of the chapter.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self, weak webView] in
                guard let self, let webView else { return }
                let scrollView = webView.scrollView
                let visible = scrollView.bounds.height - scrollView.adjustedContentInset.top
                    - scrollView.adjustedContentInset.bottom
                let reachable = max(0, scrollView.contentSize.height - visible)
                scrollView.setContentOffset(
                    CGPoint(x: 0, y: reachable * offset - scrollView.adjustedContentInset.top),
                    animated: false
                )
                isRestoring = false
            }
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            guard !isRestoring else { return }
            let visible = scrollView.bounds.height - scrollView.adjustedContentInset.top
                - scrollView.adjustedContentInset.bottom
            let reachable = max(1, scrollView.contentSize.height - visible)
            let travelled = scrollView.contentOffset.y + scrollView.adjustedContentInset.top
            parent.onScroll(min(1, max(0, travelled / reachable)))
        }

        @objc func handleTap() { parent.onTap() }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool { true }

        /// The book's own stylesheet stays in charge of everything except the things
        /// the reader chose: what colour the paper is and how big the type is. Forcing
        /// more than that is how a carefully typeset book gets flattened.
        private static func styleSource(theme: ReadingTheme, fontScale: Double) -> String {
            let colors = theme.colors
            let percent = Int((fontScale * 100).rounded())
            let css = """
            :root { color-scheme: \(theme == .light ? "light" : "dark"); }
            html, body {
              background: \(colors.background) !important;
              color: \(colors.text) !important;
              -webkit-text-size-adjust: \(percent)% !important;
            }
            body {
              margin: 0 auto !important;
              padding: 24px 20px 64px !important;
              max-width: 40em !important;
              line-height: 1.7 !important;
              word-break: keep-all;
              overflow-wrap: break-word;
            }
            p, li, div, span, td { color: \(colors.text) !important; }
            a, a * { color: \(colors.link) !important; }
            img, svg, video { max-width: 100% !important; height: auto !important; }
            """
            return """
            (function () {
              var id = 'glaze-reader-style';
              var style = document.getElementById(id);
              if (!style) {
                style = document.createElement('style');
                style.id = id;
                (document.head || document.documentElement).appendChild(style);
              }
              style.textContent = `\(css)`;
            })();
            """
        }
    }
}
