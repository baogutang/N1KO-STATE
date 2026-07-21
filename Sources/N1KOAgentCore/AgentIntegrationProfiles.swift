import Foundation

public enum AgentHookProtocolFamily: String, Codable, Sendable {
    case claudeCompatible
    case codex
    case gemini
    case copilot
    case plugin
}

public enum AgentHookInstallationKind: String, Codable, Sendable {
    case json
    case toml
    case pluginFile
    case pluginDirectory
    case hookDirectory
}

public enum AgentIntegrationCapability: String, Codable, CaseIterable, Sendable {
    case ingress
    case inlineResponse
    case terminalFocus
    case ideFocus
    case tmux
    case remoteSSH
    case symbolicCompanion
}

public enum AgentHookEntryTemplate: Codable, Equatable, Sendable {
    case plain
    case matcher(String)
    case direct
}

public struct AgentHookEventDescriptor: Codable, Equatable, Sendable {
    public let name: String
    public let templates: [AgentHookEntryTemplate]
    public let timeoutSeconds: Int?

    public init(
        name: String,
        matcher: String? = nil,
        templates: [AgentHookEntryTemplate]? = nil,
        timeoutSeconds: Int? = nil
    ) {
        self.name = name
        self.templates = templates ?? matcher.map { [.matcher($0)] } ?? [.plain]
        self.timeoutSeconds = timeoutSeconds
    }
}

public struct AgentIntegrationProfile: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let provider: AgentProvider
    public let displayName: String
    public let protocolFamily: AgentHookProtocolFamily
    public let installationKind: AgentHookInstallationKind
    public let configurationRelativePath: String
    public let activationConfigurationRelativePath: String?
    public let bundleIdentifiers: [String]
    public let events: [AgentHookEventDescriptor]
    public let capabilities: Set<AgentIntegrationCapability>
    public let managedHookAvailable: Bool
    public let defaultEnabled: Bool

    public init(
        id: String,
        provider: AgentProvider,
        displayName: String,
        protocolFamily: AgentHookProtocolFamily,
        installationKind: AgentHookInstallationKind = .json,
        configurationRelativePath: String,
        activationConfigurationRelativePath: String? = nil,
        bundleIdentifiers: [String] = [],
        events: [AgentHookEventDescriptor] = [],
        capabilities: Set<AgentIntegrationCapability>,
        managedHookAvailable: Bool = true,
        defaultEnabled: Bool = false
    ) {
        self.id = id
        self.provider = provider
        self.displayName = displayName
        self.protocolFamily = protocolFamily
        self.installationKind = installationKind
        self.configurationRelativePath = configurationRelativePath
        self.activationConfigurationRelativePath = activationConfigurationRelativePath
        self.bundleIdentifiers = bundleIdentifiers
        self.events = events
        self.capabilities = capabilities
        self.managedHookAvailable = managedHookAvailable
        self.defaultEnabled = defaultEnabled
    }

    public func configurationURL(homeDirectory: URL) -> URL {
        configurationRelativePath.split(separator: "/").reduce(homeDirectory) {
            $0.appendingPathComponent(String($1))
        }
    }

    public func activationConfigurationURL(homeDirectory: URL) -> URL? {
        activationConfigurationRelativePath.map { relativePath in
            relativePath.split(separator: "/").reduce(homeDirectory) {
                $0.appendingPathComponent(String($1))
            }
        }
    }
}

public enum AgentIntegrationRegistry {
    private static let claudeEvents: [AgentHookEventDescriptor] = [
        .init(name: "UserPromptSubmit"),
        .init(name: "PreToolUse", matcher: "*"),
        .init(name: "PostToolUse", matcher: "*"),
        .init(name: "PermissionRequest", matcher: "*", timeoutSeconds: 86_400),
        .init(name: "Notification", matcher: "*"),
        .init(name: "Stop"),
        .init(name: "SubagentStop"),
        .init(name: "SessionStart"),
        .init(name: "SessionEnd"),
        .init(name: "PreCompact", templates: [.matcher("auto"), .matcher("manual")])
    ]

    private static let qwenEvents: [AgentHookEventDescriptor] = claudeEvents + [
        .init(name: "PostToolUseFailure", matcher: "*"),
        .init(name: "SubagentStart", matcher: "*")
    ]

    private static let geminiEvents: [AgentHookEventDescriptor] = [
        .init(name: "SessionStart"), .init(name: "SessionEnd"),
        .init(name: "BeforeAgent"), .init(name: "AfterAgent"),
        .init(name: "BeforeTool", matcher: ".*"), .init(name: "AfterTool", matcher: ".*"),
        .init(name: "Notification"), .init(name: "PreCompress")
    ]

    private static let copilotEvents: [AgentHookEventDescriptor] = [
        .init(name: "sessionStart", matcher: "*"), .init(name: "sessionEnd", matcher: "*"),
        .init(name: "userPromptSubmitted", matcher: "*"), .init(name: "preToolUse", matcher: "*"),
        .init(name: "postToolUse", matcher: "*"), .init(name: "agentStop", matcher: "*"),
        .init(name: "subagentStop", matcher: "*"), .init(name: "errorOccurred", matcher: "*")
    ]

    private static let cursorEvents: [AgentHookEventDescriptor] = [
        .init(name: "beforeSubmitPrompt", templates: [.direct]),
        .init(name: "preToolUse", templates: [.direct]),
        .init(name: "postToolUse", templates: [.direct]),
        .init(name: "stop", templates: [.direct]),
        .init(name: "subagentStop", templates: [.direct]),
        .init(name: "sessionStart", templates: [.direct]),
        .init(name: "sessionEnd", templates: [.direct]),
        .init(name: "preCompact", templates: [.direct])
    ]

    private static let baseCapabilities: Set<AgentIntegrationCapability> = [.ingress, .terminalFocus]
    private static let responsiveCapabilities: Set<AgentIntegrationCapability> = [.ingress, .inlineResponse, .terminalFocus]

    public static let profiles: [AgentIntegrationProfile] = [
        .init(id: "claude-hooks", provider: .claude, displayName: "Claude Code",
              protocolFamily: .claudeCompatible, configurationRelativePath: ".claude/settings.json",
              bundleIdentifiers: ["com.anthropic.claudefordesktop"], events: claudeEvents,
              capabilities: responsiveCapabilities.union([.tmux, .remoteSSH, .symbolicCompanion]), defaultEnabled: true),
        .init(id: "codex-hooks", provider: .codex, displayName: "Codex",
              protocolFamily: .codex, configurationRelativePath: ".codex/hooks.json",
              bundleIdentifiers: ["com.openai.codex"], events: Array(claudeEvents.prefix(8)),
              capabilities: responsiveCapabilities.union([.tmux, .remoteSSH, .symbolicCompanion]), defaultEnabled: true),
        .init(id: "gemini-hooks", provider: .gemini, displayName: "Gemini CLI",
              protocolFamily: .gemini, configurationRelativePath: ".gemini/settings.json", events: geminiEvents,
              capabilities: baseCapabilities.union([.symbolicCompanion])),
        .init(id: "qwen-code-hooks", provider: .qwen, displayName: "Qwen Code",
              protocolFamily: .claudeCompatible, configurationRelativePath: ".qwen/settings.json", events: qwenEvents,
              capabilities: responsiveCapabilities.union([.tmux, .remoteSSH, .symbolicCompanion])),
        .init(id: "kimi-hooks", provider: .kimi, displayName: "Kimi CLI",
              protocolFamily: .claudeCompatible, installationKind: .toml,
              configurationRelativePath: ".kimi/config.toml", events: Array(claudeEvents.prefix(9)),
              capabilities: responsiveCapabilities.union([.remoteSSH, .symbolicCompanion])),
        .init(id: "hermes-hooks", provider: .hermes, displayName: "Hermes",
              protocolFamily: .plugin, installationKind: .pluginDirectory,
              configurationRelativePath: ".hermes/plugins/n1ko-state", capabilities: baseCapabilities.union([.remoteSSH, .symbolicCompanion])),
        .init(id: "pi-hooks", provider: .pi, displayName: "Pi Agent",
              protocolFamily: .plugin, installationKind: .pluginDirectory,
              configurationRelativePath: ".pi/agent/extensions/n1ko-state", capabilities: baseCapabilities.union([.remoteSSH, .symbolicCompanion])),
        .init(id: "opencode-hooks", provider: .openCode, displayName: "OpenCode",
              protocolFamily: .plugin, installationKind: .pluginFile,
              configurationRelativePath: ".config/opencode/plugins/n1ko-state.js",
              activationConfigurationRelativePath: ".config/opencode/opencode.json",
              bundleIdentifiers: ["ai.opencode.desktop"], capabilities: responsiveCapabilities.union([.ideFocus, .remoteSSH, .symbolicCompanion])),
        .init(id: "openclaw-hooks", provider: .openClaw, displayName: "OpenClaw",
              protocolFamily: .plugin, installationKind: .hookDirectory,
              configurationRelativePath: ".openclaw/hooks/n1ko-state",
              activationConfigurationRelativePath: ".openclaw/openclaw.json",
              events: [
                .init(name: "command:new"), .init(name: "command:reset"), .init(name: "command:stop"),
                .init(name: "message:received"), .init(name: "message:sent"),
                .init(name: "session:compact:before"), .init(name: "session:compact:after"),
                .init(name: "session:patch")
              ],
              capabilities: baseCapabilities.union([.remoteSSH, .symbolicCompanion])),
        .init(id: "qoder-hooks", provider: .qoder, displayName: "Qoder",
              protocolFamily: .claudeCompatible, configurationRelativePath: ".qoder/settings.json",
              bundleIdentifiers: ["com.qoder.ide"], events: qwenEvents,
              capabilities: baseCapabilities.union([.ideFocus, .tmux, .symbolicCompanion]), defaultEnabled: true),
        .init(id: "qoder-cli-hooks", provider: .qoderCLI, displayName: "Qoder CLI",
              protocolFamily: .claudeCompatible, configurationRelativePath: ".qoder/settings.json", events: claudeEvents,
              capabilities: responsiveCapabilities.union([.tmux, .remoteSSH, .symbolicCompanion])),
        .init(id: "qoder-cn-hooks", provider: .qoderCN, displayName: "Qoder CN",
              protocolFamily: .claudeCompatible, configurationRelativePath: ".qoder-cn/settings.json",
              bundleIdentifiers: ["com.aliyun.lingma.ide"], events: qwenEvents,
              capabilities: baseCapabilities.union([.ideFocus, .tmux, .symbolicCompanion]), defaultEnabled: true),
        .init(id: "qoder-cn-cli-hooks", provider: .qoderCNCLI, displayName: "Qoder CN CLI",
              protocolFamily: .claudeCompatible, configurationRelativePath: ".qoder-cn/settings.json", events: claudeEvents,
              capabilities: responsiveCapabilities.union([.tmux, .remoteSSH, .symbolicCompanion])),
        .init(id: "qoderwork-hooks", provider: .qoderWork, displayName: "QoderWork",
              protocolFamily: .claudeCompatible, configurationRelativePath: ".qoderwork/settings.json",
              bundleIdentifiers: ["com.qoder.work"], events: qwenEvents,
              capabilities: baseCapabilities.union([.ideFocus, .tmux, .symbolicCompanion]), defaultEnabled: true),
        .init(id: "codebuddy-hooks", provider: .codeBuddy, displayName: "CodeBuddy",
              protocolFamily: .claudeCompatible, configurationRelativePath: ".codebuddy/settings.json",
              bundleIdentifiers: ["com.tencent.codebuddy", "com.codebuddy.app"], events: claudeEvents,
              capabilities: baseCapabilities.union([.ideFocus, .tmux, .symbolicCompanion])),
        .init(id: "codebuddy-cli-hooks", provider: .codeBuddyCLI, displayName: "CodeBuddy CLI",
              protocolFamily: .claudeCompatible, configurationRelativePath: ".codebuddy/settings.json", events: claudeEvents,
              capabilities: responsiveCapabilities.union([.tmux, .remoteSSH, .symbolicCompanion])),
        .init(id: "workbuddy-hooks", provider: .workBuddy, displayName: "WorkBuddy",
              protocolFamily: .claudeCompatible, configurationRelativePath: ".workbuddy/settings.json",
              bundleIdentifiers: ["com.workbuddy.workbuddy"], events: claudeEvents,
              capabilities: baseCapabilities.union([.ideFocus, .tmux, .symbolicCompanion])),
        .init(id: "cursor-hooks", provider: .cursor, displayName: "Cursor",
              protocolFamily: .claudeCompatible, configurationRelativePath: ".cursor/hooks.json",
              bundleIdentifiers: ["com.todesktop.230313mzl4w4u92"], events: cursorEvents,
              capabilities: baseCapabilities.union([.ideFocus, .symbolicCompanion])),
        .init(id: "copilot-hooks", provider: .copilot, displayName: "GitHub Copilot",
              protocolFamily: .copilot, configurationRelativePath: ".github/hooks/n1ko-state.json",
              bundleIdentifiers: ["com.github.Copilot", "com.github.CopilotForXcode"], events: copilotEvents,
              capabilities: baseCapabilities.union([.ideFocus, .symbolicCompanion])),
        .init(id: "trae-runtime", provider: .trae, displayName: "Trae",
              protocolFamily: .claudeCompatible, configurationRelativePath: ".trae/hooks/n1ko-state.json",
              capabilities: baseCapabilities.union([.ideFocus, .symbolicCompanion]), managedHookAvailable: false),
        .init(id: "jetbrains-runtime", provider: .jetBrains, displayName: "JetBrains Agent",
              protocolFamily: .claudeCompatible, configurationRelativePath: ".config/JetBrains/n1ko-state/hooks.json",
              capabilities: baseCapabilities.union([.ideFocus, .symbolicCompanion]), managedHookAvailable: false)
    ]

    public static func profile(id: String) -> AgentIntegrationProfile? {
        profiles.first { $0.id == id }
    }

    public static func profile(provider: AgentProvider) -> AgentIntegrationProfile? {
        profiles.first { $0.provider == provider }
    }

    public static var defaultEnabledProfileIDs: Set<String> {
        Set(profiles.filter(\.defaultEnabled).map(\.id))
    }
}
