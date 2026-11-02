import AppKit
import Carbon
import ServiceManagement

/// Zero OCR: Xiaomi-OCR-0 as the Mac's text reader. A menu bar app with global shortcuts for screen
/// selections, Services for images and PDFs in any app, Open With in Finder, a zeroocr:// URL scheme
/// for Shortcuts, and the `zocr` command. The model runs in a bundled llama.cpp server (see Server).
@MainActor
final class App: NSObject, NSApplicationDelegate, NSMenuDelegate, NSMenuItemValidation {
    private var item: NSStatusItem!
    private var hotKeys: [HotKey] = []
    private let engineItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let loginItem = NSMenuItem(title: "Open at Login", action: #selector(toggleLogin), keyEquivalent: "")
    private let keepMenu = NSMenu()

    func applicationDidFinishLaunching(_ note: Notification) {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let image = NSImage(systemSymbolName: "text.viewfinder", accessibilityDescription: "Zero OCR")
        image?.isTemplate = true
        item.button?.image = image
        item.menu = buildMenu()

        // ⇧⌘2 sits right next to the system's ⇧⌘3/4/5 screenshot shortcuts.
        let two = kVK_ANSI_2
        hotKeys = [
            HotKey(keyCode: two, modifiers: cmdKey | shiftKey) { Reader.shared.capture(.text) },
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

        // It replaces the system's text reader, so it starts with the Mac by default (once; the menu wins after).
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
        func add(_ title: String, _ action: Selector, _ key: String = "", _ mods: NSEvent.ModifierFlags = [],
                 symbol: String? = nil, tag: Int = 0, to menu: NSMenu? = nil) {
            let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
            i.keyEquivalentModifierMask = mods
            i.target = self
            i.tag = tag
            if let symbol { i.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
            (menu ?? m).addItem(i)
        }
        let keys: [Mode: NSEvent.ModifierFlags] = [.text: [.command, .shift], .doc: [.command, .shift, .option],
                                                   .table: [.command, .shift, .control]]
        for (n, mode) in Mode.allCases.enumerated() {
            add("Capture \(mode.title)", #selector(captureFromMenu(_:)), keys[mode] != nil ? "2" : "",
                keys[mode] ?? [], symbol: mode.symbol, tag: n)
        }
        m.addItem(.separator())
        add("Read Image on Clipboard", #selector(readClipboard), symbol: "doc.on.clipboard")
        add("Open Image or PDF…", #selector(openFile), "o", [.command], symbol: "folder")
        add("Show Last Result", #selector(showLast), symbol: "text.alignleft")
        m.addItem(.separator())
        engineItem.isEnabled = false
        m.addItem(engineItem)
        let keep = NSMenuItem(title: "Keep Model Loaded", action: nil, keyEquivalent: "")
        for (title, secs) in [("1 Minute", 60.0), ("10 Minutes", 600.0), ("1 Hour", 3600.0), ("Always", 0.0)] {
            let i = NSMenuItem(title: title, action: #selector(setKeep(_:)), keyEquivalent: "")
            i.target = self
            i.representedObject = secs
            keepMenu.addItem(i)
        }
        keep.submenu = keepMenu
        m.addItem(keep)
        loginItem.target = self
        m.addItem(loginItem)
        add("Install Command Line Tool…", #selector(installCLI))
        add("Setup…", #selector(showSetup))
        m.addItem(.separator())
        add("About Zero OCR", #selector(about))
        add("Quit Zero OCR", #selector(NSApp.terminate(_:)), "q", [.command])
        m.items.last?.target = NSApp
        return m
    }

    func menuWillOpen(_ menu: NSMenu) {
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        engineItem.title = !Store.ready ? "Model not downloaded" : Server.shared.isRunning
            ? "Xiaomi-OCR-0 · loaded" : "Xiaomi-OCR-0 · asleep, wakes on use"
        for i in keepMenu.items { i.state = (i.representedObject as? Double) == Server.shared.keepLoaded ? .on : .off }
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        item.action == #selector(showLast) ? Reader.shared.last != nil : true
    }

    @objc private func captureFromMenu(_ sender: NSMenuItem) {
        let mode = Mode.allCases[sender.tag]
        // Let the menu finish closing first.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { Reader.shared.capture(mode) }
    }

    @objc private func readClipboard() { Reader.shared.read(Imaging.clipboardImage(), mode: .text) }

    @objc private func openFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image, .pdf]
        panel.allowsMultipleSelection = true
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK else { return }
        Reader.shared.read(files: panel.urls, mode: .text)
    }

    @objc private func showLast() { Reader.shared.showLast() }
    @objc private func showSetup() { Setup.shared.show() }

    @objc private func setKeep(_ sender: NSMenuItem) {
        UserDefaults.standard.set(sender.representedObject as? Double ?? 600, forKey: "keepLoaded")
    }

    @objc private func toggleLogin() {
        let s = SMAppService.mainApp
        if s.status == .enabled { try? s.unregister() } else { try? s.register() }
    }

    @objc private func installCLI() {
        let path = CLI.install()
        let a = NSAlert()
        a.messageText = path.isEmpty ? "Couldn't install zocr" : "zocr is installed"
        a.informativeText = path.isEmpty ? "No writable folder on your PATH." : "\(path)\n\nTry: zocr --help"
        NSApp.activate(ignoringOtherApps: true)
        a.runModal()
    }

    @objc private func about() {
        NSApp.activate(ignoringOtherApps: true)
        let credits = NSAttributedString(
            string: "Text recognition by Xiaomi-OCR-0 (Apache-2.0), run with llama.cpp (MIT). Everything stays on this Mac.\n\nzero.lou15.com",
            attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor])
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
    }

    // MARK: Services (right-click › Services in any app, Quick Actions in Finder)

    @objc func readText(_ pb: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString>) {
        servicesRead(pb, mode: .text)
    }

    @objc func readTable(_ pb: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString>) {
        servicesRead(pb, mode: .table)
    }

    @objc func readDocument(_ pb: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString>) {
        servicesRead(pb, mode: .doc)
    }

    private func servicesRead(_ pb: NSPasteboard, mode: Mode) {
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            return Reader.shared.read(files: urls, mode: mode)
        }
        for t in [NSPasteboard.PasteboardType.png, .tiff] {
            if let d = pb.data(forType: t) { return Reader.shared.read(Imaging.pages(from: d), mode: mode) }
        }
    }

    // MARK: Open With, and zeroocr:// links

    func application(_ app: NSApplication, open urls: [URL]) {
        Reader.shared.read(files: urls, mode: .text)
    }

    /// zeroocr://capture?mode=table, zeroocr://clipboard, zeroocr://file?path=/x.png&mode=doc
    /// (add &from=x,y,w,h, in screen points from the top left, to have the frame fly up from there)
    @objc private func handleURL(_ event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
        guard let s = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let c = URLComponents(string: s) else { return }
        let q = Dictionary((c.queryItems ?? []).map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { a, _ in a })
        let mode = Mode(rawValue: q["mode"] ?? "") ?? .text
        switch c.host {
        case "capture": Reader.shared.capture(mode)
        case "clipboard": Reader.shared.read(Imaging.clipboardImage(), mode: mode)
        case "file":
            guard let p = q["path"] else { return }
            var origin: CGRect?
            let v = (q["from"] ?? "").split(separator: ",").compactMap { Double($0) }
            if v.count == 4, let top = NSScreen.screens.first?.frame.maxY {
                origin = CGRect(x: v[0], y: top - v[1] - v[3], width: v[2], height: v[3])
            }
            Reader.shared.read(files: [URL(fileURLWithPath: p)], mode: mode, from: origin)
        default: break
        }
    }
}

if CLI.isInvocation(CommandLine.arguments) { CLI.run(CommandLine.arguments) }

let app = NSApplication.shared
let delegate = MainActor.assumeIsolated { App() }
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
