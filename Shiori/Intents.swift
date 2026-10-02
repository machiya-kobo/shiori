import AppIntents
import HisterKit
import SwiftUI

// Shortcuts and Siri. These live in the app target, not HisterKit: App
// Shortcuts metadata delivered from a Swift package is rejected by the
// system and the shortcuts silently never register.

/// Saves a link to Hister without opening the app. Like the share sheet,
/// it queues the page when Hister is out of reach.
struct SaveURLIntent: AppIntent {
    static let title: LocalizedStringResource = "Save URL to Hister"
    static let description = IntentDescription("Saves a web page to your Hister server, with an optional label.")
    static let openAppWhenRun = false

    @Parameter(title: "URL")
    var url: URL

    @Parameter(title: "Label", description: "A topic label, which marks the page as kept.")
    var label: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Save \(\.$url) to Hister") {
            \.$label
        }
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            throw $url.needsValueError("Which web page should Hister save?")
        }
        let outcome = await Saver.save(.init(url: url), label: label, via: "shortcut")
        return .result(dialog: IntentDialog(stringLiteral: outcome.message))
    }
}

/// Opens Shiori's search with a query.
struct SearchHisterIntent: AppIntent {
    static let title: LocalizedStringResource = "Search Hister"
    static let description = IntentDescription("Searches your Hister pages in Shiori.")
    static let openAppWhenRun = true

    @Parameter(title: "Query", requestValueDialog: "What should Shiori search for?")
    var query: String

    static var parameterSummary: some ParameterSummary {
        Summary("Search Hister for \(\.$query)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        SearchRequest.shared.pending = query
        return .result()
    }
}

/// A search asked for from outside (the shortcut), picked up by the tabs.
@Observable
final class SearchRequest {
    static let shared = SearchRequest()
    var pending: String?
}

struct ShioriShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SearchHisterIntent(),
            phrases: [
                "Search \(.applicationName)",
                "Search Hister in \(.applicationName)",
            ],
            shortTitle: "Search Hister",
            systemImageName: "magnifyingglass")
        AppShortcut(
            intent: SaveURLIntent(),
            phrases: [
                "Save to Hister with \(.applicationName)",
                "Save a page with \(.applicationName)",
            ],
            shortTitle: "Save URL",
            systemImageName: "bookmark")
    }
}
