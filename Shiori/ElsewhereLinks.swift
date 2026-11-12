import HisterKit
import SwiftUI

/// A web page elsewhere: on Archive.org and Archive.is, and through the
/// build's privacy front ends that stand in for its site (`Elsewhere`).
/// Links only, opened in the browser.
struct ElsewhereLinks: View {
    let url: String
    /// The front ends ahead of the archives (the share sheet, where
    /// they're the reason to be there).
    var frontendsFirst = false

    /// The build's front ends (`SHIORI_FRONTENDS`), read once.
    static let instances = Elsewhere.instances(
        from: (Bundle.main.object(forInfoDictionaryKey: "ShioriFrontends") as? String) ?? "")

    var body: some View {
        // A page on one of the front ends (saved while browsing Redlib, say):
        // its own site too, and the archives of that address, which they can reach.
        let original = Elsewhere.original(of: url, instances: Self.instances)
        let page = original?.url.absoluteString ?? url
        if frontendsFirst { frontendLinks }
        if let original {
            Link(destination: original.url) { Label("Open Original on \(original.site)", systemImage: "arrow.uturn.backward") }
        }
        if let wayback = Elsewhere.wayback(page) {
            Link(destination: wayback) { Label("Open on Archive.org", systemImage: "building.columns") }
        }
        if let archive = Elsewhere.archiveToday(page) {
            Link(destination: archive) { Label("Open on Archive.is", systemImage: "archivebox") }
        }
        if !frontendsFirst { frontendLinks }
    }

    private var frontendLinks: some View {
        ForEach(Elsewhere.frontends(for: url, instances: Self.instances), id: \.url) { frontend in
            Link(destination: frontend.url) { Label("Open in \(frontend.name)", systemImage: "eye.slash") }
        }
    }
}
