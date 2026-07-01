import AppKit
import SwiftUI
import Combine

final class SettingsNavigationModel: ObservableObject {
    @Published var selectedTab: SettingsTab

    init(selectedTab: SettingsTab = .overview) {
        self.selectedTab = selectedTab
    }
}

final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()
    private var window: NSWindow?
    private var hostingController: NSHostingController<SettingsView>?
    private let navigation = SettingsNavigationModel()
    private weak var fans: FanControlService?
    private weak var hub: MonitorHub?

    func showAbout(fans: FanControlService, hub: MonitorHub) {
        show(fans: fans, hub: hub, tab: .advanced)
    }

    func show(fans: FanControlService? = nil, hub: MonitorHub? = nil, tab: SettingsTab? = nil) {
        if let fans { self.fans = fans }
        if let hub { self.hub = hub }
        if let tab { navigation.selectedTab = tab }
        if let window {
            window.deminiaturize(nil)
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            self.fans?.refreshHelperStatus()
            return
        }

        guard let fans else { return }
        let hosting = NSHostingController(rootView: SettingsView(fans: fans, hub: hub ?? self.hub, initialTab: navigation.selectedTab, navigation: navigation))
        let w = NSWindow(contentViewController: hosting)
        w.title = "N1KO-STATE Settings"
        w.styleMask = [.titled, .closable, .resizable, .fullSizeContentView]
        w.minSize = NSSize(width: 900, height: 600)
        w.setContentSize(NSSize(width: 980, height: 720))
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.isMovableByWindowBackground = true
        w.isReleasedWhenClosed = false
        w.delegate = self
        w.center()
        hostingController = hosting
        window = w

        w.deminiaturize(nil)
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        window?.delegate = nil
        window = nil
        hostingController = nil
    }
}
