import AppKit
import QuartzCore

/// One screen's overlay: the neon frame while you select, then the flight into the toast in the top
/// right corner, where the frame hugs the toast as a glowing rim while the model reads. One
/// borderless, click-through window above everything, drawn by GlowView on the display link.
final class Stage: NSObject {
    enum Phase { case hover, selecting, captured, collapse, fly, rim, fade, closed }

    let screen: NSScreen
    let window: StagePanel
    private let root = FlippedView()
    private let glow: GlowView
    private var link: CADisplayLink?
    private var last: CFTimeInterval = 0
    private var clock: CGFloat = 0
    private var phaseStart: CGFloat = 0

    private(set) var phase: Phase = .hover
    // Frame edges in view points (flipped): left, top, right, bottom.
    private var l = Spring(0), t = Spring(0), r = Spring(0), b = Spring(0)
    private var gain = Spring(0)
    private var hoverRect: CGRect?
    private var selection: CGRect = .zero
    private var reading = true

    var onSelect: ((CGRect?) -> Void)?   // global (bottom-left) rect of the selection, nil when cancelled
    var onLanded: (() -> Void)?
    /// Where the toast card is (global), or will be.
    var target: (() -> CGRect)?

    init(screen: NSScreen) {
        self.screen = screen
        window = StagePanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false, screen: screen)
        glow = GlowView(frame: CGRect(origin: .zero, size: screen.frame.size))
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
        window.contentView = root
        window.stage = self
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
        window.orderOut(nil)
    }

    // MARK: selection

    func beginSelecting() {
        phase = .hover
        window.ignoresMouseEvents = false
        window.acceptsMouseMovedEvents = true
        window.makeKeyAndOrderFront(nil)
        NSCursor.crosshair.push()
    }

    private func toView(_ g: CGRect) -> CGRect {
        CGRect(x: g.minX - screen.frame.minX, y: screen.frame.maxY - g.maxY, width: g.width, height: g.height)
    }

    private func toGlobal(_ v: CGRect) -> CGRect {
        CGRect(x: v.minX + screen.frame.minX, y: screen.frame.maxY - v.maxY, width: v.width, height: v.height)
    }

    private var dragStart: CGPoint?

    func mouseMoved(_ p: CGPoint) {
        guard phase == .hover else { return }
        hoverRect = Stage.windowRect(at: window.convertPoint(toScreen: p)).map(toView)
    }

    func mouseDown(_ p: CGPoint) { dragStart = root.convert(p, from: nil) }

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
        start(from: rect)
        onSelect?(toGlobal(rect))
    }

    /// Start the flight from a rectangle (view coordinates): a fresh selection, or the last area again.
    private func start(from rect: CGRect) {
        (l, t, r, b) = (Spring(rect.minX), Spring(rect.minY), Spring(rect.maxX), Spring(rect.maxY))
        gain = Spring(max(gain.x, 0.6))
        phase = Prefs.neon ? .captured : .fade
        phaseStart = clock
        if !Prefs.neon { onLanded?() }
    }

    /// The last area again (global rect): the frame flashes there, then flies.
    func replay(_ global: CGRect) { start(from: toView(global)) }

    /// No selection (a file, the clipboard): the rim just glows around the toast.
    func rimOnly() {
        let c = toView(target?() ?? .zero)
        (l, t, r, b) = (Spring(c.minX), Spring(c.minY), Spring(c.maxX), Spring(c.maxY))
        phase = Prefs.neon ? .rim : .fade
        phaseStart = clock
    }

    func finished() { reading = false; phaseStart = clock }

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

    // MARK: animation

    @objc private func tick(_ link: CADisplayLink) {
        let now = link.timestamp
        let dt = CGFloat(last == 0 ? 1 / 120 : min(max(now - last, 0), 1 / 20))
        last = now
        clock += dt
        let since = clock - phaseStart
        var radius: CGFloat = 10
        var outer: Float = 0.35
        let f = screen.visibleFrame
        let goal = toView(target?() ?? CGRect(x: f.maxX - 386, y: f.maxY - 116, width: 360, height: 92))

        switch phase {
        case .hover:
            if let h = hoverRect {
                if gain.x < 0.01 { (l, t, r, b) = (Spring(h.minX), Spring(h.minY), Spring(h.maxX), Spring(h.maxY)) }
                l.step(to: h.minX, dt: dt, omega: 24); t.step(to: h.minY, dt: dt, omega: 24)
                r.step(to: h.maxX, dt: dt, omega: 24); b.step(to: h.maxY, dt: dt, omega: 24)
            }
            gain.step(to: hoverRect == nil ? 0 : 0.42, dt: dt, omega: 14)
        case .selecting:
            (l, t, r, b) = (Spring(selection.minX), Spring(selection.minY), Spring(selection.maxX), Spring(selection.maxY))
            gain.step(to: 1, dt: dt, omega: 20)
        case .captured:
            gain.step(to: 1.35, dt: dt, omega: 18)
            if since > 0.12 { phase = .collapse; phaseStart = clock }
        case .collapse:
            let c = CGPoint(x: (l.x + r.x) / 2, y: (t.x + b.x) / 2)
            l.step(to: c.x - 7, dt: dt, omega: 17); r.step(to: c.x + 7, dt: dt, omega: 17)
            t.step(to: c.y - 7, dt: dt, omega: 17); b.step(to: c.y + 7, dt: dt, omega: 17)
            gain.step(to: 1.25, dt: dt, omega: 10)
            radius = min(r.x - l.x, b.x - t.x) / 2
            outer = 0.35 + Float(max(0, 1 - (r.x - l.x) / 120)) * 0.9
            if r.x - l.x < 26, b.x - t.x < 26 { phase = .fly; phaseStart = clock }
        case .fly:
            // The edge facing the toast pulls ahead and the trailing one catches up, so the dot
            // stretches into a streak on its way to the corner.
            let target = CGPoint(x: goal.midX, y: goal.midY)
            let dx = target.x - (l.x + r.x) / 2, dy = target.y - (t.x + b.x) / 2
            let fast: CGFloat = 16, slow: CGFloat = 8.5
            l.step(to: target.x - 7, dt: dt, omega: dx < 0 ? fast : slow)
            r.step(to: target.x + 7, dt: dt, omega: dx > 0 ? fast : slow)
            t.step(to: target.y - 7, dt: dt, omega: dy < 0 ? fast : slow)
            b.step(to: target.y + 7, dt: dt, omega: dy > 0 ? fast : slow)
            gain.step(to: 1.35, dt: dt, omega: 10)
            radius = min(r.x - l.x, b.x - t.x) / 2
            outer = 1.2
            if hypot(dx, dy) < 22 || since > 1.6 {
                phase = .rim; phaseStart = clock
                onLanded?()
            }
        case .rim:
            // Bursts open around the toast, then breathes while the model reads.
            l.step(to: goal.minX, dt: dt, omega: 15, damping: 0.72); r.step(to: goal.maxX, dt: dt, omega: 15, damping: 0.72)
            t.step(to: goal.minY, dt: dt, omega: 15, damping: 0.72); b.step(to: goal.maxY, dt: dt, omega: 15, damping: 0.72)
            radius = min(24, min(r.x - l.x, b.x - t.x) / 2)
            outer = 0.55
            if reading {
                gain.step(to: 0.8 + 0.18 * sin(clock * 3.4), dt: dt, omega: 10)
            } else {
                // A last bright pulse as the text lands, then the light goes out.
                gain.step(to: since < 0.18 ? 1.5 : 0, dt: dt, omega: since < 0.18 ? 20 : 5)
                if since > 0.5, gain.x < 0.02 { close(); return }
            }
        case .fade:
            gain.step(to: 0, dt: dt, omega: 12)
            if gain.x < 0.02 { close(); return }
        case .closed:
            return
        }

        let rect = CGRect(x: l.x, y: t.x, width: max(r.x - l.x, 1), height: max(b.x - t.x, 1))
        glow.state = GlowState(rect: rect, radii: (radius, radius, radius, radius),
                               gain: Float(max(gain.x, 0)), fill: 0, outer: outer, rot: Float(clock * 0.14))
        glow.render()
    }
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
