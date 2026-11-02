// Renders the SF Symbols the site uses into white-on-transparent PNGs, used as CSS masks.
//   swift site/tools/symbols.swift site/public/sym
import AppKit

let names = ["command", "lock.shield.fill", "bolt.fill", "tablecells", "function", "translate",
             "speaker.wave.2.fill", "link", "envelope.fill", "phone.fill", "map.fill", "calendar.badge.plus",
             "qrcode", "clock.arrow.circlepath", "pin.fill", "folder.fill", "menubar.rectangle", "terminal.fill",
             "text.viewfinder", "wifi.slash", "cpu.fill", "macwindow", "doc.richtext.fill", "arrow.down.circle.fill",
             "checkmark.seal.fill", "sparkles", "memorychip.fill", "internaldrive.fill", "laptopcomputer"]
let out = URL(fileURLWithPath: CommandLine.arguments[1])
for name in names {
    let cfg = NSImage.SymbolConfiguration(pointSize: 120, weight: .medium)
        .applying(.preferringMonochrome())
    guard let img = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(cfg) else {
        print("missing", name); continue
    }
    // Square canvas, symbol centred, so every icon sits on the same box.
    let side = 168
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = img.size, k = min(CGFloat(side) * 0.9 / s.width, CGFloat(side) * 0.9 / s.height, 1)
    let w = s.width * k, h = s.height * k
    img.draw(in: NSRect(x: (CGFloat(side) - w) / 2, y: (CGFloat(side) - h) / 2, width: w, height: h))
    // Monochrome keeps the cut-outs (the lock in the shield); then paint whatever was drawn white.
    NSColor.white.set()
    NSRect(x: 0, y: 0, width: side, height: side).fill(using: .sourceAtop)
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent(name.replacingOccurrences(of: ".", with: "-") + ".png"))
}
