import AppKit

/// AppKit entry point. PresentationCoordinator is the only Quick Panel and
/// Settings authority; there is no second SwiftUI Settings scene lifecycle.
@main
enum N1KOStateApp {
    @MainActor
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.run()
        withExtendedLifetime(delegate) {}
    }
}
