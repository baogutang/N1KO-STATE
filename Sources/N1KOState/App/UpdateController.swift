import AppKit
import N1KOAgentCore
import Sparkle

final class AgentUpdateDeferralGate {
    private var pendingInstallHandler: (() -> Void)?

    static func hasActiveWork(_ snapshot: AgentSnapshot) -> Bool {
        snapshot.sessions.contains { session in
            switch session.phase {
            case .starting, .processing, .waitingForApproval, .waitingForAnswer:
                return true
            case .completed, .interrupted, .failed, .ended, .archived:
                return false
            }
        }
    }

    func postponeIfNeeded(snapshot: AgentSnapshot?, installHandler: @escaping () -> Void) -> Bool {
        guard let snapshot, Self.hasActiveWork(snapshot) else { return false }
        pendingInstallHandler = installHandler
        return true
    }

    func snapshotDidChange(_ snapshot: AgentSnapshot) {
        guard !Self.hasActiveWork(snapshot), let handler = pendingInstallHandler else { return }
        pendingInstallHandler = nil
        handler()
    }
}

/// Thin wrapper around Sparkle so AppKit-facing code does not spread across the app.
final class UpdateController: NSObject, SPUUpdaterDelegate {
    static let shared = UpdateController()

    /// Stable feed URL on `main` — avoids GitHub `releases/latest` redirect + CDN cache issues.
    static let feedURL = "https://raw.githubusercontent.com/baogutang/N1KO-STATE/main/appcast.xml"

    private weak var agentCoordinator: AgentSessionCoordinator?
    private var agentObserverID: UUID?
    private let agentDeferralGate = AgentUpdateDeferralGate()

    private lazy var updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: self,
        userDriverDelegate: nil
    )

    var canCheckForUpdates: Bool {
        updaterController.updater.canCheckForUpdates
    }

    func start() {
        _ = updaterController
    }

    func configure(agentCoordinator: AgentSessionCoordinator?) {
        if let agentObserverID, let current = self.agentCoordinator {
            current.removeSnapshotObserver(agentObserverID)
        }
        self.agentCoordinator = agentCoordinator
        agentObserverID = agentCoordinator?.addSnapshotObserver { [weak self] snapshot in
            self?.agentDeferralGate.snapshotDidChange(snapshot)
        }
    }

    @objc func checkForUpdates(_ sender: Any?) {
        // Drop cached appcast responses so a manual check always sees the latest feed.
        URLCache.shared.removeAllCachedResponses()
        updaterController.checkForUpdates(sender)
    }

    func feedURLString(for updater: SPUUpdater) -> String? {
        Self.feedURL
    }

    func updater(
        _ updater: SPUUpdater,
        shouldPostponeRelaunchForUpdate item: SUAppcastItem,
        untilInvokingBlock installHandler: @escaping () -> Void
    ) -> Bool {
        agentDeferralGate.postponeIfNeeded(
            snapshot: agentCoordinator?.snapshot,
            installHandler: installHandler
        )
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        if let error {
            DiagLog.log("Sparkle", "update check finished with error: \(error.localizedDescription)")
        }
    }
}
