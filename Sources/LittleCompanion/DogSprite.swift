import CoreGraphics
import Foundation
import ImageIO

/// Ollie's pixel-art frames, from Resources/ollie.png (six 48×36 frames, drawn in Pixelwright, facing right).
enum DogSprite {
    enum Frame: Int { case stand, walkA, walkB, sit, sleep, bow, runA, runB, zoomA, zoomB, look, sitFront, pawUp, shakeA, shakeB, sitBack }
    static let pixels = CGSize(width: 48, height: 36)
    static let pointsPerPixel: CGFloat = 1.5   // 72×54 pt: 3 device pixels per art pixel on Retina, so edges stay crisp
    static var size: CGSize { CGSize(width: pixels.width * pointsPerPixel, height: pixels.height * pointsPerPixel) }
    static let footRows: CGFloat = 2           // empty art rows under the paws
    static let scale: CGFloat = 2              // backing scale for the CoreGraphics-drawn objects

    private static let sheet: CGImage = {
        guard let url = Bundle.module.url(forResource: "ollie", withExtension: "png"),
              let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let img = CGImageSourceCreateImageAtIndex(src, 0, nil)
        else { fatalError("ollie.png missing from the app bundle") }
        return img
    }()
    nonisolated(unsafe) private static var cache: [String: CGImage] = [:]

    static func image(_ frame: Frame, facing dir: CGFloat) -> CGImage {
        let key = "\(frame.rawValue)\(dir)"
        if let img = cache[key] { return img }
        let w = Int(pixels.width), h = Int(pixels.height)
        var img = sheet.cropping(to: CGRect(x: frame.rawValue * w, y: 0, width: w, height: h))!
        if dir < 0 {   // mirror for facing left
            let c = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            c.translateBy(x: CGFloat(w), y: 0); c.scaleBy(x: -1, y: 1)
            c.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
            img = c.makeImage()!
        }
        cache[key] = img
        return img
    }

    /// Draws into a Retina bitmap with a top-left origin in points.
    static func render(_ size: CGSize, _ body: (CGContext) -> Void) -> CGImage {
        let w = Int(size.width * scale), h = Int(size.height * scale)
        let c = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                          space: CGColorSpace(name: CGColorSpace.sRGB)!,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        c.translateBy(x: 0, y: CGFloat(h))
        c.scaleBy(x: scale, y: -scale)
        body(c)
        return c.makeImage()!
    }

    static func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: 1) }
    static func ellipse(_ c: CGContext, _ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat) {
        c.fillEllipse(in: CGRect(x: cx - rx, y: cy - ry, width: rx * 2, height: ry * 2))
    }
}

/// Home objects from Resources/objects.png (drawn in Pixelwright), bottom-aligned on the floor.
enum ObjectSprite {
    private static let atlas: CGImage = {
        guard let url = Bundle.module.url(forResource: "objects", withExtension: "png"),
              let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let img = CGImageSourceCreateImageAtIndex(src, 0, nil)
        else { fatalError("objects.png missing from the app bundle") }
        return img
    }()
    private static let rects: [String: [Int]] = {
        guard let url = Bundle.module.url(forResource: "objects", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let r = try? JSONDecoder().decode([String: [Int]].self, from: data)
        else { fatalError("objects.json missing from the app bundle") }
        return r
    }()
    nonisolated(unsafe) private static var cache: [String: (CGImage, CGSize)] = [:]

    /// The picture and its size in points (art pixels × DogSprite.pointsPerPixel).
    static func image(id: String, kind: String) -> (CGImage, CGSize) {
        let key = id == "tennis" ? "tennis" : kind
        if let hit = cache[key] { return hit }
        let r = rects[key] ?? rects["ball"]!
        let img = atlas.cropping(to: CGRect(x: r[0], y: r[1], width: r[2], height: r[3]))!
        let result = (img, CGSize(width: CGFloat(r[2]) * DogSprite.pointsPerPixel, height: CGFloat(r[3]) * DogSprite.pointsPerPixel))
        cache[key] = result
        return result
    }
}
