// Renders the 1024 px app icon: a near-black squircle with the text.viewfinder glyph lit in the
// neon frame's colours (the same 13 stops around the perimeter), a soft halo, and the text lines
// inside tone mapped toward white, like the light of the frame.
// usage: swift makeicon.swift out.png
import AppKit
import CoreImage

let N = 1024
let size = CGFloat(N)
let space = CGColorSpace(name: CGColorSpace.sRGB)!

func context() -> CGContext {
    CGContext(data: nil, width: N, height: N, bitsPerComponent: 8, bytesPerRow: N * 4, space: space,
              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}

// The frame's stops, as on the site.
let hex: [Int] = [0x8e42e9, 0x6769e8, 0x47abe1, 0x68def3, 0x59aeda, 0x5d57ee, 0x8e41e3,
                                         0xc75976, 0xd1a036, 0xeab748, 0xd99c59, 0xd875a1, 0xb64ad7]
let stops: [(Double, Double, Double)] = hex.map { h in
    (Double((h >> 16) & 255) / 255, Double((h >> 8) & 255) / 255, Double(h & 255) / 255)
}
func neon(_ angle: Double) -> (Double, Double, Double) {
    let t = (angle / (2 * .pi)).truncatingRemainder(dividingBy: 1) * Double(stops.count)
    let i = Int(t) % stops.count, f = t - floor(t)
    let a = stops[i], b = stops[(i + 1) % stops.count]
    return (a.0 + (b.0 - a.0) * f, a.1 + (b.1 - a.1) * f, a.2 + (b.2 - a.2) * f)
}

// 1. The glyph as a mask.
let glyph = context()
let cfg = NSImage.SymbolConfiguration(pointSize: 470, weight: .medium).applying(.preferringMonochrome())
let sym = NSImage(systemSymbolName: "text.viewfinder", accessibilityDescription: nil)!.withSymbolConfiguration(cfg)!
let gs = sym.size
let gRect = NSRect(x: (size - gs.width) / 2, y: (size - gs.height) / 2, width: gs.width, height: gs.height)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(cgContext: glyph, flipped: false)
sym.draw(in: gRect)
NSGraphicsContext.restoreGraphicsState()

// 2. Colour it: neon by angle around the centre on the corners, near white on the lines inside.
let px = glyph.data!.bindMemory(to: UInt8.self, capacity: N * N * 4)
let inner = gRect.insetBy(dx: gs.width * 0.2, dy: gs.height * 0.2)
for y in 0..<N {
    for x in 0..<N {
        let o = (y * N + x) * 4
        let a = Double(px[o + 3]) / 255
        guard a > 0 else { continue }
        let cy = Double(N - 1 - y)   // bitmap rows run top down
        // The lines take the colours left to right, so they have no seam where the angles meet.
        let isLine = inner.contains(NSPoint(x: Double(x), y: cy))
        let angle = isLine ? (Double(x) - inner.minX) / inner.width * .pi + 3.4
                           : atan2(cy - Double(size) / 2, Double(x) - Double(size) / 2) + .pi
        var (r, g, b) = neon(angle)
        let w = isLine ? 0.8 : 0.12
        r += (1 - r) * w; g += (1 - g) * w; b += (1 - b) * w
        px[o] = UInt8(r * a * 255); px[o + 1] = UInt8(g * a * 255); px[o + 2] = UInt8(b * a * 255)
    }
}
let lit = glyph.makeImage()!

// 3. The halo: the lit glyph, blurred.
let ci = CIContext()
let blur = CIImage(cgImage: lit).applyingGaussianBlur(sigma: 30).cropped(to: CGRect(x: 0, y: 0, width: N, height: N))
let halo = ci.createCGImage(blur, from: blur.extent)!

// 4. Compose.
let out = context()
let rect = CGRect(x: 100, y: 100, width: size - 200, height: size - 200)
let shape = CGPath(roundedRect: rect, cornerWidth: 185, cornerHeight: 185, transform: nil)
out.saveGState()
out.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: CGColor(gray: 0, alpha: 0.32))
out.addPath(shape); out.setFillColor(CGColor(gray: 0, alpha: 1)); out.fillPath()
out.restoreGState()

out.saveGState()
out.addPath(shape); out.clip()
let bg = CGGradient(colorsSpace: space, colors: [CGColor(srgbRed: 0.13, green: 0.13, blue: 0.16, alpha: 1),
                                                 CGColor(srgbRed: 0.035, green: 0.035, blue: 0.045, alpha: 1)] as CFArray,
                    locations: [0, 1])!
out.drawLinearGradient(bg, start: CGPoint(x: 0, y: rect.maxY), end: CGPoint(x: 0, y: rect.minY), options: [])
out.setBlendMode(.plusLighter)
out.setAlpha(0.95)
out.draw(halo, in: CGRect(x: 0, y: 0, width: N, height: N))
out.setAlpha(1)
out.setBlendMode(.normal)
out.draw(lit, in: CGRect(x: 0, y: 0, width: N, height: N))
// The glass edge: a faint top sheen and a hairline.
let sheen = CGGradient(colorsSpace: space, colors: [CGColor(gray: 1, alpha: 0.14), CGColor(gray: 1, alpha: 0)] as CFArray,
                       locations: [0, 1])!
out.drawLinearGradient(sheen, start: CGPoint(x: 0, y: rect.maxY), end: CGPoint(x: 0, y: rect.midY), options: [])
out.restoreGState()
out.addPath(CGPath(roundedRect: rect.insetBy(dx: 1.5, dy: 1.5), cornerWidth: 184, cornerHeight: 184, transform: nil))
out.setStrokeColor(CGColor(gray: 1, alpha: 0.10)); out.setLineWidth(3); out.strokePath()

let rep = NSBitmapImageRep(cgImage: out.makeImage()!)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
