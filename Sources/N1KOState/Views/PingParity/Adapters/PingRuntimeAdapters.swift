import AppKit
import Combine
import Foundation
import N1KOAgentCore

// N1KO boundary adapters for upstream services that must not become a second
// lifecycle, updater, telemetry client, or window/session owner.

@MainActor
final class ScreenSelector: ObservableObject {
    static let shared = ScreenSelector()
    @Published private(set) var availableScreens: [NSScreen] = NSScreen.screens
    @Published private(set) var selectedScreen: NSScreen? = NSScreen.main

    func projectN1KOTarget(_ screen: NSScreen?) {
        availableScreens = NSScreen.screens
        selectedScreen = screen ?? NSScreen.main
    }
}

extension NSScreen {
    var notchMetrics: ScreenNotchMetrics {
        ScreenNotchMetrics.detect(
            screenFrame: frame,
            safeAreaTop: safeAreaInsets.top,
            auxiliaryTopLeftWidth: auxiliaryTopLeftArea?.width,
            auxiliaryTopRightWidth: auxiliaryTopRightArea?.width
        )
    }

    var notchSize: CGSize { notchMetrics.size }
    var hasPhysicalNotch: Bool { notchMetrics.hasPhysicalNotch }

    var isBuiltinDisplay: Bool {
        guard let displayID = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
                as? CGDirectDisplayID else { return false }
        return CGDisplayIsBuiltin(displayID) != 0
    }
}

@MainActor
final class UpdateManager: ObservableObject {
    static let shared = UpdateManager()
    @Published private(set) var hasUnseenUpdate = false
    func markUpdateSeen() { hasUnseenUpdate = false }
}

actor TelemetryService {
    static let shared = TelemetryService()
    func recordIslandOpened(openSource: String, contentRoute: String, presentation: String) {}
    func recordIslandClosed(openSource: String, contentRoute: String, presentation: String) {}
}

actor WindowFinder {
    static let shared = WindowFinder()
    func isYabaiAvailable() -> Bool { false }
}

actor SessionLauncher {
    static let shared = SessionLauncher()

    @discardableResult
    func activate(_ session: SessionState) async -> Bool {
        await MainActor.run {
            if let source = N1KOSessionActionRouter.shared.source(sessionID: session.sessionId) {
                AgentIntegrationController.shared.focus(session: source)
                return true
            }
            if let bundleID = session.clientInfo.terminalBundleIdentifier,
               let application = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
                return application.activate(options: [.activateIgnoringOtherApps])
            }
            return Self.activateClientApplicationOnMainActor(session)
        }
    }

    @discardableResult
    func activateClientApplication(_ session: SessionState) async -> Bool {
        await MainActor.run { Self.activateClientApplicationOnMainActor(session) }
    }

    @MainActor
    private static func activateClientApplicationOnMainActor(_ session: SessionState) -> Bool {
        if let bundleID = session.clientInfo.bundleIdentifier,
           let application = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
            return application.activate(options: [.activateIgnoringOtherApps])
        }
        guard FileManager.default.fileExists(atPath: session.cwd) else { return false }
        return NSWorkspace.shared.open(URL(fileURLWithPath: session.cwd, isDirectory: true))
    }
}

@MainActor
final class N1KOSessionActionRouter {
    static let shared = N1KOSessionActionRouter()

    private var sources: [String: AgentSessionSnapshot] = [:]

    func replace(with sources: [String: AgentSessionSnapshot]) {
        self.sources = sources
    }

    func source(sessionID: String) -> AgentSessionSnapshot? {
        sources[sessionID]
    }
}

class NotchPanel: NSPanel {}

extension Notification.Name {
    static let n1koOpenActiveSessionShortcut = Notification.Name("n1ko.agent.openActiveSession")
    static let n1koOpenSessionListShortcut = Notification.Name("n1ko.agent.openSessionList")
    static let n1koPresentNotchDetachmentHint = Notification.Name("n1ko.agent.presentDetachmentHint")
    static let n1koHookWalkthroughDemoShouldCloseNotch = Notification.Name("n1ko.agent.walkthrough.closeIsland")
}
