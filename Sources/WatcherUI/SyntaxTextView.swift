import AppKit
import SwiftUI
import WatcherCore

/// Monospaced text with syntax colours. Read-only by default; editable for the compose and script editors.
/// An NSTextView underneath gives the standard Find bar (⌘F), selection, undo and Services.
///
/// Colouring is done for the lines on screen only. The document is parsed once on a background thread (tree-sitter for JSON,
/// HTML/XML, CSS and JavaScript) and each scroll asks for just the visible range, so a 30 MB body opens as fast as a small one.
struct SyntaxTextView: NSViewRepresentable {
    @Binding var text: String
    var language: BodyLanguage
    var isEditable = false
    var wraps = true
    var fontSize: CGFloat = 12

    init(_ text: String, language: BodyLanguage, wraps: Bool = true, fontSize: CGFloat = 12) {
        _text = .constant(text); self.language = language; self.wraps = wraps; self.fontSize = fontSize
    }

    init(text: Binding<String>, language: BodyLanguage, wraps: Bool = true, fontSize: CGFloat = 12) {
        _text = text; self.language = language; isEditable = true; self.wraps = wraps; self.fontSize = fontSize
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        guard let view = scroll.documentView as? NSTextView else { return scroll }
        // TextKit 1 with non-contiguous layout: jumping to the middle of a huge body lays out only that part,
        // and temporary attributes colour text without touching the storage.
        view.layoutManager?.allowsNonContiguousLayout = true
        view.isEditable = isEditable; view.isSelectable = true; view.isRichText = false
        view.allowsUndo = isEditable; view.drawsBackground = false
        view.usesFindBar = true; view.isIncrementalSearchingEnabled = true
        view.textContainerInset = NSSize(width: 8, height: 8)
        view.isAutomaticQuoteSubstitutionEnabled = false; view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticTextReplacementEnabled = false; view.isAutomaticSpellingCorrectionEnabled = false
        view.isContinuousSpellCheckingEnabled = false; view.isGrammarCheckingEnabled = false
        view.setAccessibilityLabel(isEditable ? "Editor" : "Text")
        view.delegate = context.coordinator
        scroll.contentView.postsBoundsChangedNotifications = true
        context.coordinator.attach(view: view, scroll: scroll)
        configureWrapping(scroll, view)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let view = scroll.documentView as? NSTextView else { return }
        context.coordinator.parent = self
        configureWrapping(scroll, view)
        context.coordinator.sync(text: text, language: language, fontSize: fontSize)
    }

    private func configureWrapping(_ scroll: NSScrollView, _ view: NSTextView) {
        scroll.hasHorizontalScroller = !wraps
        view.isHorizontallyResizable = !wraps
        view.textContainer?.widthTracksTextView = wraps
        if !wraps {
            view.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: SyntaxTextView
        private weak var view: NSTextView?
        private weak var scroll: NSScrollView?
        private var observer: NSObjectProtocol?
        /// What the view currently shows, to skip work when SwiftUI re-renders with the same text.
        private var shown: (text: String, language: BodyLanguage, size: CGFloat)?
        private var index: SyntaxIndex?
        private var coloured = IndexSet()
        private var pending: DispatchWorkItem?
        private var generation = 0
        /// Beyond this, languages without a parser are coloured by visible range too instead of all at once.
        private static let wholeDocumentLimit = 200_000
        private static let margin = 6000

        init(_ parent: SyntaxTextView) {
            self.parent = parent
        }

        deinit {
            if let observer {
                NotificationCenter.default.removeObserver(observer)
            }
        }

        func attach(view: NSTextView, scroll: NSScrollView) {
            self.view = view; self.scroll = scroll
            observer = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: scroll.contentView, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.scheduleColouring() }
            }
        }

        func textDidChange(_: Notification) {
            guard let view else { return }
            let text = view.string
            parent.text = text
            shown = nil
            sync(text: text, language: parent.language, fontSize: parent.fontSize, fromEditor: true)
        }

        func sync(text: String, language: BodyLanguage, fontSize: CGFloat, fromEditor: Bool = false) {
            guard let view, let storage = view.textStorage else { return }
            if let shown, shown.language == language, shown.size == fontSize, shown.text == text {
                return
            } // same storage: O(1)
            shown = (text, language, fontSize)
            generation += 1
            let current = generation

            if !fromEditor, view.string != text {
                let selection = view.selectedRange()
                view.string = text
                if parent.isEditable, selection.upperBound <= (text as NSString).length {
                    view.setSelectedRange(selection)
                }
            }
            storage.beginEditing()
            storage.setAttributes(
                [.font: NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular), .foregroundColor: NSColor.labelColor],
                range: NSRange(location: 0, length: storage.length)
            )
            storage.endEditing()
            view.layoutManager?.removeTemporaryAttribute(.foregroundColor, forCharacterRange: NSRange(location: 0, length: storage.length))
            coloured = IndexSet()
            index = nil

            if let fresh = SyntaxIndex(language: language), text.utf16.count <= Self.wholeDocumentLimit {
                fresh.parse(text) // small: well under a millisecond, and the first frame is already coloured
                index = fresh
                colourVisible()
            } else if let fresh = SyntaxIndex(language: language) {
                // Parsing is the slow part: do it away from the main thread, then colour what is on screen.
                Task.detached(priority: .userInitiated) { [weak self] in
                    fresh.parse(text)
                    await MainActor.run {
                        guard let self, self.generation == current else { return }
                        self.index = fresh
                        self.scheduleColouring(delay: 0)
                    }
                }
            } else {
                scheduleColouring(delay: 0)
            }
        }

        private func scheduleColouring(delay: TimeInterval = 0.03) {
            pending?.cancel()
            let work = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.colourVisible() } }
            pending = work
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        }

        private func colourVisible() {
            guard let view, let scroll, let layout = view.layoutManager, let container = view.textContainer, let shown else { return }
            let length = (shown.text as NSString).length
            guard length > 0 else { return }
            var range = NSRange(location: 0, length: length)
            if length > Self.wholeDocumentLimit { // large: only what is on screen, plus a margin for smooth scrolling
                let glyphs = layout.glyphRange(forBoundingRect: scroll.contentView.bounds, in: container)
                let visible = layout.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
                range = NSIntersectionRange(NSRange(location: max(0, visible.location - Self.margin), length: visible.length + 2 * Self.margin), range)
            }
            guard range.length > 0 else { return }

            let text = shown.text as NSString
            let supported = SyntaxIndex.supports(shown.language)
            for gap in missing(in: range) {
                let tokens: [SyntaxHighlighter.Token]
                if supported {
                    guard let index else { return } // still parsing; scheduled again when it is ready
                    tokens = index.tokens(in: gap)
                } else if length <= Self.wholeDocumentLimit {
                    tokens = SyntaxHighlighter.tokens(in: shown.text, language: shown.language)
                    mark(NSRange(location: 0, length: length)); apply(tokens, layout); return
                } else {
                    let lines = text.lineRange(for: gap)
                    tokens = SyntaxHighlighter.tokens(in: text.substring(with: lines), language: shown.language)
                        .map { .init(range: NSRange(location: $0.range.location + lines.location, length: $0.range.length), kind: $0.kind) }
                }
                apply(tokens, layout)
                mark(gap)
            }
        }

        private func apply(_ tokens: [SyntaxHighlighter.Token], _ layout: NSLayoutManager) {
            for token in tokens {
                layout.addTemporaryAttribute(.foregroundColor, value: Theme.color(token.kind), forCharacterRange: token.range)
            }
        }

        private func mark(_ range: NSRange) {
            coloured.insert(integersIn: range.location ..< NSMaxRange(range))
        }

        private func missing(in range: NSRange) -> [NSRange] {
            var wanted = IndexSet(integersIn: range.location ..< NSMaxRange(range))
            wanted.subtract(coloured)
            return wanted.rangeView.map { NSRange(location: $0.lowerBound, length: $0.count) }
        }
    }

    /// System colours adapt to light and dark appearance on their own.
    enum Theme {
        static func color(_ kind: SyntaxHighlighter.Kind) -> NSColor {
            switch kind {
            case .keyword: .systemPink
            case .string: .systemGreen
            case .number: .systemOrange
            case .key: .systemTeal
            case .tag: .systemBlue
            case .attribute: .systemPurple
            case .comment: .secondaryLabelColor
            case .type: .systemCyan
            case .variable: .systemIndigo
            }
        }
    }
}

extension BodyLanguage {
    var displayName: String {
        switch self {
        case .json: "JSON"; case .xml: "XML"; case .html: "HTML"; case .javascript: "JavaScript"; case .css: "CSS"; case .graphql: "GraphQL"
        case .protobuf: "Protobuf"; case .urlencoded: "Form"; case .plist: "Plist"; case .http: "HTTP"; case .curl: "cURL"
        case .swift: "Swift"; case .python: "Python"; case .go: "Go"; case .ruby: "Ruby"; case .php: "PHP"; case .plain: "Text"; case .binary: "Binary"
        }
    }
}
