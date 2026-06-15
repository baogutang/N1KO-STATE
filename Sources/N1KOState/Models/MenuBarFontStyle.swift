import Foundation

enum MenuBarFontStyle: String, CaseIterable, Identifiable {
    case rounded
    case system
    case monospaced

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rounded: return "Rounded"
        case .system: return "System Font"
        case .monospaced: return "Monospaced"
        }
    }

    static func normalized(_ raw: String?) -> MenuBarFontStyle {
        raw.flatMap(MenuBarFontStyle.init(rawValue:)) ?? .rounded
    }
}
