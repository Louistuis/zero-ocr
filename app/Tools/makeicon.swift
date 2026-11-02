// Renders the 1024 px app icon: a soft graphite squircle with the text.viewfinder glyph.
// usage: swift makeicon.swift out.png
import AppKit

let size: CGFloat = 1024
let img = NSImage(size: NSSize(width: size, height: size))
img.lockFocus()
let inset: CGFloat = 100
let rect = NSRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
let shape = NSBezierPath(roundedRect: rect, xRadius: 185, yRadius: 185)

NSGraphicsContext.current?.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowBlurRadius = 28
shadow.shadowOffset = NSSize(width: 0, height: -12)
shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
shadow.set()
NSColor.black.setFill()
shape.fill()
NSGraphicsContext.current?.restoreGraphicsState()

NSGradient(colors: [NSColor(calibratedRed: 0.20, green: 0.22, blue: 0.27, alpha: 1),
                    NSColor(calibratedRed: 0.07, green: 0.08, blue: 0.10, alpha: 1)])!.draw(in: shape, angle: -90)
// A faint top sheen, the glass highlight.
NSGradient(colors: [NSColor.white.withAlphaComponent(0.16), NSColor.white.withAlphaComponent(0)])!
    .draw(in: NSBezierPath(roundedRect: rect.insetBy(dx: 6, dy: 6), xRadius: 180, yRadius: 180), angle: -90)

let cfg = NSImage.SymbolConfiguration(pointSize: 470, weight: .regular)
    .applying(.init(paletteColors: [NSColor(calibratedRed: 1, green: 0.47, blue: 0.16, alpha: 1)]))
if let sym = NSImage(systemSymbolName: "text.viewfinder", accessibilityDescription: nil)?.withSymbolConfiguration(cfg) {
    let s = sym.size
    sym.draw(in: NSRect(x: (size - s.width) / 2, y: (size - s.height) / 2, width: s.width, height: s.height))
}
img.unlockFocus()

let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
