import Foundation
import ServiceManagement

/// Thin wrapper around `SMAppService` for the "launch at login" preference.
///
/// `SMAppService.mainApp` (macOS 13+) registers the running `.app` itself as a
/// login item — no separate helper target needed. On macOS 12 the API is
/// unavailable, so the option is hidden.
enum LoginItem {

    /// Whether the platform supports the modern login-item API.
    static var isAvailable: Bool {
        if #available(macOS 13.0, *) { return true }
        return false
    }

    /// Current registration state (source of truth lives in the system, not
    /// `UserDefaults`).
    static var isEnabled: Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return false
    }

    /// Registers or unregisters the app as a login item. Failures (e.g. an
    /// unsigned dev build, or running from a non-Applications location) are
    /// swallowed — the UI simply won't reflect a change.
    @discardableResult
    static func set(_ enabled: Bool) -> Bool {
        guard #available(macOS 13.0, *) else { return false }
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
            } else {
                if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            }
            return true
        } catch {
            return false
        }
    }
}
