import Foundation
import SwiftUI

/// Selects which `.lproj` bundle `.loc` reads from, so the user can override the
/// app language independently of the system language (and switch it live).
final class LocalizationManager {
    static let shared = LocalizationManager()

    /// "system" follows the OS language; otherwise a specific `.lproj` code.
    static let system = "system"

    private(set) var bundle: Bundle = .main

    /// Apply a language code ("system" / "en" / "zh-Hans" / "zh-Hant").
    func apply(_ language: String) {
        guard language != Self.system,
              let path = Bundle.main.path(forResource: language, ofType: "lproj"),
              let b = Bundle(path: path) else {
            bundle = .main
            return
        }
        bundle = b
    }
}

/// Tiny localization helper.
///
/// User-facing strings are looked up in `Localizable.strings` (en / zh-Hans /
/// zh-Hant) shipped inside the app bundle. The English text is also used as the
/// lookup *key*, so a missing translation gracefully falls back to English.
extension String {
    /// Localized form of `self` using the key == English-text convention.
    var loc: String {
        LocalizationManager.shared.bundle.localizedString(forKey: self, value: self, table: nil)
    }

    /// Localized + formatted, e.g. `"%@ free".locf(used)`.
    func locf(_ args: CVarArg...) -> String {
        String(format: loc, arguments: args)
    }
}

/// `Text` from an already-localized String (verbatim — avoids double lookup).
extension Text {
    init(loc key: String) {
        self.init(verbatim: key.loc)
    }
}
