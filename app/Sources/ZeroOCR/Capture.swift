import AppKit
import ScreenCaptureKit

/// Screen capture of a selected rectangle, with Zero OCR's own windows left out.
enum Capture {
    static var allowed: Bool { CGPreflightScreenCaptureAccess() }

    /// The preflight answer is cached for the life of the process, so a permission granted while the
    /// app runs only shows up after a restart. Asking ScreenCaptureKit directly sees it straight away.
    static func check() async -> Bool {
        if allowed { return true }
        return (try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)) != nil
    }

    /// Fetched as the selection starts, so the capture itself is instant on mouse up.
    private static var content: Task<SCShareableContent, Error>?

    static func prefetch() {
        content = Task { try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true) }
    }

    static func image(of rect: CGRect, on screen: NSScreen) async throws -> CGImage {
        let shareable = try await (content ?? Task { try await SCShareableContent.current }).value
        content = nil
        let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
        guard let display = shareable.displays.first(where: { $0.displayID == id }) ?? shareable.displays.first else {
            throw NSError(domain: "ZeroOCR", code: 1, userInfo: [NSLocalizedDescriptionKey: "No display to capture."])
        }
        let me = shareable.applications.filter { $0.processID == getpid() }
        let filter = SCContentFilter(display: display, excludingApplications: me, exceptingWindows: [])
        let cfg = SCStreamConfiguration()
        let local = CGRect(x: rect.minX - screen.frame.minX, y: screen.frame.maxY - rect.maxY,
                           width: rect.width, height: rect.height)
        let scale = CGFloat(filter.pointPixelScale)
        cfg.sourceRect = local
        cfg.width = max(1, Int(local.width * scale))
        cfg.height = max(1, Int(local.height * scale))
        cfg.showsCursor = false
        cfg.captureResolution = .best
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg)
    }
}
