import CoreGraphics

/// Placeholder dog poses drawn once with CoreGraphics and cached; replaced by pixel-art sprite sheets later.
enum DogSprite {
    static let canvas = CGSize(width: 80, height: 64)   // sprite image size, points
    static let dogOrigin = CGPoint(x: 8, y: 20)         // where the 64x44 dog sits inside it (top-left)
    static let scale: CGFloat = 2

    nonisolated(unsafe) private static var cache: [String: CGImage] = [:]

    static func image(pose: String, facing dir: CGFloat) -> CGImage {
        let key = "\(pose)\(dir)"
        if let img = cache[key] { return img }
        let w = Int(canvas.width * scale), h = Int(canvas.height * scale)
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        // Top-left origin in points, mirrored for facing left.
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: scale, y: -scale)
        ctx.translateBy(x: dogOrigin.x + 32, y: dogOrigin.y)
        ctx.scaleBy(x: dir, y: 1)
        ctx.translateBy(x: -32, y: 0)
        draw(pose, in: ctx)
        let img = ctx.makeImage()!
        cache[key] = img
        return img
    }

    private static let fur = CGColor(srgbRed: 0.851, green: 0.627, blue: 0.4, alpha: 1)
    private static let dark = CGColor(srgbRed: 0.561, green: 0.337, blue: 0.231, alpha: 1)
    private static let ink = CGColor(srgbRed: 0.13, green: 0.13, blue: 0.13, alpha: 1)

    private static func ellipse(_ c: CGContext, _ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat) {
        c.fillEllipse(in: CGRect(x: cx - rx, y: cy - ry, width: rx * 2, height: ry * 2))
    }

    /// Poses: "sleep", "walk0", "walk1", "idle0", "idle1", "hop".
    private static func draw(_ pose: String, in c: CGContext) {
        if pose == "sleep" {
            c.setFillColor(fur); ellipse(c, 32, 34, 28, 10); ellipse(c, 54, 32, 10, 8)
            c.setFillColor(dark); c.fill(CGRect(x: 52, y: 25, width: 6, height: 8))
            c.setStrokeColor(CGColor(srgbRed: 0.35, green: 0.29, blue: 0.42, alpha: 1)); c.setLineWidth(2) // "z"
            c.strokeLineSegments(between: [CGPoint(x: 58, y: 6), CGPoint(x: 66, y: 6), CGPoint(x: 66, y: 6),
                                           CGPoint(x: 58, y: 14), CGPoint(x: 58, y: 14), CGPoint(x: 66, y: 14)])
            return
        }
        let step: CGFloat = pose.hasSuffix("1") ? 1 : 0
        let stride: CGFloat = pose.hasPrefix("walk") ? step * 3 : 0
        c.setFillColor(dark)
        c.fill(CGRect(x: 14 + stride, y: 30, width: 6, height: 14)); c.fill(CGRect(x: 40 - stride, y: 30, width: 6, height: 14))
        c.setFillColor(fur); ellipse(c, 30, 26, 22, 11); ellipse(c, 52, 14, 11, 10)
        c.setFillColor(dark)
        c.fill(CGRect(x: 46, y: 4, width: 6, height: 12))                                        // ear
        c.fill(CGRect(x: 4, y: 14 - (pose.hasPrefix("idle") ? step * 3 : 0), width: 8, height: 4)) // tail
        c.setFillColor(ink); c.fill(CGRect(x: 56, y: 11, width: 3, height: 3)); c.fill(CGRect(x: 62, y: 16, width: 3, height: 3))
    }
}
