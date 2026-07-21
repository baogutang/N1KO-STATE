// N1KO modification notice: adapted from Ping Island commit da130d6 for
// N1KO's single-owner integration, macOS 12 compatibility, or fullscreen boundary.

import Foundation

struct HookEvent: Sendable {
    let sessionId: String
    let cwd: String
    let event: String
    let status: String
    let provider: SessionProvider
    let clientInfo: SessionClientInfo
    let pid: Int?
    let tty: String?
    let tool: String?
    let toolInput: [String: AnyCodable]?
    let toolUseId: String?
    let notificationType: String?
    let message: String?
    let ingress: SessionIngress
    let bridgeIntervention: SessionIntervention?
    let bridgeExpectsResponse: Bool?
    let suppressInAppPrompt: Bool
    /// True when Codex fires a PermissionRequest hook with `permission_mode=bypassPermissions`,
    /// meaning Codex has already auto-approved the tool call internally.  Island should
    /// respond to the hook immediately without showing an approval card.
    let codexBypassPermissions: Bool

    nonisolated init(
        sessionId: String,
        cwd: String,
        event: String,
        status: String,
        provider: SessionProvider,
        clientInfo: SessionClientInfo,
        pid: Int?,
        tty: String?,
        tool: String?,
        toolInput: [String: AnyCodable]?,
        toolUseId: String?,
        notificationType: String?,
        message: String?,
        ingress: SessionIngress = .hookBridge,
        bridgeIntervention: SessionIntervention? = nil,
        bridgeExpectsResponse: Bool? = nil,
        suppressInAppPrompt: Bool = false,
        codexBypassPermissions: Bool = false
    ) {
        self.sessionId = sessionId
        self.cwd = cwd
        self.event = event
        self.status = status
        self.provider = provider
        self.clientInfo = clientInfo
        self.pid = pid
        self.tty = tty
        self.tool = tool
        self.toolInput = toolInput
        self.toolUseId = toolUseId
        self.notificationType = notificationType
        self.message = message
        self.ingress = ingress
        self.bridgeIntervention = bridgeIntervention
        self.bridgeExpectsResponse = bridgeExpectsResponse
        self.suppressInAppPrompt = suppressInAppPrompt
        self.codexBypassPermissions = codexBypassPermissions
    }

    nonisolated var sessionPhase: SessionPhase {
        if event == "PreCompact" {
            return .compacting
        }

        if shouldSuppressApprovalHandling,
           status == "waiting_for_approval" {
            return .processing
        }

        switch status {
        case "waiting_for_approval":
            return .waitingForApproval(PermissionContext(
                toolUseId: toolUseId ?? "",
                toolName: tool ?? "unknown",
                toolInput: toolInput,
                receivedAt: Date()
            ))
        case "waiting_for_input":
            return .waitingForInput
        case "running_tool", "processing", "starting":
            return .processing
        case "compacting":
            return .compacting
        default:
            return .idle
        }
    }

    nonisolated var expectsResponse: Bool {
        if bridgeExpectsResponse == false {
            return false
        }

        if isQoderCLIAnsweredQuestionPermissionRequest {
            return true
        }

        if isQoderWorkNotifyOnlyPermissionRequest {
            return false
        }

        if isQoderWorkNonResponsiveToolEvent {
            return false
        }

        if isQoderIDENotifyOnlyClient {
            return false
        }

        let normalizedTool = tool?
            .lowercased()
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
        let isPermissionRequest = event == "PermissionRequest" && status == "waiting_for_approval"
        if suppressInAppPrompt, !isPermissionRequest {
            return false
        }
        let isPlainClaudeCodeClient = clientInfo.isPlainClaudeCodeRouting

        return isPermissionRequest
            || (event == "Notification" && status == "waiting_for_approval"
                && clientInfo.isQwenCodeClient && notificationType == "permission_prompt")
            || (
                event == "Notification"
                    && clientInfo.isCodeBuddyCLIClient
                    && notificationType == "permission_prompt"
                    && isCodeBuddyCLIAskUserQuestionNotification
            )
            || (
                event == "PreToolUse"
                    && normalizedTool == "askuserquestion"
                    && toolInput?["questions"] != nil
                    && !isAnsweredAskUserQuestionEvent
                    && !isPlainClaudeCodeClient
            )
            || (
                event == "PermissionRequest"
                    && normalizedTool == "askuserquestion"
                    && toolInput?["questions"] != nil
                    && !isAnsweredAskUserQuestionEvent
                    && isPlainClaudeCodeClient
            )
            || (
                event == "PreToolUse"
                    && normalizedTool == "exitplanmode"
                    && clientInfo.normalizedForClaudeRouting().profileID == "qoder-cli"
            )
    }

    nonisolated var isQoderWorkNonResponsiveToolEvent: Bool {
        guard bridgeExpectsResponse == false else { return false }
        guard event == "PreToolUse" || event == "PostToolUse" || event == "PermissionRequest" else {
            return false
        }
        return isQoderWorkClient
    }

    nonisolated var isQoderWorkNotifyOnlyPermissionRequest: Bool {
        event == "PermissionRequest"
            && isQoderWorkClient
            && !isAskUserQuestionRequest
    }

    private nonisolated var isQoderWorkClient: Bool {
        let normalizedClientInfo = clientInfo.normalizedForClaudeRouting()
        if normalizedClientInfo.profileID == "qoderwork" {
            return true
        }

        return [
            normalizedClientInfo.terminalBundleIdentifier,
            normalizedClientInfo.bundleIdentifier,
            clientInfo.terminalBundleIdentifier,
            clientInfo.bundleIdentifier
        ].contains { value in
            value?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased() == "com.qoder.work"
        }
    }

    nonisolated var shouldFilterBeforeApprovalHandling: Bool {
        isQoderWorkNonResponsiveToolEvent || isQoderWorkNotifyOnlyPermissionRequest
    }

    nonisolated var shouldSuppressApprovalHandling: Bool {
        bridgeExpectsResponse == false || isQoderWorkNotifyOnlyPermissionRequest
    }

    private nonisolated var isCodeBuddyCLIAskUserQuestionNotification: Bool {
        let normalizedMessage = message?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard let normalizedMessage else { return false }
        return normalizedMessage.contains("askuserquestion")
            || normalizedMessage.contains("ask user question")
            || normalizedMessage.contains("ask_user_question")
            || normalizedMessage.contains("askfollowupquestion")
            || normalizedMessage.contains("ask followup question")
            || normalizedMessage.contains("ask_followup_question")
    }

    private nonisolated var isQoderCLIAnsweredQuestionPermissionRequest: Bool {
        event == "PermissionRequest"
            && clientInfo.profileID?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased() == "qoder-cli"
            && isAnsweredAskUserQuestionEvent
    }

    private nonisolated var isQoderIDENotifyOnlyClient: Bool {
        let normalizedClientInfo = clientInfo.normalizedForClaudeRouting()
        if normalizedClientInfo.profileID == "qoder" {
            return true
        }

        return [
            normalizedClientInfo.terminalBundleIdentifier,
            normalizedClientInfo.bundleIdentifier,
            clientInfo.terminalBundleIdentifier,
            clientInfo.bundleIdentifier
        ].contains { value in
            value?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased() == "com.qoder.ide"
        }
    }
}

extension HookEvent {
    nonisolated func withToolUseId(_ toolUseId: String) -> HookEvent {
        HookEvent(
            sessionId: sessionId,
            cwd: cwd,
            event: event,
            status: status,
            provider: provider,
            clientInfo: clientInfo,
            pid: pid,
            tty: tty,
            tool: tool,
            toolInput: toolInput,
            toolUseId: toolUseId,
            notificationType: notificationType,
            message: message,
            ingress: ingress,
            bridgeIntervention: bridgeIntervention?.withResolvedToolUseId(toolUseId),
            bridgeExpectsResponse: bridgeExpectsResponse,
            suppressInAppPrompt: suppressInAppPrompt,
            codexBypassPermissions: codexBypassPermissions
        )
    }

    nonisolated func withIngress(_ ingress: SessionIngress) -> HookEvent {
        HookEvent(
            sessionId: sessionId,
            cwd: cwd,
            event: event,
            status: status,
            provider: provider,
            clientInfo: clientInfo,
            pid: pid,
            tty: tty,
            tool: tool,
            toolInput: toolInput,
            toolUseId: toolUseId,
            notificationType: notificationType,
            message: message,
            ingress: ingress,
            bridgeIntervention: bridgeIntervention,
            bridgeExpectsResponse: bridgeExpectsResponse,
            suppressInAppPrompt: suppressInAppPrompt,
            codexBypassPermissions: codexBypassPermissions
        )
    }
}

private extension SessionIntervention {
    nonisolated func withResolvedToolUseId(_ toolUseId: String) -> SessionIntervention {
        guard !toolUseId.isEmpty else { return self }

        var metadata = self.metadata
        metadata["toolUseId"] = toolUseId
        metadata["tool_use_id"] = toolUseId
        metadata["originalToolUseId"] = toolUseId

        return SessionIntervention(
            id: id,
            kind: kind,
            title: title,
            message: message,
            options: options,
            questions: questions,
            supportsSessionScope: supportsSessionScope,
            metadata: metadata
        )
    }
}

private enum BridgeProvider: String, Codable, Sendable {
    case claude
    case codex
    case copilot
    case kimi
    case gemini
}

private enum BridgeStatusKind: String, Codable, Sendable {
    case idle
    case active
    case thinking
    case runningTool
    case waitingForApproval
    case waitingForInput
    case compacting
    case completed
    case interrupted
    case notification
    case error
}

private struct BridgeStatus: Codable, Sendable {
    let kind: BridgeStatusKind
    let detail: String?
}

private struct BridgeTerminalContext: Codable, Sendable {
    let terminalProgram: String?
    let terminalBundleID: String?
    let ideName: String?
    let ideBundleID: String?
    let iTermSessionID: String?
    let terminalSessionID: String?
    let tty: String?
    let currentDirectory: String?
    let transport: String?
    let remoteHost: String?
    let tmuxSession: String?
    let tmuxPane: String?
}

private struct BridgeEnvelope: Decodable, Sendable {
    let id: UUID
    let provider: BridgeProvider
    let eventType: String
    let sessionKey: String
    let title: String?
    let preview: String?
    let cwd: String?
    let status: BridgeStatus?
    let terminalContext: BridgeTerminalContext
    let intervention: BridgeEnvelopeIntervention?
    let expectsResponse: Bool
    let metadata: [String: String]
    let sentAt: Date

    private enum CodingKeys: String, CodingKey {
        case id
        case provider
        case eventType
        case sessionKey
        case title
        case preview
        case cwd
        case status
        case terminalContext
        case intervention
        case expectsResponse
        case metadata
        case clientKind
        case clientName
        case sentAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(UUID.self, forKey: .id)
        provider = try container.decode(BridgeProvider.self, forKey: .provider)
        eventType = try container.decode(String.self, forKey: .eventType)
        sessionKey = try container.decode(String.self, forKey: .sessionKey)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        preview = try container.decodeIfPresent(String.self, forKey: .preview)
        cwd = try container.decodeIfPresent(String.self, forKey: .cwd)
        status = try container.decodeIfPresent(BridgeStatus.self, forKey: .status)
        terminalContext = try container.decodeIfPresent(BridgeTerminalContext.self, forKey: .terminalContext)
            ?? BridgeTerminalContext(
                terminalProgram: nil,
                terminalBundleID: nil,
                ideName: nil,
                ideBundleID: nil,
                iTermSessionID: nil,
                terminalSessionID: nil,
                tty: nil,
                currentDirectory: nil,
                transport: nil,
                remoteHost: nil,
                tmuxSession: nil,
                tmuxPane: nil
            )
        intervention = try container.decodeIfPresent(BridgeEnvelopeIntervention.self, forKey: .intervention)

        var decodedMetadata = try container.decodeIfPresent([String: String].self, forKey: .metadata) ?? [:]
        if decodedMetadata["client_kind"] == nil,
           let clientKind = try container.decodeIfPresent(String.self, forKey: .clientKind),
           !clientKind.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            decodedMetadata["client_kind"] = clientKind
        }
        if decodedMetadata["client_name"] == nil,
           let clientName = try container.decodeIfPresent(String.self, forKey: .clientName),
           !clientName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            decodedMetadata["client_name"] = clientName
        }
        let expectation = try Self.decodeResponseExpectation(from: container)
        if decodedMetadata["tool_input_json"] == nil,
           let injectedToolInput = expectation.injectedToolInput,
           let encodedToolInput = Self.encodeToolInputJSON(injectedToolInput) {
            decodedMetadata["tool_input_json"] = encodedToolInput
        }

        expectsResponse = expectation.value
        metadata = decodedMetadata
        sentAt = try container.decodeIfPresent(Date.self, forKey: .sentAt) ?? Date()
    }

    private static func decodeResponseExpectation(
        from container: KeyedDecodingContainer<CodingKeys>
    ) throws -> (value: Bool, injectedToolInput: [String: Any]?) {
        if let expectsResponse = try? container.decode(Bool.self, forKey: .expectsResponse) {
            return (expectsResponse, nil)
        }

        if let questionArray = try? container.decode([AnyCodable].self, forKey: .expectsResponse) {
            let questions = questionArray.map(\.value)
            guard !questions.isEmpty else {
                return (false, nil)
            }
            return (true, ["questions": questions])
        }

        if let responseObject = try? container.decode([String: AnyCodable].self, forKey: .expectsResponse) {
            let normalizedObject = responseObject.mapValues(\.value)
            if normalizedObject["questions"] != nil {
                return (true, normalizedObject)
            }

            let looksLikeQuestion = [
                normalizedObject["question"],
                normalizedObject["prompt"],
                normalizedObject["header"],
                normalizedObject["options"]
            ].contains { $0 != nil }

            if looksLikeQuestion {
                return (true, ["questions": [normalizedObject]])
            }

            return (!normalizedObject.isEmpty, nil)
        }

        return (false, nil)
    }

    private static func encodeToolInputJSON(_ object: [String: Any]) -> String? {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              let json = String(data: data, encoding: .utf8) else {
            return nil
        }
        return json
    }
}

private struct BridgeEnvelopeIntervention: Codable, Sendable {
    let id: String?
    let kind: String
    let title: String?
    let message: String?
    let options: [BridgeEnvelopeInterventionOption]?
    let supportsSessionScope: Bool?
    let sessionID: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case kind
        case title
        case message
        case options
        case supportsSessionScope
        case sessionID
    }

    func sessionIntervention(fallbackID: String?, metadata: [String: String]) -> SessionIntervention? {
        guard let kind = SessionInterventionKind(rawValue: self.kind) else {
            return nil
        }

        var interventionMetadata: [String: String] = [:]
        for key in [
            "tool_name",
            "toolName",
            "tool_input_json",
            "toolInputJSON",
            "tool_use_id",
            "permission_suggestions",
            "permission_rules",
            "permissionRules"
        ] {
            if let value = metadata[key], !value.isEmpty {
                interventionMetadata[key] = value
            }
        }

        return SessionIntervention(
            id: id ?? fallbackID ?? UUID().uuidString,
            kind: kind,
            title: title ?? defaultTitle(for: kind),
            message: message ?? "",
            options: (options ?? []).map(\.sessionOption),
            questions: [],
            supportsSessionScope: supportsSessionScope ?? false,
            metadata: interventionMetadata
        )
    }

    private func defaultTitle(for kind: SessionInterventionKind) -> String {
        switch kind {
        case .approval:
            return "Approval Needed"
        case .question:
            return "Question"
        }
    }
}

private struct BridgeEnvelopeInterventionOption: Codable, Sendable {
    let id: String
    let title: String
    let detail: String?

    var sessionOption: SessionInterventionOption {
        SessionInterventionOption(id: id, title: title, detail: detail)
    }
}

struct AnyCodable: Codable, @unchecked Sendable {
    nonisolated(unsafe) let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            value = NSNull()
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode value")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch value {
        case is NSNull:
            try container.encodeNil()
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        default:
            throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: [], debugDescription: "Cannot encode value"))
        }
    }
}
