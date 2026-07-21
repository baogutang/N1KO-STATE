// N1KO modification notice: adapted from Ping Island commit da130d6 for
// N1KO's single-owner integration, macOS 12 compatibility, or fullscreen boundary.

//
//  Settings.swift
//  PingIsland
//
//  App settings manager using UserDefaults
//

import AppKit
import Combine
import Foundation

enum AppSettingsDefaultKeys {
    nonisolated static let surfaceMode = "surfaceMode"
    nonisolated static let notchModuleWidth = "notchModuleWidth"
    nonisolated static let floatingPetAnchor = "floatingPetAnchor"
    nonisolated static let floatingPetSizeMode = "floatingPetSizeMode"
    nonisolated static let presentationModeOnboardingPending = "presentationModeOnboardingPending"
    nonisolated static let notchDetachmentHintPending = "notchDetachmentHintPending"
    nonisolated static let floatingPetSettingsHintPending = "floatingPetSettingsHintPending"
    nonisolated static let hookInstallOnboardingPending = "hookInstallOnboardingPending"
    nonisolated static let analyticsEnabled = TelemetryConsent.analyticsEnabledKey
    nonisolated static let analyticsConsentPromptCompleted = "analyticsConsentPromptCompleted"
}

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case simplifiedChinese
    case english

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system:
            return "跟随系统"
        case .simplifiedChinese:
            return "简体中文"
        case .english:
            return "English"
        }
    }

    func resolvedLanguageCode(preferredLanguages: [String] = Locale.preferredLanguages) -> String {
        switch self {
        case .system:
            let preferredLanguage = preferredLanguages.first?.lowercased() ?? ""
            if preferredLanguage.hasPrefix("zh") {
                return "zh-Hans"
            }
            return "en"
        case .simplifiedChinese:
            return "zh-Hans"
        case .english:
            return "en"
        }
    }

    func resolvedLocale(preferredLanguages: [String] = Locale.preferredLanguages) -> Locale {
        Locale(identifier: resolvedLanguageCode(preferredLanguages: preferredLanguages))
    }
}

/// Available notification sounds
enum NotificationSound: String, CaseIterable {
    case none = "None"
    case pop = "Pop"
    case ping = "Ping"
    case tink = "Tink"
    case glass = "Glass"
    case blow = "Blow"
    case bottle = "Bottle"
    case frog = "Frog"
    case funk = "Funk"
    case hero = "Hero"
    case morse = "Morse"
    case purr = "Purr"
    case sosumi = "Sosumi"
    case submarine = "Submarine"
    case basso = "Basso"

    /// The system sound name to use with NSSound, or nil for no sound
    var soundName: String? {
        self == .none ? nil : rawValue
    }
}

final class SoundPlaybackCoordinator {
    private var activeSound: NSSound?

    @discardableResult
    func play(_ sound: NSSound, volume: Float) -> Bool {
        stopActiveSound(except: sound)

        if isActiveSound(sound), sound.isPlaying {
            sound.stop()
        }

        sound.volume = volume
        let didPlay = sound.play()
        activeSound = didPlay ? sound : nil
        return didPlay
    }

    func clearIfActive(_ sound: NSSound) {
        guard isActiveSound(sound) else { return }
        activeSound = nil
    }

    private func stopActiveSound(except sound: NSSound) {
        guard let activeSound, !isSameSound(activeSound, sound) else { return }
        if activeSound.isPlaying {
            activeSound.stop()
        }
        self.activeSound = nil
    }

    private func isActiveSound(_ sound: NSSound) -> Bool {
        guard let activeSound else { return false }
        return isSameSound(activeSound, sound)
    }

    private func isSameSound(_ lhs: NSSound, _ rhs: NSSound) -> Bool { lhs === rhs }
}

enum AppSoundPlayback {
    static let shared = SoundPlaybackCoordinator()
}

enum UsageValueMode: String, CaseIterable, Identifiable {
    case used
    case remaining

    var id: String { rawValue }

    var title: String {
        switch self {
        case .used:
            return "已用量"
        case .remaining:
            return "剩余量"
        }
    }
}

enum AutoRoutePromptsIdleDelay: Int, CaseIterable, Identifiable {
    case tenMinutes = 600
    case twentyMinutes = 1200
    case thirtyMinutes = 1800
    case sixtyMinutes = 3600

    nonisolated var id: Int { rawValue }

    nonisolated var duration: TimeInterval {
        TimeInterval(rawValue)
    }

    nonisolated var title: String {
        switch self {
        case .tenMinutes:
            return "10 分钟"
        case .twentyMinutes:
            return "20 分钟"
        case .thirtyMinutes:
            return "30 分钟"
        case .sixtyMinutes:
            return "1 小时"
        }
    }
}

enum NotchDisplayMode: String, CaseIterable, Identifiable {
    case compact
    case detailed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .compact:
            return "简约"
        case .detailed:
            return "详细"
        }
    }

    var subtitle: String {
        switch self {
        case .compact:
            return "只显示图标和会话数量"
        case .detailed:
            return "额外显示激活会话的最新消息"
        }
    }
}

enum ClosedNotchTrailingContentMode: String, CaseIterable, Identifiable {
    case sessionCount
    case claudeSevenDayRemaining
    case codexSevenDayRemaining

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sessionCount:
            return "会话数量"
        case .claudeSevenDayRemaining:
            return "Claude Code 7d 余量"
        case .codexSevenDayRemaining:
            return "Codex 7d 余量"
        }
    }

    var usageProviderID: String? {
        switch self {
        case .sessionCount:
            return nil
        case .claudeSevenDayRemaining:
            return "claude"
        case .codexSevenDayRemaining:
            return "codex"
        }
    }
}

enum IslandSurfaceMode: String, CaseIterable, Identifiable {
    case notch
    case floatingPet

    var id: String { rawValue }

    var title: String {
        switch self {
        case .notch:
            return "刘海屏方式"
        case .floatingPet:
            return "独立悬浮宠物"
        }
    }

    var subtitle: String {
        switch self {
        case .notch:
            return "固定在屏幕顶部中央，沿用 Island 刘海/胶囊体验"
        case .floatingPet:
            return "默认贴近当前激活窗口右下角，可拖动并记住位置"
        }
    }
}

struct FloatingPetAnchor: Codable, Equatable {
    let xRatio: Double
    let yRatio: Double
}

enum FloatingPetSizeMode: String, CaseIterable, Identifiable {
    case automatic
    case standard
    case large

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic:
            return "自动"
        case .standard:
            return "标准"
        case .large:
            return "较大"
        }
    }

    var subtitle: String {
        switch self {
        case .automatic:
            return "按显示器分辨率调整，高分屏会更醒目"
        case .standard:
            return "固定为旧版悬浮宠物尺寸"
        case .large:
            return "在所有显示器上放大宠物形象"
        }
    }
}

enum SubagentVisibilityMode: String, CaseIterable, Identifiable {
    case hidden
    case visible

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hidden:
            return "不显示"
        case .visible:
            return "显示"
        }
    }

    var subtitle: String {
        switch self {
        case .hidden:
            return "主列表里隐藏挂靠在主 Agent 下的子 Agent 项"
        case .visible:
            return "主列表里将明确的子 Agent 挂靠在主 Agent 下展示"
        }
    }

    init?(persistedValue: String) {
        switch persistedValue {
        case Self.hidden.rawValue:
            self = .hidden
        case Self.visible.rawValue, "firstLevelOnly", "all":
            self = .visible
        default:
            return nil
        }
    }
}

enum NotchPetStyle: String, CaseIterable, Identifiable {
    case crab
    case slime
    case cat
    case sittingCat
    case owl
    case snowyOwl
    case bee
    case roundBlob
    case antennaBean
    case tinyDino

    var id: String { rawValue }

    var title: String {
        switch self {
        case .crab:
            return "小螃蟹"
        case .slime:
            return "果冻史莱姆"
        case .cat:
            return "团子猫"
        case .sittingCat:
            return "坐着猫"
        case .owl:
            return "豆豆鸮"
        case .snowyOwl:
            return "雪团鸮"
        case .bee:
            return "小蜜蜂"
        case .roundBlob:
            return "正面团子兽"
        case .antennaBean:
            return "天线豆豆"
        case .tinyDino:
            return "侧身小恐龙"
        }
    }

    var subtitle: String {
        switch self {
        case .crab:
            return "经典横向步行动画"
        case .slime:
            return "软弹变形与高光晃动"
        case .cat:
            return "尾巴摆动和眨眼反馈"
        case .sittingCat:
            return "一直端坐，支持更多表情动作"
        case .owl:
            return "轻拍翅膀和点头观察"
        case .snowyOwl:
            return "圆脸立姿与扑翼巡航"
        case .bee:
            return "条纹圆身与振翅动画"
        case .roundBlob:
            return "早期口袋宠物式正面团子构图"
        case .antennaBean:
            return "大头小身与双角剪影"
        case .tinyDino:
            return "侧身尾巴外扩的经典小兽构图"
        }
    }
}

/// Geometry-only compatibility namespace. N1KO's `AppSettings` remains the
/// single settings object; this name is retained because the pinned Island
/// view model references the upstream geometry constants.
enum AppSettingsStore {
    static var shared: AppSettings { AppSettings.shared }
    static let defaultNotchModuleWidth: Double = 266
    static let minimumNotchModuleWidth: Double = 64
    static let maximumNotchModuleWidth: Double = 420

    static func normalizedNotchModuleWidth(_ width: Double) -> Double {
        min(max(width, minimumNotchModuleWidth), maximumNotchModuleWidth)
    }
}

enum TelemetryConsent {
    static let analyticsEnabledKey = "agent.island.analyticsEnabled"
}
