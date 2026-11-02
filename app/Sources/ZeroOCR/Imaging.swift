import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Turns anything readable into the PNGs the model sees: one per image, one per PDF page.
enum Imaging {
    static let maxPixels = 2560.0 * 1600.0   // bigger only slows the read; text stays legible well below
    /// Small crops (a word, a line) read much better scaled up first. Below about 200k pixels the
    /// quantised model starts to guess (the low-res test line went from wrong to exact at 2x).
    static let minPixels = 200_000.0

    static func pages(from data: Data) -> [CGImage] {
        if data.starts(with: Array("%PDF-".utf8)) {
            guard let provider = CGDataProvider(data: data as CFData), let pdf = CGPDFDocument(provider) else { return [] }
            return (1...max(pdf.numberOfPages, 1)).compactMap { pdf.page(at: $0).flatMap(render) }
        }
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let img = CGImageSourceCreateImageAtIndex(src, 0, [kCGImageSourceShouldAllowFloat: false] as CFDictionary)
        else { return [] }
        return [img]
    }

    static func pages(from url: URL) -> [CGImage] {
        (try? Data(contentsOf: url)).map(pages(from:)) ?? []
    }

    private static func render(_ page: CGPDFPage) -> CGImage? {
        let box = page.getBoxRect(.cropBox)
        let k = 200.0 / 72.0
        let w = Int(box.width * k), h = Int(box.height * k)
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        ctx.setFillColor(.white)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.scaleBy(x: k, y: k)
        ctx.translateBy(x: -box.minX, y: -box.minY)
        ctx.drawPDFPage(page)
        return ctx.makeImage()
    }

    /// Sized for the model, flattened onto white (transparent screenshots read as black otherwise), as PNG.
    static func prepare(_ img: CGImage) -> Data? {
        let px = Double(img.width * img.height)
        var k = 1.0
        if px > maxPixels { k = (maxPixels / px).squareRoot() }
        else if px < minPixels { k = min(4, (minPixels / px).squareRoot()) }
        let w = max(1, Int(Double(img.width) * k)), h = max(1, Int(Double(img.height) * k))
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        ctx.setFillColor(.white)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.interpolationQuality = .high
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let out = ctx.makeImage() else { return nil }
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, out, nil)
        return CGImageDestinationFinalize(dest) ? data as Data : nil
    }

    static let readableExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "heif", "tif", "tiff", "gif", "bmp", "webp", "pdf"]
    static func readable(_ url: URL) -> Bool { readableExtensions.contains(url.pathExtension.lowercased()) }

    static func clipboardImage() -> [CGImage] {
        let pb = NSPasteboard.general
        if let url = (pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL])?
            .first(where: readable) { return pages(from: url) }
        for t in [NSPasteboard.PasteboardType.png, .tiff, NSPasteboard.PasteboardType("com.adobe.pdf")] {
            if let d = pb.data(forType: t) { return pages(from: d) }
        }
        return []
    }
}
