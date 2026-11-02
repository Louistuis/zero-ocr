import AppKit
import SwiftUI

/// Pinned text: a small glass note that floats above other windows until you close it.
@MainActor
final class Pins {
    static let shared = Pins()
    private var windows: [NSPanel] = []

    func pin(_ text: String) {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 320, height: 200),
                            styleMask: [.borderless, .nonactivatingPanel, .resizable], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.minSize = NSSize(width: 200, height: 90)
        let view = PinView(text: text) { [weak self, weak panel] in
            guard let panel else { return }
            panel.orderOut(nil)
            self?.windows.removeAll { $0 === panel }
        }
        panel.contentView = NSHostingView(rootView: view)
        // Cascade from the top right, under where the toast sits.
        if let f = NSScreen.main?.visibleFrame {
            let n = CGFloat(windows.count % 6)
            panel.setFrameOrigin(NSPoint(x: f.maxX - 340 - n * 24, y: f.maxY - 420 - n * 24))
        }
        panel.orderFrontRegardless()
        windows.append(panel)
    }
}

private struct PinView: View {
    let text: String
    let close: () -> Void
    @State private var hover = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ScrollView {
                Text(text)
                    .font(.system(size: 13))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 30))
            }
            HStack(spacing: 4) {
                GlassIconButton(symbol: "doc.on.doc") { Clipboard.put(text, html: nil); Sound.play("Pop") }
                GlassIconButton(symbol: "xmark") { close() }
            }
            .padding(8)
            .opacity(hover ? 1 : 0.0)
        }
        .glassCard(radius: 18)
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hover = h } }
    }
}
