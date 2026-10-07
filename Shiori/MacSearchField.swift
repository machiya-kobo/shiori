#if os(macOS)
import AppKit
import HisterKit
import SwiftUI

/// The Mac's search field, over the results column. macOS 26 keeps `.searchable`'s field at the toolbar's
/// trailing end whatever its placement (`.toolbarPrincipal` and
/// `DefaultToolbarItem(kind: .search)` at `.navigation` or
/// `.primaryAction` were all tried, and measured), so this is our own: a
/// real `NSSearchField` (the app's select-on-click already covers it, and
/// ⌘F and / focus it through `searchFocusRequests`). No suggestions under
/// it: recent searches are in the sidebar.
/// Instead, type-ahead: the rest of a recent search, or of the web's
/// autocomplete, grey after the caret; Tab or → takes it, and so does a
/// click on it. Nothing after a delete, so it never fights a correction.
struct MacSearchField: View {
    @Binding var text: String
    let prompt: String
    @Binding var focused: Bool
    let width: CGFloat
    let store: MacSearchFieldStore
    /// Off while the field searches within a collection or label: recent
    /// searches and the web's completions are for everything.
    var typeAhead = true
    let submit: () -> Void

    @Environment(AppState.self) private var app
    // The type-ahead's state lives in the store, not in @State: SwiftUI
    // rebuilds this toolbar item when results arrive, and a rebuilt view
    // starts empty, which dropped the completion before Tab.
    private var web: (typed: String, list: [String]) {
        get { store.web }
        nonmutating set { store.web = newValue }
    }
    private var completion: String {
        get { store.completion }
        nonmutating set { store.completion = newValue }
    }
    private var previous: String {
        get { store.previous }
        nonmutating set { store.previous = newValue }
    }

    var body: some View {
        SearchFieldRepresentable(
            text: $text, prompt: prompt, focused: $focused, store: store, completion: completion, submit: submit
        ) {
            text += completion
            completion = ""
        }
        .frame(width: width)
        .onChange(of: text) { old, new in
            previous = old
            completion = typedAhead(new, deleting: new.count < old.count || !new.hasPrefix(old))
        }
        .task(id: text) {
            let typed = text
            guard typeAhead, focused, app.allSearch.webResults, let searx = app.searx, typed.trimmingCharacters(in: .whitespaces).count >= 2,
                  !(typed.count < previous.count)
            else { return }
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            let list = await searx.autocomplete(typed)
            guard !Task.isCancelled, text == typed else { return }
            web = (typed, list)
            completion = typedAhead(typed, deleting: false)
        }
    }

    private func typedAhead(_ typed: String, deleting: Bool) -> String {
        guard typeAhead, !deleting, focused else { return "" }
        let fits = !web.typed.isEmpty && typed.lowercased().hasPrefix(web.typed.lowercased())
        let recents = app.searchPage.searchHistory ? app.recentSearches : []
        return Respelling.typeAhead(typed, candidates: recents + (fits ? web.list : []))
    }
}

/// The window's one field, reused by every rebuild of the toolbar item,
/// and its type-ahead, which must outlive a rebuild too.
@MainActor @Observable final class MacSearchFieldStore {
    @ObservationIgnored fileprivate var field: FocusReportingSearchField?
    var completion = ""
    @ObservationIgnored var web: (typed: String, list: [String]) = ("", [])
    @ObservationIgnored var previous = ""
}

/// Says when it takes the keyboard: NSControl's "did begin editing" waits
/// for the first keystroke, so a click alone left the binding unfocused
/// and the next update took the keyboard away again.
///
/// SwiftUI rebuilds the toolbar item when the window's toolbar changes
/// (a new search's results arriving), so the one field is kept
/// and moved into each rebuild. A move takes it out of the window, which
/// ends its editing; it notes that and where the caret was, and takes the
/// keyboard back with the caret in place (a plain refocus selects all, and
/// the next keystroke replaced what was typed).
fileprivate final class FocusReportingSearchField: NSSearchField {
    var becameFocused: () -> Void = {}
    /// Type-ahead: the grey rest, drawn at the caret; a click takes it.
    var completion = "" {
        didSet { if completion != oldValue { placeGhost() } }
    }
    var acceptCompletion: () -> Void = {}
    private lazy var ghost: NSTextField = {
        let label = NSTextField(labelWithString: "")
        label.textColor = .placeholderTextColor
        label.lineBreakMode = .byClipping
        label.isHidden = true
        label.addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(ghostClicked)))
        addSubview(label)
        return label
    }()

    @objc private func ghostClicked() {
        acceptCompletion()
    }

    /// Return, and Tab or → to take the completion. SwiftUI's windows give
    /// a field their own text editor, which never passes these on to the
    /// delegate's `doCommandBy` (not even Return), so
    /// the keys are caught before it, while this field is being edited.
    var submit: () -> Void = {}
    private var keys: Any?

    private func installKeys() {
        guard keys == nil else { return }
        keys = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let code = event.keyCode
            let plain = event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty
            let window = event.window
            // Decided on the main actor; the event itself stays out here.
            let handled = MainActor.assumeIsolated { () -> Bool in
                guard let self, plain, let editor = self.currentEditor() as? NSTextView, window === self.window else { return false }
                switch code {
                case 36, 76: // Return, Enter
                    self.submit()
                    return true
                case 48, 124: // Tab, →
                    let atEnd = editor.selectedRange().location == (editor.string as NSString).length
                    guard !self.completion.isEmpty, atEnd, editor.selectedRange().length == 0 else { return false }
                    self.acceptCompletion()
                    return true
                default:
                    return false
                }
            }
            return handled ? nil : event
        }
    }

    private func removeKeys() {
        if let keys { NSEvent.removeMonitor(keys) }
        keys = nil
    }

    /// Where the caret is, from the field editor, so the grey starts right
    /// after the text whatever its size or scroll; hidden unless the caret
    /// is at the end with nothing selected.
    func placeGhost() {
        guard !completion.isEmpty, let window, let editor = currentEditor() as? NSTextView else {
            ghost.isHidden = true
            return
        }
        let length = (editor.string as NSString).length
        let selection = editor.selectedRange()
        guard selection.location == length, selection.length == 0 else {
            ghost.isHidden = true
            return
        }
        let caret = convert(window.convertFromScreen(editor.firstRect(forCharacterRange: NSRange(location: length, length: 0), actualRange: nil)), from: nil)
        let text = (cell as? NSSearchFieldCell)?.searchTextRect(forBounds: bounds) ?? bounds
        ghost.font = font
        ghost.stringValue = completion
        ghost.sizeToFit()
        // A label draws its text a line-fragment's padding in.
        let x = caret.minX - 2
        let room = text.maxX - x
        guard room > 12 else {
            ghost.isHidden = true
            return
        }
        ghost.frame = CGRect(x: x, y: caret.midY - ghost.frame.height / 2, width: min(ghost.frame.width, room), height: ghost.frame.height)
        ghost.isHidden = false
    }

    /// The caret moved (a click, ← →): the grey follows or hides.
    @objc func textViewDidChangeSelection(_ notification: Notification) {
        placeGhost()
    }

    override func textDidEndEditing(_ notification: Notification) {
        super.textDidEndEditing(notification)
        ghost.isHidden = true
    }
    /// Out of the window mid-edit, and the caret it had then.
    private(set) var parked = false
    private var caret = NSRange(location: 0, length: 0)

    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        if became { DispatchQueue.main.async { self.becameFocused() } }
        return became
    }

    /// The rebuilt item first takes it into a view not yet in the window,
    /// and leaving the old one ends the editing: note it here, before that.
    override func viewWillMove(toSuperview newSuperview: NSView?) {
        if let editor = currentEditor() {
            parked = true
            caret = editor.selectedRange
        }
        super.viewWillMove(toSuperview: newSuperview)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // Out of a window (the toolbar rebuilt, the window closed), the keys'
        // monitor goes too: installed again when the field is back.
        guard let window else {
            removeKeys()
            return
        }
        installKeys()
        guard parked else { return }
        parked = false
        window.makeFirstResponder(self)
        let length = (stringValue as NSString).length
        currentEditor()?.selectedRange = NSRange(location: min(caret.location, length), length: min(caret.length, max(0, length - caret.location)))
    }
}

/// `NSSearchField`, bound: its text, whether it's being edited, and Return.
private struct SearchFieldRepresentable: NSViewRepresentable {
    @Binding var text: String
    let prompt: String
    @Binding var focused: Bool
    let store: MacSearchFieldStore
    let completion: String
    let submit: () -> Void
    let accept: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSSearchField {
        let field = store.field ?? FocusReportingSearchField()
        store.field = field
        field.acceptCompletion = { [weak coordinator = context.coordinator] in coordinator?.parent.accept() }
        field.submit = { [weak coordinator = context.coordinator] in coordinator?.parent.submit() }
        field.becameFocused = { [weak coordinator = context.coordinator] in
            guard let coordinator, !coordinator.parent.focused else { return }
            coordinator.parent.focused = true
        }
        field.delegate = context.coordinator
        field.target = context.coordinator
        field.action = #selector(Coordinator.changed(_:))
        field.sendsSearchStringImmediately = true
        // Query words are case-sensitive (label:books), and Hister remembers
        // what you opened by the exact query.
        field.isAutomaticTextCompletionEnabled = false
        field.placeholderString = prompt
        field.setAccessibilityLabel("Search")
        return field
    }

    func updateNSView(_ field: NSSearchField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text {
            field.stringValue = text
            // After a completion is taken: the caret to the end.
            if let editor = field.currentEditor() { editor.selectedRange = NSRange(location: (text as NSString).length, length: 0) }
        }
        if let field = field as? FocusReportingSearchField {
            field.completion = completion
            // After the text lays out, so the caret's place is current.
            DispatchQueue.main.async { field.placeGhost() }
        }
        if field.placeholderString != prompt { field.placeholderString = prompt }
        let editing = field.currentEditor() != nil
        if focused, !editing {
            // After this update, not during it (the window may not be up yet).
            DispatchQueue.main.async {
                guard let window = field.window, field.currentEditor() == nil else { return }
                window.makeFirstResponder(field)
            }
        } else if !focused, editing, context.coordinator.wasFocused {
            // Only a change to unfocused, never a binding that hasn't caught
            // up with a click yet.
            DispatchQueue.main.async {
                guard field.currentEditor() != nil else { return }
                field.window?.makeFirstResponder(nil)
            }
        }
        context.coordinator.wasFocused = focused
    }

    @MainActor
    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var parent: SearchFieldRepresentable
        var wasFocused = false

        init(_ parent: SearchFieldRepresentable) {
            self.parent = parent
        }

        /// Typing, and the field's own ⓧ.
        @objc func changed(_ sender: NSSearchField) {
            if parent.text != sender.stringValue { parent.text = sender.stringValue }
        }

        func controlTextDidChange(_ note: Notification) {
            guard let field = note.object as? NSSearchField else { return }
            changed(field)
        }

        func controlTextDidBeginEditing(_ note: Notification) {
            if !parent.focused { parent.focused = true }
        }

        func controlTextDidEndEditing(_ note: Notification) {
            // Moved into a rebuilt toolbar item, not left.
            if (note.object as? FocusReportingSearchField)?.parked == true { return }
            if parent.focused { parent.focused = false }
        }
    }
}
#endif
