import AppKit

/// One read from start to finish: selection (or a file), capture, the model streaming into the toast,
/// the result on the clipboard and in History.
@MainActor
final class Reader {
    static let shared = Reader()

    private var stages: [Stage] = []
    private var active = false
    /// The last selected area, for ⇧⌘1.
    private var lastArea: (rect: CGRect, screen: NSScreen)?

    var lastEntry: Entry? { History.shared.entries.first }

    // MARK: entry points

    /// ⇧⌘2: the neon frame follows your drag, or picks the window you click.
    func capture(_ mode: Mode) {
        guard !active else { return }
        guard Store.ready else { return Setup.shared.show() }
        active = true
        let app = NSWorkspace.shared.frontmostApplication?.localizedName
        Task {
            guard await Capture.check() else { active = false; return Setup.shared.show(permission: true) }
            Capture.prefetch()
            Task.detached { try? await Server.shared.warm() }   // loads while you select
            NSApp.activate(ignoringOtherApps: true)
            stages = NSScreen.screens.map { Stage(screen: $0) }
            for s in stages {
                s.onSelect = { [weak self, weak s] rect in
                    guard let self, let s else { return }
                    self.selected(rect, on: s, mode: mode, app: app)
                }
                s.show()
                s.beginSelecting()
            }
        }
    }

    /// ⇧⌘1: the same area again (subtitles, a live dashboard, a game).
    func repeatLast() {
        guard let area = lastArea, NSScreen.screens.contains(area.screen) else { return capture(.text) }
        guard !active else { return }
        active = true
        let mode = Mode(rawValue: UserDefaults.standard.string(forKey: "lastMode") ?? "") ?? .text
        let app = NSWorkspace.shared.frontmostApplication?.localizedName
        Task {
            guard await Capture.check() else { active = false; return Setup.shared.show(permission: true) }
            Capture.prefetch()
            let stage = Stage(screen: area.screen)
            stages = [stage]
            stage.show()
            stage.replay(area.rect)
            await go(area.rect, on: stage, mode: mode, app: app)
        }
    }

    private func selected(_ rect: CGRect?, on stage: Stage, mode: Mode, app: String?) {
        for s in stages where s !== stage { s.close() }
        stages = [stage]
        guard let rect else { active = false; stages = []; return }
        lastArea = (rect, stage.screen)
        Task { await go(rect, on: stage, mode: mode, app: app) }
    }

    private func go(_ rect: CGRect, on stage: Stage, mode: Mode, app: String?) async {
        UserDefaults.standard.set(mode.rawValue, forKey: "lastMode")
        let toast = Toast.shared.begin(mode: mode, lines: Int((rect.height / 22).rounded()), screen: stage.screen, show: !Prefs.neon)
        stage.target = { Toast.shared.cardFrame ?? Toast.shared.landing(on: stage.screen) }
        stage.onLanded = { Toast.shared.appear() }
        do {
            let img = try await Capture.image(of: rect, on: stage.screen)
            await run([img], mode: mode, toast: toast, stage: stage, app: app)
        } catch {
            Toast.shared.appear()
            fail(toast, stage: stage, "Couldn't capture", error)
        }
    }

    /// Files, Services, the clipboard and links: no selection, so the toast simply appears.
    func read(_ images: [CGImage], mode: Mode, app: String? = nil) {
        guard !images.isEmpty else { return }
        guard Store.ready else { return Setup.shared.show() }
        guard !active else { return }
        active = true
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main!
        let toast = Toast.shared.begin(mode: mode, lines: 3, screen: screen, show: true)
        let stage = Stage(screen: screen)
        stage.target = { Toast.shared.cardFrame ?? Toast.shared.landing(on: screen) }
        stages = [stage]
        stage.show()
        stage.rimOnly()
        Task { await run(images, mode: mode, toast: toast, stage: stage, app: app) }
    }

    func read(files: [URL], mode: Mode) {
        let urls = files.filter(Imaging.readable)
        guard !urls.isEmpty else { return }
        read(urls.flatMap { Imaging.pages(from: $0) }, mode: mode, app: urls.count == 1 ? urls[0].lastPathComponent : "\(urls.count) files")
    }

    /// Read a History entry's image again in another mode.
    func reread(_ entry: Entry, as mode: Mode) {
        guard let img = History.shared.image(entry.id)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        read([img], mode: mode, app: entry.app)
    }

    // MARK: the read

    private func run(_ images: [CGImage], mode: Mode, toast: ToastModel, stage: Stage, app: String?) async {
        let start = Date()
        var parts: [Shaped] = []
        var firstPNG: Data?
        toast.status = Server.shared.isRunning ? "Reading" : "Waking the model"
        do {
            for (i, img) in images.enumerated() {
                let page = images.count > 1 ? "Page \(i + 1) of \(images.count)" : nil
                if let page { toast.status = page }
                guard let png = Imaging.prepare(img) else { continue }
                if firstPNG == nil { firstPNG = png }
                let before = parts.map(\.text).joined(separator: "\n\n")
                let (raw, _) = try await Server.shared.read(png: png, mode: mode) { partial in
                    let shown = Shape.preview(partial, mode: mode)
                    Task { @MainActor in
                        toast.status = page ?? "Reading"
                        toast.text = before.isEmpty ? shown : before + "\n\n" + shown
                    }
                }
                parts.append(Shape.apply(raw, mode: mode))
            }
        } catch {
            fail(toast, stage: stage, "Couldn't read that", error)
            return
        }
        active = false
        var text = parts.map(\.text).joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
        if mode == .text, Prefs.joinLines { text = Smart.joinLines(text) }
        let seconds = Date().timeIntervalSince(start)
        stage.finished()
        toast.canReread = true
        guard !text.isEmpty else {
            toast.text = ""
            toast.title = "No text found"
            toast.detail = "Try a larger area, or Read as Table or Formula."
            toast.phase = .done
            toast.reread = { [weak self] m in if let first = images.first { self?.read([first], mode: m, app: app) } }
            Toast.shared.finish(toast)
            return
        }
        // Tables paste as a real grid into Numbers, Excel, Pages and Notes; everywhere else gets plain text.
        let html = mode == .table && parts.count == 1 ? parts[0].html : nil
        Clipboard.put(text, html: html)
        Sound.play("Pop")
        let entry = History.shared.add(text: text, html: html, mode: mode, seconds: seconds, image: firstPNG, app: app)
        let words = text.split(whereSeparator: \.isWhitespace).count
        toast.entry = entry
        toast.text = text
        toast.html = html
        toast.title = mode == .table ? "Copied table" : mode == .formula ? "Copied LaTeX" : words == 1 ? "Copied 1 word" : "Copied \(words) words"
        toast.detail = [String(format: "%.1f s", seconds), app.map { "from \($0)" }, images.count > 1 ? "\(images.count) pages" : nil]
            .compactMap { $0 }.joined(separator: " · ")
        toast.actions = Smart.actions(in: text, image: images.first)
        toast.reread = { [weak self] m in if let first = images.first { self?.read([first], mode: m, app: app) } }
        toast.phase = .done
        Toast.shared.finish(toast)
    }

    private func fail(_ toast: ToastModel, stage: Stage, _ title: String, _ error: Error) {
        active = false
        stage.finished()
        toast.title = title
        toast.detail = error.localizedDescription
        toast.phase = .failed
        Toast.shared.finish(toast)
    }

    func showLast() { HistoryWindow.shared.show(select: lastEntry?.id) }
}

enum Clipboard {
    static func put(_ text: String, html: String?) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        if let html { pb.setString(html, forType: .html) }
    }
}
