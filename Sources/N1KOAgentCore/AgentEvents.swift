// N1KO modification notice:
// Event normalization semantics were adapted from Apache-2.0 Ping Island at
// commit da130d6 and reduced to the Claude/Codex WP3 boundary for N1KO-STATE.

import Foundation

public enum AgentEventKind: String, Codable, Sendable {
    case started
    case promptSubmitted
    case processing
    case toolResult
    case approvalRequested
    case answerRequested
    case interventionResolved
    case completed
    case interrupted
    case failed
    case ended
    case archived
    case usage
}

public struct AgentNavigationContext: Codable, Equatable, Sendable {
    public let terminalBundleIdentifier: String?
    public let tmuxTarget: AgentTMUXTarget?
    public let remoteHost: String?

    public init(
        terminalBundleIdentifier: String? = nil,
        tmuxTarget: AgentTMUXTarget? = nil,
        remoteHost: String? = nil
    ) {
        self.terminalBundleIdentifier = terminalBundleIdentifier
        self.tmuxTarget = tmuxTarget
        self.remoteHost = remoteHost
    }
}

public struct AgentIngressEvent: Codable, Equatable, Sendable {
    public let provider: AgentProvider
    public let sessionID: String
    public let kind: AgentEventKind
    public let timestamp: Date
    public let cwd: String?
    public let title: String?
    public let message: String?
    public let toolName: String?
    public let toolInput: String?
    public let toolResult: String?
    public let toolSucceeded: Bool?
    public let requestID: String?
    public let questions: [AgentQuestion]
    public let responseOwnerID: String?
    public let usage: AgentUsage?
    public let usageWindows: [AgentUsageWindow]
    public let parentSessionID: String?
    public let transcriptPath: String?
    public let navigation: AgentNavigationContext?

    public init(
        provider: AgentProvider,
        sessionID: String,
        kind: AgentEventKind,
        timestamp: Date = Date(),
        cwd: String? = nil,
        title: String? = nil,
        message: String? = nil,
        toolName: String? = nil,
        toolInput: String? = nil,
        toolResult: String? = nil,
        toolSucceeded: Bool? = nil,
        requestID: String? = nil,
        questions: [AgentQuestion] = [],
        responseOwnerID: String? = nil,
        usage: AgentUsage? = nil,
        usageWindows: [AgentUsageWindow] = [],
        parentSessionID: String? = nil,
        transcriptPath: String? = nil,
        navigation: AgentNavigationContext? = nil
    ) {
        self.provider = provider
        self.sessionID = sessionID
        self.kind = kind
        self.timestamp = timestamp
        self.cwd = cwd
        self.title = title
        self.message = message
        self.toolName = toolName
        self.toolInput = toolInput
        self.toolResult = toolResult
        self.toolSucceeded = toolSucceeded
        self.requestID = requestID
        self.questions = questions
        self.responseOwnerID = responseOwnerID
        self.usage = usage
        self.usageWindows = usageWindows
        self.parentSessionID = parentSessionID
        self.transcriptPath = transcriptPath
        self.navigation = navigation
    }
}

public enum AgentLifecycleState: String, Codable, Sendable {
    case active
    case screenLocked
    case userSessionInactive
    case systemSleeping
    case shuttingDown
}

public struct AgentEnergyPolicy: Equatable, Sendable {
    public let lifecycle: AgentLifecycleState
    public let watchersEnabled: Bool
    public let socketEnabled: Bool
    public let subprocessesAllowed: Bool

    public static func policy(for lifecycle: AgentLifecycleState) -> AgentEnergyPolicy {
        switch lifecycle {
        case .active:
            return AgentEnergyPolicy(
                lifecycle: lifecycle,
                watchersEnabled: true,
                socketEnabled: true,
                subprocessesAllowed: true
            )
        case .screenLocked, .userSessionInactive:
            return AgentEnergyPolicy(
                lifecycle: lifecycle,
                watchersEnabled: false,
                socketEnabled: true,
                subprocessesAllowed: false
            )
        case .systemSleeping, .shuttingDown:
            return AgentEnergyPolicy(
                lifecycle: lifecycle,
                watchersEnabled: false,
                socketEnabled: false,
                subprocessesAllowed: false
            )
        }
    }
}
