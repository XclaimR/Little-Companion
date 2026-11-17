import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.accessory) // menu bar only, no Dock icon
let delegate = AppDelegate()
app.delegate = delegate
app.run()

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    var world: World?
    var statusItem: NSStatusItem?
    let header = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    let dogMenu = NSMenu()

    func applicationDidFinishLaunching(_ note: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.title = "🐾"
        let menu = NSMenu()
        header.isEnabled = false
        menu.addItem(header)
        let dogs = menu.addItem(withTitle: "Change dog", action: nil, keyEquivalent: "")
        for (id, name, kind) in DogSprite.dogs {
            let item = dogMenu.addItem(withTitle: "\(name) — \(kind)", action: #selector(pickDog(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = id
        }
        menu.setSubmenu(dogMenu, for: dogs)
        menu.addItem(.separator())
        if ProcessInfo.processInfo.environment["LC_DEBUG"] != nil {
            for (title, sel) in [("Test: play with the ball", #selector(testBall)), ("Test: shake the plush", #selector(testPlush)),
                                 ("Test: go to the kennel", #selector(testKennel)), ("Test: zoomies", #selector(testZoomies)),
                                 ("Test: follow the cursor", #selector(testFollow)), ("Test: sit", #selector(testSit)), ("Test: groom", #selector(testGroom)),
                                 ("Test: trip", #selector(testTrip)), ("Test: tumble", #selector(testTumble)),
                                 ("Test: busy Mac on/off", #selector(testBusy))] {
                menu.addItem(withTitle: title, action: sel, keyEquivalent: "").target = self
            }
            menu.addItem(.separator())
        }
        menu.addItem(withTitle: "Quit Little Companion", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item

        world = World(screen: NSScreen.main!)
        refreshDogMenu()
    }

    @objc func pickDog(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        world?.switchDog(to: id)
        refreshDogMenu()
    }

    func refreshDogMenu() {
        header.title = DogSprite.dogs.first { $0.0 == DogSprite.dog }?.1 ?? "Little Companion"
        for item in dogMenu.items { item.state = item.representedObject as? String == DogSprite.dog ? .on : .off }
    }

    func applicationWillTerminate(_ note: Notification) { world?.save() }

    @objc func testBall() { world?.test(.play, "ball") }
    @objc func testPlush() { world?.test(.play, "plush") }
    @objc func testKennel() { world?.test(.kennel, "kennel") }
    @objc func testZoomies() { world?.test(.zoomies) }
    @objc func testFollow() { world?.test(.follow) }
    @objc func testSit() { world?.test(.sit) }
    @objc func testGroom() { world?.test(.groom) }
    @objc func testTrip() { world?.testFall(tumble: false) }
    @objc func testTumble() { world?.testFall(tumble: true) }
    @objc func testBusy() { world?.forceBusy.toggle() }
}
