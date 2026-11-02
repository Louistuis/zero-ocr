import AppKit

/// Editable view of the last result, for when the clipboard alone is not enough (fix a word, copy part).
final class ResultWindow: NSWindowController {
    static let shared = ResultWindow()

    private let textView: NSTextView
    private let info = NSTextField(labelWithString: "")
    private var html: String?

    private init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 420),
                              styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
                              backing: .buffered, defer: true)
        window.title = "Zero OCR"
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 360, height: 220)
        window.center()
        window.setFrameAutosaveName("ZeroOCRResult")

        let scroll = NSTextView.scrollableTextView()
        textView = scroll.documentView as! NSTextView
        textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.textContainerInset = NSSize(width: 14, height: 14)
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        scroll.drawsBackground = false
        textView.drawsBackground = false

        info.font = .systemFont(ofSize: 11)
        info.textColor = .secondaryLabelColor
        let copy = NSButton(title: "Copy All", target: nil, action: #selector(copyAll))
        copy.bezelStyle = .push
        copy.keyEquivalent = "\r"
        copy.keyEquivalentModifierMask = .command
        let bar = NSStackView(views: [info, NSView(), copy])
        bar.edgeInsets = NSEdgeInsets(top: 8, left: 16, bottom: 12, right: 14)

        let stack = NSStackView(views: [scroll, bar])
        stack.orientation = .vertical
        stack.spacing = 0
        stack.edgeInsets = NSEdgeInsets(top: 28, left: 0, bottom: 0, right: 0)
        let bg = NSVisualEffectView()
        bg.material = .windowBackground
        bg.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: bg.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: bg.trailingAnchor),
            stack.topAnchor.constraint(equalTo: bg.topAnchor),
            stack.bottomAnchor.constraint(equalTo: bg.bottomAnchor),
        ])
        window.contentView = bg
        super.init(window: window)
        copy.target = self
    }

    required init?(coder: NSCoder) { fatalError() }

    func show(text: String, html: String?, info line: String) {
        textView.string = text
        self.html = html
        info.stringValue = line
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    @objc private func copyAll() {
        // An edited table no longer matches the HTML grid, so only keep it while the text is untouched.
        Clipboard.put(textView.string, html: textView.undoManager?.canUndo == true ? nil : html)
        window?.close()
    }
}
