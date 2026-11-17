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
    let dogMenu = NSMenu()
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
        let dogs = menu.addItem(withTitle: "Change dog", action: nil, keyEquivalent: "")
        for (id, name, kind) in DogSprite.dogs {
            let item = dogMenu.addItem(withTitle: "\(name) — \(kind)", action: #selector(pickDog(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = id
        }
        menu.setSubmenu(dogMenu, for: dogs)
        hideItem.target = self
        menu.addItem(hideItem)
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
        let name = DogSprite.dogs.first { $0.0 == DogSprite.dog }?.1 ?? "Little Companion"
        header.title = name
        for item in dogMenu.items { item.state = item.representedObject as? String == DogSprite.dog ? .on : .off }
        hideItem.title = world?.isHidden == true ? "Show \(name) now" : "Hide for an hour"
        readOnlyNote.isHidden = !Store.readOnly.contains(DogSprite.dog)
    }

    func menuWillOpen(_ menu: NSMenu) { refreshDogMenu() }

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
