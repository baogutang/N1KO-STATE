// N1KO modification notice: adapted from Ping Island commit da130d6 for
// N1KO's single-owner integration, macOS 12 compatibility, or fullscreen boundary.

import AppKit
import Combine
import Foundation

enum NotificationEvent: String, CaseIterable, Identifiable {
    case processingStarted
    case attentionRequired
    case taskCompleted
    case taskError
    case resourceLimit

    var id: String { rawValue }

    var title: String {
        switch self {
        case .processingStarted:
            return "开始处理"
        case .attentionRequired:
            return "需要介入"
        case .taskCompleted:
            return "完成"
        case .taskError:
            return "任务失败"
        case .resourceLimit:
            return "资源受限"
        }
    }

    var subtitle: String {
        switch self {
        case .processingStarted:
            return "会话开始处理、运行工具或进入阶段切换。"
        case .attentionRequired:
            return "等待审批、回答问题或其他需要你接手的时刻。"
        case .taskCompleted:
            return "当前处理结束，回到等待你下一步输入。"
        case .taskError:
            return "工具或子代理执行失败。"
        case .resourceLimit:
            return "进入 PreCompact / compacting，通常表示上下文或资源逼近限制。"
        }
    }

    var defaultSound: NotificationSound {
        switch self {
        case .processingStarted:
            return .tink
        case .attentionRequired:
            return .glass
        case .taskCompleted:
            return .blow
        case .taskError:
            return .basso
        case .resourceLimit:
            return .morse
        }
    }

    var cespCategories: [String] {
        switch self {
        case .processingStarted:
            return ["task.acknowledge", "session.start"]
        case .attentionRequired:
            return ["input.required"]
        case .taskCompleted:
            return ["task.complete"]
        case .taskError:
            return ["task.error"]
        case .resourceLimit:
            return ["resource.limit"]
        }
    }

}

enum SoundThemeMode: String, CaseIterable, Identifiable {
    case builtIn
    case island8Bit
    case soundPack

    var id: String { rawValue }

    var title: String {
        switch self {
        case .builtIn:
            return "系统音"
        case .island8Bit:
            return "内置 8-bit"
        case .soundPack:
            return "主题包"
        }
    }

    var subtitle: String {
        switch self {
        case .builtIn:
            return "为不同阶段分别选择 macOS 系统音。"
        case .island8Bit:
            return "使用 Island 内置的 8-bit 固定方案，并带有客户端启动音。"
        case .soundPack:
            return "使用兼容 OpenPeon / CESP 的本地音效包。"
        }
    }
}

enum Island8BitSound: String, CaseIterable, Identifiable {
    case approvalAlert = "8bit_approval_alert"
    case bootJingle = "8bit_boot_jingle"
    case bubblePop = "bubbles_pop"
    case completeDing = "8bit_complete_ding"
    case errorBuzz = "8bit_error_buzz"
    case hurt = "8bit_hurt"
    case itemPickup = "8bit_item_pickup"
    case menuHighlight = "8bit_menu_highlight"
    case menuSelect = "8bit_menu_select"
    case powerUp = "8bit_power_up"
    case startChime = "8bit_start_chime"
    case submitBlip = "8bit_submit_blip"
    case winJingle = "8bit_win_jingle"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .approvalAlert:
            return "Approval Alert"
        case .bootJingle:
            return "Boot Jingle"
        case .bubblePop:
            return "Bubble Pop"
        case .completeDing:
            return "Complete Ding"
        case .errorBuzz:
            return "Error Buzz"
        case .hurt:
            return "Hurt"
        case .itemPickup:
            return "Item Pickup"
        case .menuHighlight:
            return "Menu Highlight"
        case .menuSelect:
            return "Menu Select"
        case .powerUp:
            return "Power Up"
        case .startChime:
            return "Start Chime"
        case .submitBlip:
            return "Submit Blip"
        case .winJingle:
            return "Win Jingle"
        }
    }

    static let allOrdered: [Island8BitSound] = Island8BitSound.allCases.sorted { $0.label < $1.label }
}
