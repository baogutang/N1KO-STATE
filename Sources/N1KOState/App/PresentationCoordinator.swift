import AppKit
import N1KOAgentCore
import SwiftUI

/// Sole owner of Quick Panel and Settings presentation transitions.
@MainActor
final class PresentationCoordinator: NSObject, NSPopoverDelegate {
    private let hub: MonitorHub
    private let menuBar: MenuBarStatusController
    private let settingsController: SettingsWindowController
    private let popover = NSPopover()
    private var popoverEventMonitors: [Any] = []
    private var popoverHostingController: NSHostingController<PopoverRootView>?
    private var agentSurface: AgentSurfaceCoordinator!

    init(hub: MonitorHub,
         menuBar: MenuBarStatusController,
         agentCoordinator: AgentSessionCoordinator? = nil,
         settingsController: SettingsWindowController = .shared) {
        self.hub = hub
        self.menuBar = menuBar
        self.settingsController = settingsController
        super.init()

        agentSurface = AgentSurfaceCoordinator(
            agentCoordinator: agentCoordinator,
            onOpenAgentCenter: { [weak self] in self?.showSettings(tab: .agentCenter) }
        )
        settingsController.configurePresentation(fans: hub.fans, hub: hub)
        settingsController.configureAgentSurface(model: agentSurface.model)

        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        settingsController.onVisibilityChange = { [weak hub] visible in
            hub?.setSettingsVisible(visible)
        }
    }

    func install() {
        menuBar.onClick = { [weak self] in self?.toggleQuickPanel() }
        agentSurface.install()
    }

    func shutdown() {
        agentSurface.shutdown()
        stopPopoverEventMonitoring()
        closeQuickPanel()
    }

    func popoverDidClose(_ notification: Notification) {
        stopPopoverEventMonitoring()
        hub.setPopoverVisible(false)
        // Keep the hosting controller and SwiftUI tree for the next opening.
    }

    func toggleQuickPanel() {
        guard let button = menuBar.statusItem.button else { return }

        if NSApp.currentEvent?.type == .rightMouseUp {
            closeQuickPanel()
            showContextMenu(from: button)
            return
        }

        guard LicenseService.shared.isUnlocked else {
            closeQuickPanel()
            LicenseWindowController.shared.showIfNeeded()
            return
        }

        if popover.isShown {
            closeQuickPanel()
        } else {
            showQuickPanel(from: button)
        }
    }

    func closeQuickPanel() {
        hub.setPopoverVisible(false)
        if popover.isShown { popover.performClose(nil) }
        stopPopoverEventMonitoring()
    }

    func showSettings(tab: SettingsTab? = nil) {
        // One ordered transition prevents stale popover visibility from
        // influencing the sampling plan after Settings opens.
        closeQuickPanel()
        settingsController.show(fans: hub.fans, hub: hub, tab: tab)
    }

    func showAbout() {
        closeQuickPanel()
        settingsController.showAbout(fans: hub.fans, hub: hub)
    }

    func showQuickPanelForPerformanceBenchmark() {
        guard let button = menuBar.statusItem.button else { return }
        popover.behavior = .applicationDefined
        showQuickPanel(from: button)
        stopPopoverEventMonitoring()
    }

    func restoreTransientBehavior() {
        popover.behavior = .transient
    }

    var isQuickPanelVisible: Bool { popover.isShown }
    var quickPanelHostIdentity: ObjectIdentifier? {
        popoverHostingController.map(ObjectIdentifier.init)
    }

    var agentSurfaceCoordinatorForTesting: AgentSurfaceCoordinator { agentSurface }
    var agentSurfacesVisible: Bool {
        agentSurface.desktopPanel?.isVisible == true || agentSurface.revealPanel?.isVisible == true
    }

    @discardableResult
    func prepareQuickPanelHost() -> NSHostingController<PopoverRootView> {
        if let popoverHostingController { return popoverHostingController }
        let root = PopoverRootView(
            hub: hub,
            onOpenSettings: { [weak self] tab in self?.showSettings(tab: tab) },
            onQuit: { NSApp.terminate(nil) }
        )
        let hosting = NSHostingController(rootView: root)
        popoverHostingController = hosting
        popover.contentViewController = hosting
        return hosting
    }

    private func showQuickPanel(from button: NSStatusBarButton) {
        prepareQuickPanelHost()
        hub.setPopoverVisible(true)
        menuBar.redrawNow()
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
                self.closeQuickPanel()
            }
            return event
        }) {
            popoverEventMonitors.append(local)
        }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in
            DispatchQueue.main.async { self?.closeQuickPanel() }
        }) {
            popoverEventMonitors.append(global)
        }
    }

    private func stopPopoverEventMonitoring() {
        for monitor in popoverEventMonitors { NSEvent.removeMonitor(monitor) }
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
        menu.addItem(NSMenuItem(title: "Settings".loc,
                                action: #selector(openSettings),
                                keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "Check for Updates…".loc,
                                action: #selector(checkForUpdates),
                                keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "About N1KO-STATE".loc,
                                action: #selector(openAbout),
                                keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit N1KO-STATE".loc,
                                action: #selector(quit),
                                keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }
        menu.popUp(positioning: nil,
                   at: NSPoint(x: 0, y: button.bounds.height + 4),
                   in: button)
    }

    @objc private func openSettings() { showSettings() }
    @objc private func openAbout() { showAbout() }
    @objc private func checkForUpdates() { UpdateController.shared.checkForUpdates(nil) }
    @objc private func quit() { NSApp.terminate(nil) }
}
