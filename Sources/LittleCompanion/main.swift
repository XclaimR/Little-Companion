import AppKit
import ServiceManagement

let app = NSApplication.shared
app.setActivationPolicy(.accessory) // menu bar only, no Dock icon
let delegate = AppDelegate()
app.delegate = delegate
app.run()

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var world: World?
    var statusItem: NSStatusItem?
    let header = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    var petItems: [NSMenuItem] = []
    let hideItem = NSMenuItem(title: "Hide for an hour", action: #selector(toggleHide), keyEquivalent: "")
    let readOnlyNote = NSMenuItem(title: "Saved by a newer version — not saving", action: nil, keyEquivalent: "")

    func applicationDidFinishLaunching(_ note: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.title = "🐾"
        item.button?.setAccessibilityLabel("Little Companion")
        let menu = NSMenu()
        menu.delegate = self
        header.isEnabled = false
        menu.addItem(header)
        readOnlyNote.isEnabled = false
        menu.addItem(readOnlyNote)
        let pets = menu.addItem(withTitle: "Change pet", action: nil, keyEquivalent: "")
        let species = NSMenu()
        for (title, list) in [("Dogs", DogSprite.dogs), ("Birds", DogSprite.birds)] {   // Change pet ▸ Dogs ▸ … / Birds ▸ …
            let group = NSMenu()
            for (id, name, kind) in list {
                let item = group.addItem(withTitle: "\(name) — \(kind)", action: #selector(pickDog(_:)), keyEquivalent: "")
                item.target = self; item.representedObject = id
                petItems.append(item)
            }
            species.setSubmenu(group, for: species.addItem(withTitle: title, action: nil, keyEquivalent: ""))
        }
        menu.setSubmenu(species, for: pets)
        hideItem.target = self
        menu.addItem(hideItem)
        menu.addItem(.separator())
        if ProcessInfo.processInfo.environment["LC_DEBUG"] != nil {
            for (title, sel) in [("Test: play with the ball", #selector(testBall)), ("Test: shake the plush", #selector(testPlush)),
                                 ("Test: go to the kennel", #selector(testKennel)), ("Test: zoomies", #selector(testZoomies)),
                                 ("Test: follow the cursor", #selector(testFollow)), ("Test: sit", #selector(testSit)), ("Test: eat", #selector(testEat)), ("Test: drink", #selector(testDrink)), ("Test: groom", #selector(testGroom)),
                                 ("Test: trip", #selector(testTrip)), ("Test: tumble", #selector(testTumble)),
                                 ("Test: busy Mac on/off", #selector(testBusy)),
                                 ("Test (bird): fly to a window", #selector(testFlyToWindow)), ("Test (bird): pretend its window closed", #selector(testWindowClosed)),
                                 ("Test (bird): swing", #selector(testSwing)), ("Test (bird): ring the bell", #selector(testBell)),
                                 ("Test (bird): splash", #selector(testSplash)), ("Test (bird): sleep in the birdhouse", #selector(testHouseSleep))] {
                menu.addItem(withTitle: title, action: sel, keyEquivalent: "").target = self
            }
            menu.addItem(.separator())
        }
        if Bundle.main.bundleURL.pathExtension == "app" {   // only an installed app can open itself at login
            let login = menu.addItem(withTitle: "Open at login", action: #selector(toggleLogin(_:)), keyEquivalent: "")
            login.target = self
            login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        }
        menu.addItem(withTitle: "Quit Little Companion", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item

        world = World(screen: NSScreen.screens.first!)   // the menu-bar screen, where the Dock's floor is
        world?.onStateChange = { [weak self] in self?.refreshDogMenu() }
        refreshDogMenu()
    }

    @objc func toggleLogin(_ sender: NSMenuItem) {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() } else { try SMAppService.mainApp.register() }
        } catch { NSLog("LittleCompanion: open at login failed: \(error)") }
        sender.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    @objc func pickDog(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        world?.switchDog(to: id)
        refreshDogMenu()
    }

    /// Out of sight for an hour (screen sharing, a demo); the dog keeps living meanwhile.
    @objc func toggleHide() {
        guard let world else { return }
        if world.isHidden { world.showNow() } else { world.hide(for: 3600) }
        refreshDogMenu()
    }

    func refreshDogMenu() {
        let name = DogSprite.name
        header.title = name
        for item in petItems { item.state = item.representedObject as? String == DogSprite.dog ? .on : .off }
        hideItem.title = world?.isHidden == true ? "Show \(name) now" : "Hide for an hour"
        readOnlyNote.isHidden = !Store.readOnly.contains(DogSprite.dog)
    }

    func menuWillOpen(_ menu: NSMenu) { refreshDogMenu() }

    func applicationWillTerminate(_ note: Notification) { world?.save() }

    @objc func testBall() { world?.test(.play, "ball") }
    @objc func testPlush() { world?.test(.play, "plush") }
    @objc func testKennel() { world?.test(.kennel, DogSprite.isBird ? "house" : "kennel") }
    @objc func testFlyToWindow() { world?.testFlyToWindow() }
    @objc func testWindowClosed() { world?.testWindowClosed() }
    @objc func testSwing() { world?.test(.swing) }
    @objc func testBell() { world?.test(.bell) }
    @objc func testSplash() { world?.test(.splash, "birdbath") }
    @objc func testHouseSleep() { world?.test(.sleep, "house") }
    @objc func testZoomies() { world?.test(.zoomies) }
    @objc func testFollow() { world?.test(.follow) }
    @objc func testSit() { world?.test(.sit) }
    @objc func testEat() { world?.test(.eat, "food") }
    @objc func testDrink() { world?.test(.drink, "water") }
    @objc func testGroom() { world?.test(.groom) }
    @objc func testTrip() { world?.testFall(tumble: false) }
    @objc func testTumble() { world?.testFall(tumble: true) }
    @objc func testBusy() { world?.forceBusy.toggle() }
}
