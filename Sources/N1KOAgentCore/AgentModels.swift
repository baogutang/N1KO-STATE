// N1KO modification notice:
// The lifecycle vocabulary in this file was adapted for N1KO-STATE from the
// Apache-2.0 Ping Island session model at commit da130d6. The implementation,
// storage shape, identity rules, and public snapshot contract were rewritten.

import Foundation

public enum AgentProvider: String, Codable, CaseIterable, Sendable {
    case claude
    case codex
    case gemini
    case qwen
    case kimi
    case hermes
    case openCode = "opencode"
    case pi
    case qoder
    case qoderCN = "qoder-cn"
    case qoderWork = "qoder-work"
    case qoderCLI = "qoder-cli"
    case qoderCNCLI = "qoder-cn-cli"
    case codeBuddy = "codebuddy"
    case codeBuddyCLI = "codebuddy-cli"
    case workBuddy = "workbuddy"
    case cursor
    case trae
    case openClaw = "openclaw"
    case copilot
    case jetBrains = "jetbrains"
    case legacyImport = "legacy-import"

    public var displayName: String {
        switch self {
        case .claude: return "Claude"
        case .codex: return "Codex"
        case .gemini: return "Gemini"
        case .qwen: return "Qwen Code"
        case .kimi: return "Kimi"
        case .hermes: return "Hermes"
        case .openCode: return "OpenCode"
        case .pi: return "Pi Agent"
        case .qoder: return "Qoder"
        case .qoderCN: return "Qoder CN"
        case .qoderWork: return "QoderWork"
        case .qoderCLI: return "Qoder CLI"
        case .qoderCNCLI: return "Qoder CN CLI"
        case .codeBuddy: return "CodeBuddy"
        case .codeBuddyCLI: return "CodeBuddy CLI"
        case .workBuddy: return "WorkBuddy"
        case .cursor: return "Cursor"
        case .trae: return "Trae"
        case .openClaw: return "OpenClaw"
        case .copilot: return "GitHub Copilot"
        case .jetBrains: return "JetBrains Agent"
        case .legacyImport: return "Imported Agent data"
        }
    }

    public var usesClaudeCompatibleHooks: Bool {
        switch self {
        case .codex, .copilot, .gemini, .legacyImport:
            return false
        default:
            return true
        }
    }
}

public struct AgentSessionKey: Hashable, Codable, Sendable {
    public let provider: AgentProvider
    public let sessionID: String

    public init(provider: AgentProvider, sessionID: String) {
        self.provider = provider
        self.sessionID = sessionID
    }
}

public enum AgentPhase: String, Codable, Sendable {
    case starting
    case processing
    case waitingForApproval
    case waitingForAnswer
    case completed
    case interrupted
    case failed
    case ended
    case archived

    public var needsAttention: Bool {
        self == .waitingForApproval || self == .waitingForAnswer || self == .failed
    }

    public var isTerminal: Bool {
        switch self {
        case .completed, .interrupted, .failed, .ended, .archived:
            return true
        default:
            return false
        }
    }
}

public enum AgentInterventionKind: String, Codable, Sendable {
    case approval
    case question
}

public enum AgentAttentionKind: String, Codable, Sendable {
    case approval
    case question
    case completion
    case failure
}

public struct AgentQuestionOption: Codable, Equatable, Sendable {
    public let label: String
    public let description: String?

    public init(label: String, description: String? = nil) {
        self.label = label
        self.description = description
    }
}

public struct AgentQuestion: Codable, Equatable, Sendable {
    public let id: String
    public let header: String?
    public let prompt: String
    public let options: [AgentQuestionOption]
    public let allowsMultiple: Bool
    public let allowsOther: Bool

    public init(
        id: String,
        header: String? = nil,
        prompt: String,
        options: [AgentQuestionOption] = [],
        allowsMultiple: Bool = false,
        allowsOther: Bool = true
    ) {
        self.id = id
        self.header = header
        self.prompt = prompt
        self.options = options
        self.allowsMultiple = allowsMultiple
        self.allowsOther = allowsOther
    }
}

/// A capability is intentionally opaque and unguessable. A response is only
/// routed when provider, session, request, connection owner, and this value all
/// match the pending route.
public struct AgentIntervention: Codable, Equatable, Sendable {
    public let requestID: String
    public let kind: AgentInterventionKind
    public let title: String
    public let message: String?
    public let toolName: String?
    public let questions: [AgentQuestion]
    public let responseOwnerID: String
    public let responseCapability: String

    public init(
        requestID: String,
        kind: AgentInterventionKind,
        title: String,
        message: String? = nil,
        toolName: String? = nil,
        questions: [AgentQuestion] = [],
        responseOwnerID: String,
        responseCapability: String
    ) {
        self.requestID = requestID
        self.kind = kind
        self.title = title
        self.message = message
        self.toolName = toolName
        self.questions = questions
        self.responseOwnerID = responseOwnerID
        self.responseCapability = responseCapability
    }
}

public struct AgentUsage: Codable, Equatable, Sendable {
    public let inputTokens: Int
    public let cachedInputTokens: Int
    public let outputTokens: Int

    public init(inputTokens: Int = 0, cachedInputTokens: Int = 0, outputTokens: Int = 0) {
        self.inputTokens = max(inputTokens, 0)
        self.cachedInputTokens = max(cachedInputTokens, 0)
        self.outputTokens = max(outputTokens, 0)
    }

    public var totalTokens: Int { inputTokens + outputTokens }

    public func mergingLatest(_ other: AgentUsage) -> AgentUsage {
        AgentUsage(
            inputTokens: max(inputTokens, other.inputTokens),
            cachedInputTokens: max(cachedInputTokens, other.cachedInputTokens),
            outputTokens: max(outputTokens, other.outputTokens)
        )
    }
}

public struct AgentUsageWindow: Codable, Equatable, Identifiable, Sendable {
    public var id: String { key }
    public let key: String
    public let label: String
    public let usedPercentage: Double
    public let resetsAt: Date?
    public let capturedAt: Date?

    public init(
        key: String,
        label: String,
        usedPercentage: Double,
        resetsAt: Date? = nil,
        capturedAt: Date? = nil
    ) {
        self.key = key
        self.label = label
        self.usedPercentage = min(max(usedPercentage, 0), 100)
        self.resetsAt = resetsAt
        self.capturedAt = capturedAt
    }

    public var remainingPercentage: Double { max(0, 100 - usedPercentage) }
}

/// Bounded, presentation-safe conversation projection. It deliberately keeps
/// only display text and tool labels; raw hook payloads, capabilities, secrets,
/// and full transcript files never cross into the UI snapshot.
public enum AgentConversationKind: String, Codable, Equatable, Sendable {
    case user
    case assistant
    case tool
    case attention
    case status
}

public enum AgentToolStatus: String, Codable, Equatable, Sendable {
    case running
    case waitingForApproval
    case completed
    case failed
}

public struct AgentConversationItem: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let kind: AgentConversationKind
    public let text: String
    public let toolName: String?
    public let toolCallID: String?
    public let toolInput: String?
    public let toolResult: String?
    public let toolStatus: AgentToolStatus?
    public let timestamp: Date

    public init(
        id: String,
        kind: AgentConversationKind,
        text: String,
        toolName: String? = nil,
        toolCallID: String? = nil,
        toolInput: String? = nil,
        toolResult: String? = nil,
        toolStatus: AgentToolStatus? = nil,
        timestamp: Date
    ) {
        self.id = id
        self.kind = kind
        self.text = text
        self.toolName = toolName
        self.toolCallID = toolCallID
        self.toolInput = toolInput
        self.toolResult = toolResult
        self.toolStatus = toolStatus
        self.timestamp = timestamp
    }
}

public struct AgentSessionSnapshot: Codable, Equatable, Identifiable, Sendable {
    public var id: String { "\(provider.rawValue):\(sessionID)" }

    public let provider: AgentProvider
    public let sessionID: String
    public let cwd: String?
    public let title: String
    public let preview: String?
    public let phase: AgentPhase
    public let attention: AgentAttentionKind?
    public let intervention: AgentIntervention?
    public let usage: AgentUsage
    public let createdAt: Date
    public let lastActivityAt: Date
    public let completedAt: Date?
    public let archivedAt: Date?
    public let wasRestored: Bool
    public let parentSessionID: String?
    public let navigation: AgentNavigationContext?
    /// Optional for backward-compatible decoding of snapshots written before
    /// the Ping-Island parity projection was added.
    public let conversation: [AgentConversationItem]?

    public var needsAttention: Bool {
        if phase.needsAttention || intervention != nil { return true }
        switch attention {
        case .approval, .question, .failure: return true
        case .completion, .none: return false
        }
    }
    public var conversationItems: [AgentConversationItem] { conversation ?? [] }
}

public struct AgentUsageSummary: Codable, Equatable, Sendable {
    public let byProvider: [AgentProvider: AgentUsage]
    /// Optional for backward-compatible decoding of pre-quota snapshots.
    public let windowsByProvider: [AgentProvider: [AgentUsageWindow]]?

    public init(
        byProvider: [AgentProvider: AgentUsage],
        windowsByProvider: [AgentProvider: [AgentUsageWindow]]? = nil
    ) {
        self.byProvider = byProvider
        self.windowsByProvider = windowsByProvider
    }

    public var providerWindows: [AgentProvider: [AgentUsageWindow]] { windowsByProvider ?? [:] }
}

/// The only presentation-facing Agent value. Every field is immutable and the
/// target has no dependency on a view or window type.
public struct AgentSnapshot: Codable, Equatable, Sendable {
    public let generation: UInt64
    public let generatedAt: Date
    public let sessions: [AgentSessionSnapshot]
    public let usage: AgentUsageSummary

    public static let empty = AgentSnapshot(
        generation: 0,
        generatedAt: Date(timeIntervalSince1970: 0),
        sessions: [],
        usage: AgentUsageSummary(byProvider: [:])
    )
}

public enum AgentResponseAction: Codable, Equatable, Sendable {
    case approve(scope: String?)
    case deny(reason: String?)
    case answer([String: [String]])
}

public enum AgentResponseRoutingError: Error, Equatable {
    case noPendingIntervention
    case providerMismatch
    case requestMismatch
    case ownerMismatch
    case authenticationFailed
    case channelClosed
}
