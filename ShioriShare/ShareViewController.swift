import HisterKit
import SwiftUI

/// The "Save to Shiori" share extension's entry point. It saves the page
/// itself; if Hister is out of reach the page waits in the App Group
/// outbox and the app sends it later. (A share extension can't open its
/// app.) It also opens the page elsewhere (a front end, an archive) in the
/// browser. The model and view are shared by both platforms (ShareModel.swift).
#if os(iOS)
import SafariServices
import UIKit

final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        let root = makeRoot(context: extensionContext) { [weak self] url in self?.open(url) }
        let host = UIHostingController(rootView: root)
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
    }

    /// In the browser, then the sheet closes. A share extension has no
    /// openURL of its own (extensionContext.open is a widget's): the app
    /// object up the responder chain opens it. If that's refused, the page
    /// opens here instead, in a Safari view over the sheet.
    private func open(_ url: URL) {
        var responder: UIResponder? = self
        while let next = responder, !(next is UIApplication) { responder = next.next }
        guard let application = responder as? UIApplication else { return showHere(url) }
        application.open(url, options: [:]) { [weak self] opened in
            guard let self else { return }
            if opened {
                self.extensionContext?.completeRequest(returningItems: nil)
            } else {
                self.showHere(url)
            }
        }
    }

    private func showHere(_ url: URL) {
        present(SFSafariViewController(url: url), animated: true)
    }
}
#else
import AppKit

final class ShareViewController: NSViewController {
    override func loadView() {
        let root = makeRoot(context: extensionContext) { [weak self] url in
            NSWorkspace.shared.open(url)
            self?.extensionContext?.completeRequest(returningItems: nil)
        }
        let host = NSHostingView(rootView: root)
        host.frame = NSRect(x: 0, y: 0, width: 440, height: 340)
        view = host
        preferredContentSize = host.frame.size
    }
}
#endif

@MainActor
private func makeRoot(context: NSExtensionContext?, open: @escaping @MainActor (URL) -> Void) -> some View {
    let model = ShareModel(context: context, open: open)
    let theme = AppTheme.resolve(SharedSettings.defaults?.string(forKey: SharedSettings.Key.theme))
    let palette = AppPalette.resolve(SharedSettings.defaults?.string(forKey: SharedSettings.Key.palette))
    // The app's Text Size too (on the Mac the only way text grows).
    let size = TextSize.resolve(SharedSettings.defaults?.string(forKey: SharedSettings.Key.textSize))
    return ShareView(model: model)
        .modifier(ThemedRoot(theme: theme, palette: palette))
        .modifier(TextSizeRoot(size: size))
        .task { await model.load() }
}
