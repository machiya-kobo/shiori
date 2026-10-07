import HisterKit
import SwiftUI
import WebKit
import os

/// Builds the page the preview shows: Hister's readable HTML under a header,
/// styled in the theme's palette.
enum PreviewPage {
    /// `place`: a vault note's place in the vault, shown instead of the
    /// Niwa or Konbini host it's stored under.
    /// `images`: whether the page's own images load (Settings → Images in
    /// Previews). They come from the page's sites, so off means nothing
    /// third-party is fetched at all.
    static func html(
        document: StoredPage, preview: PagePreview, label: String, palette: Palette, place: String? = nil,
        images: Bool = true, kura: String = ""
    ) -> String {
        let imageSources = images ? "* data:" : "data:"
        // A file: where it lives on the server, not Hister's "local".
        let shownDomain = LocalFiles.isLocalFile(document.url) ? LocalFiles.path(of: document.url) : document.domain
        let whereLine = place.map { escape($0) } ?? #"<span class="domain">\#(escape(shownDomain))</span>"#
        let title = escape(preview.title.isEmpty ? document.displayTitle : preview.title)
        let dates = [
            // No date (`.distantPast`): none shown, not year 1.
            preview.added > .distantPast ? "Added \(preview.added.formatted(date: .abbreviated, time: .omitted))" : nil,
            preview.updated != preview.added && preview.updated > .distantPast
                ? "updated \(preview.updated.formatted(date: .abbreviated, time: .omitted))" : nil,
            preview.visits > 1 ? "\(preview.visits) visits" : nil,
        ].compactMap { $0 }.joined(separator: " · ")
        let chip = label.isEmpty
            ? "" : #"<span class="chip" style="--chip: \#(Palette.css(palette.chipHex(for: label)))">\#(escape(label))</span>"#
        let byline = preview.author.map { "<p class=\"meta\">\(escape($0))</p>" } ?? ""
        // A note's Obsidian tags ("#topic/docker"), after its label.
        // Each links to its Kura tag page, which lists the vault's notes with it.
        let tags = preview.tags.isEmpty
            ? "" : #"<p class="meta tags">"# + preview.tags.map { tag in
                guard let url = Notes.tagURL(base: kura, tag: tag) else { return "#" + escape(tag) }
                return #"<a href="\#(escape(url.absoluteString))">#\#(escape(tag))</a>"#
            }.joined(separator: " ") + "</p>"
        return """
            <!doctype html>
            <html>
            <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src \(imageSources); style-src 'unsafe-inline'; font-src data:">
            <meta name="referrer" content="no-referrer">
            <style>
            :root { \(palette.cssVariables) color-scheme: light dark; }
            html { background: var(--bg); }
            /* 56em, not 42: in a wide pane the centred column left more
               empty margin than text. */
            body {
              font: -apple-system-body; font-family: -apple-system, system-ui, sans-serif;
              color: var(--text); background: var(--bg);
              margin: 0 auto; padding: 16px 20px 48px; max-width: 56em;
              line-height: 1.55; overflow-wrap: anywhere; -webkit-text-size-adjust: 100%;
            }
            header { border-bottom: 1px solid var(--raised); margin-bottom: 1.25em; padding-bottom: 0.75em; }
            header h1 { font: -apple-system-title2; font-weight: 700; margin: 0 0 0.3em; line-height: 1.25; }
            .meta { color: var(--secondary); font: -apple-system-footnote; margin: 0.2em 0; }
            .domain { font-family: ui-monospace, monospace; }
            .chip {
              display: inline-block; margin-top: 0.5em; padding: 1px 9px; border-radius: 999px;
              /* Outlined, as the search page draws its tags. */
              color: var(--chip); border: 1px solid currentColor; background: transparent; font: -apple-system-caption1;
            }
            a { color: var(--accent); }
            h1, h2, h3, h4 { line-height: 1.3; }
            img, video, figure { max-width: 100%; height: auto; border-radius: 6px; }
            svg, picture, canvas, iframe, object, embed { max-width: 100%; height: auto; }
            figure { margin: 1em 0; }
            pre, code { font-family: ui-monospace, monospace; font-size: 0.9em; background: var(--surface); border-radius: 6px; }
            pre { padding: 12px; overflow-x: auto; }
            code { padding: 1px 4px; }
            pre code { padding: 0; background: none; }
            blockquote { margin: 1em 0; padding-left: 1em; border-left: 3px solid var(--raised); color: var(--secondary); }
            table { border-collapse: collapse; display: block; overflow-x: auto; }
            td, th { border: 1px solid var(--raised); padding: 4px 8px; }
            hr { border: none; border-top: 1px solid var(--raised); }
            mark { background: color-mix(in srgb, var(--highlight) calc(var(--highlight-opacity) * 100%), transparent); color: inherit; }
            </style>
            </head>
            <body>
            <header>
            <h1>\(title)</h1>
            <p class="meta">\(whereLine)</p>
            <p class="meta">\(escape(dates))</p>
            \(byline)
            \(chip)
            \(tags)
            </header>
            <article>\(images ? linkingImages(preview.contentHTML) : preview.contentHTML)</article>
            </body>
            </html>
            """
    }

    /// Images outside any link get one to themselves, marked, so a tap
    /// shows them large (`ImageViewer`) instead of doing nothing: with
    /// JavaScript off, a link is the only way a tap reaches the app.
    static func linkingImages(_ html: String) -> String {
        let pattern = /(?i)<a\b[^>]*>|<\/a\s*>|<img\b[^>]*?\bsrc\s*=\s*"([^"]+)"[^>]*>/
        var out = ""
        out.reserveCapacity(html.utf8.count + 256)
        var depth = 0
        var last = html.startIndex
        for match in html.matches(of: pattern) {
            out += html[last..<match.range.lowerBound]
            let tag = html[match.range]
            if tag.lowercased().hasPrefix("</a") {
                depth = max(0, depth - 1)
                out += tag
            } else if tag.lowercased().hasPrefix("<a") {
                depth += 1
                out += tag
            } else if depth == 0, let src = match.output.1, !src.hasPrefix("data:") {
                out += "<a href=\"\(src)#\(imageMarker)\">\(tag)</a>"
            } else {
                out += tag
            }
            last = match.range.upperBound
        }
        out += html[last...]
        return out
    }

    static let imageMarker = "shiori-image"

    /// An image to show large rather than open: marked by `linkingImages`,
    /// or a link straight to an image file.
    static func isImage(_ url: URL) -> Bool {
        if url.fragment == imageMarker { return true }
        return ["jpg", "jpeg", "png", "gif", "webp", "avif", "heic"].contains(url.pathExtension.lowercased())
    }

    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

/// A read-only web view: JavaScript off, and any tapped link opens in the
/// browser instead of inside the preview.
struct PreviewWebView {
    let html: String
    let baseURL: URL?
    let openLink: (URL) -> Void
    /// Called once the page has drawn, so a spinner can cover WebKit's
    /// first-launch start-up.
    var onFinish: () -> Void = {}
    /// Called if the page can't be drawn (or WebKit's page process died),
    /// so the spinner gives way to an error with Try Again.
    var onFailure: () -> Void = {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    private func makeWebView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        config.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = false
        #if DEBUG
        webView.isInspectable = true
        #endif
        return webView
    }

    private func update(_ webView: WKWebView, context: Context) {
        // The page follows Settings → Text Size (and on iOS, the system's).
        #if os(macOS)
        let zoom = context.environment.macTextScale
        #else
        // The page's -apple-system fonts already follow the system's size,
        // so zoom only by how far Shiori's own size differs from it.
        let system = DynamicTypeSize(UIApplication.shared.preferredContentSizeCategory) ?? .large
        let zoom = TextSize.scale(for: context.environment.dynamicTypeSize) / TextSize.scale(for: system)
        #endif
        if webView.pageZoom != zoom { webView.pageZoom = zoom }
        context.coordinator.openLink = openLink
        context.coordinator.onFinish = onFinish
        context.coordinator.onFailure = onFailure
        guard context.coordinator.loadedHTML != html else { return }
        context.coordinator.loadedHTML = html
        webView.loadHTMLString(html, baseURL: baseURL)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var openLink: (URL) -> Void = { _ in }
        var onFinish: () -> Void = {}
        var onFailure: () -> Void = {}
        var loadedHTML: String?
        private let log = Logger(subsystem: ShioriID.app, category: "preview")

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            onFinish()
        }

        // Private: an error's description can carry the page's URL.
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
            log.error("preview failed: \(error.localizedDescription, privacy: .private)")
            onFailure()
        }

        func webView(
            _ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error
        ) {
            log.error("preview failed provisionally: \(error.localizedDescription, privacy: .private)")
            onFailure()
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            log.error("preview's web content process ended")
            loadedHTML = nil
            onFailure()
        }

        func webView(
            _ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
            decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
        ) {
            if action.navigationType == .linkActivated, let url = action.request.url {
                openLink(url)
                decisionHandler(.cancel)
            } else if action.navigationType == .other, action.targetFrame?.isMainFrame == true {
                // The initial loadHTMLString.
                decisionHandler(.allow)
            } else {
                decisionHandler(action.targetFrame?.isMainFrame == false ? .allow : .cancel)
            }
        }
    }
}

#if os(iOS)
extension PreviewWebView: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView {
        let webView = makeWebView(context: context)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        update(webView, context: context)
    }
}
#else
extension PreviewWebView: NSViewRepresentable {
    func makeNSView(context: Context) -> WKWebView {
        let webView = makeWebView(context: context)
        webView.underPageBackgroundColor = .clear
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        update(webView, context: context)
    }
}
#endif
