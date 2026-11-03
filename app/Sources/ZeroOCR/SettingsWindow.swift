import AppKit
import ServiceManagement
import SwiftUI

@MainActor
final class SettingsWindow {
    static let shared = SettingsWindow()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 460),
                             styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: true)
            w.title = "Zero OCR Settings"
            w.titlebarAppearsTransparent = true
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: SettingsView())
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct SettingsView: View {
    @AppStorage(Prefs.Key.sounds) private var sounds = true
    @AppStorage(Prefs.Key.neon) private var neon = true
    @AppStorage(Prefs.Key.toastSeconds) private var toastSeconds = 4.0
    @AppStorage(Prefs.Key.joinLines) private var joinLines = false
    @AppStorage(Prefs.Key.keepLoaded) private var keepLoaded = 600.0
    @AppStorage(Prefs.Key.history) private var history = true
    @AppStorage(Prefs.Key.translateTo) private var translateTo = "en"
    @AppStorage(Prefs.Key.finderMode) private var finderMode = Mode.text.rawValue
    @State private var login = SMAppService.mainApp.status == .enabled
    @State private var confirmClear = false

    private let languages = ["en", "nb", "sv", "da", "de", "fr", "es", "it", "pt", "nl", "pl", "uk", "ru", "tr", "ar", "hi", "zh", "ja", "ko"]

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    shortcut("⇧⌘2", "Read any area. Click a window to take all of it.")
                    shortcut("⇧⌘1", "Read the same area again.")
                    Text("Everything else is on the card that appears: Copy, Translate, Speak, Pin, and Read as Table, Markdown or Formula.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            } header: { Text("How to use") }

            Section("Feel") {
                Toggle("Neon frame and flight", isOn: $neon)
                Toggle("Sound when text is copied", isOn: $sounds)
                Picker("Card stays for", selection: $toastSeconds) {
                    Text("3 seconds").tag(3.0); Text("4 seconds").tag(4.0); Text("6 seconds").tag(6.0); Text("10 seconds").tag(10.0)
                }
            }

            Section("Reading") {
                Toggle("Join lines into paragraphs", isOn: $joinLines)
                Picker("Translate into", selection: $translateTo) {
                    ForEach(languages, id: \.self) { code in
                        Text(Locale.current.localizedString(forLanguageCode: code)?.capitalized ?? code).tag(code)
                    }
                }
                Picker("Finder Open With reads as", selection: $finderMode) {
                    ForEach(Mode.allCases, id: \.self) { Text($0.title).tag($0.rawValue) }
                }
                Picker("Keep the model loaded", selection: $keepLoaded) {
                    Text("1 minute").tag(60.0); Text("3 minutes").tag(180.0); Text("10 minutes").tag(600.0); Text("1 hour").tag(3600.0); Text("Always").tag(0.0)
                }
            }

            Section("Privacy") {
                Toggle("Keep a history of reads on this Mac", isOn: $history)
                HStack {
                    Text("\(History.shared.entries.count) reads saved").foregroundStyle(.secondary)
                    Spacer()
                    Button("Clear History…") { confirmClear = true }
                        .confirmationDialog("Delete every saved read and image?", isPresented: $confirmClear) {
                            Button("Clear History", role: .destructive) { History.shared.clear() }
                        }
                }
            }

            Section("System") {
                Toggle("Open at login", isOn: $login)
                    .onChange(of: login) { _, on in
                        if on { try? SMAppService.mainApp.register() } else { try? SMAppService.mainApp.unregister() }
                    }
                HStack {
                    Text("Command line tool")
                    Spacer()
                    Button("Install zocr") { App.installCLI() }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 500)
        .frame(minHeight: 460)
    }

    private func shortcut(_ keys: String, _ what: String) -> some View {
        HStack(spacing: 12) {
            Text(keys)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                .frame(width: 64, alignment: .leading)
            Text(what)
        }
    }
}
