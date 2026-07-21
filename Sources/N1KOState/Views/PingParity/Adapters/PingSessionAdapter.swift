import Combine
import Foundation
import N1KOAgentCore

@MainActor
final class SessionStore {
    static let shared = SessionStore()
    let sessionsPublisher = CurrentValueSubject<[SessionState], Never>([])

    func replace(with sessions: [SessionState]) {
        sessionsPublisher.send(sessions)
    }

    func session(for sessionID: String) -> SessionState? {
        sessionsPublisher.value.first { $0.sessionId == sessionID }
    }

    func process(_ event: SessionEvent) async {
        switch event {
        case .sessionArchived(let sessionID):
            sessionsPublisher.send(sessionsPublisher.value.filter { $0.sessionId != sessionID })
        default:
            break
        }
    }
}

enum PingSessionAdapterError: Error {
    case unavailable
}

/// Presents N1KO's bounded Agent snapshot through Ping-Island's exact UI
/// model. It is an adapter only: no sockets, watchers, persistence, updater,
/// telemetry, or independent runtime is started here.
@MainActor
final class SessionMonitor: ObservableObject {
    nonisolated static var isRunningUnderXCTest: Bool {
        Foundation.ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || NSClassFromString("XCTestCase") != nil
    }

    @Published var instances: [SessionState] = []
    @Published var pendingInstances: [SessionState] = []
    @Published private(set) var claudeUsageSnapshot: ClaudeUsageSnapshot?
    @Published private(set) var codexUsageSnapshot: CodexUsageSnapshot?

    private weak var coordinator: AgentSessionCoordinator?
    private var observerID: UUID?
    private var sourceBySessionID: [String: AgentSessionSnapshot] = [:]
    private var lastSnapshot: AgentSnapshot = .empty
    private var questionDraftCache = SessionQuestionDraftCache()

    deinit {
        if let observerID { coordinator?.removeSnapshotObserver(observerID) }
    }

    func configure(coordinator: AgentSessionCoordinator?) {
        if let observerID { self.coordinator?.removeSnapshotObserver(observerID) }
        observerID = nil
        self.coordinator = coordinator
        guard let coordinator else {
            N1KOSessionActionRouter.shared.replace(with: [:])
            apply(.empty)
            return
        }
        observerID = coordinator.addSnapshotObserver { [weak self] snapshot in
            DispatchQueue.main.async { self?.apply(snapshot) }
        }
    }

    func startMonitoring() {}

    func refreshUsageState() {
        applyUsage(from: lastSnapshot)
    }

    func questionDraft(sessionId: String, interventionId: String) -> SessionQuestionFormDraft? {
        questionDraftCache.draft(sessionId: sessionId, interventionId: interventionId)
    }

    func updateQuestionDraft(
        sessionId: String,
        interventionId: String,
        draft: SessionQuestionFormDraft
    ) {
        questionDraftCache.update(
            sessionId: sessionId,
            interventionId: interventionId,
            draft: draft
        )
    }

    func clearQuestionDraft(sessionId: String, interventionId: String) {
        questionDraftCache.clear(sessionId: sessionId, interventionId: interventionId)
    }

    func approvePermission(sessionId: String, forSession: Bool = false) {
        respond(sessionID: sessionId, action: .approve(scope: forSession ? "session" : nil))
    }

    func denyPermission(sessionId: String, reason: String?) {
        respond(sessionID: sessionId, action: .deny(reason: reason))
    }

    func answerIntervention(sessionId: String, answers: [String: [String]]) {
        respond(sessionID: sessionId, action: .answer(answers))
    }

    func archiveSession(sessionId: String) {
        guard let source = sourceBySessionID[sessionId] else { return }
        _ = coordinator?.archive(provider: source.provider, sessionID: source.sessionID)
    }

    func startNativeSession(provider: SessionProvider, cwd: String, preferredSessionID: String? = nil) {
        guard let coordinator, let nativeProvider = Self.nativeProvider(provider) else { return }
        Task {
            _ = try? await coordinator.startNativeSession(
                provider: nativeProvider,
                cwd: cwd,
                preferredSessionID: preferredSessionID
            )
        }
    }

    func terminateNativeSession(sessionId: String) {
        guard let coordinator, let source = sourceBySessionID[sessionId] else { return }
        Task {
            try? await coordinator.terminateNativeSession(
                provider: source.provider,
                sessionID: source.sessionID
            )
        }
    }

    func loadCodexThread(sessionId: String) async throws -> CodexThreadSnapshot {
        guard let session = instances.first(where: { $0.sessionId == sessionId }) else {
            throw PingSessionAdapterError.unavailable
        }
        return CodexThreadSnapshot(
            threadId: session.sessionId,
            name: session.sessionName,
            preview: session.previewText,
            cwd: session.cwd,
            parentThreadId: session.codexParentThreadId,
            subagentDepth: session.codexSubagentDepth,
            subagentNickname: session.codexSubagentNickname,
            subagentRole: session.codexSubagentRole,
            clientInfo: session.clientInfo,
            intervention: session.intervention,
            createdAt: session.createdAt,
            updatedAt: session.lastActivity,
            phase: session.phase,
            historyItems: session.chatItems,
            conversationInfo: session.conversationInfo,
            latestTurnId: nil,
            latestResponseText: session.conversationInfo.lastMessage,
            latestResponsePhase: session.phase.description,
            latestUserText: session.conversationInfo.firstUserMessage,
            isTurnInterrupted: false
        )
    }

    func sendSessionMessage(sessionId: String, text: String, expectedTurnId: String? = nil) async throws {
        guard let source = sourceBySessionID[sessionId] else {
            throw PingSessionAdapterError.unavailable
        }
        if source.provider == .codex,
           coordinator?.nativeRuntimeAvailable(provider: .codex) == true {
            try await coordinator?.sendNativeMessage(
                provider: .codex,
                sessionID: source.sessionID,
                expectedTurnID: expectedTurnId,
                text: text
            )
            return
        }
        if coordinator?.managesNativeSession(
            provider: source.provider,
            sessionID: source.sessionID
        ) == true {
            try await coordinator?.sendNativeMessage(
                provider: source.provider,
                sessionID: source.sessionID,
                expectedTurnID: expectedTurnId,
                text: text
            )
            return
        }
        guard AgentIntegrationController.shared.canSendFollowUp(to: source) else {
            throw PingSessionAdapterError.unavailable
        }
        let succeeded = await withCheckedContinuation { continuation in
            AgentIntegrationController.shared.sendFollowUp(text, to: source) {
                continuation.resume(returning: $0)
            }
        }
        if !succeeded { throw PingSessionAdapterError.unavailable }
    }

    private func respond(sessionID: String, action: AgentResponseAction) {
        guard let source = sourceBySessionID[sessionID],
              let intervention = source.intervention,
              let coordinator else { return }
        try? coordinator.respond(
            provider: source.provider,
            sessionID: source.sessionID,
            requestID: intervention.requestID,
            ownerID: intervention.responseOwnerID,
            capability: intervention.responseCapability,
            action: action
        )
    }

    private func apply(_ snapshot: AgentSnapshot) {
        lastSnapshot = snapshot
        sourceBySessionID = Dictionary(
            snapshot.sessions.map { ($0.sessionID, $0) },
            uniquingKeysWith: { newer, _ in newer }
        )
        N1KOSessionActionRouter.shared.replace(with: sourceBySessionID)
        let mapped = snapshot.sessions
            .filter { $0.phase != .archived }
            .map { self.mapSession($0) }
            .filter { !$0.shouldHideFromPrimaryUI }
            .sorted(by: { $0.shouldSortBeforeInQueue($1) })
        instances = mapped
        pendingInstances = mapped.filter(\.needsManualAttention)
        SessionStore.shared.replace(with: mapped)
        applyUsage(from: snapshot)
    }

    private func applyUsage(from snapshot: AgentSnapshot) {
        let claudeWindows = snapshot.usage.providerWindows[.claude] ?? []
        claudeUsageSnapshot = ClaudeUsageSnapshot(
            fiveHour: Self.claudeWindow(claudeWindows.first(where: { $0.key == "primary" || $0.label.contains("5") })),
            sevenDay: Self.claudeWindow(claudeWindows.first(where: { $0.key == "secondary" || $0.label.lowercased().contains("7d") })),
            cachedAt: snapshot.generatedAt
        )

        let codexWindows = snapshot.usage.providerWindows[.codex] ?? []
        let codexUsage = snapshot.usage.byProvider[.codex]
        codexUsageSnapshot = CodexUsageSnapshot(
            sourceFilePath: "n1ko-agent-snapshot",
            capturedAt: snapshot.generatedAt,
            planType: nil,
            limitID: nil,
            tokenUsage: codexUsage.map {
                CodexTokenUsage(
                    inputTokens: $0.inputTokens,
                    outputTokens: $0.outputTokens,
                    totalTokens: $0.totalTokens
                )
            },
            windows: codexWindows.map {
                CodexUsageWindow(
                    key: $0.key,
                    label: $0.label,
                    usedPercentage: $0.usedPercentage,
                    leftPercentage: $0.remainingPercentage,
                    windowMinutes: 0,
                    resetsAt: $0.resetsAt
                )
            }
        )
    }

    private static func claudeWindow(_ source: AgentUsageWindow?) -> ClaudeUsageWindow? {
        source.map { ClaudeUsageWindow(usedPercentage: $0.usedPercentage, resetsAt: $0.resetsAt) }
    }

    private func mapSession(_ source: AgentSessionSnapshot) -> SessionState {
        let provider = Self.mapProvider(source.provider)
        let chatItems = source.conversationItems.map(Self.mapConversationItem)
        let intervention = source.intervention.map(Self.mapIntervention)
        let lastAssistant = source.conversationItems.last(where: { $0.kind == .assistant })?.text
        let lastUser = source.conversationItems.last(where: { $0.kind == .user })?.text
        let profileID = Self.mapProfileID(source.provider)
        let profile = ClientProfileRegistry.runtimeProfile(id: profileID)
        let client = SessionClientInfo(
            kind: profile?.kind
                ?? (source.provider == .codex ? .codexApp : (provider == .claude ? .claudeCode : .custom)),
            profileID: profileID,
            name: source.provider.displayName,
            bundleIdentifier: source.provider == .codex
                ? "com.openai.codex"
                : profile?.defaultBundleIdentifier,
            origin: "n1ko-agent-core",
            remoteHost: source.navigation?.remoteHost,
            terminalBundleIdentifier: source.navigation?.terminalBundleIdentifier,
            tmuxSessionIdentifier: source.navigation?.tmuxTarget?.session,
            tmuxPaneIdentifier: source.navigation?.tmuxTarget?.pane
        )
        return SessionState(
            sessionId: source.sessionID,
            cwd: source.cwd ?? FileManager.default.homeDirectoryForCurrentUser.path,
            projectName: source.cwd.map { URL(fileURLWithPath: $0).lastPathComponent },
            provider: provider,
            clientInfo: client,
            ingress: coordinator?.managesNativeSession(
                provider: source.provider,
                sessionID: source.sessionID
            ) == true ? .nativeRuntime : (source.provider == .codex ? .codexAppServer : .hookBridge),
            sessionName: source.title,
            previewText: source.preview,
            latestHookMessage: source.preview,
            suppressInAppPromptControls: false,
            intervention: intervention,
            pendingInterventions: intervention.map { [$0] } ?? [],
            codexParentThreadId: source.parentSessionID,
            linkedParentSessionId: source.parentSessionID,
            isInTmux: source.navigation?.tmuxTarget != nil,
            phase: Self.mapPhase(source, intervention: intervention),
            chatItems: chatItems,
            completedErrorToolIDs: Set(source.conversationItems.compactMap { item in
                item.toolStatus == .failed ? (item.toolCallID ?? item.id) : nil
            }),
            conversationInfo: ConversationInfo(
                summary: source.preview,
                lastMessage: lastAssistant ?? source.preview,
                lastMessageRole: lastAssistant == nil ? nil : "assistant",
                lastToolName: source.conversationItems.last(where: { $0.kind == .tool })?.toolName,
                firstUserMessage: lastUser,
                lastUserMessageDate: source.conversationItems.last(where: { $0.kind == .user })?.timestamp
            ),
            lastActivity: source.lastActivityAt,
            createdAt: source.createdAt
        )
    }

    private static func mapProvider(_ provider: AgentProvider) -> SessionProvider {
        switch provider {
        case .codex: return .codex
        case .copilot: return .copilot
        case .kimi: return .kimi
        case .gemini: return .gemini
        default: return .claude
        }
    }

    private static func nativeProvider(_ provider: SessionProvider) -> AgentProvider? {
        switch provider {
        case .claude: return .claude
        case .codex: return .codex
        case .copilot, .kimi, .gemini: return nil
        }
    }

    private static func mapProfileID(_ provider: AgentProvider) -> String {
        switch provider {
        case .claude: return "claude-code"
        case .codex: return "codex-app"
        case .gemini: return "gemini"
        case .qwen: return "qwen-code"
        case .kimi: return "kimi"
        case .hermes: return "hermes"
        case .openCode: return "opencode"
        case .pi: return "pi"
        case .qoder: return "qoder"
        case .qoderCN: return "qoder-cn"
        case .qoderWork: return "qoderwork"
        case .qoderCLI: return "qoder-cli"
        case .qoderCNCLI: return "qoder-cn-cli"
        case .codeBuddy: return "codebuddy"
        case .codeBuddyCLI: return "codebuddy-cli"
        case .workBuddy: return "workbuddy"
        case .cursor: return "cursor"
        case .trae: return "trae"
        case .openClaw: return "openclaw"
        case .copilot: return "copilot-cli"
        case .jetBrains: return "jb-plugin"
        case .legacyImport: return "claude-code"
        }
    }

    private static func mapPhase(
        _ source: AgentSessionSnapshot,
        intervention: SessionIntervention?
    ) -> SessionPhase {
        switch source.phase {
        case .starting, .processing:
            return .processing
        case .waitingForApproval:
            return .waitingForApproval(PermissionContext(
                toolUseId: source.intervention?.requestID ?? source.sessionID,
                toolName: source.intervention?.toolName ?? "permission",
                toolInput: nil,
                receivedAt: source.lastActivityAt
            ))
        case .waitingForAnswer:
            return .waitingForInput
        case .completed:
            return source.provider == .codex ? .idle : .waitingForInput
        case .interrupted:
            return .idle
        case .failed:
            return .ended
        case .ended, .archived:
            return .ended
        }
    }

    private static func mapIntervention(_ source: AgentIntervention) -> SessionIntervention {
        let questions = source.questions.map { question in
            SessionInterventionQuestion(
                id: question.id,
                header: question.header ?? "Question",
                prompt: question.prompt,
                detail: nil,
                options: question.options.enumerated().map { index, option in
                    SessionInterventionOption(
                        id: "\(question.id)-\(index)",
                        title: option.label,
                        detail: option.description
                    )
                },
                allowsMultiple: question.allowsMultiple,
                allowsOther: question.allowsOther,
                isSecret: false
            )
        }
        return SessionIntervention(
            id: source.requestID,
            kind: source.kind == .approval ? .approval : .question,
            title: source.title,
            message: source.message ?? "",
            options: questions.first?.options ?? [],
            questions: questions,
            supportsSessionScope: source.kind == .approval,
            metadata: [:]
        )
    }

    private static func mapConversationItem(_ source: AgentConversationItem) -> ChatHistoryItem {
        let type: ChatHistoryItemType
        switch source.kind {
        case .user:
            type = .user(source.text)
        case .assistant:
            type = .assistant(source.text)
        case .tool:
            let status: ToolStatus = switch source.toolStatus {
            case .running: .running
            case .waitingForApproval: .waitingForApproval
            case .completed, .none: .success
            case .failed: .error
            }
            type = .toolCall(ToolCallItem(
                name: source.toolName ?? "Tool",
                input: source.toolInput.map { ["input": $0] } ?? [:],
                status: status,
                result: source.toolResult ?? source.text,
                structuredResult: nil,
                subagentTools: []
            ))
        case .attention, .status:
            type = .thinking(source.text)
        }
        return ChatHistoryItem(id: source.id, type: type, timestamp: source.timestamp)
    }
}
