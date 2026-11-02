import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Every read, kept on this Mac: the text, how it was read, and the image it came from (so it can be
/// read again another way). Turn it off in Settings; Clear History deletes the files too.
struct Entry: Codable, Identifiable, Hashable {
    let id: UUID
    let date: Date
    var mode: String
    var text: String
    var html: String?
    var seconds: Double
    var app: String?

    var modeValue: Mode { Mode(rawValue: mode) ?? .text }
    var title: String {
        let first = text.split(separator: "\n").first.map(String.init) ?? ""
        return first.isEmpty ? "Empty" : String(first.prefix(80))
    }
    var words: Int { text.split(whereSeparator: \.isWhitespace).count }
}

@MainActor
final class History: ObservableObject {
    static let shared = History()
    @Published private(set) var entries: [Entry] = []
    @Published var selection: UUID?

    private let dir = Store.dir.appendingPathComponent("History", isDirectory: true)
    private var file: URL { dir.appendingPathComponent("history.json") }
    private let limit = 500

    init() {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let d = try? Data(contentsOf: file), let e = try? JSONDecoder().decode([Entry].self, from: d) { entries = e }
    }

    func imageURL(_ id: UUID) -> URL { dir.appendingPathComponent("\(id.uuidString).png") }

    @discardableResult
    func add(text: String, html: String?, mode: Mode, seconds: Double, image: Data?, app: String?) -> Entry {
        let e = Entry(id: UUID(), date: Date(), mode: mode.rawValue, text: text, html: html, seconds: seconds, app: app)
        guard Prefs.history else { return e }
        if let image { try? image.write(to: imageURL(e.id)) }
        entries.insert(e, at: 0)
        while entries.count > limit { remove(entries.last!.id) }
        save()
        return e
    }

    func update(_ id: UUID, text: String) {
        guard let i = entries.firstIndex(where: { $0.id == id }), entries[i].text != text else { return }
        entries[i].text = text
        entries[i].html = nil   // the grid no longer matches an edited text
        save()
    }

    func remove(_ id: UUID) {
        entries.removeAll { $0.id == id }
        try? FileManager.default.removeItem(at: imageURL(id))
        if selection == id { selection = entries.first?.id }
        save()
    }

    func clear() {
        for e in entries { try? FileManager.default.removeItem(at: imageURL(e.id)) }
        entries = []
        selection = nil
        save()
    }

    func image(_ id: UUID) -> NSImage? { NSImage(contentsOf: imageURL(id)) }

    private func save() {
        let e = entries
        let url = file
        DispatchQueue.global(qos: .utility).async {
            if let d = try? JSONEncoder().encode(e) { try? d.write(to: url, options: .atomic) }
        }
    }
}

// MARK: window

@MainActor
final class HistoryWindow {
    static let shared = HistoryWindow()
    private var window: NSWindow?

    func show(select id: UUID? = nil) {
        if let id { History.shared.selection = id } else if History.shared.selection == nil {
            History.shared.selection = History.shared.entries.first?.id
        }
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 860, height: 560),
                             styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
                             backing: .buffered, defer: true)
            w.title = "Zero OCR"
            w.titlebarAppearsTransparent = true
            w.isReleasedWhenClosed = false
            w.minSize = NSSize(width: 640, height: 400)
            w.contentView = NSHostingView(rootView: HistoryView().environmentObject(History.shared))
            w.center()
            w.setFrameAutosaveName("ZeroOCRHistory")
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct HistoryView: View {
    @EnvironmentObject var history: History
    @State private var query = ""

    private var filtered: [Entry] {
        query.isEmpty ? history.entries : history.entries.filter { $0.text.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $history.selection) {
                ForEach(filtered) { e in
                    Row(entry: e).tag(e.id)
                        .contextMenu {
                            Button("Copy") { Clipboard.put(e.text, html: e.html) }
                            Button("Delete", role: .destructive) { history.remove(e.id) }
                        }
                }
            }
            .searchable(text: $query, placement: .sidebar, prompt: "Search everything you read")
            .navigationSplitViewColumnWidth(min: 240, ideal: 280)
            .overlay {
                if history.entries.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "text.viewfinder").font(.system(size: 28)).foregroundStyle(.secondary)
                        Text("Nothing read yet").font(.headline)
                        Text("Press ⇧⌘2 and drag over any text.").font(.callout).foregroundStyle(.secondary)
                    }
                }
            }
        } detail: {
            if let id = history.selection, let e = history.entries.first(where: { $0.id == id }) {
                Detail(entry: e).id(e.id)
            } else {
                Text("Select a read").foregroundStyle(.secondary)
            }
        }
    }
}

private struct Row: View {
    let entry: Entry
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(entry.title).lineLimit(2).font(.system(size: 13, weight: .medium))
            HStack(spacing: 6) {
                Image(systemName: entry.modeValue.symbol)
                Text(entry.date, format: .relative(presentation: .named))
                if let app = entry.app { Text("· \(app)") }
            }
            .font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
    }
}

private struct Detail: View {
    @EnvironmentObject var history: History
    let entry: Entry
    @State private var text = ""
    @State private var showImage = false
    @State private var translating = false
    @State private var preview = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Label(entry.modeValue.title, systemImage: entry.modeValue.symbol).font(.headline)
                Text(entry.date.formatted(date: .abbreviated, time: .shortened)).foregroundStyle(.secondary)
                if let app = entry.app { Text("from \(app)").foregroundStyle(.secondary) }
                Spacer()
                Text("\(entry.words) words · \(String(format: "%.1f", entry.seconds)) s").foregroundStyle(.secondary)
            }
            .font(.callout)
            .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 10)

            if showImage, let img = history.image(entry.id) {
                Image(nsImage: img).resizable().scaledToFit().frame(maxHeight: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 10)).padding(.horizontal, 20).padding(.bottom, 10)
            }

            if preview {
                ScrollView {
                    RichText(text: text, mode: entry.modeValue, html: text == entry.text ? entry.html : nil, maxHeight: 4000)
                        .padding(.horizontal, 20)
                }
            } else {
                TextEditor(text: $text)
                    .font(entry.modeValue == .text ? .system(size: 14) : .system(size: 13, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 14)
                    .onChange(of: text) { _, t in history.update(entry.id, text: t) }
            }

            if translating { TranslationPane(text: text) }

            Divider()
            HStack(spacing: 8) {
                Button { Clipboard.put(text, html: entry.html); Sound.play("Pop") } label: { Label("Copy", systemImage: "doc.on.doc") }
                    .keyboardShortcut("c", modifiers: [.command, .shift])
                Group {
                    Button { translating.toggle() } label: { Label("Translate", systemImage: "translate") }.help("Translate")
                    Button { Speaker.shared.toggle(text) } label: { Label("Speak", systemImage: "speaker.wave.2") }.help("Speak")
                    Button { Pins.shared.pin(text) } label: { Label("Pin", systemImage: "pin") }.help("Pin to the screen")
                }
                .labelStyle(.iconOnly)
                if history.image(entry.id) != nil {
                    Menu {
                        ForEach(Mode.allCases, id: \.self) { m in
                            Button(m.title) { Reader.shared.reread(entry, as: m) }
                        }
                    } label: { Label("Read Again", systemImage: "arrow.clockwise") }
                    .fixedSize()
                    Toggle(isOn: $showImage) { Image(systemName: "photo") }.toggleStyle(.button).help("Show the image")
                }
                Spacer()
                if entry.modeValue != .text || RichText.wanted(entry.modeValue, text) {
                    Picker("", selection: $preview) {
                        Text("Source").tag(false)
                        Text("Formatted").tag(true)
                    }
                    .pickerStyle(.segmented).fixedSize()
                }
                Button { export() } label: { Image(systemName: "square.and.arrow.down") }.help("Save as a file")
                Button(role: .destructive) { history.remove(entry.id) } label: { Image(systemName: "trash") }.help("Delete")
            }
            .controlSize(.regular)
            .lineLimit(1)
            .padding(12)
        }
        .onAppear { text = entry.text; preview = entry.modeValue != .text }
    }

    private func export() {
        let p = NSSavePanel()
        let md = entry.modeValue == .doc
        p.allowedContentTypes = [md ? UTType(filenameExtension: "md") ?? .plainText : entry.modeValue == .table ? .tabSeparatedText : .plainText]
        p.nameFieldStringValue = String(entry.title.prefix(40)).replacingOccurrences(of: "/", with: "-") + (md ? ".md" : entry.modeValue == .table ? ".tsv" : ".txt")
        if p.runModal() == .OK, let url = p.url { try? text.write(to: url, atomically: true, encoding: .utf8) }
    }
}
