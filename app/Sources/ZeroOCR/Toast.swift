import AppKit
import SwiftUI

// MARK: glass

extension View {
    /// Liquid Glass on macOS 26, a material on older systems and in the lighter Intel edition.
    @ViewBuilder
    func glassCard(radius: CGFloat) -> some View {
        if !Edition.intel, #available(macOS 26.0, *) {
            self.glassEffect(.regular, in: .rect(cornerRadius: radius))
        } else {
            self.background(.regularMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(.white.opacity(0.12)))
        }
    }

    @ViewBuilder
    func glassButton() -> some View {
        if !Edition.intel, #available(macOS 26.0, *) { self.buttonStyle(.glass) } else { self.buttonStyle(.bordered) }
    }
}

struct GlassIconButton: View {
    let symbol: String
    var help = ""
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 11.5, weight: .semibold)).frame(width: 16, height: 16)
        }
        .glassButton()
        .buttonBorderShape(.circle)
        .controlSize(.small)
        .help(help)
    }
}

// MARK: model

@MainActor
final class ToastModel: ObservableObject {
    enum Phase { case reading, done, failed }
    @Published var phase = Phase.reading
    @Published var mode = Mode.text
    @Published var text = ""
    @Published var html: String?
    @Published var status = "Reading"
    @Published var title = ""
    @Published var detail = ""
    @Published var actions: [SmartAction] = []
    @Published var lines = 3
    @Published var visible = false
    @Published var expanded = false
    @Published var translating = false
    @Published var hovering = false
    @Published var copied = 0
    var entry: Entry?
    var canReread = false
    var reread: ((Mode) -> Void)?
    var dismiss: (() -> Void)?
}

// MARK: view

/// The card. It starts as a small glowing pill where the neon dot lands, springs open into the
/// full card, and keeps growing smoothly as text arrives.
struct ToastView: View {
    @ObservedObject var m: ToastModel
    var onFrame: (CGRect) -> Void = { _ in }
    @State private var shimmer = false

    private let open = Animation.spring(response: 0.55, dampingFraction: 0.78)

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            card
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { onFrame($0) }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .padding(16)
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 11) {
            if m.expanded {
                header.transition(.opacity.combined(with: .offset(y: -4)))
                content.transition(.opacity)
                if m.phase == .done { toolbar.transition(.opacity.combined(with: .offset(y: 6))) }
                if m.phase == .done, !m.actions.isEmpty { smart.transition(.opacity) }
            } else {
                Image(systemName: m.mode.symbol).font(.system(size: 15, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .transition(.opacity)
            }
        }
        .padding(m.expanded ? 16 : 0)
        .frame(width: m.expanded ? 360 : 44, alignment: .leading)
        .frame(minHeight: 44)
        .glassCard(radius: m.expanded ? 24 : 22)
        .scaleEffect(m.visible ? 1 : 0.35, anchor: .topTrailing)
        .opacity(m.visible ? 1 : 0)
        .blur(radius: m.visible ? 0 : 6)
        .animation(open, value: m.expanded)
        .animation(.spring(response: 0.38, dampingFraction: 0.7), value: m.visible)
        .animation(.spring(response: 0.4, dampingFraction: 0.86), value: m.phase)
        .animation(.spring(response: 0.4, dampingFraction: 0.86), value: m.translating)
        .animation(.easeOut(duration: 0.2), value: m.text.count / 60)
        .onHover { m.hovering = $0 }
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(iconTint.opacity(0.16))
                if m.phase == .reading {
                    ProgressView().controlSize(.small).scaleEffect(0.8)
                } else {
                    Image(systemName: m.phase == .done ? "checkmark" : "exclamationmark.triangle.fill")
                        .font(.system(size: 13, weight: .bold)).foregroundStyle(iconTint)
                        .symbolEffect(.bounce, value: m.copied)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(m.phase == .reading ? m.status : m.title).font(.system(size: 13.5, weight: .semibold))
                    .contentTransition(.numericText())
                Text(m.phase == .reading ? m.mode.title : m.detail).font(.system(size: 11.5)).foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            GlassIconButton(symbol: "xmark", help: "Close") { m.dismiss?() }
                .opacity(m.hovering || m.phase != .reading ? 1 : 0)
        }
    }

    private var iconTint: Color { m.phase == .failed ? .orange : m.phase == .done ? .green : .accentColor }

    @ViewBuilder
    private var content: some View {
        if m.phase == .reading && m.text.isEmpty {
            placeholder(m.lines)
        } else if !m.text.isEmpty {
            Group {
                // Tables render once the grid is complete; Markdown and formulas render live.
                if RichText.wanted(m.mode, m.text) && !(m.mode == .table && m.phase == .reading) {
                    RichText(text: m.text, mode: m.mode, html: m.html, maxHeight: m.translating ? 120 : 300)
                } else {
                    Text(m.mode == .table ? m.text.replacingOccurrences(of: "\t", with: "   ") : m.text)
                        .font(m.mode == .text ? .system(size: 13) : .system(size: 12, design: .monospaced))
                        .lineLimit(m.translating ? 3 : 8, reservesSpace: false)
                        .truncationMode(m.phase == .reading ? .head : .tail)
                        .foregroundStyle(.primary.opacity(0.92))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { openEditor() }
            .help("Click to edit")
            if m.phase == .reading { placeholder(1) }
            if m.translating, m.phase == .done {
                TranslationPane(text: m.text).padding(.horizontal, -20).padding(.vertical, -8).transition(.opacity)
            }
        }
    }

    /// Swooshing placeholder lines while the model reads.
    private func placeholder(_ n: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(0..<max(1, n), id: \.self) { i in
                GeometryReader { g in
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(.primary.opacity(0.07))
                        .overlay(alignment: .leading) {
                            LinearGradient(colors: [.clear, .primary.opacity(0.22), .clear], startPoint: .leading, endPoint: .trailing)
                                .frame(width: g.size.width * 0.55)
                                .offset(x: shimmer ? g.size.width * 1.1 : -g.size.width * 0.6)
                                .animation(.linear(duration: 1.25).repeatForever(autoreverses: false).delay(Double(i) * 0.14), value: shimmer)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                }
                .frame(width: [300.0, 268, 214, 286, 180][i % 5], height: 11)
            }
        }
        .onAppear { shimmer = true }
    }

    private var toolbar: some View {
        HStack(spacing: 6) {
            Button {
                Clipboard.put(m.text, html: m.html)
                Sound.play("Pop")
                m.copied += 1
            } label: {
                Label("Copy", systemImage: "doc.on.doc").font(.system(size: 12, weight: .medium))
            }
            .glassButton().controlSize(.small)
            GlassIconButton(symbol: "translate", help: "Translate") { m.translating.toggle() }
            GlassIconButton(symbol: "speaker.wave.2", help: "Read aloud") { Speaker.shared.toggle(m.text) }
            GlassIconButton(symbol: "pin", help: "Pin to screen") { Pins.shared.pin(m.text); m.dismiss?() }
            GlassIconButton(symbol: "square.and.pencil", help: "Edit, and see History") { openEditor() }
            Spacer(minLength: 0)
            if m.canReread {
                Menu {
                    ForEach(Mode.allCases.filter { $0 != m.mode }, id: \.self) { mode in
                        Button { m.reread?(mode) } label: { Label(mode.title, systemImage: mode.symbol) }
                    }
                } label: {
                    Text("Read as").font(.system(size: 12, weight: .medium))
                }
                .menuStyle(.button)
                .glassButton()
                .controlSize(.small)
                .fixedSize()
                .help("Read the same area again as a table, Markdown or a formula")
            }
        }
    }

    private var smart: some View {
        FlowRow(spacing: 6) {
            ForEach(m.actions) { a in
                Button { a.perform() } label: {
                    Label(a.label, systemImage: a.symbol).font(.system(size: 11.5, weight: .medium)).lineLimit(1)
                }
                .glassButton().controlSize(.small)
            }
        }
    }

    private func openEditor() {
        if let e = m.entry { HistoryWindow.shared.show(select: e.id) } else { HistoryWindow.shared.show() }
        m.dismiss?()
    }
}

/// Wrapping row of chips.
struct FlowRow: Layout {
    var spacing: CGFloat = 6
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let w = proposal.width ?? 328
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0
        for s in subviews {
            let z = s.sizeThatFits(.unspecified)
            if x + z.width > w, x > 0 { x = 0; y += row + spacing; row = 0 }
            x += z.width + spacing
            row = max(row, z.height)
        }
        return CGSize(width: w, height: y + row)
    }
    func placeSubviews(in b: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = b.minX, y = b.minY, row: CGFloat = 0
        for s in subviews {
            let z = s.sizeThatFits(.unspecified)
            if x + z.width > b.maxX, x > b.minX { x = b.minX; y += row + spacing; row = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(z))
            x += z.width + spacing
            row = max(row, z.height)
        }
    }
}

// MARK: window

/// The card lives in a fixed, transparent, non-activating panel in the top right corner, so SwiftUI
/// can animate it freely and it never takes focus. Only the card itself catches the mouse; the rest
/// of the panel lets clicks through to whatever is underneath.
@MainActor
final class Toast {
    static let shared = Toast()
    private let size = CGSize(width: 420, height: 820)
    private var panel: NSPanel?
    private(set) var model = ToastModel()
    private var ticker: Timer?
    private var hideAt: Date?
    private var screen: NSScreen?
    private var card: CGRect = .zero   // in the panel, top-left origin

    /// The card in global coordinates, for the neon rim.
    var cardFrame: CGRect? {
        guard let p = panel, p.isVisible, model.visible, card.width > 1 else { return nil }
        return CGRect(x: p.frame.minX + card.minX, y: p.frame.maxY - card.maxY, width: card.width, height: card.height)
    }

    /// Where the pill appears (global): the neon dot flies here.
    func landing(on screen: NSScreen) -> CGRect {
        let f = screen.visibleFrame
        return CGRect(x: f.maxX - 2 - 16 - 44, y: f.maxY - 2 - 16 - 44, width: 44, height: 44)
    }

    func begin(mode: Mode, lines: Int, screen: NSScreen, show: Bool) -> ToastModel {
        if model.visible { model.visible = false }
        let m = ToastModel()
        m.mode = mode
        m.lines = max(1, min(lines, 4))
        m.dismiss = { [weak self, weak m] in if let m { self?.dismiss(m) } }
        model = m
        self.screen = screen
        hideAt = nil
        card = .zero
        if panel == nil {
            let p = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = false
            p.level = .statusBar
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            p.isReleasedWhenClosed = false
            p.hidesOnDeactivate = false
            panel = p
        }
        let f = screen.visibleFrame
        panel?.setFrame(CGRect(x: f.maxX - 2 - size.width, y: f.maxY - 2 - size.height, width: size.width, height: size.height), display: false)
        let host = NSHostingView(rootView: ToastView(m: m) { [weak self] r in self?.card = r })
        host.sizingOptions = []   // the panel keeps its size; the card animates inside it
        panel?.contentView = host
        panel?.ignoresMouseEvents = true
        panel?.orderFrontRegardless()
        if show { appear() }
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: 1 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        return m
    }

    /// The pill pops in, then springs open into the card.
    func appear() {
        let m = model
        m.visible = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) { m.expanded = true }
    }

    func finish(_ m: ToastModel) {
        guard m === model else { return }
        hideAt = Date().addingTimeInterval(Prefs.toastSeconds + (m.phase == .failed ? 1.5 : 0) + min(3, Double(m.text.count) / 400))
    }

    private func tick() {
        // Clicks outside the card fall through to the app underneath.
        if let panel, let c = cardFrame { panel.ignoresMouseEvents = !c.insetBy(dx: -2, dy: -2).contains(NSEvent.mouseLocation) }
        guard let hideAt else { return }
        if model.hovering || model.translating { self.hideAt = max(hideAt, Date().addingTimeInterval(2.5)); return }
        if Date() > hideAt { dismiss(model) }
    }

    func dismiss(_ m: ToastModel) {
        guard m === model else { return }
        m.expanded = false
        hideAt = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { m.visible = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) { [weak self] in
            guard let self, m === self.model, !m.visible else { return }
            self.ticker?.invalidate()
            self.panel?.orderOut(nil)
        }
    }
}
