import AppKit
import Carbon
import ServiceManagement

/// Zero OCR: Xiaomi-OCR-0 as the Mac's text reader. One shortcut (⇧⌘2) for anything on screen, a
/// Liquid Glass card with everything else, History, Services and Quick Actions, Open With, a
/// zeroocr:// URL scheme for Shortcuts, and the `zocr` command. The model runs in a bundled
/// llama.cpp server (see Server).
@MainActor
final class App: NSObject, NSApplicationDelegate, NSMenuDelegate, NSMenuItemValidation, NSDraggingDestination {
    private var item: NSStatusItem!
    private var hotKeys: [HotKey] = []
    private let engineItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")

    func applicationDidFinishLaunching(_ note: Notification) {
        Prefs.register()
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let image = NSImage(systemSymbolName: "text.viewfinder", accessibilityDescription: "Zero OCR")
        image?.isTemplate = true
        item.button?.image = image
        item.menu = buildMenu()
        // Drop images or PDFs on the menu bar icon to read them.
        item.button?.window?.registerForDraggedTypes([.fileURL, .png, .tiff])
        item.button?.window?.delegate = self

        // ⇧⌘2 sits right next to the system's ⇧⌘3/4/5 screenshot shortcuts; ⇧⌘1 repeats the last area.
        let two = kVK_ANSI_2, one = kVK_ANSI_1
        hotKeys = [
            HotKey(keyCode: two, modifiers: cmdKey | shiftKey) { Reader.shared.capture(.text) },
            HotKey(keyCode: one, modifiers: cmdKey | shiftKey) { Reader.shared.repeatLast() },
            HotKey(keyCode: two, modifiers: cmdKey | shiftKey | optionKey) { Reader.shared.capture(.doc) },
            HotKey(keyCode: two, modifiers: cmdKey | shiftKey | controlKey) { Reader.shared.capture(.table) },
        ]

        NSApp.servicesProvider = self
        NSUpdateDynamicServices()
        NSAppleEventManager.shared().setEventHandler(self, andSelector: #selector(handleURL(_:reply:)),
                                                     forEventClass: AEEventClass(kInternetEventClass),
                                                     andEventID: AEEventID(kAEGetURL))
        Server.shared.startReaper()
        if Setup.shared.needed { Setup.shared.show() }
        suggestAppleSiliconEdition()

        // It replaces the system's text reader, so it starts with the Mac by default (once; Settings wins after).
        if !UserDefaults.standard.bool(forKey: "loginItemSet") {
            try? SMAppService.mainApp.register()
            UserDefaults.standard.set(true, forKey: "loginItemSet")
        }
    }

    func applicationWillTerminate(_ note: Notification) {
        Server.shared.stop()
    }

    // MARK: menu

    private func buildMenu() -> NSMenu {
        let m = NSMenu()
        m.delegate = self
        @discardableResult
        func add(_ title: String, _ action: Selector, _ key: String = "", _ mods: NSEvent.ModifierFlags = [],
                 symbol: String? = nil, tag: Int = 0, to menu: NSMenu? = nil) -> NSMenuItem {
            let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
            i.keyEquivalentModifierMask = mods
            i.target = self
            i.tag = tag
            if let symbol { i.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
            (menu ?? m).addItem(i)
            return i
        }
        add("Read Text", #selector(captureFromMenu(_:)), "2", [.command, .shift], symbol: "text.viewfinder", tag: 0)
        add("Read Same Area Again", #selector(repeatLast), "1", [.command, .shift], symbol: "arrow.clockwise")
        let readAs = NSMenu()
        add("Markdown", #selector(captureFromMenu(_:)), "2", [.command, .shift, .option], symbol: Mode.doc.symbol, tag: 1, to: readAs)
        add("Table", #selector(captureFromMenu(_:)), "2", [.command, .shift, .control], symbol: Mode.table.symbol, tag: 2, to: readAs)
        add("Formula", #selector(captureFromMenu(_:)), symbol: Mode.formula.symbol, tag: 3, to: readAs)
        let readAsItem = NSMenuItem(title: "Read As", action: nil, keyEquivalent: "")
        readAsItem.image = NSImage(systemSymbolName: "square.stack.3d.up", accessibilityDescription: nil)
        readAsItem.submenu = readAs
        m.addItem(readAsItem)
        m.addItem(.separator())
        add("Read Image on Clipboard", #selector(readClipboard), symbol: "doc.on.clipboard")
        add("Open Image or PDF…", #selector(openFile), "o", [.command], symbol: "folder")
        add("History", #selector(showHistory), "y", [.command], symbol: "clock.arrow.circlepath")
        m.addItem(.separator())
        engineItem.isEnabled = false
        m.addItem(engineItem)
        add("Settings…", #selector(showSettings), ",", [.command])
        add("About Zero OCR", #selector(about))
        add("Quit Zero OCR", #selector(NSApp.terminate(_:)), "q", [.command]).target = NSApp
        return m
    }

    func menuWillOpen(_ menu: NSMenu) {
        engineItem.title = !Store.ready ? "Model not downloaded" : Server.shared.isRunning
            ? "Xiaomi-OCR-0 · ready" : "Xiaomi-OCR-0 · asleep, wakes on use"
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool { true }

    private static let menuModes: [Mode] = [.text, .doc, .table, .formula]

    @objc private func captureFromMenu(_ sender: NSMenuItem) {
        let mode = App.menuModes[sender.tag]
        // Let the menu finish closing first.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { Reader.shared.capture(mode) }
    }

    @objc private func repeatLast() { DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { Reader.shared.repeatLast() } }
    @objc private func readClipboard() { Reader.shared.read(Imaging.clipboardImage(), mode: .text, app: "Clipboard") }
    @objc private func showHistory() { HistoryWindow.shared.show() }
    @objc private func showSettings() { SettingsWindow.shared.show() }

    @objc private func openFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image, .pdf]
        panel.allowsMultipleSelection = true
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK else { return }
        Reader.shared.read(files: panel.urls, mode: .text)
    }

    static func installCLI() {
        let path = CLI.install()
        let a = NSAlert()
        a.messageText = path.isEmpty ? "Couldn't install zocr" : "zocr is installed"
        a.informativeText = path.isEmpty ? "No writable folder on your PATH." : "\(path)\n\nTry: zocr --help"
        NSApp.activate(ignoringOtherApps: true)
        a.runModal()
    }

    /// Someone who downloaded the Intel edition onto an Apple silicon Mac hears about the faster one, once.
    private func suggestAppleSiliconEdition() {
        guard Edition.intel, Edition.translated, !UserDefaults.standard.bool(forKey: "toldAboutAppleSilicon") else { return }
        UserDefaults.standard.set(true, forKey: "toldAboutAppleSilicon")
        let a = NSAlert()
        a.messageText = "This Mac has Apple silicon"
        a.informativeText = "This is the Intel edition of Zero OCR, which runs here through Rosetta. The Apple silicon edition reads many times faster."
        a.addButton(withTitle: "Get the Apple Silicon Edition")
        a.addButton(withTitle: "Not Now")
        NSApp.activate(ignoringOtherApps: true)
        if a.runModal() == .alertFirstButtonReturn { NSWorkspace.shared.open(URL(string: "https://zero.lou15.com/#editions")!) }
    }

    @objc private func about() {
        NSApp.activate(ignoringOtherApps: true)
        let credits = NSAttributedString(
            string: "\(Edition.name) edition. Text recognition by Xiaomi-OCR-0 (Apache-2.0), run with llama.cpp (MIT). Everything stays on this Mac.\n\nzero.lou15.com",
            attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor])
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
    }

    // MARK: drop on the menu bar icon

    nonisolated func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }

    nonisolated func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pb = sender.draggingPasteboard
        MainActor.assumeIsolated { self.readPasteboard(pb, mode: Prefs.finderMode) }
        return true
    }

    // MARK: Services (right-click › Services in any app, Quick Actions in Finder)

    @objc func readText(_ pb: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString>) {
        readPasteboard(pb, mode: .text)
    }

    @objc func readTable(_ pb: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString>) {
        readPasteboard(pb, mode: .table)
    }

    @objc func readDocument(_ pb: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString>) {
        readPasteboard(pb, mode: .doc)
    }

    private func readPasteboard(_ pb: NSPasteboard, mode: Mode) {
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            return Reader.shared.read(files: urls, mode: mode)
        }
        for t in [NSPasteboard.PasteboardType.png, .tiff] {
            if let d = pb.data(forType: t) { return Reader.shared.read(Imaging.pages(from: d), mode: mode) }
        }
    }

    // MARK: Open With, and zeroocr:// links

    func application(_ app: NSApplication, open urls: [URL]) {
        Reader.shared.read(files: urls, mode: Prefs.finderMode)
    }

    /// zeroocr://capture?mode=table, zeroocr://repeat, zeroocr://clipboard, zeroocr://file?path=/x.png&mode=doc,
    /// zeroocr://history, zeroocr://settings
    @objc private func handleURL(_ event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
        guard let s = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let c = URLComponents(string: s) else { return }
        let q = Dictionary((c.queryItems ?? []).map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { a, _ in a })
        let mode = Mode(rawValue: q["mode"] ?? "") ?? .text
        switch c.host {
        case "capture": Reader.shared.capture(mode)
        case "repeat": Reader.shared.repeatLast()
        case "clipboard": Reader.shared.read(Imaging.clipboardImage(), mode: mode, app: "Clipboard")
        case "file": if let p = q["path"] { Reader.shared.read(files: [URL(fileURLWithPath: p)], mode: mode) }
        case "history": HistoryWindow.shared.show()
        case "settings": SettingsWindow.shared.show()
        default: break
        }
    }
}

extension App: NSWindowDelegate {}

if CLI.isInvocation(CommandLine.arguments) { CLI.run(CommandLine.arguments) }

let app = NSApplication.shared
let delegate = MainActor.assumeIsolated { App() }
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
