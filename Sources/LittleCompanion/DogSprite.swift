import CoreGraphics
import Foundation
import ImageIO
import PetCore

/// The current dog's pixel-art frames, from Resources/<dog>.png (48×36 frames facing right, built by tools/art/ollie_sheet.py).
enum DogSprite {
    enum Frame: Int { case stand, walkA, walkB, sit, sleep, bow, runA, runB, zoomA, zoomB, look, sitFront, pawUp, shakeA, shakeB, sitBack, sleepTwitch, sleepCurl, sleepSide, sleepBelly, sleepCurlTwitch, sleepSideTwitch, sleepBellyTwitch
        case wagStandA = 55, wagStandB, wagSitA, wagSitB, wagFrontA, wagFrontB, wagBackA, wagBackB,   // after the 32 baked toy frames
             wagWalkA1, wagWalkA2, wagWalkB1, wagWalkB2, wagLookA, wagLookB, wagBowA, wagBowB,
             jumpCrouch, jumpUp, jumpDown, trip, tumbleRoll, tumbleSprawl, lickA, lickB, scratchA, scratchB,
             blinkStand, blinkSit, blinkFront,
             eatA, eatB, drinkA, drinkB, sniffA, sniffB, stretchB

        /// The same pose with its eyes shut for an idle blink; nil if this pose has no blink art.
        var blinking: Frame? {
            switch self {
            case .stand: .blinkStand
            case .sit: .blinkSit
            case .sitFront: .blinkFront
            default: nil
            }
        }

        /// The same pose with the tail wagging, flicking between two frames at `t`; nil if this pose has no wag art.
        func wagging(_ t: Double) -> Frame? {
            let base: Frame? = switch self {
            case .stand: .wagStandA
            case .sit: .wagSitA
            case .sitFront: .wagFrontA
            case .sitBack: .wagBackA
            case .walkA: .wagWalkA1
            case .walkB: .wagWalkB1
            case .look: .wagLookA
            case .bow: .wagBowA
            default: nil
            }
            return base.flatMap { Frame(rawValue: $0.rawValue + Int(t * 7) % 2) }
        }
    }
    /// Mango's frames, in the order tools/art/bird_sheet.py draws them (32×32, facing right).
    enum Bird: Int { case idle, idleCrest, front, lookBack, bobA, bobB, lookUp, tilt, blink, hopA, hopB, peckA, peckB,
                          takeoff, flapUp, flapMid, flapDown, glide, flare, wobble, preenA, preenB, stretch, eatA, eatB, splashA, splashB,
                          swing, bellA, bellB, nap, sleep, dream, startled, fallA, fallB, recover, frontBlink, recoverB }
    static var pixels: CGSize { isBird ? CGSize(width: 32, height: 32) : CGSize(width: 48, height: 36) }
    static let pointsPerPixel: CGFloat = 1.5   // 72×54 pt: 3 device pixels per art pixel on Retina, so edges stay crisp
    static var size: CGSize { CGSize(width: pixels.width * pointsPerPixel, height: pixels.height * pointsPerPixel) }
    static var footRows: CGFloat { isBird ? 1 : 2 }   // empty art rows under the paws (feet)
    static let scale: CGFloat = 2              // backing scale for the CoreGraphics-drawn objects

    /// The dogs you can have: sheet name, name, and what they are. Every sheet has the same frame layout.
    static let dogs = [("ollie", "Ollie", "beagle"), ("biscuit", "Biscuit", "shiba"), ("mochi", "Mochi", "fluffy white pup"),
                       ("bean", "Bean", "dachshund"), ("pepper", "Pepper", "border collie")]
    /// The birds: same layout as `dogs`; their sheets are bird frames (see `Bird`).
    static let birds = [("mango", "Mango", "cockatiel"), ("pearl", "Pearl", "lutino cockatiel"), ("kiwi", "Kiwi", "budgie"), ("sunny", "Sunny", "sun conure")]
    static var isBird: Bool { birds.contains { $0.0 == dog } }
    static var name: String { (dogs + birds).first { $0.0 == dog }?.1 ?? "Little Companion" }
    nonisolated(unsafe) static var dog = "ollie" { didSet { if dog != oldValue { cache = [:]; loaded = nil } } }
    nonisolated(unsafe) private static var loaded: CGImage?
    private static var sheet: CGImage {
        if let loaded { return loaded }
        guard let url = resource(dog, "png"),
              let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let img = CGImageSourceCreateImageAtIndex(src, 0, nil)
        else { fatalError("\(dog).png missing from the app bundle") }
        loaded = img
        return img
    }
    nonisolated(unsafe) private static var cache: [String: CGImage] = [:]

    static func image(_ frame: Frame, facing dir: CGFloat) -> CGImage { image(frame.rawValue, facing: dir) }

    /// Ollie holding a toy: frames 23 + toy×8 + pose (walk A/B, run A/B, stand, shake up/down, toss).
    static let toys = ["ball", "tennis", "plush", "rope"]
    /// Which toy art a held object uses: the tennis ball has its own; otherwise the kind's.
    static func toyArt(_ o: PetObject) -> String { o.id == "tennis" ? "tennis" : o.kind.rawValue }
    static func toyFrame(_ toy: String, _ pose: Int) -> Int? { toys.firstIndex(of: toy).map { 23 + $0 * 8 + pose } }

    static func image(_ index: Int, facing dir: CGFloat) -> CGImage {
        let key = "\(index)\(dir)"
        if let img = cache[key] { return img }
        let w = Int(pixels.width), h = Int(pixels.height)
        var img = sheet.cropping(to: CGRect(x: index * w, y: 0, width: w, height: h))!
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

    /// The same frame as a soft dark shadow: how it looks through the kennel window.
    static func silhouette(_ index: Int, facing dir: CGFloat) -> CGImage {
        let key = "s\(index)\(dir)"
        if let img = cache[key] { return img }
        let src = image(index, facing: dir)
        let c = CGContext(data: nil, width: src.width, height: src.height, bitsPerComponent: 8, bytesPerRow: 0,
                          space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let r = CGRect(x: 0, y: 0, width: src.width, height: src.height)
        c.draw(src, in: r)
        c.setBlendMode(.sourceIn)
        c.setFillColor(CGColor(srgbRed: 0.48, green: 0.34, blue: 0.24, alpha: 1))   // soft shadow against the lamp-lit interior
        c.fill(r)
        let img = c.makeImage()!
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
        guard let url = resource("objects", "png"),
              let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let img = CGImageSourceCreateImageAtIndex(src, 0, nil)
        else { fatalError("objects.png missing from the app bundle") }
        return img
    }()
    private static let rects: [String: [Int]] = {
        guard let url = resource("objects", "json"),
              let data = try? Data(contentsOf: url),
              let r = try? JSONDecoder().decode([String: [Int]].self, from: data)
        else { fatalError("objects.json missing from the app bundle") }
        return r
    }()
    nonisolated(unsafe) private static var cache: [String: (CGImage, CGSize)] = [:]

    /// The picture and its size in points (art pixels × DogSprite.pointsPerPixel).
    static func image(id: String, kind: String) -> (CGImage, CGSize) {
        let key = id == "tennis" ? "tennis" : kind == "kennel" ? "kennelBack" : kind
        if let hit = cache[key] { return hit }
        let r = rects[key] ?? rects["ball"]!
        let img = atlas.cropping(to: CGRect(x: r[0], y: r[1], width: r[2], height: r[3]))!
        let result = (img, CGSize(width: CGFloat(r[2]) * DogSprite.pointsPerPixel, height: CGFloat(r[3]) * DogSprite.pointsPerPixel))
        cache[key] = result
        return result
    }
}

/// The packaged .app carries its art in Contents/Resources; `swift run` finds it in SwiftPM's resource bundle.
func resource(_ name: String, _ ext: String) -> URL? {
    Bundle.main.url(forResource: name, withExtension: ext) ?? Bundle.module.url(forResource: name, withExtension: ext)
}
