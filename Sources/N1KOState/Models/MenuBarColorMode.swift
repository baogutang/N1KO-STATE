import Foundation

/// Color strategy for the menu-bar readout.
enum MenuBarColorMode: String, CaseIterable, Identifiable {
    case colorful
    case adaptive

    var id: String { rawValue }

    var title: String {
        switch self {
        case .colorful: return "Colorful"
        case .adaptive: return "Menu Bar Adaptive"
        }
    }

    var detail: String {
        switch self {
        case .colorful: return "Use colored metric accents."
        case .adaptive: return "Use the menu bar's automatic inverted color."
        }
    }

    static func normalized(_ raw: String?) -> MenuBarColorMode {
        raw.flatMap(MenuBarColorMode.init(rawValue:)) ?? .colorful
    }
}
