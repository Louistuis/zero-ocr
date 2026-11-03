import SwiftUI

extension RichText {
    /// Plain text needs no rendering; everything else gets the document treatment.
    static func wanted(_ mode: Mode, _ text: String) -> Bool {
        mode != .text || text.contains("$") || text.contains("\\(") || text.contains("| ---") || text.hasPrefix("#")
    }
}

#if !arch(x86_64)
import WebKit

/// Markdown, tables and LaTeX, rendered like a document: marked + KaTeX, bundled, offline,
/// in a transparent web view that reports its own height so the card can grow around it.
struct RichText: View {
    let text: String
    let mode: Mode
    var html: String?
    var maxHeight: CGFloat = 280
    @State private var height: CGFloat = 18

    var body: some View {
        RichWeb(text: text, mode: mode, html: html, height: $height)
            .frame(height: min(max(height, 18), maxHeight))
    }
}

private struct RichWeb: NSViewRepresentable {
    let text: String
    let mode: Mode
    let html: String?
    @Binding var height: CGFloat

    func makeCoordinator() -> Coordinator { Coordinator(height: $height) }

    func makeNSView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.userContentController.add(context.coordinator, name: "size")
        let web = WKWebView(frame: .zero, configuration: cfg)
        web.setValue(false, forKey: "drawsBackground")
        web.navigationDelegate = context.coordinator
        web.allowsMagnification = false
        if let dir = Bundle.main.resourceURL?.appendingPathComponent("web") {
            web.loadFileURL(dir.appendingPathComponent("render.html"), allowingReadAccessTo: dir)
        }
        context.coordinator.web = web
        return web
    }

    func updateNSView(_ web: WKWebView, context: Context) {
        context.coordinator.height = $height
        context.coordinator.show(text, mode: mode, html: html)
    }

    static func dismantleNSView(_ web: WKWebView, coordinator: Coordinator) {
        web.configuration.userContentController.removeScriptMessageHandler(forName: "size")
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var height: Binding<CGFloat>
        weak var web: WKWebView?
        private var loaded = false
        private var pending: (String, Mode, String?)?
        private var shown = ""
        private var scheduled = false

        init(height: Binding<CGFloat>) { self.height = height }

        /// Streaming text arrives many times a second; render at most every 120 ms.
        func show(_ text: String, mode: Mode, html: String?) {
            pending = (text, mode, html)
            guard loaded, !scheduled else { return }
            scheduled = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
                self?.scheduled = false
                self?.flush()
            }
        }

        private func flush() {
            guard let (text, mode, html) = pending, let web else { return }
            let key = mode.rawValue + (html ?? "") + text
            guard key != shown else { return }
            shown = key
            let args = [text, mode.rawValue, html ?? ""].map { s -> String in
                let d = try! JSONSerialization.data(withJSONObject: [s])
                return String(data: d, encoding: .utf8)!.dropFirst().dropLast().description
            }
            web.evaluateJavaScript("render(\(args.joined(separator: ",")))")
        }

        func webView(_ web: WKWebView, didFinish _: WKNavigation!) {
            loaded = true
            flush()
        }

        func userContentController(_: WKUserContentController, didReceive m: WKScriptMessage) {
            if let h = m.body as? Double {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { height.wrappedValue = CGFloat(h) }
            }
        }

        /// Links open in the browser, never inside the card.
        func webView(_ web: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
            if action.navigationType == .linkActivated, let u = action.request.url {
                NSWorkspace.shared.open(u)
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }
        }
    }
}
#endif
