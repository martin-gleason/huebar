// Created: 2026-10-12 11:06 -05:00 · Edited: 2026-10-12 11:30 -05:00
import AppKit

@main
enum HueBarApp {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)   // menu bar only; no Dock icon, no main window
        app.run()
    }
}
