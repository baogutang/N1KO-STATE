import AppKit
import SwiftUI
import Combine

enum SettingsLayoutPolicy {
    static let minimumSize = NSSize(width: 900, height: 600)
    static let idealSize = NSSize(width: 980, height: 720)
}

final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()
    private var window: NSWindow?
    private var hostingController: NSHostingController<SettingsView>?
    private let navigation = SettingsNavigationModel()
    private weak var fans: FanControlService?
    private weak var hub: MonitorHub?
    private var agentSurfaceModel: AgentSurfaceModel?
    private var titleObservation: AnyCancellable?
    private(set) var windowCreationCount = 0
    var onVisibilityChange: ((Bool) -> Void)?

    func configureAgentSurface(model: AgentSurfaceModel) {
        agentSurfaceModel = model
    }

    /// Installs the dependencies owned by N1KO's sole presentation authority.
    /// Pinned Island source can then open Settings on a fresh launch without
    /// creating or owning a second settings controller.
    func configurePresentation(fans: FanControlService, hub: MonitorHub) {
        self.fans = fans
        self.hub = hub
    }

    func showAbout(fans: FanControlService, hub: MonitorHub) {
        show(fans: fans, hub: hub, tab: .advanced)
    }

    func show(fans: FanControlService? = nil, hub: MonitorHub? = nil, tab: SettingsTab? = nil) {
        if let fans { self.fans = fans }
        if let hub { self.hub = hub }
        if let tab { navigation.selectedTab = tab }
        guard let activeFans = fans ?? self.fans else { return }
        guard let monitorHub = hub ?? self.hub else { return }
        let w = prepareWindow()
        if let hostingController {
            if w.contentViewController !== hostingController {
                w.contentViewController = hostingController
            }
        } else {
            let hosting = NSHostingController(
                rootView: SettingsView(
                    fans: activeFans,
                    hub: monitorHub,
                    initialTab: navigation.selectedTab,
                    navigation: navigation,
                    agentModel: agentSurfaceModel ?? AgentSurfaceModel()
                )
            )
            hostingController = hosting
            w.contentViewController = hosting
        }
        updateWindowTitle(for: navigation.selectedTab)
        w.deminiaturize(nil)
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        activeFans.refreshHelperStatus()
        onVisibilityChange?(true)
    }

    /// Pinned-source action compatibility; presentation still routes through
    /// N1KO's single settings-window controller.
    func present() {
        show(tab: .agentCenter)
    }

    @discardableResult
    private func prepareWindow() -> NSWindow {
        if let window { return window }

        let w = NSWindow()
        w.styleMask = [.titled, .closable, .resizable, .fullSizeContentView]
        w.minSize = SettingsLayoutPolicy.minimumSize
        w.setContentSize(SettingsLayoutPolicy.idealSize)
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.isMovableByWindowBackground = true
        w.isReleasedWhenClosed = false
        w.delegate = self
        w.center()
        window = w
        windowCreationCount += 1
        titleObservation = navigation.$selectedTab
            .removeDuplicates()
            .sink { [weak self] tab in self?.updateWindowTitle(for: tab) }
        return w
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        hideAndDetachContent()
        return false
    }

    private func hideAndDetachContent() {
        window?.orderOut(nil)
        onVisibilityChange?(false)
        window?.contentViewController = nil
    }

    private func updateWindowTitle(for tab: SettingsTab) {
        window?.title = "N1KO-STATE — %@".locf(tab.rawValue.loc)
    }

    /// Used only by the opt-in WP0 benchmark driver so repeated lifecycle
    /// measurements do not depend on Accessibility-driven UI automation.
    func closeForPerformanceBenchmark() {
        hideAndDetachContent()
    }

    var isVisibleForPerformanceBenchmark: Bool {
        window?.isVisible == true
    }

    /// Creates the native window without attaching live monitor content. This
    /// keeps the one-window identity gate deterministic in unit tests.
    @discardableResult
    func prepareWindowForTesting() -> ObjectIdentifier {
        let prepared = prepareWindow()
        prepared.orderOut(nil)
        return ObjectIdentifier(prepared)
    }

    var windowIdentity: ObjectIdentifier? { window.map(ObjectIdentifier.init) }
    var hostingIdentity: ObjectIdentifier? { hostingController.map(ObjectIdentifier.init) }
    var selectedTabForTesting: SettingsTab { navigation.selectedTab }
}
