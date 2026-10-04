import HisterKit
import SwiftUI

/// The "Save to Shiori" share extension's entry point. It saves the page
/// itself; if Hister is out of reach the page waits in the App Group
/// outbox and the app sends it later. (A share extension can't open its
/// app.) The model and view are shared by both platforms (ShareModel.swift).
#if os(iOS)
import UIKit

final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        let host = UIHostingController(rootView: makeRoot(context: extensionContext))
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
    }
}
#else
import AppKit

final class ShareViewController: NSViewController {
    override func loadView() {
        let host = NSHostingView(rootView: makeRoot(context: extensionContext))
        host.frame = NSRect(x: 0, y: 0, width: 440, height: 340)
        view = host
        preferredContentSize = host.frame.size
    }
}
#endif

@MainActor
private func makeRoot(context: NSExtensionContext?) -> some View {
    let model = ShareModel(context: context)
    let theme = AppTheme.resolve(SharedSettings.defaults?.string(forKey: SharedSettings.Key.theme))
    let palette = AppPalette.resolve(SharedSettings.defaults?.string(forKey: SharedSettings.Key.palette))
    // The app's Text Size too (on the Mac the only way text grows).
    let size = TextSize.resolve(SharedSettings.defaults?.string(forKey: SharedSettings.Key.textSize))
    return ShareView(model: model)
        .modifier(ThemedRoot(theme: theme, palette: palette))
        .modifier(TextSizeRoot(size: size))
        .task { await model.load() }
}
