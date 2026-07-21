// N1KO modification notice:
// This N1KO-owned store implements the lifecycle invariants selected from the
// Apache-2.0 Ping Island SessionStore/association behavior at commit da130d6.
// It is a new, compact persistence and snapshot implementation for WP3.

import Foundation

public protocol AgentSessionPersisting: AnyObject {
    func load() throws -> AgentPersistedState?
    func save(_ state: AgentPersistedState) throws
}

public struct AgentPersistedState: Codable, Equatable, Sendable {
    public let sessions: [AgentPersistedSession]
    public let associations: [String: AgentSessionKey]
    public let importedUsage: [AgentProvider: AgentUsage]?
    public let usageWindows: [AgentProvider: [AgentUsageWindow]]?

    public init(
        sessions: [AgentPersistedSession],
        associations: [String: AgentSessionKey],
        importedUsage: [AgentProvider: AgentUsage]? = nil,
        usageWindows: [AgentProvider: [AgentUsageWindow]]? = nil
    ) {
        self.sessions = sessions
        self.associations = associations
        self.importedUsage = importedUsage
        self.usageWindows = usageWindows
    }
}

public struct AgentPersistedSession: Codable, Equatable, Sendable {
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
    public let parentSessionID: String?
    public let lastEventKind: AgentEventKind?
    public let navigation: AgentNavigationContext?
    public let conversation: [AgentConversationItem]?

    public init(
        provider: AgentProvider,
        sessionID: String,
        cwd: String?,
        title: String,
        preview: String?,
        phase: AgentPhase,
        attention: AgentAttentionKind?,
        intervention: AgentIntervention?,
        usage: AgentUsage,
        createdAt: Date,
        lastActivityAt: Date,
        completedAt: Date?,
        archivedAt: Date?,
        parentSessionID: String?,
        lastEventKind: AgentEventKind? = nil,
        navigation: AgentNavigationContext? = nil,
        conversation: [AgentConversationItem]? = nil
    ) {
        self.provider = provider
        self.sessionID = sessionID
        self.cwd = cwd
        self.title = title
        self.preview = preview
        self.phase = phase
        self.attention = attention
        self.intervention = intervention
        self.usage = usage
        self.createdAt = createdAt
        self.lastActivityAt = lastActivityAt
        self.completedAt = completedAt
        self.archivedAt = archivedAt
        self.parentSessionID = parentSessionID
        self.lastEventKind = lastEventKind
        self.navigation = navigation
        self.conversation = conversation
    }
}

public final class AgentJSONSessionPersistence: AgentSessionPersisting {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func load() throws -> AgentPersistedState? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        return try JSONDecoder.agent.decode(AgentPersistedState.self, from: Data(contentsOf: fileURL))
    }

    public func save(_ state: AgentPersistedState) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let data = try JSONEncoder.agent.encode(state)
        try data.write(to: fileURL, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }
}

private struct MutableAgentSession {
    static let conversationLimit = 80
    var provider: AgentProvider
    var sessionID: String
    var cwd: String?
    var title: String
    var preview: String?
    var phase: AgentPhase
    var attention: AgentAttentionKind?
    var intervention: AgentIntervention?
    var usage: AgentUsage
    var createdAt: Date
    var lastActivityAt: Date
    var completedAt: Date?
    var archivedAt: Date?
    var wasRestored: Bool
    var parentSessionID: String?
    var lastEventKind: AgentEventKind?
    var navigation: AgentNavigationContext?
    var conversation: [AgentConversationItem]

    init(persisted: AgentPersistedSession) {
        provider = persisted.provider
        sessionID = persisted.sessionID
        cwd = persisted.cwd
        title = persisted.title
        preview = persisted.preview
        phase = persisted.phase
        attention = persisted.attention
        // A response channel never survives a process restart. Preserve the
        // visible attention state but remove the stale response capability.
        intervention = nil
        usage = persisted.usage
        createdAt = persisted.createdAt
        lastActivityAt = persisted.lastActivityAt
        completedAt = persisted.completedAt
        archivedAt = persisted.archivedAt
        wasRestored = true
        parentSessionID = persisted.parentSessionID
        lastEventKind = persisted.lastEventKind
        navigation = persisted.navigation
        conversation = persisted.conversation ?? []
    }

    var snapshot: AgentSessionSnapshot {
        AgentSessionSnapshot(
            provider: provider,
            sessionID: sessionID,
            cwd: cwd,
            title: title,
            preview: preview,
            phase: phase,
            attention: attention,
            intervention: intervention,
            usage: usage,
            createdAt: createdAt,
            lastActivityAt: lastActivityAt,
            completedAt: completedAt,
            archivedAt: archivedAt,
            wasRestored: wasRestored,
            parentSessionID: parentSessionID,
            navigation: navigation,
            conversation: conversation
        )
    }

    var persisted: AgentPersistedSession {
        AgentPersistedSession(
            provider: provider,
            sessionID: sessionID,
            cwd: cwd,
            title: title,
            preview: preview,
            phase: phase,
            attention: attention,
            // Response capabilities and connection ownership are process-local.
            // Persist attention/phase, never a live intervention route.
            intervention: nil,
            usage: usage,
            createdAt: createdAt,
            lastActivityAt: lastActivityAt,
            completedAt: completedAt,
            archivedAt: archivedAt,
            parentSessionID: parentSessionID,
            lastEventKind: lastEventKind,
            navigation: navigation,
            conversation: conversation
        )
    }
}

public final class AgentSessionStore {
    private let persistence: AgentSessionPersisting?
    private var sessions: [AgentSessionKey: MutableAgentSession] = [:]
    private var associations: [String: AgentSessionKey] = [:]
    private var importedUsage: [AgentProvider: AgentUsage] = [:]
    private var usageWindows: [AgentProvider: [AgentUsageWindow]] = [:]
    private var generation: UInt64 = 0

    public init(persistence: AgentSessionPersisting? = nil) {
        self.persistence = persistence
        if let state = try? persistence?.load() {
            associations = state.associations
            importedUsage = state.importedUsage ?? [:]
            usageWindows = state.usageWindows ?? [:]
            for persisted in state.sessions {
                let key = AgentSessionKey(provider: persisted.provider, sessionID: persisted.sessionID)
                sessions[key] = MutableAgentSession(persisted: persisted)
            }
            if !sessions.isEmpty { generation = 1 }
        }
    }

    @discardableResult
    public func associate(provider: AgentProvider, externalID: String, sessionID: String) -> AgentSnapshot {
        associations[associationKey(provider: provider, externalID: externalID)] = AgentSessionKey(
            provider: provider,
            sessionID: sessionID
        )
        generation &+= 1
        persist()
        return makeSnapshot()
    }

    public func resolvedSessionID(provider: AgentProvider, externalID: String) -> String {
        associations[associationKey(provider: provider, externalID: externalID)]?.sessionID ?? externalID
    }

    @discardableResult
    public func importLegacy(
        associations incomingAssociations: [String: AgentSessionKey],
        usage incomingUsage: [AgentProvider: AgentUsage]
    ) -> AgentSnapshot {
        var changed = false
        for (key, value) in incomingAssociations where associations[key] == nil {
            associations[key] = value
            changed = true
        }
        for (provider, usage) in incomingUsage {
            let merged = (importedUsage[provider] ?? AgentUsage()).mergingLatest(usage)
            if merged != importedUsage[provider] {
                importedUsage[provider] = merged
                changed = true
            }
        }
        if changed {
            generation &+= 1
            persist()
        }
        return makeSnapshot()
    }

    @discardableResult
    public func process(_ event: AgentIngressEvent, responseCapability: String? = nil) -> AgentSnapshot {
        _ = apply(event, responseCapability: responseCapability, persistImmediately: true)
        return makeSnapshot()
    }

    /// Applies one parser/file batch with a single persistence write and a
    /// single snapshot composition. This is critical for bounded-history
    /// restoration, where one Codex rollout can project up to 82 events and an
    /// initial scan can contain hundreds of rollouts.
    @discardableResult
    public func process(
        _ batch: [(event: AgentIngressEvent, responseCapability: String?)]
    ) -> AgentSnapshot {
        var changed = false
        for item in batch {
            changed = apply(
                item.event,
                responseCapability: item.responseCapability,
                persistImmediately: false
            ) || changed
        }
        if changed { persist() }
        return makeSnapshot()
    }

    @discardableResult
    private func apply(
        _ event: AgentIngressEvent,
        responseCapability: String?,
        persistImmediately: Bool
    ) -> Bool {
        let resolvedID = resolvedSessionID(provider: event.provider, externalID: event.sessionID)
        let key = AgentSessionKey(provider: event.provider, sessionID: resolvedID)
        // Rollout restoration replays immutable JSONL history on every launch.
        // Older records may hydrate bounded detail, but must never roll the
        // persisted lifecycle, attention, or usage state backward.
        if let existing = sessions[key],
           event.timestamp < existing.lastActivityAt
            || (event.timestamp == existing.lastActivityAt && event.kind == existing.lastEventKind) {
            var hydrated = existing
            let previousConversation = hydrated.conversation
            let previousUsage = hydrated.usage
            let previousWindows = usageWindows[event.provider]
            if let usage = event.usage { hydrated.usage = hydrated.usage.mergingLatest(usage) }
            if Self.shouldReplaceUsageWindows(
                event.usageWindows,
                current: usageWindows[event.provider]
            ) {
                usageWindows[event.provider] = event.usageWindows
            }
            hydrated.appendConversation(event)
            if hydrated.conversation != previousConversation
                || hydrated.usage != previousUsage
                || usageWindows[event.provider] != previousWindows {
                sessions[key] = hydrated
                generation &+= 1
                if persistImmediately { persist() }
                return true
            }
            return false
        }
        var session = sessions[key] ?? MutableAgentSession(
            provider: event.provider,
            sessionID: resolvedID,
            cwd: event.cwd,
            title: event.title ?? Self.defaultTitle(provider: event.provider, cwd: event.cwd),
            preview: nil,
            phase: .starting,
            attention: nil,
            intervention: nil,
            usage: AgentUsage(),
            createdAt: event.timestamp,
            lastActivityAt: event.timestamp,
            completedAt: nil,
            archivedAt: nil,
            wasRestored: false,
            parentSessionID: event.parentSessionID,
            lastEventKind: nil,
            navigation: event.navigation,
            conversation: []
        )

        if let cwd = Self.nonEmpty(event.cwd) { session.cwd = cwd }
        if let title = Self.nonEmpty(event.title) { session.title = title }
        if let message = Self.nonEmpty(event.message) { session.preview = message }
        if let parent = Self.nonEmpty(event.parentSessionID) { session.parentSessionID = parent }
        if let navigation = event.navigation { session.navigation = navigation }
        session.lastActivityAt = max(session.lastActivityAt, event.timestamp)
        session.archivedAt = event.kind == .archived ? event.timestamp : session.archivedAt

        switch event.kind {
        case .started:
            session.phase = .starting
            session.attention = nil
            session.intervention = nil
        case .promptSubmitted, .processing:
            session.phase = .processing
            session.attention = nil
            session.intervention = nil
        case .toolResult:
            session.phase = .processing
            if session.intervention?.requestID == event.requestID {
                session.attention = nil
                session.intervention = nil
            }
        case .approvalRequested, .answerRequested:
            let kind: AgentInterventionKind = event.kind == .approvalRequested ? .approval : .question
            let attention: AgentAttentionKind = event.kind == .approvalRequested ? .approval : .question
            let requestID = Self.nonEmpty(event.requestID) ?? "request-\(resolvedID)"
            let ownerID = Self.nonEmpty(event.responseOwnerID) ?? "external"
            session.phase = event.kind == .approvalRequested ? .waitingForApproval : .waitingForAnswer
            session.attention = attention
            session.intervention = AgentIntervention(
                requestID: requestID,
                kind: kind,
                title: event.title ?? (kind == .approval ? "Approval required" : "Input required"),
                message: event.message,
                toolName: event.toolName,
                questions: event.questions,
                responseOwnerID: ownerID,
                responseCapability: responseCapability ?? ""
            )
        case .interventionResolved:
            session.phase = .processing
            session.attention = nil
            session.intervention = nil
        case .completed:
            session.phase = .completed
            session.attention = .completion
            session.intervention = nil
            session.completedAt = event.timestamp
        case .interrupted:
            session.phase = .interrupted
            session.attention = nil
            session.intervention = nil
            session.completedAt = event.timestamp
        case .failed:
            session.phase = .failed
            session.attention = .failure
            session.intervention = nil
            session.completedAt = event.timestamp
        case .ended:
            session.phase = .ended
            session.intervention = nil
        case .archived:
            session.phase = .archived
            session.attention = nil
            session.intervention = nil
            session.archivedAt = event.timestamp
        case .usage:
            if let usage = event.usage { session.usage = session.usage.mergingLatest(usage) }
        }

        if let usage = event.usage { session.usage = session.usage.mergingLatest(usage) }
        if Self.shouldReplaceUsageWindows(
            event.usageWindows,
            current: usageWindows[event.provider]
        ) {
            usageWindows[event.provider] = event.usageWindows
        }
        session.appendConversation(event)
        session.lastEventKind = event.kind
        sessions[key] = session
        generation &+= 1
        if persistImmediately { persist() }
        return true
    }

    public func snapshot() -> AgentSnapshot { makeSnapshot() }

    public func flush() { persist() }

    private func makeSnapshot() -> AgentSnapshot {
        let values = sessions.values
            .map(\.snapshot)
            .sorted {
                if $0.lastActivityAt != $1.lastActivityAt { return $0.lastActivityAt > $1.lastActivityAt }
                return $0.id < $1.id
            }
        var providerUsage = importedUsage
        for session in values {
            let current = providerUsage[session.provider] ?? AgentUsage()
            providerUsage[session.provider] = AgentUsage(
                inputTokens: current.inputTokens + session.usage.inputTokens,
                cachedInputTokens: current.cachedInputTokens + session.usage.cachedInputTokens,
                outputTokens: current.outputTokens + session.usage.outputTokens
            )
        }
        return AgentSnapshot(
            generation: generation,
            generatedAt: Date(),
            sessions: values,
            usage: AgentUsageSummary(
                byProvider: providerUsage,
                windowsByProvider: usageWindows.isEmpty ? nil : usageWindows
            )
        )
    }

    private func persist() {
        let state = AgentPersistedState(
            sessions: sessions.values.map(\.persisted),
            associations: associations,
            importedUsage: importedUsage.isEmpty ? nil : importedUsage,
            usageWindows: usageWindows.isEmpty ? nil : usageWindows
        )
        try? persistence?.save(state)
    }

    private func associationKey(provider: AgentProvider, externalID: String) -> String {
        "\(provider.rawValue):\(externalID)"
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private static func defaultTitle(provider: AgentProvider, cwd: String?) -> String {
        if let cwd = nonEmpty(cwd) {
            let name = URL(fileURLWithPath: cwd).lastPathComponent
            if !name.isEmpty { return name }
        }
        return "\(provider.displayName) session"
    }

    private static func shouldReplaceUsageWindows(
        _ incoming: [AgentUsageWindow],
        current: [AgentUsageWindow]?
    ) -> Bool {
        guard !incoming.isEmpty else { return false }
        guard let current, !current.isEmpty else { return true }
        let incomingDate = incoming.compactMap(\.capturedAt).max()
        let currentDate = current.compactMap(\.capturedAt).max()
        switch (incomingDate, currentDate) {
        case let (incoming?, current?): return incoming >= current
        case (.some, .none): return true
        case (.none, .some): return false
        case (.none, .none): return incoming != current
        }
    }
}

private extension MutableAgentSession {
    mutating func appendConversation(_ event: AgentIngressEvent) {
        let message = event.message?.trimmingCharacters(in: .whitespacesAndNewlines)
        let tool = event.toolName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let callID = event.requestID?.trimmingCharacters(in: .whitespacesAndNewlines)

        if event.kind == .toolResult {
            appendToolResult(event, callID: callID)
            trimConversationIfNeeded()
            return
        }

        if event.kind == .approvalRequested || event.kind == .answerRequested,
           let index = matchingToolIndex(callID: callID) {
            let existing = conversation[index]
            conversation[index] = existing.replacingToolState(
                status: .waitingForApproval,
                timestamp: event.timestamp
            )
        }

        let kind: AgentConversationKind
        let fallback: String

        switch event.kind {
        case .promptSubmitted:
            kind = .user
            fallback = "Prompt submitted"
        case .processing:
            kind = tool?.isEmpty == false ? .tool : .assistant
            fallback = tool?.isEmpty == false ? "Using \(tool!)" : "Working"
        case .toolResult:
            return
        case .approvalRequested, .answerRequested:
            kind = .attention
            fallback = event.kind == .approvalRequested ? "Approval required" : "Answer required"
        case .completed:
            kind = message?.isEmpty == false ? .assistant : .status
            fallback = "Completed"
        case .interrupted:
            kind = .status
            fallback = "Interrupted"
        case .failed:
            kind = .status
            fallback = "Failed"
        case .ended:
            kind = .status
            fallback = "Ended"
        case .interventionResolved:
            kind = .status
            fallback = "Response sent"
        case .started, .archived, .usage:
            return
        }

        let text = message?.isEmpty == false ? message! : fallback
        if conversation.contains(where: {
            $0.kind == kind
                && $0.text == text
                && $0.toolName == tool
                && $0.toolCallID == callID
                && $0.timestamp == event.timestamp
        }) {
            return
        }
        let ordinal = conversation.count
        conversation.append(AgentConversationItem(
            id: "\(event.timestamp.timeIntervalSince1970)-\(event.kind.rawValue)-\(ordinal)",
            kind: kind,
            text: text,
            toolName: tool?.isEmpty == false ? tool : nil,
            toolCallID: callID?.isEmpty == false ? callID : nil,
            toolInput: Self.bounded(event.toolInput, limit: 2_048),
            toolStatus: kind == .tool ? .running : nil,
            timestamp: event.timestamp
        ))
        trimConversationIfNeeded()
    }

    private mutating func appendToolResult(_ event: AgentIngressEvent, callID: String?) {
        let result = Self.bounded(event.toolResult ?? event.message, limit: 8_192)
        let status: AgentToolStatus = event.toolSucceeded == false ? .failed : .completed
        if let index = matchingToolIndex(callID: callID) {
            let existing = conversation[index]
            conversation[index] = existing.replacingToolState(
                result: result,
                status: status,
                timestamp: event.timestamp
            )
            return
        }

        let ordinal = conversation.count
        conversation.append(AgentConversationItem(
            id: "\(event.timestamp.timeIntervalSince1970)-\(event.kind.rawValue)-\(ordinal)",
            kind: .tool,
            text: event.toolSucceeded == false ? "Tool failed" : "Tool finished",
            toolName: Self.bounded(event.toolName, limit: 160),
            toolCallID: callID?.isEmpty == false ? callID : nil,
            toolResult: result,
            toolStatus: status,
            timestamp: event.timestamp
        ))
    }

    private func matchingToolIndex(callID: String?) -> Int? {
        if let callID, !callID.isEmpty,
           let exact = conversation.lastIndex(where: { $0.kind == .tool && $0.toolCallID == callID }) {
            return exact
        }
        return conversation.lastIndex(where: { $0.kind == .tool && $0.toolStatus == .running })
    }

    private mutating func trimConversationIfNeeded() {
        conversation.sort {
            if $0.timestamp != $1.timestamp { return $0.timestamp < $1.timestamp }
            return $0.id < $1.id
        }
        if conversation.count > Self.conversationLimit {
            conversation.removeFirst(conversation.count - Self.conversationLimit)
        }
    }

    private static func bounded(_ value: String?, limit: Int) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        guard value.count > limit else { return value }
        return String(value.prefix(limit)) + "…"
    }
}

private extension AgentConversationItem {
    func replacingToolState(
        result: String? = nil,
        status: AgentToolStatus,
        timestamp: Date
    ) -> AgentConversationItem {
        AgentConversationItem(
            id: id,
            kind: kind,
            text: text,
            toolName: toolName,
            toolCallID: toolCallID,
            toolInput: toolInput,
            toolResult: result ?? toolResult,
            toolStatus: status,
            timestamp: timestamp
        )
    }
}

extension JSONEncoder {
    fileprivate static var agent: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

extension JSONDecoder {
    fileprivate static var agent: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

private extension MutableAgentSession {
    init(
        provider: AgentProvider,
        sessionID: String,
        cwd: String?,
        title: String,
        preview: String?,
        phase: AgentPhase,
        attention: AgentAttentionKind?,
        intervention: AgentIntervention?,
        usage: AgentUsage,
        createdAt: Date,
        lastActivityAt: Date,
        completedAt: Date?,
        archivedAt: Date?,
        wasRestored: Bool,
        parentSessionID: String?,
        lastEventKind: AgentEventKind?,
        navigation: AgentNavigationContext? = nil,
        conversation: [AgentConversationItem] = []
    ) {
        self.provider = provider
        self.sessionID = sessionID
        self.cwd = cwd
        self.title = title
        self.preview = preview
        self.phase = phase
        self.attention = attention
        self.intervention = intervention
        self.usage = usage
        self.createdAt = createdAt
        self.lastActivityAt = lastActivityAt
        self.completedAt = completedAt
        self.archivedAt = archivedAt
        self.wasRestored = wasRestored
        self.parentSessionID = parentSessionID
        self.lastEventKind = lastEventKind
        self.navigation = navigation
        self.conversation = conversation
    }
}
