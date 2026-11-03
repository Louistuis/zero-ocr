import AppKit
import CryptoKit

/// First run: download the model (once, checked by hash) and allow screen reading.
@MainActor
final class Setup: NSObject, URLSessionDownloadDelegate {
    static let shared = Setup()

    private var window: NSWindow?
    private let modelRow = Step(symbol: "arrow.down.circle", title: "Download the model",
                                detail: "Xiaomi-OCR-0, \(Store.downloadMB) MB, once. It never leaves this Mac.")
    private let screenRow = Step(symbol: "rectangle.dashed", title: "Allow screen reading",
                                 detail: "So Zero OCR can see the area you select.")
    private let tryRow = Step(symbol: "command", title: "Press ⇧⌘2 and drag over any text",
                              detail: "It lands on your clipboard. ⌥ for Markdown, ⌃ for tables.")
    private let progress = NSProgressIndicator()
    private let doneButton = NSButton(title: "Done", target: nil, action: nil)
    private var poll: Timer?
    private var session: URLSession?
    private var queue: [Store.File] = []
    private var received: Int64 = 0
    private var finishedBytes: Int64 = 0

    var needed: Bool { !Store.ready || !Capture.allowed }

    private var asked = false
    private var screenOK = Capture.allowed

    func show(permission: Bool = false) {
        if window == nil { build() }
        refresh()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        poll?.invalidate()
        poll = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in Task { @MainActor in self.refresh() } }
        // For testing the first run end to end: open --env ZEROOCR_AUTODOWNLOAD=1 "Zero OCR.app"
        if ProcessInfo.processInfo.environment["ZEROOCR_AUTODOWNLOAD"] != nil, !Store.ready, session == nil { download() }
    }

    private func build() {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 470),
                         styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: true)
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.isMovableByWindowBackground = true
        w.isReleasedWhenClosed = false
        w.center()

        let icon = NSImageView(image: NSApp.applicationIconImage)
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.widthAnchor.constraint(equalToConstant: 84).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 84).isActive = true
        let title = NSTextField(labelWithString: "Zero OCR")
        title.font = .systemFont(ofSize: 24, weight: .bold)
        let sub = NSTextField(wrappingLabelWithString: "Reads any text on your screen with Xiaomi-OCR-0, entirely on this Mac.")
        sub.alignment = .center
        sub.textColor = .secondaryLabelColor
        sub.font = .systemFont(ofSize: 13)
        sub.preferredMaxLayoutWidth = 340

        modelRow.button.title = "Download"
        modelRow.button.target = self
        modelRow.button.action = #selector(download)
        screenRow.button.title = "Allow"
        screenRow.button.target = self
        screenRow.button.action = #selector(allow)
        tryRow.button.isHidden = true

        progress.style = .bar
        progress.isIndeterminate = false
        progress.minValue = 0
        progress.maxValue = 1
        progress.controlSize = .small
        progress.isHidden = true
        modelRow.extra.addArrangedSubview(progress)
        progress.widthAnchor.constraint(equalToConstant: 250).isActive = true

        doneButton.target = self
        doneButton.action = #selector(close)
        doneButton.bezelStyle = .push
        doneButton.keyEquivalent = "\r"
        doneButton.controlSize = .large

        let steps = NSStackView(views: [modelRow, screenRow, tryRow])
        steps.orientation = .vertical
        steps.spacing = 18
        steps.alignment = .leading

        let stack = NSStackView(views: [icon, title, sub, steps, doneButton])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 10
        stack.setCustomSpacing(26, after: sub)
        stack.setCustomSpacing(28, after: steps)
        stack.edgeInsets = NSEdgeInsets(top: 44, left: 36, bottom: 28, right: 36)
        let bg = NSVisualEffectView()
        bg.material = .underWindowBackground
        bg.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: bg.leadingAnchor), stack.trailingAnchor.constraint(equalTo: bg.trailingAnchor),
            stack.topAnchor.constraint(equalTo: bg.topAnchor), stack.bottomAnchor.constraint(lessThanOrEqualTo: bg.bottomAnchor),
            steps.widthAnchor.constraint(equalToConstant: 388),
        ])
        w.contentView = bg
        window = w
    }

    private func refresh() {
        let haveModel = Store.ready
        modelRow.done = haveModel
        if session == nil { modelRow.button.isHidden = haveModel }
        Task { @MainActor in
            screenOK = await Capture.check()
            screenRow.done = screenOK
            screenRow.button.isHidden = screenOK
            // After the switch is turned on, macOS often only lets the app see it after a restart.
            screenRow.button.title = asked ? "Restart Zero OCR" : "Allow"
            screenRow.detail = screenOK ? "Allowed." : asked
                ? "Turn on Zero OCR in the list, then restart it." : "So Zero OCR can see the area you select."
            doneButton.title = haveModel && screenOK ? "Start" : "Done"
            if haveModel, screenOK { poll?.invalidate() }
        }
        doneButton.isEnabled = haveModel
    }

    @objc private func close() {
        poll?.invalidate()
        window?.close()
        if Store.ready { Task.detached { try? await Server.shared.warm() } }
    }

    // MARK: screen permission

    @objc private func allow() {
        if asked { return Setup.relaunch() }
        asked = true
        refresh()
        // The first call shows the system prompt; after that only System Settings can change it.
        if !CGRequestScreenCaptureAccess() {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
        }
    }

    static func relaunch() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "sleep 0.7; /usr/bin/open \"\(Bundle.main.bundlePath)\""]
        try? p.run()
        NSApp.terminate(nil)
    }

    // MARK: download

    @objc private func download() {
        queue = Store.files.filter { f in
            ((try? FileManager.default.attributesOfItem(atPath: f.url.path)[.size]) as? Int64) != f.bytes
        }
        finishedBytes = Store.files.filter { !queue.map(\.name).contains($0.name) }.reduce(0) { $0 + $1.bytes }
        modelRow.button.isHidden = true
        progress.isHidden = false
        session = URLSession(configuration: .default, delegate: self, delegateQueue: .main)
        next()
    }

    private var total: Int64 { Store.files.reduce(0) { $0 + $1.bytes } }

    private func next() {
        guard let f = queue.first else {
            session?.finishTasksAndInvalidate()
            session = nil
            progress.isHidden = true
            modelRow.detail = "Xiaomi-OCR-0 is ready."
            refresh()
            Task.detached { try? await Server.shared.warm() }
            return
        }
        received = 0
        session?.downloadTask(with: f.remote).resume()
    }

    nonisolated func urlSession(_ s: URLSession, downloadTask: URLSessionDownloadTask, didWriteData _: Int64,
                                totalBytesWritten: Int64, totalBytesExpectedToWrite _: Int64) {
        MainActor.assumeIsolated {
            received = totalBytesWritten
            let done = Double(finishedBytes + received)
            progress.doubleValue = done / Double(total)
            modelRow.detail = String(format: "%.0f of %.0f MB", done / 1e6, Double(total) / 1e6)
        }
    }

    nonisolated func urlSession(_ s: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // The temporary file disappears when this returns, so move it first and verify after.
        let part = Store.dir.appendingPathComponent(UUID().uuidString + ".part")
        try? FileManager.default.moveItem(at: location, to: part)
        MainActor.assumeIsolated {
            guard let f = queue.first else { return }
            modelRow.detail = "Checking \(f.name)…"
            Task.detached {
                let ok = Setup.sha256(part) == f.sha256
                await MainActor.run {
                    if ok {
                        try? FileManager.default.removeItem(at: f.url)
                        try? FileManager.default.moveItem(at: part, to: f.url)
                        self.finishedBytes += f.bytes
                        self.queue.removeFirst()
                        self.next()
                    } else {
                        try? FileManager.default.removeItem(at: part)
                        self.fail("The download did not match its checksum. Try again.")
                    }
                }
            }
        }
    }

    nonisolated func urlSession(_ s: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        MainActor.assumeIsolated { fail(error.localizedDescription) }
    }

    private func fail(_ message: String) {
        session?.invalidateAndCancel()
        session = nil
        progress.isHidden = true
        modelRow.detail = message
        modelRow.button.title = "Try Again"
        modelRow.button.isHidden = false
    }

    nonisolated static func sha256(_ url: URL) -> String {
        guard let h = try? FileHandle(forReadingFrom: url) else { return "" }
        defer { try? h.close() }
        var hasher = SHA256()
        while let chunk = try? h.read(upToCount: 8 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

/// One row of the setup list: icon, title, detail, and an action button or a check mark.
final class Step: NSStackView {
    let button = NSButton(title: "", target: nil, action: nil)
    let extra = NSStackView()
    private let icon = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private let sub = NSTextField(wrappingLabelWithString: "")
    private let symbol: String

    var detail: String { get { sub.stringValue } set { sub.stringValue = newValue } }
    var done = false { didSet { paint() } }

    private func paint() {
        icon.image = NSImage(systemSymbolName: done ? "checkmark.circle.fill" : symbol, accessibilityDescription: nil)
        icon.contentTintColor = done ? .systemGreen : .secondaryLabelColor
    }

    init(symbol: String, title: String, detail: String) {
        self.symbol = symbol
        super.init(frame: .zero)
        icon.symbolConfiguration = .init(pointSize: 20, weight: .regular)
        icon.widthAnchor.constraint(equalToConstant: 28).isActive = true
        label.stringValue = title
        label.font = .systemFont(ofSize: 13.5, weight: .semibold)
        sub.stringValue = detail
        sub.font = .systemFont(ofSize: 12)
        sub.textColor = .secondaryLabelColor
        sub.preferredMaxLayoutWidth = 260
        extra.orientation = .vertical
        extra.alignment = .leading
        let text = NSStackView(views: [label, sub, extra])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 3
        button.bezelStyle = .push
        button.controlSize = .regular
        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        setViews([icon, text, spacer, button], in: .leading)
        alignment = .top
        spacing = 12
        paint()
    }

    required init?(coder: NSCoder) { fatalError() }
}
