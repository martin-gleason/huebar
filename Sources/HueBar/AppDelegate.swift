import AppKit
import HueCore

/// What a menu item points at. Stored in `representedObject` so clicks need no lookup tables.
enum Ref {
    case light(String)
    case room(String)
    case group(groupedLightID: String, roomID: String, on: Bool)
    case scene(String, roomID: String)
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private var client: HueClient?
    private var snapshot = HueSnapshot.empty
    private var lastError: String?
    private var menuIsOpen = false
    private var menuNeedsRebuild = false
    private var refreshing = false
    private var refreshAgain = false

    func applicationDidFinishLaunching(_ note: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "lightbulb", accessibilityDescription: "Hue")
        menu.delegate = self
        statusItem.menu = menu
        Settings.migrateLegacyDefaults()
        makeClient()
        rebuildMenu()
        Task { await refresh() }
    }

    private var isPaired: Bool { client?.config.appKey != nil }

    private func makeClient() {
        guard let host = Settings.host, (try? Validation.host(host)) != nil else { client = nil; return }
        // The credential only counts if it was issued for this exact address.
        let cred = Settings.credential.flatMap { $0.host == host ? $0 : nil }
        let c = HueClient(config: .init(host: host, appKey: cred?.appKey,
                                        bridgeID: cred?.bridgeID, certFingerprint: cred?.certFingerprint))
        c.onTrustEstablished = { cfg in
            Task { @MainActor in
                guard let key = cfg.appKey else { return }   // persisted by pair() once a key exists
                Settings.credential = BridgeCredential(host: cfg.host, appKey: key, bridgeID: cfg.bridgeID, certFingerprint: cfg.certFingerprint)
            }
        }
        client = c
    }

    // MARK: Refresh

    func refresh() async {
        guard let client, client.config.appKey != nil else { return }
        if refreshing { refreshAgain = true; return }   // a click landed mid-refresh: go once more after
        refreshing = true
        defer { refreshing = false }
        repeat {
            refreshAgain = false
            do {
                snapshot = try await client.snapshot()
                lastError = nil
            } catch {
                lastError = error.localizedDescription
            }
        } while refreshAgain
        if menuIsOpen { applyState(); menuNeedsRebuild = true } else { rebuildMenu() }
        updateIcon()
    }

    private func updateIcon() {
        statusItem.button?.image = NSImage(systemSymbolName: snapshot.anyOn ? "lightbulb.fill" : "lightbulb",
                                           accessibilityDescription: "Hue")
    }

    // MARK: NSMenuDelegate

    func menuWillOpen(_ menu: NSMenu) {
        guard menu === self.menu else { return }
        menuIsOpen = true
        Task { await refresh() }           // menu shows cached state at once; checkmarks update in place
    }

    func menuDidClose(_ menu: NSMenu) {
        guard menu === self.menu else { return }
        menuIsOpen = false
        if menuNeedsRebuild { menuNeedsRebuild = false; rebuildMenu() }
    }

    // MARK: Menu construction

    private func rebuildMenu() {
        menu.removeAllItems()
        if let err = lastError {
            menu.addItem(disabled("⚠︎ \(Validation.displayName(err, maxLength: 120))"))
            menu.addItem(.separator())
        }
        if client == nil {
            menu.addItem(action("Find Bridge…", #selector(findBridge)))
            menu.addItem(action("Set Bridge Address…", #selector(setAddress)))
        } else if !isPaired {
            menu.addItem(action("Pair with Bridge…", #selector(pair)))
            menu.addItem(action("Set Bridge Address…", #selector(setAddress)))
        } else {
            for room in snapshot.rooms { menu.addItem(roomItem(room)) }
            if !snapshot.unassigned.isEmpty {
                if !snapshot.rooms.isEmpty { menu.addItem(.separator()) }
                menu.addItem(.sectionHeader(title: "Other Lights"))
                for light in snapshot.unassigned { menu.addItem(lightItem(light)) }
            }
            if snapshot.rooms.isEmpty && snapshot.unassigned.isEmpty { menu.addItem(disabled("No lights found")) }
            menu.addItem(.separator())
            menu.addItem(action("All Lights Off", #selector(allOff)))
            menu.addItem(action("Refresh", #selector(refreshAction), key: "r"))
            menu.addItem(.separator())
            menu.addItem(disabled("Bridge: \(Settings.host ?? "")"))
            menu.addItem(action("Set Bridge Address…", #selector(setAddress)))
            menu.addItem(action("Pair Again…", #selector(pair)))
        }
        menu.addItem(.separator())
        menu.addItem(action("Quit HueBar", #selector(quit), key: "q"))
    }

    private func roomItem(_ room: HueSnapshot.Room) -> NSMenuItem {
        let parent = NSMenuItem(title: room.name, action: nil, keyEquivalent: "")
        parent.representedObject = Ref.room(room.id)
        parent.state = room.anyOn ? .on : .off
        let sub = NSMenu(title: room.name)
        if let g = room.groupedLightID {
            sub.addItem(action("All On", #selector(setGroup(_:)), ref: .group(groupedLightID: g, roomID: room.id, on: true)))
            sub.addItem(action("All Off", #selector(setGroup(_:)), ref: .group(groupedLightID: g, roomID: room.id, on: false)))
        }
        if !room.scenes.isEmpty {
            sub.addItem(.separator())
            sub.addItem(.sectionHeader(title: "Scenes"))
            for s in room.scenes { sub.addItem(action(s.displayName, #selector(recallScene(_:)), ref: .scene(s.id, roomID: room.id))) }
        }
        if !room.lights.isEmpty {
            sub.addItem(.separator())
            sub.addItem(.sectionHeader(title: "Lights"))
            for l in room.lights { sub.addItem(lightItem(l)) }
        }
        parent.submenu = sub
        return parent
    }

    private func lightItem(_ light: Light) -> NSMenuItem {
        let item = action(light.displayName, #selector(toggleLight(_:)), ref: .light(light.id))
        item.state = light.isOn ? .on : .off
        return item
    }

    private func action(_ title: String, _ selector: Selector, key: String = "", ref: Ref? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: key)
        item.target = self
        item.representedObject = ref
        return item
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    /// Update checkmarks in place without rebuilding (safe while the menu is open).
    private func applyState() {
        func walk(_ m: NSMenu) {
            for item in m.items {
                switch item.representedObject as? Ref {
                case .light(let id)?: item.state = (snapshot.light(id)?.isOn ?? false) ? .on : .off
                case .room(let id)?: item.state = (snapshot.rooms.first { $0.id == id }?.anyOn ?? false) ? .on : .off
                default: break
                }
                if let sub = item.submenu { walk(sub) }
            }
        }
        walk(menu)
    }

    // MARK: Actions (optimistic: update the menu now, tell the bridge, then re-sync)

    @objc private func toggleLight(_ sender: NSMenuItem) {
        guard case .light(let id)? = sender.representedObject as? Ref, let client else { return }
        let on = !(snapshot.light(id)?.isOn ?? false)
        snapshot.setLight(id, on: on)
        send { try await client.setLight(id, on: on) }
    }

    @objc private func setGroup(_ sender: NSMenuItem) {
        guard case .group(let gid, let roomID, let on)? = sender.representedObject as? Ref, let client else { return }
        snapshot.setRoom(roomID, on: on)
        send { try await client.setGroupedLight(gid, on: on) }
    }

    @objc private func recallScene(_ sender: NSMenuItem) {
        guard case .scene(let sid, let roomID)? = sender.representedObject as? Ref, let client else { return }
        snapshot.setRoom(roomID, on: true)
        send { try await client.recallScene(sid) }
    }

    @objc private func allOff() {
        guard let client else { return }
        snapshot.setAll(on: false)
        if let all = snapshot.allGroupedLightID {
            send { try await client.setGroupedLight(all, on: false) }
        } else {
            let groups = snapshot.rooms.compactMap { $0.kind == .room ? $0.groupedLightID : nil }
            let loose = snapshot.unassigned.map(\.id)
            send {
                for g in groups { try await client.setGroupedLight(g, on: false) }
                for l in loose { try await client.setLight(l, on: false) }
            }
        }
    }

    private func send(_ op: @escaping () async throws -> Void) {
        applyState()
        updateIcon()
        Task {
            do { try await op() } catch { lastError = error.localizedDescription; menuNeedsRebuild = true }
            try? await Task.sleep(for: .milliseconds(700))   // let the bridge settle, then re-sync
            await refresh()
        }
    }

    @objc private func refreshAction() { Task { await refresh() } }

    @objc private func quit() { NSApp.terminate(nil) }

    // MARK: Setup flows

    @objc private func findBridge() {
        Task {
            do {
                guard let bridge = try await Discovery.cloud().first else {
                    show("No bridge found", "The Hue cloud lookup returned nothing. Use Set Bridge Address… and enter the bridge IP.")
                    return
                }
                setHost(bridge.internalipaddress)
                pair()
            } catch {
                show("Discovery failed", error.localizedDescription)
            }
        }
    }

    @objc private func setAddress() {
        let alert = NSAlert()
        alert.messageText = "Bridge Address"
        alert.informativeText = "IP address or hostname of your Hue Bridge."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.stringValue = Settings.host ?? ""
        field.placeholderString = "192.168.1.2"
        alert.accessoryView = field
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        guard let host = try? Validation.host(field.stringValue) else {
            show("Not a valid address", "Enter an IP address such as 192.168.1.2, or a plain hostname.")
            return
        }
        setHost(host)
        if !isPaired { pair() }
    }

    private func setHost(_ host: String) {
        if host != Settings.host {
            Settings.credential = nil      // a new address means a new bridge: re-pair and re-verify identity
            snapshot = .empty
        }
        Settings.host = host
        lastError = nil
        makeClient()
        rebuildMenu()
        updateIcon()
    }

    @objc private func pair() {
        guard let client else { return }
        let alert = NSAlert()
        alert.messageText = "Pair with Hue Bridge"
        alert.informativeText = "Press the round link button on the bridge, then click Pair."
        alert.addButton(withTitle: "Pair")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        Task {
            do {
                let key = try await client.pair(deviceType: "huebar#mac")
                let cfg = client.config
                Settings.credential = BridgeCredential(host: cfg.host, appKey: key, bridgeID: cfg.bridgeID, certFingerprint: cfg.certFingerprint)
                makeClient()
                await refresh()
                rebuildMenu()
            } catch HueClient.HueError.linkButtonNotPressed {
                show("Link button not pressed", "Press the button on the bridge and try again within 30 seconds.")
            } catch {
                show("Pairing failed", error.localizedDescription)
            }
        }
    }

    private func show(_ title: String, _ text: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
