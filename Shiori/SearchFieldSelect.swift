import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// Tapping or clicking into a search field selects what's in it, so typing
/// replaces it at once (the web app and the search page do the same).
/// SwiftUI's `.searchable` has no such option, so it's done beneath it,
/// once for the app.
@MainActor
enum SearchFieldSelect {
    private static var installed = false

    static func install() {
        guard !installed else { return }
        installed = true
        #if os(iOS)
        NotificationCenter.default.addObserver(
            forName: UITextField.textDidBeginEditingNotification, object: nil, queue: .main
        ) { note in
            guard let field = note.object as? UISearchTextField else { return }
            MainActor.assumeIsolated {
                // After the tap has placed its caret, or it would undo this.
                DispatchQueue.main.async {
                    guard field.isFirstResponder, !(field.text ?? "").isEmpty else { return }
                    field.selectedTextRange = field.textRange(from: field.beginningOfDocument, to: field.endOfDocument)
                }
            }
        }
        #else
        // A click into a search field that wasn't being edited: select all
        // once the click is done (the click itself places a caret).
        var cameFromClick = false
        NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp]) { event in
            MainActor.assumeIsolated {
                let editor = event.window?.firstResponder as? NSTextView
                let editing = editor.map { ($0.delegate as? NSSearchField) != nil } ?? false
                if event.type == .leftMouseDown {
                    cameFromClick = !editing
                } else if cameFromClick {
                    cameFromClick = false
                    DispatchQueue.main.async {
                        guard let editor = event.window?.firstResponder as? NSTextView,
                            editor.delegate is NSSearchField, !editor.string.isEmpty
                        else { return }
                        editor.selectAll(nil)
                    }
                }
            }
            return event
        }
        #endif
    }
}
