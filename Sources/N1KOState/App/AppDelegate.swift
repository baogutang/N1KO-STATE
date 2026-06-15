import AppKit
import SwiftUI
import UserNotifications

/// Owns the shared monitor hub, menu-bar status item, and popover.
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate, NSPopoverDelegate {

    let hub = MonitorHub()
    private var menuBar: MenuBarStatusController!
    private let popover = NSPopover()
    private var popoverEventMonitors: [Any] = []

    /// `atexit` can't capture `self`; route the last-ditch reset through a
    /// process-global weak reference. This is a best-effort backstop only — the
    /// real guarantee that `FS!` returns to 0 on any exit (including SIGKILL) is
    /// the daemon's connection-invalidation handler.
    static weak var sharedFans: FanControlService?
    static weak var sharedHub: MonitorHub?

    func applicationWillTerminate(_ notification: Notification) {
        hub.flushHistory()
        hub.fans.resetAllFansSync()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        DiagLog.bootstrap()
        DiagLog.log("AppDelegate", "applicationDidFinishLaunching")
        NSApp.setActivationPolicy(.accessory)
        migrateOldDefaults()

        if AlertManager.notificationsSupported {
            UNUserNotificationCenter.current().delegate = self
        }

        hub.start()
        setupMenuBar()
        setupPopover()
        UpdateController.shared.start()
        LicenseService.shared.refresh()

        // Bug-1: initialise UI from the real SMC FS! value (not any persisted
        // preference), and re-sync after the machine wakes from sleep.
        hub.fans.syncFromSMC()
        AppDelegate.sharedFans = hub.fans
        AppDelegate.sharedHub = hub
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(systemDidWake),
            name: NSWorkspace.didWakeNotification, object: nil)
        atexit { AppDelegate.sharedFans?.resetAllFansSync(timeout: 1.5) }

        if !UserDefaults.standard.bool(forKey: "didShowOnboarding") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                NSApp.activate(ignoringOtherApps: true)
                OnboardingWindowController.shared.show(hub: self.hub)
            }
        } else {
            DispatchQueue.main.async {
                LicenseWindowController.shared.showIfNeeded()
            }
        }
        hub.fans.refreshHelperStatus()
    }

    @objc private func systemDidWake() {
        hub.fans.syncFromSMC()
    }

    /// One-time migration from the old bundle ID's UserDefaults domain.
    private func migrateOldDefaults() {
        let cur = UserDefaults.standard
        guard !cur.bool(forKey: "didMigrateV1") else { return }
        if let old = UserDefaults(suiteName: "com.n1kostate.menubar.app2026") {
            let keys = ["menuCPU", "menuGPU", "menuMemory", "menuNetwork",
                        "menuBattery", "menuCompact", "menuBarLayout", "popoverStyle", "refreshInterval",
                        "accentHex", "useFahrenheit", "sensorsDetailed",
                        "language", "showCPU", "showGPU", "showMemory",
                        "showDisk", "showNetwork", "showSensors", "showBattery",
                        "moduleOrder", "alertsEnabled", "cpuAlert", "cpuThreshold",
                        "memAlert", "memThreshold", "tempAlert", "tempThreshold",
                        "diskAlert", "diskFreeThreshold", "batteryAlert", "batteryThreshold"]
            for key in keys {
                if let val = old.object(forKey: key) {
                    cur.set(val, forKey: key)
                }
            }
        }
        cur.set(true, forKey: "didMigrateV1")
    }

    private func setupMenuBar() {
        menuBar = MenuBarStatusController(hub: hub)
        menuBar.onClick = { [weak self] in self?.togglePopover() }
        menuBar.install()
    }

    private func setupPopover() {
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
    }

    func popoverDidClose(_ notification: Notification) {
        stopPopoverEventMonitoring()
        popover.contentViewController = nil
        hub.setPopoverVisible(false)
    }

    private func togglePopover() {
        guard let button = menuBar.statusItem.button else { return }

        if NSApp.currentEvent?.type == .rightMouseUp {
            closePopoverIfShown()
            showContextMenu(from: button)
            return
        }

        guard LicenseService.shared.isUnlocked else {
            closePopoverIfShown()
            LicenseWindowController.shared.showIfNeeded()
            return
        }

        if popover.isShown {
            closePopoverIfShown()
        } else {
            showPopover(from: button)
        }
    }

    private func closePopoverIfShown() {
        guard popover.isShown else { return }
        hub.setPopoverVisible(false)
        popover.performClose(nil)
        stopPopoverEventMonitoring()
    }

    private func showPopover(from button: NSStatusBarButton) {
        if popover.contentViewController == nil {
            popover.contentViewController = NSHostingController(rootView: PopoverRootView(hub: hub))
        }
        hub.setPopoverVisible(true)
        if !popover.isShown {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
        startPopoverEventMonitoring()
    }

    private func startPopoverEventMonitoring() {
        stopPopoverEventMonitoring()
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown]
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            guard let self else { return event }
            if self.popover.isShown,
               !self.isEventInsidePopover(event),
               !self.isEventOnStatusItem(event) {
                self.closePopoverIfShown()
            }
            return event
        }) {
            popoverEventMonitors.append(local)
        }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in
            DispatchQueue.main.async {
                self?.closePopoverIfShown()
            }
        }) {
            popoverEventMonitors.append(global)
        }
    }

    private func stopPopoverEventMonitoring() {
        for monitor in popoverEventMonitors {
            NSEvent.removeMonitor(monitor)
        }
        popoverEventMonitors.removeAll()
    }

    private func isEventInsidePopover(_ event: NSEvent) -> Bool {
        guard let popoverWindow = popover.contentViewController?.view.window else { return false }
        return event.window === popoverWindow
    }

    private func isEventOnStatusItem(_ event: NSEvent) -> Bool {
        guard let button = menuBar.statusItem.button,
              let buttonWindow = button.window,
              event.window === buttonWindow else { return false }
        let point = button.convert(event.locationInWindow, from: nil)
        return button.bounds.contains(point)
    }

    private func showContextMenu(from button: NSStatusBarButton) {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Settings".loc, action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "Check for Updates…".loc,
                                action: #selector(checkForUpdates),
                                keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "About N1KO-STATE".loc, action: #selector(openAbout), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit N1KO-STATE".loc, action: #selector(quit), keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 4), in: button)
    }

    @objc private func openSettings() {
        SettingsWindowController.shared.show(fans: hub.fans, hub: hub)
    }

    @objc private func openAbout() {
        SettingsWindowController.shared.showAbout(fans: hub.fans, hub: hub)
    }

    @objc private func checkForUpdates() {
        UpdateController.shared.checkForUpdates(nil)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
