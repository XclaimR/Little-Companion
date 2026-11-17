import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.accessory) // menu bar only, no Dock icon
let delegate = AppDelegate()
app.delegate = delegate
app.run()

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    var world: World?
    var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ note: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.title = "🐾"
        let menu = NSMenu()
        menu.addItem(withTitle: "Quit Little Companion", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item

        world = World(screen: NSScreen.main!, bench: ProcessInfo.processInfo.environment["LC_BENCH"])
    }
}
