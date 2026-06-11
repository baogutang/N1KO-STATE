import SwiftUI

/// Entry point. The menu-bar icon is an `NSStatusItem` (see `MenuBarStatusController`)
/// because SwiftUI `MenuBarExtra` often fails to show a label on recent macOS.
@main
struct N1KOStateApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsSceneHost()
        }
    }
}

/// Bridges the system Settings scene (Cmd+,) to the shared `FanControlService`.
private struct SettingsSceneHost: View {
    var body: some View {
        if let fans = AppDelegate.sharedFans {
            SettingsView(fans: fans, hub: AppDelegate.sharedHub, initialTab: nil)
        } else {
            Text(loc: "Loading…")
                .frame(width: 400, height: 300)
        }
    }
}
