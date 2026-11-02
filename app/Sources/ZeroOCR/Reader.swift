import AppKit

/// One read from start to finish: selection (or a file), capture, the model streaming into the
/// island, and the result on the clipboard.
@MainActor
final class Reader {
    static let shared = Reader()

    private(set) var last: (text: String, html: String?, mode: Mode, seconds: Double, pages: Int)?
    private var stages: [Stage] = []
    private var active = false

    var busy: Bool { active }

    /// ⇧⌘2 and friends: the neon frame follows your drag, or picks the window you click.
    func capture(_ mode: Mode) {
        guard !active else { return }
        guard Capture.allowed else { return Setup.shared.show() }
        active = true
        Capture.prefetch()
        Task.detached { try? await Server.shared.warm() }   // loads while you select
        NSApp.activate(ignoringOtherApps: true)
        stages = NSScreen.screens.map { Stage(screen: $0) }
        for s in stages {
            s.onSelect = { [weak self, weak s] rect in
                guard let self, let s else { return }
                self.selected(rect, on: s, mode: mode)
            }
            s.show()
            s.beginSelecting()
        }
    }

    private func selected(_ rect: CGRect?, on stage: Stage, mode: Mode) {
        for s in stages where s !== stage { s.close() }
        stages = [stage]
        guard let rect else { active = false; stages = []; return }
        let lines = Int((rect.height / 22).rounded())
        stage.reading(lines: lines)
        Task {
            do {
                let img = try await Capture.image(of: rect, on: stage.screen)
                await run([img], mode: mode, on: stage)
            } catch {
                stage.finish(symbol: "exclamationmark.triangle.fill", title: "Couldn't capture", detail: error.localizedDescription, hold: 4)
                active = false
            }
        }
    }

    /// Files, Services, the clipboard and links: no selection, so the island grows straight out of the notch.
    func read(_ images: [CGImage], mode: Mode, from origin: CGRect? = nil) {
        guard !images.isEmpty else { return }
        guard Store.ready else { return Setup.shared.show() }
        if active { return }
        active = true
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main!
        let stage = Stage(screen: screen)
        stages = [stage]
        stage.show()
        if let origin { stage.beginFromRect(origin, lines: Int((origin.height / 22).rounded())) } else { stage.beginFromNotch(lines: 3) }
        Task { await run(images, mode: mode, on: stage) }
    }

    func read(files: [URL], mode: Mode, from origin: CGRect? = nil) {
        let urls = files.filter(Imaging.readable)
        read(urls.flatMap { Imaging.pages(from: $0) }, mode: mode, from: origin)
    }

    private func run(_ images: [CGImage], mode: Mode, on stage: Stage) async {
        stage.onClick = { [weak self] in self?.showLast() }
        stage.onClosed = { [weak self] in self?.stages.removeAll { $0 === stage } }
        let start = Date()
        var parts: [Shaped] = []
        do {
            for (i, img) in images.enumerated() {
                stage.status(images.count > 1 ? "Page \(i + 1) of \(images.count)" : Server.shared.isRunning ? "Reading" : "Waking the model")
                guard let png = Imaging.prepare(img) else { continue }
                let before = parts.map(\.text).joined(separator: "\n\n")
                let (raw, _) = try await Server.shared.read(png: png, mode: mode) { partial in
                    let shown = Shape.preview(partial, mode: mode)
                    Task { @MainActor in
                        stage.status(images.count > 1 ? "Page \(i + 1) of \(images.count)" : "Reading")
                        stage.update(text: before.isEmpty ? shown : before + "\n\n" + shown)
                    }
                }
                parts.append(Shape.apply(raw, mode: mode))
            }
        } catch {
            stage.finish(symbol: "exclamationmark.triangle.fill", title: "Couldn't read that", detail: error.localizedDescription, hold: 4.5)
            active = false
            return
        }
        active = false
        let text = parts.map(\.text).joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
        let seconds = Date().timeIntervalSince(start)
        guard !text.isEmpty else {
            stage.update(text: "")
            stage.finish(symbol: "text.magnifyingglass", title: "No text found", detail: "", hold: 2)
            return
        }
        // Tables paste as a real grid into Numbers, Excel, Pages and Notes; everywhere else gets plain text.
        let html = mode == .table && parts.count == 1 ? parts[0].html : nil
        Clipboard.put(text, html: html)
        last = (text, html, mode, seconds, images.count)
        stage.update(text: mode == .table ? text.replacingOccurrences(of: "\t", with: "   ") : text)
        let words = text.split(whereSeparator: \.isWhitespace).count
        let what = mode == .table ? "Copied table" : mode == .formula ? "Copied LaTeX" : words == 1 ? "Copied 1 word" : "Copied \(words) words"
        stage.markResult()
        stage.finish(symbol: "checkmark.circle.fill", title: what, detail: String(format: "%.1f s", seconds),
                     hold: min(5, 2.2 + CGFloat(words) / 60))
    }

    func showLast() {
        guard let l = last else { return }
        ResultWindow.shared.show(text: l.text, html: l.html, info: "\(l.mode.title)  ·  " + (l.pages > 1 ? "\(l.pages) pages  ·  " : "")
            + "\(l.text.split(whereSeparator: \.isWhitespace).count) words  ·  " + String(format: "%.1f s", l.seconds))
    }
}

enum Clipboard {
    static func put(_ text: String, html: String?) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        if let html { pb.setString(html, forType: .html) }
    }
}
