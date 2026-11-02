import AppKit
import QuartzCore

/// One screen's overlay: the neon frame while you select, the flight up to the notch, and the island
/// that shows the text as it is read. Everything is one borderless window above the menu bar, drawn
/// by GlowView plus a few layer-backed views, driven by the display link.
final class Stage: NSObject {
    enum Phase { case hover, selecting, captured, collapse, fly, island, retract, closed }

    let screen: NSScreen
    let window: StagePanel
    private let root = FlippedView()
    private let glow: GlowView
    private let island = IslandView()
    private var link: CADisplayLink?
    private var last: CFTimeInterval = 0
    private var clock: CGFloat = 0
    private var phaseStart: CGFloat = 0

    private(set) var phase: Phase = .hover
    // Frame edges in view points (flipped): left, top, right, bottom.
    private var l = Spring(0), t = Spring(0), r = Spring(0), b = Spring(0)
    private var gain = Spring(0), fill = Spring(0), content = Spring(0), pulse = Spring(0)
    private var hoverRect: CGRect?
    private var selection: CGRect = .zero
    private var linger: CGFloat = 2.6
    private var hovering = false
    private let catcher: ClickCatcher

    var onSelect: ((CGRect?) -> Void)?   // global (bottom-left) rect of the selection, nil when cancelled
    var onClick: (() -> Void)?
    var onClosed: (() -> Void)?

    /// Height of the notch (or 0), and the island's size.
    private var notch: CGRect {
        let f = screen.frame
        let h = screen.safeAreaInsets.top
        guard h > 0, let la = screen.auxiliaryTopLeftArea, let ra = screen.auxiliaryTopRightArea else {
            return CGRect(x: f.width / 2 - 90, y: 0, width: 180, height: 0)
        }
        let w = f.width - la.width - ra.width
        return CGRect(x: la.width, y: 0, width: w, height: h)
    }

    init(screen: NSScreen) {
        self.screen = screen
        window = StagePanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false, screen: screen)
        glow = GlowView(frame: CGRect(origin: .zero, size: screen.frame.size))
        catcher = ClickCatcher()
        super.init()
        window.setFrame(screen.frame, display: false)
        window.level = .screenSaver
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        window.isReleasedWhenClosed = false
        root.frame = CGRect(origin: .zero, size: screen.frame.size)
        glow.autoresizingMask = [.width, .height]
        root.addSubview(glow)
        root.addSubview(island)
        island.alphaValue = 0
        window.contentView = root
        window.stage = self
        catcher.onClick = { [weak self] in self?.onClick?() }
        catcher.onHover = { [weak self] in self?.hovering = $0 }
    }

    func show() {
        window.orderFrontRegardless()
        let link = window.displayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func close() {
        guard phase != .closed else { return }
        phase = .closed
        link?.invalidate()
        link = nil
        catcher.orderOut(nil)
        window.orderOut(nil)
        onClosed?()
    }

    // MARK: selection

    func beginSelecting() {
        phase = .hover
        window.ignoresMouseEvents = false
        window.acceptsMouseMovedEvents = true
        window.makeKeyAndOrderFront(nil)
        NSCursor.crosshair.push()
    }

    private func toView(_ global: CGRect) -> CGRect {
        CGRect(x: global.minX - screen.frame.minX, y: screen.frame.maxY - global.maxY, width: global.width, height: global.height)
    }

    private func toGlobal(_ v: CGRect) -> CGRect {
        CGRect(x: v.minX + screen.frame.minX, y: screen.frame.maxY - v.maxY, width: v.width, height: v.height)
    }

    private var dragStart: CGPoint?

    func mouseMoved(_ p: CGPoint) {
        guard phase == .hover else { return }
        hoverRect = Stage.windowRect(at: window.convertPoint(toScreen: p)).map(toView)
    }

    func mouseDown(_ p: CGPoint) {
        dragStart = root.convert(p, from: nil)
    }

    func mouseDragged(_ p: CGPoint) {
        guard let s = dragStart else { return }
        let q = root.convert(p, from: nil)
        let rect = CGRect(x: min(s.x, q.x), y: min(s.y, q.y), width: abs(q.x - s.x), height: abs(q.y - s.y))
        if phase == .hover, rect.width + rect.height > 6 { phase = .selecting }
        if phase == .selecting { selection = rect }
    }

    func mouseUp(_ p: CGPoint) {
        defer { dragStart = nil }
        if phase == .selecting, selection.width > 3, selection.height > 3 {
            finishSelecting(selection)
        } else if let h = hoverRect {
            selection = h
            finishSelecting(h)
        }
    }

    func cancelSelecting() {
        NSCursor.pop()
        onSelect?(nil)
        close()
    }

    private func finishSelecting(_ rect: CGRect) {
        NSCursor.pop()
        window.ignoresMouseEvents = true
        // Snap the springs onto the selection so the flight starts exactly where it was drawn.
        (l, t, r, b) = (Spring(rect.minX), Spring(rect.minY), Spring(rect.maxX), Spring(rect.maxY))
        phase = .captured
        phaseStart = clock
        pulse.x = 1
        onSelect?(toGlobal(rect))
    }

    /// The topmost normal window under a global point, for click-to-pick.
    static func windowRect(at p: CGPoint) -> CGRect? {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]], let primary = NSScreen.screens.first else { return nil }
        let me = getpid()
        for w in list {
            guard (w[kCGWindowLayer as String] as? Int) == 0, (w[kCGWindowOwnerPID as String] as? pid_t) != me,
                  let bd = w[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = bd["X"], let y = bd["Y"], let wd = bd["Width"], let ht = bd["Height"], wd > 40, ht > 30
            else { continue }
            let rect = CGRect(x: x, y: primary.frame.maxY - y - ht, width: wd, height: ht)
            if rect.contains(p) { return rect }
        }
        return nil
    }

    // MARK: reading

    /// A read that starts from a known rectangle on screen (global coordinates): it flies from there.
    func beginFromRect(_ global: CGRect, lines: Int) {
        let rect = toView(global)
        selection = rect
        (l, t, r, b) = (Spring(rect.minX), Spring(rect.minY), Spring(rect.maxX), Spring(rect.maxY))
        island.prepare(lines: lines, topInset: notch.height)
        phase = .captured
        phaseStart = clock
        pulse.x = 1
    }

    /// For reads that start without a selection (files, clipboard, Services): the island grows out of the notch.
    func beginFromNotch(lines: Int) {
        let n = notch
        (l, t, r, b) = (Spring(n.midX - 10), Spring(0), Spring(n.midX + 10), Spring(max(n.height, 8)))
        island.prepare(lines: lines, topInset: notch.height)
        phase = .island
        phaseStart = clock
    }

    func reading(lines: Int) { island.prepare(lines: lines, topInset: notch.height) }
    func update(text: String) { island.stream(text) }
    func status(_ s: String) { island.status = s }

    func finish(symbol: String, title: String, detail: String, hold: CGFloat) {
        island.finish(symbol: symbol, title: title, detail: detail)
        linger = hold
        phaseStart = clock
        finished = true
    }

    private var finished = false

    // MARK: animation

    private var islandRect: CGRect {
        let n = notch
        let size = island.fittingSize(width: max(n.width + 90, 400))
        return CGRect(x: n.midX - size.width / 2, y: 0, width: size.width, height: size.height)
    }

    @objc private func tick(_ link: CADisplayLink) {
        let now = link.timestamp
        let dt = CGFloat(last == 0 ? 1 / 120 : min(max(now - last, 0), 1 / 20))
        last = now
        clock += dt
        let since = clock - phaseStart
        let n = notch
        var radiusTop: CGFloat = 10, radiusBottom: CGFloat = 10
        var outer: Float = 0.35

        switch phase {
        case .hover:
            if let h = hoverRect {
                l.step(to: h.minX, dt: dt, omega: 24); t.step(to: h.minY, dt: dt, omega: 24)
                r.step(to: h.maxX, dt: dt, omega: 24); b.step(to: h.maxY, dt: dt, omega: 24)
                if gain.x < 0.01 { (l, t, r, b) = (Spring(h.minX), Spring(h.minY), Spring(h.maxX), Spring(h.maxY)) }
            }
            gain.step(to: hoverRect == nil ? 0 : 0.42, dt: dt, omega: 14)
        case .selecting:
            (l, t, r, b) = (Spring(selection.minX), Spring(selection.minY), Spring(selection.maxX), Spring(selection.maxY))
            gain.step(to: 1, dt: dt, omega: 20)
        case .captured:
            gain.step(to: 1, dt: dt, omega: 20)
            if since > 0.14 { phase = .collapse; phaseStart = clock }
        case .collapse:
            let c = CGPoint(x: (l.x + r.x) / 2, y: (t.x + b.x) / 2)
            l.step(to: c.x - 7, dt: dt, omega: 15); r.step(to: c.x + 7, dt: dt, omega: 15)
            t.step(to: c.y - 7, dt: dt, omega: 15); b.step(to: c.y + 7, dt: dt, omega: 15)
            gain.step(to: 1.25, dt: dt, omega: 10)
            radiusTop = min(r.x - l.x, b.x - t.x) / 2; radiusBottom = radiusTop
            outer = 0.35 + Float(max(0, 1 - (r.x - l.x) / 120)) * 0.9
            if r.x - l.x < 26, b.x - t.x < 26 { phase = .fly; phaseStart = clock }
        case .fly:
            // The leading edge pulls ahead and the trailing one catches up, so the dot stretches
            // into a streak on the way up, like the frame is being dragged into the notch.
            let target = CGPoint(x: n.midX, y: max(n.height / 2, 9))
            l.step(to: target.x - 7, dt: dt, omega: 10.5); r.step(to: target.x + 7, dt: dt, omega: 10.5)
            t.step(to: target.y - 7, dt: dt, omega: 15.5); b.step(to: target.y + 7, dt: dt, omega: 8.2)
            gain.step(to: 1.3, dt: dt, omega: 10)
            radiusTop = min(r.x - l.x, b.x - t.x) / 2; radiusBottom = radiusTop
            outer = 1.2
            if abs(t.x - (target.y - 7)) < 10, abs((l.x + r.x) / 2 - target.x) < 14 {
                phase = .island; phaseStart = clock
                island.layout(width: islandRect.width)
            }
        case .island:
            let ir = islandRect
            l.step(to: ir.minX, dt: dt, omega: 13, damping: 0.78); r.step(to: ir.maxX, dt: dt, omega: 13, damping: 0.78)
            t.step(to: ir.minY, dt: dt, omega: 16); b.step(to: ir.maxY, dt: dt, omega: 12, damping: 0.74)
            fill.step(to: 1, dt: dt, omega: 14)
            let w = r.x - l.x, h = b.x - t.x
            content.step(to: w > ir.width * 0.8 && h > ir.height * 0.6 ? 1 : 0, dt: dt, omega: 18)
            // Breathing while it reads, a pulse when the text lands.
            let breathe: CGFloat = finished ? 0 : 0.1 * sin(clock * 3.2)
            gain.step(to: (finished ? 0.95 : 1.05) + breathe + pulse.x * 0.8, dt: dt, omega: 12)
            radiusTop = min(min(w, h) / 2, max(0, t.x) + 6)
            radiusBottom = min(min(w, h) / 2, 22)
            outer = 0.45
            catcher.place(over: toGlobal(CGRect(x: l.x, y: t.x, width: w, height: h)), level: window.level + 1,
                          visible: finished && content.x > 0.9)
            if finished, !hovering, since > linger { phase = .retract; phaseStart = clock }
        case .retract:
            let target = CGRect(x: n.midX - n.width / 2, y: 0, width: n.width, height: max(n.height, 0))
            l.step(to: target.minX, dt: dt, omega: 14); r.step(to: target.maxX, dt: dt, omega: 14)
            t.step(to: target.minY, dt: dt, omega: 14); b.step(to: target.maxY, dt: dt, omega: 15)
            content.step(to: 0, dt: dt, omega: 26)
            gain.step(to: 0, dt: dt, omega: 9)
            fill.step(to: n.height > 0 ? 1 : 0, dt: dt, omega: 9)
            let w = r.x - l.x, h = b.x - t.x
            radiusTop = 0; radiusBottom = min(min(w, h) / 2, 22)
            catcher.orderOut(nil)
            if since > 0.55 { close(); return }
        case .closed:
            return
        }
        pulse.step(to: 0, dt: dt, omega: 6)

        let rect = CGRect(x: l.x, y: t.x, width: max(r.x - l.x, 1), height: max(b.x - t.x, 1))
        glow.state = GlowState(rect: rect, radii: (radiusTop, radiusTop, radiusBottom, radiusBottom),
                               gain: Float(max(gain.x, 0)), fill: Float(min(max(fill.x, 0), 1)), outer: outer,
                               rot: Float(clock * 0.14))
        glow.render()
        island.frame = rect
        island.alphaValue = min(max(content.x, 0), 1)
        island.tick(clock)
    }

    func markResult() { pulse.x = 1 }
}

/// Island content: swooshing placeholder lines while reading, then the text as it streams in,
/// then a one-line result footer.
final class IslandView: NSView {
    private let text = NSTextField(wrappingLabelWithString: "")
    private let footerIcon = NSImageView()
    private let footer = NSTextField(labelWithString: "")
    private var bars: [CALayer] = []
    private var shimmers: [CAGradientLayer] = []
    private var lines = 3
    private var topInset: CGFloat = 0
    private var streamed = ""
    private var done = false
    private var width: CGFloat = 400
    var status = "" { didSet { if !done { footer.stringValue = status } } }

    override var isFlipped: Bool { true }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        text.font = .systemFont(ofSize: 13, weight: .medium)
        text.textColor = NSColor(white: 1, alpha: 0.94)
        text.maximumNumberOfLines = 6
        text.lineBreakMode = .byTruncatingHead
        text.cell?.truncatesLastVisibleLine = true
        footer.font = .systemFont(ofSize: 11.5, weight: .medium)
        footer.textColor = NSColor(white: 1, alpha: 0.55)
        footerIcon.symbolConfiguration = .init(pointSize: 12, weight: .semibold)
        footerIcon.contentTintColor = NSColor(white: 1, alpha: 0.85)
        for v in [text, footer, footerIcon] { addSubview(v) }
    }

    required init?(coder: NSCoder) { fatalError() }

    func prepare(lines n: Int, topInset inset: CGFloat) {
        lines = max(1, min(n, 5))
        topInset = inset
        streamed = ""
        done = false
        text.stringValue = ""
        footer.stringValue = status
        footerIcon.image = nil
        bars.forEach { $0.removeFromSuperlayer() }
        bars = []
        shimmers = []
        for i in 0..<lines {
            let bar = CALayer()
            bar.backgroundColor = NSColor(white: 1, alpha: 0.075).cgColor
            bar.cornerRadius = 5
            bar.masksToBounds = true
            let s = CAGradientLayer()
            s.startPoint = CGPoint(x: 0, y: 0.5)
            s.endPoint = CGPoint(x: 1, y: 0.5)
            s.colors = [NSColor(white: 1, alpha: 0).cgColor, NSColor(white: 1, alpha: 0.32).cgColor, NSColor(white: 1, alpha: 0).cgColor]
            bar.addSublayer(s)
            layer?.addSublayer(bar)
            bars.append(bar)
            shimmers.append(s)
            bar.setValue(CGFloat(0.55 + 0.4 * CGFloat((i * 7919 % 13)) / 13), forKey: "widthFraction")
        }
        needsLayout = true
    }

    func layout(width w: CGFloat) { width = w }

    func stream(_ s: String) {
        streamed = s
        // Tabs (table cells) line up on even stops, digits stay the same width.
        let p = NSMutableParagraphStyle()
        p.tabStops = []
        p.defaultTabInterval = 64
        p.lineBreakMode = .byWordWrapping
        text.attributedStringValue = NSAttributedString(string: s, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor(white: 1, alpha: 0.94), .paragraphStyle: p,
        ])
        text.lineBreakMode = .byTruncatingHead
        needsLayout = true
    }

    func finish(symbol: String, title: String, detail: String) {
        done = true
        footerIcon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        footer.stringValue = detail.isEmpty ? title : "\(title)  ·  \(detail)"
        needsLayout = true
    }

    private let pad: CGFloat = 20

    private var textHeight: CGFloat {
        guard !streamed.isEmpty else { return 0 }
        text.preferredMaxLayoutWidth = width - 2 * pad
        return min(ceil(text.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: width - 2 * pad, height: 400)).height ?? 18), 6 * 17.5)
    }

    /// Placeholder lines still waiting for text.
    private var barsLeft: Int {
        if done { return 0 }
        let got = streamed.isEmpty ? 0 : max(1, Int((textHeight / 17).rounded()))
        return max(streamed.isEmpty ? lines : 1, lines - got)
    }

    func fittingSize(width w: CGFloat) -> CGSize {
        width = w
        let bars = CGFloat(barsLeft)
        var h = topInset + 14 + textHeight
        if bars > 0 { h += (textHeight > 0 ? 8 : 0) + bars * 11 + (bars - 1) * 9 }
        h += 12 + 16 + 14
        return CGSize(width: w, height: max(h, topInset + 44))
    }

    override func layout() {
        super.layout()
        var y = topInset + 14
        let th = textHeight
        text.frame = CGRect(x: pad, y: y, width: bounds.width - 2 * pad, height: th)
        y += th + (th > 0 ? 8 : 0)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let left = barsLeft
        for (i, bar) in bars.enumerated() {
            let frac = bar.value(forKey: "widthFraction") as? CGFloat ?? 0.8
            let visible = i < left
            bar.opacity = visible ? 1 : 0
            let w = (bounds.width - 2 * pad) * (i == left - 1 && left > 1 ? frac * 0.7 : frac)
            bar.frame = CGRect(x: pad, y: y + CGFloat(i) * 20, width: max(w, 20), height: 11)
            shimmers[i].frame = CGRect(x: 0, y: 0, width: bar.frame.width * 0.6, height: 11)
        }
        CATransaction.commit()
        let fy = bounds.height - 14 - 16
        let hasIcon = footerIcon.image != nil
        footerIcon.frame = CGRect(x: pad, y: fy, width: hasIcon ? 16 : 0, height: 16)
        footer.frame = CGRect(x: pad + (hasIcon ? 21 : 0), y: fy, width: bounds.width - 2 * pad - 21, height: 16)
    }

    /// Each placeholder line has its own light sweeping across it, a little behind the one above.
    func tick(_ clock: CGFloat) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (i, s) in shimmers.enumerated() {
            guard let bar = bars[safe: i] else { continue }
            let w = bar.bounds.width
            let p = (clock * 0.85 - CGFloat(i) * 0.13).truncatingRemainder(dividingBy: 1.25) / 1.25
            s.frame.origin.x = -s.frame.width + p * (w + s.frame.width)
        }
        CATransaction.commit()
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}

final class FlippedView: NSView {
    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// The overlay window; it forwards the selection gestures to its stage.
final class StagePanel: NSPanel {
    weak var stage: Stage?
    override var canBecomeKey: Bool { true }

    override func mouseMoved(with e: NSEvent) { stage?.mouseMoved(e.locationInWindow) }
    override func mouseDown(with e: NSEvent) { stage?.mouseDown(e.locationInWindow) }
    override func mouseDragged(with e: NSEvent) { stage?.mouseDragged(e.locationInWindow) }
    override func mouseUp(with e: NSEvent) { stage?.mouseUp(e.locationInWindow) }
    override func keyDown(with e: NSEvent) {
        if e.keyCode == 53 { stage?.cancelSelecting() } else { super.keyDown(with: e) }   // Esc
    }
    override func rightMouseDown(with e: NSEvent) { stage?.cancelSelecting() }
}

/// A transparent window over the finished island, so it can be clicked (opens the editor) and
/// hovered (keeps it open) while the rest of the overlay stays click-through.
final class ClickCatcher: NSPanel {
    var onClick: (() -> Void)?
    var onHover: ((Bool) -> Void)?
    private var area: NSTrackingArea?

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = NSColor(white: 0, alpha: 0.001)
        hasShadow = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isReleasedWhenClosed = false
    }

    func place(over rect: CGRect, level: NSWindow.Level, visible: Bool) {
        guard visible else { if isVisible { orderOut(nil) }; return }
        self.level = level
        if frame != rect { setFrame(rect, display: false) }
        if !isVisible {
            orderFrontRegardless()
            if let v = contentView {
                if let a = area { v.removeTrackingArea(a) }
                let a = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
                v.addTrackingArea(a)
                area = a
            }
        }
    }

    override func mouseEntered(with e: NSEvent) { onHover?(true); NSCursor.pointingHand.set() }
    override func mouseExited(with e: NSEvent) { onHover?(false); NSCursor.arrow.set() }
    override func mouseUp(with e: NSEvent) { onHover?(false); onClick?() }
}
