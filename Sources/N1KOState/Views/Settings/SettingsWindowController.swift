import AppKit
import SwiftUI

final class SettingsWindowController {
    static let shared = SettingsWindowController()
    private var window: NSWindow?
    private weak var fans: FanControlService?
    private weak var hub: MonitorHub?

    func showAbout(fans: FanControlService, hub: MonitorHub) {
        show(fans: fans, hub: hub, tab: .about)
    }

    func show(fans: FanControlService? = nil, hub: MonitorHub? = nil, tab: SettingsTab? = nil) {
        if let fans { self.fans = fans }
        if let hub { self.hub = hub }
        if let window {
            window.deminiaturize(nil)
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            self.fans?.refreshHelperStatus()
            return
        }

        guard let fans else { return }
        let hosting = NSHostingController(rootView: SettingsView(fans: fans, hub: hub ?? self.hub, initialTab: tab))
        let w = NSWindow(contentViewController: hosting)
        w.title = "N1KO-STATE Settings"
        w.styleMask = [.titled, .closable, .fullSizeContentView]
        w.minSize = NSSize(width: 720, height: 500)
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.isMovableByWindowBackground = true
        w.isReleasedWhenClosed = false
        w.center()
        window = w

        w.deminiaturize(nil)
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
