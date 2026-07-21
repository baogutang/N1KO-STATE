// N1KO modification notice: adapted from Ping Island commit da130d6 for
// N1KO's single-owner integration, macOS 12 compatibility, or fullscreen boundary.

//
//  FeatureFlags.swift
//  PingIsland
//
//  Isolated feature flags for staged runtime rollout.
//

import Foundation

enum RuntimeFeatureFlag: String, CaseIterable, Sendable {
    case nativeClaudeRuntime
    case nativeCodexRuntime

    nonisolated var defaultsKey: String {
        switch self {
        case .nativeClaudeRuntime:
            return "n1ko.agent.feature.nativeClaudeRuntime"
        case .nativeCodexRuntime:
            return "n1ko.agent.feature.nativeCodexRuntime"
        }
    }

    nonisolated var environmentKey: String {
        switch self {
        case .nativeClaudeRuntime:
            return "N1KO_STATE_NATIVE_CLAUDE_RUNTIME"
        case .nativeCodexRuntime:
            return "N1KO_STATE_NATIVE_CODEX_RUNTIME"
        }
    }
}

enum FeatureFlags {
    private static let truthyValues: Set<String> = ["1", "true", "yes", "on", "enabled"]
    private static let falsyValues: Set<String> = ["0", "false", "no", "off", "disabled"]

    nonisolated static func isEnabled(
        _ flag: RuntimeFeatureFlag,
        defaults: UserDefaults = .standard,
        environment: [String: String] = Foundation.ProcessInfo.processInfo.environment
    ) -> Bool {
        if let rawValue = environment[flag.environmentKey]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            if truthyValues.contains(rawValue) {
                return true
            }
            if falsyValues.contains(rawValue) {
                return false
            }
        }

        if defaults.object(forKey: flag.defaultsKey) == nil {
            return true
        }
        return defaults.bool(forKey: flag.defaultsKey)
    }

    nonisolated static func setEnabled(
        _ isEnabled: Bool,
        for flag: RuntimeFeatureFlag,
        defaults: UserDefaults = .standard
    ) {
        defaults.set(isEnabled, forKey: flag.defaultsKey)
    }

    nonisolated static var nativeClaudeRuntime: Bool {
        isEnabled(.nativeClaudeRuntime)
    }

    nonisolated static var nativeCodexRuntime: Bool {
        isEnabled(.nativeCodexRuntime)
    }
}
