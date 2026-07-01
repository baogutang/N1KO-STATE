import AppKit
import Sparkle

/// Thin wrapper around Sparkle so AppKit-facing code does not spread across the app.
final class UpdateController: NSObject, SPUUpdaterDelegate {
    static let shared = UpdateController()

    /// Stable feed URL on `main` — avoids GitHub `releases/latest` redirect + CDN cache issues.
    static let feedURL = "https://raw.githubusercontent.com/baogutang/N1KO-STATE/main/appcast.xml"

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

    @objc func checkForUpdates(_ sender: Any?) {
        // Drop cached appcast responses so a manual check always sees the latest feed.
        URLCache.shared.removeAllCachedResponses()
        updaterController.checkForUpdates(sender)
    }

    func feedURLString(for updater: SPUUpdater) -> String? {
        Self.feedURL
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        if let error {
            DiagLog.log("Sparkle", "update check finished with error: \(error.localizedDescription)")
        }
    }
}
