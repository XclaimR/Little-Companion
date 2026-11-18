import AppKit

/// Full-screen transparent panel that sits just above the desktop icons and below every normal window.
/// Non-activating, so clicking the dog never takes focus from the app you're working in.
final class DesktopPanel: NSPanel {
    init(frame: NSRect, onTop: Bool) {
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        becomesKeyOnlyIfNeeded = true
        ignoresMouseEvents = true
        level = onTop ? .floating : NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        if onTop { collectionBehavior.insert(.fullScreenAuxiliary) }   // LC_TOP (testing, recordings): visible over full-screen apps too
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Content view that forwards clicks; only receives them while the cursor is over a hit rect.
final class ClickView: NSView {
    var onClick: ((CGPoint) -> Void)?
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { onClick?(NSEvent.mouseLocation) }
}

/// Other apps' ordinary windows, front-to-back, in top-left-origin points. Bounds need no permission.
func otherWindowRects() -> [CGRect] { otherWindows().map(\.rect) }

/// The same with each window's id (a bird tracks the one it's perched on). Invisible (alpha 0) windows are skipped.
func otherWindows() -> [(id: Int, rect: CGRect)] {
    guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
    else { return [] }
    let me = ProcessInfo.processInfo.processIdentifier
    return list.compactMap { d in
        guard d[kCGWindowLayer as String] as? Int == 0,
              d[kCGWindowOwnerPID as String] as? Int32 != me,
              (d[kCGWindowAlpha as String] as? Double ?? 1) > 0,
              let id = d[kCGWindowNumber as String] as? Int,
              let b = d[kCGWindowBounds as String] as? NSDictionary,
              let r = CGRect(dictionaryRepresentation: b),
              r.width >= 80, r.height >= 40
        else { return nil }
        return (id, r)
    }
}

/// Whether a window still exists anywhere (minimised or on another Space counts); false once it's closed.
func windowExists(_ id: Int) -> Bool {
    ((CGWindowListCopyWindowInfo(.optionIncludingWindow, CGWindowID(id)) as? [[String: Any]]) ?? []).isEmpty == false
}
