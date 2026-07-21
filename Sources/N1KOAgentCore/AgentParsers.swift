// N1KO modification notice:
// Claude transcript and Codex rollout normalization behavior was adapted from
// the Apache-2.0 Ping Island parsers at commit da130d6. This file is a compact,
// Foundation-only rewrite for N1KO-STATE's provider integration boundary.

import Foundation

public enum AgentParseError: Error, Equatable {
    case invalidJSON
    case missingSessionID
    case unsupportedProvider
}

public enum ClaudeHookParser {
    public static func parse(
        _ data: Data,
        responseOwnerID: String,
        provider: AgentProvider = .claude
    ) throws -> [AgentIngressEvent] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AgentParseError.invalidJSON
        }
        guard let sessionID = string(root, "session_id", "sessionId"), !sessionID.isEmpty else {
            throw AgentParseError.missingSessionID
        }

        let hookName = string(root, "hook_event_name", "hookEventName", "event_name", "eventName", "event") ?? ""
        let timestamp = date(root["timestamp"]) ?? Date()
        let cwd = string(root, "cwd")
        let message = string(root, "message", "prompt")
        let toolName = string(root, "tool_name", "tool")
        let requestID = string(root, "tool_use_id", "toolUseId", "request_id", "requestId")
        let toolInput = jsonProjection(root["tool_input"] ?? root["toolInput"], limit: 2_048)
        let toolResult = toolResultContent(
            root["tool_response"] ?? root["toolResponse"] ?? root["tool_result"] ?? root["toolResult"]
        )
        let transcriptPath = string(root, "transcript_path", "transcriptPath")
        let usage = parseUsage(root["usage"] as? [String: Any] ?? root)
        let usageWindows = parseClaudeUsageWindows(root, capturedAt: timestamp)
        let navigation = parseNavigation(root)
        let normalizedTool = toolName?
            .lowercased()
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")

        let kind: AgentEventKind
        var questions: [AgentQuestion] = []
        switch normalizedEventName(hookName) {
        case "sessionstart":
            kind = .started
        case "userpromptsubmit", "userpromptsubmitted", "beforesubmitprompt", "beforeagent", "messagereceived":
            kind = .promptSubmitted
        case "permissionrequest":
            questions = parseQuestions(from: root)
            kind = normalizedTool == "askuserquestion" || !questions.isEmpty
                ? .answerRequested
                : .approvalRequested
        case "pretooluse", "beforetool":
            questions = parseQuestions(from: root)
            kind = normalizedTool == "askuserquestion" && !questions.isEmpty
                ? .answerRequested
                : .processing
        case "posttooluse", "aftertool":
            kind = .toolResult
        case "posttoolusefailure":
            kind = .toolResult
        case "subagentstart", "messagesent", "sessioncompactbefore", "sessioncompactafter",
             "sessionpatch", "precompact", "precompress":
            kind = .processing
        case "stop", "agentstop", "subagentstop", "afteragent", "commandstop":
            kind = .completed
        case "sessionend", "commandreset":
            kind = .ended
        case "commandnew":
            kind = .started
        case "erroroccurred":
            kind = .failed
        case "notification":
            let type = string(root, "notification_type", "notificationType")?.lowercased()
            kind = type == "permission_prompt" ? .approvalRequested : .processing
        default:
            kind = .processing
        }

        return [AgentIngressEvent(
            provider: provider,
            sessionID: sessionID,
            kind: kind,
            timestamp: timestamp,
            cwd: cwd,
            title: string(root, "session_name", "title"),
            message: message,
            toolName: toolName,
            toolInput: toolInput,
            toolResult: toolResult,
            toolSucceeded: normalizedEventName(hookName) == "posttoolusefailure"
                ? false
                : (kind == .toolResult ? true : nil),
            requestID: requestID,
            questions: questions,
            responseOwnerID: kind == .approvalRequested || kind == .answerRequested ? responseOwnerID : nil,
            usage: usage,
            usageWindows: usageWindows,
            transcriptPath: transcriptPath,
            navigation: navigation
        )]
    }
}

/// Single N1KO-owned dispatch point for every managed client. Provider-specific
/// bridges normalize their wire payload to one of these public protocol
/// families without importing another lifecycle or settings owner.
public enum AgentManagedHookParser {
    public static func parse(
        _ data: Data,
        provider: AgentProvider,
        responseOwnerID: String
    ) throws -> [AgentIngressEvent] {
        if provider == .codex, looksLikeJSONRPC(data) {
            return try CodexAppServerParser.parse(data, responseOwnerID: responseOwnerID)
        }
        return try ClaudeHookParser.parse(
            data,
            responseOwnerID: responseOwnerID,
            provider: provider
        )
    }

    private static func looksLikeJSONRPC(_ data: Data) -> Bool {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }
        return root["jsonrpc"] != nil || root["method"] != nil
    }
}

public enum ClaudeTranscriptParser {
    /// Parses a bounded transcript payload. The caller owns file-size limits and
    /// watching; this parser has no timer or filesystem side effects.
    public static func parse(
        _ data: Data,
        fallbackSessionID: String? = nil,
        provider: AgentProvider = .claude
    ) throws -> [AgentIngressEvent] {
        guard let text = String(data: data, encoding: .utf8) else { throw AgentParseError.invalidJSON }
        var events: [AgentIngressEvent] = []
        for line in text.split(whereSeparator: \.isNewline) {
            guard let lineData = String(line).data(using: .utf8),
                  let root = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else {
                continue
            }
            guard let sessionID = string(root, "sessionId", "session_id") ?? fallbackSessionID else { continue }
            let timestamp = date(root["timestamp"]) ?? Date()
            let cwd = string(root, "cwd")
            let type = string(root, "type")?.lowercased() ?? ""
            let message = root["message"] as? [String: Any]
            let role = string(message ?? [:], "role")?.lowercased()

            if type == "user" || role == "user" {
                let content = message?["content"]
                if let blocks = content as? [[String: Any]] {
                    for block in blocks where string(block, "type") == "tool_result" {
                        events.append(AgentIngressEvent(
                            provider: provider,
                            sessionID: sessionID,
                            kind: .toolResult,
                            timestamp: timestamp,
                            cwd: cwd,
                            toolResult: toolResultContent(block["content"] ?? block["result"]),
                            toolSucceeded: (block["is_error"] as? Bool).map { !$0 } ?? true,
                            requestID: string(block, "tool_use_id", "toolUseId", "id")
                        ))
                    }
                }
                if let userText = textOnlyContent(content) {
                    events.append(AgentIngressEvent(
                        provider: provider,
                        sessionID: sessionID,
                        kind: .promptSubmitted,
                        timestamp: timestamp,
                        cwd: cwd,
                        message: userText
                    ))
                }
                continue
            }

            if type == "assistant" || role == "assistant" {
                let blocks = message?["content"] as? [[String: Any]] ?? []
                if let assistantText = textOnlyContent(message?["content"]) {
                    events.append(AgentIngressEvent(
                        provider: provider,
                        sessionID: sessionID,
                        kind: .processing,
                        timestamp: timestamp,
                        cwd: cwd,
                        message: assistantText
                    ))
                }
                for block in blocks where string(block, "type") == "tool_use" {
                    let name = string(block, "name")
                    let normalized = name?.lowercased().replacingOccurrences(of: "_", with: "")
                    let input = block["input"] as? [String: Any] ?? [:]
                    let questions = parseQuestions(from: ["tool_input": input])
                    events.append(AgentIngressEvent(
                        provider: provider,
                        sessionID: sessionID,
                        kind: normalized == "askuserquestion" ? .answerRequested : .processing,
                        timestamp: timestamp,
                        cwd: cwd,
                        toolName: name,
                        toolInput: jsonProjection(block["input"], limit: 2_048),
                        requestID: string(block, "id"),
                        questions: questions,
                        responseOwnerID: normalized == "askuserquestion" ? "transcript-external" : nil
                    ))
                }
                if blocks.isEmpty, textOnlyContent(message?["content"]) == nil {
                    events.append(AgentIngressEvent(
                        provider: provider,
                        sessionID: sessionID,
                        kind: .processing,
                        timestamp: timestamp,
                        cwd: cwd,
                        message: textContent(message?["content"])
                    ))
                }
                continue
            }

            if type == "result" {
                let usage = parseUsage(root["usage"] as? [String: Any] ?? root)
                events.append(AgentIngressEvent(
                    provider: provider,
                    sessionID: sessionID,
                    kind: (root["is_error"] as? Bool) == true ? .failed : .completed,
                    timestamp: timestamp,
                    cwd: cwd,
                    message: string(root, "result"),
                    usage: usage
                ))
            }
        }
        return events
    }
}

public enum CodexRolloutParser {
    public static func parse(_ data: Data, fallbackSessionID: String? = nil) throws -> [AgentIngressEvent] {
        guard let text = String(data: data, encoding: .utf8) else { throw AgentParseError.invalidJSON }
        var events: [AgentIngressEvent] = []
        var sessionID = fallbackSessionID
        var cwd: String?
        var title: String?
        var parentSessionID: String?
        var isCLI = false

        for line in text.split(whereSeparator: \.isNewline) {
            guard let lineData = String(line).data(using: .utf8),
                  let root = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let type = string(root, "type"),
                  let payload = root["payload"] as? [String: Any] else {
                continue
            }
            let timestamp = date(root["timestamp"]) ?? Date()

            if type == "session_meta" {
                sessionID = string(payload, "id") ?? sessionID
                cwd = string(payload, "cwd") ?? cwd
                title = string(payload, "title", "name") ?? title
                parentSessionID = string(payload, "forked_from_id", "parent_thread_id")
                    ?? subagentParentID(payload)
                let originator = string(payload, "originator")?.lowercased() ?? ""
                let source = string(payload, "source")?.lowercased() ?? ""
                isCLI = originator.contains("tui") || source == "cli"
                if cwd?.contains("/.codex/memories") == true { return [] }
                if let sessionID {
                    events.append(AgentIngressEvent(
                        provider: .codex,
                        sessionID: sessionID,
                        kind: .started,
                        timestamp: timestamp,
                        cwd: cwd,
                        title: title,
                        parentSessionID: parentSessionID
                    ))
                }
                continue
            }

            guard let sessionID else { continue }
            let payloadType = string(payload, "type") ?? ""
            switch type {
            case "event_msg":
                switch payloadType {
                case "user_message":
                    events.append(event(.promptSubmitted, payload, sessionID, timestamp, cwd, title, parentSessionID))
                case "agent_message":
                    let phase = string(payload, "phase")?.lowercased()
                    events.append(event(phase == "final" ? .completed : .processing,
                                        payload, sessionID, timestamp, cwd, title, parentSessionID))
                case "task_started", "turn_started":
                    events.append(event(.processing, payload, sessionID, timestamp, cwd, title, parentSessionID))
                case "task_complete", "turn_completed":
                    events.append(event(.completed, payload, sessionID, timestamp, cwd, title, parentSessionID))
                case "turn_aborted":
                    events.append(event(.interrupted, payload, sessionID, timestamp, cwd, title, parentSessionID))
                case "token_count":
                    let windows = parseCodexUsageWindows(payload, capturedAt: timestamp)
                    if let usage = codexUsage(payload) {
                        events.append(AgentIngressEvent(
                            provider: .codex,
                            sessionID: sessionID,
                            kind: .usage,
                            timestamp: timestamp,
                            usage: usage,
                            usageWindows: windows
                        ))
                    } else if !windows.isEmpty {
                        events.append(AgentIngressEvent(
                            provider: .codex,
                            sessionID: sessionID,
                            kind: .usage,
                            timestamp: timestamp,
                            usageWindows: windows
                        ))
                    }
                default:
                    break
                }
            case "response_item":
                switch payloadType {
                case "function_call":
                    let name = string(payload, "name") ?? "tool"
                    let requestID = string(payload, "call_id", "id")
                    if name == "request_user_input" {
                        let args = decodedObject(string(payload, "arguments"))
                        let questions = parseQuestions(from: args ?? [:])
                        events.append(AgentIngressEvent(
                            provider: .codex,
                            sessionID: sessionID,
                            kind: .answerRequested,
                            timestamp: timestamp,
                            cwd: cwd,
                            title: "Codex needs input",
                            message: questions.first?.prompt,
                            toolName: name,
                            toolInput: boundedString(string(payload, "arguments"), limit: 2_048),
                            requestID: requestID,
                            questions: questions,
                            responseOwnerID: "codex-rollout"
                        ))
                    } else if isCLI && name.hasPrefix("mcp__") {
                        events.append(AgentIngressEvent(
                            provider: .codex,
                            sessionID: sessionID,
                            kind: .approvalRequested,
                            timestamp: timestamp,
                            cwd: cwd,
                            title: "MCP tool approval required",
                            message: name,
                            toolName: name,
                            toolInput: boundedString(string(payload, "arguments"), limit: 2_048),
                            requestID: requestID,
                            responseOwnerID: "codex-rollout"
                        ))
                    } else {
                        events.append(AgentIngressEvent(
                            provider: .codex,
                            sessionID: sessionID,
                            kind: .processing,
                            timestamp: timestamp,
                            cwd: cwd,
                            toolName: name,
                            toolInput: boundedString(string(payload, "arguments"), limit: 2_048),
                            requestID: requestID
                        ))
                    }
                case "function_call_output":
                    events.append(AgentIngressEvent(
                        provider: .codex,
                        sessionID: sessionID,
                        kind: .toolResult,
                        timestamp: timestamp,
                        cwd: cwd,
                        toolResult: toolResultContent(payload["output"] ?? payload["content"]),
                        toolSucceeded: (payload["is_error"] as? Bool).map { !$0 } ?? true,
                        requestID: string(payload, "call_id")
                    ))
                case "message":
                    let phase = string(payload, "phase")?.lowercased()
                    events.append(AgentIngressEvent(
                        provider: .codex,
                        sessionID: sessionID,
                        kind: phase == "final" ? .completed : .processing,
                        timestamp: timestamp,
                        cwd: cwd,
                        title: title,
                        message: textContent(payload["content"]),
                        parentSessionID: parentSessionID
                    ))
                default:
                    break
                }
            default:
                break
            }
        }
        return events
    }

    private static func event(
        _ kind: AgentEventKind,
        _ payload: [String: Any],
        _ sessionID: String,
        _ timestamp: Date,
        _ cwd: String?,
        _ title: String?,
        _ parentSessionID: String?
    ) -> AgentIngressEvent {
        AgentIngressEvent(
            provider: .codex,
            sessionID: sessionID,
            kind: kind,
            timestamp: timestamp,
            cwd: cwd,
            title: title,
            message: string(payload, "message") ?? textContent(payload["content"]),
            usage: codexUsage(payload),
            parentSessionID: parentSessionID
        )
    }
}

public enum CodexAppServerParser {
    public static func parse(_ data: Data, responseOwnerID: String) throws -> [AgentIngressEvent] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let method = string(root, "method") else {
            throw AgentParseError.invalidJSON
        }
        let params = root["params"] as? [String: Any] ?? [:]
        let requestID = string(root, "id") ?? string(params, "requestId", "request_id")

        if method == "thread/started", let thread = params["thread"] as? [String: Any],
           let sessionID = string(thread, "id") {
            return [AgentIngressEvent(
                provider: .codex,
                sessionID: sessionID,
                kind: .started,
                cwd: string(thread, "cwd", "path"),
                title: string(thread, "name", "title"),
                message: string(thread, "preview"),
                parentSessionID: string(thread, "parentThreadId", "parent_thread_id")
            )]
        }

        guard let sessionID = string(params, "threadId", "thread_id", "conversationId") else {
            throw AgentParseError.missingSessionID
        }

        switch method {
        case "thread/status/changed":
            let status = params["status"] as? [String: Any] ?? [:]
            let type = string(status, "type")
            let flags = status["activeFlags"] as? [String] ?? []
            let kind: AgentEventKind
            if flags.contains("waitingOnApproval") { kind = .approvalRequested }
            else if flags.contains("waitingOnUserInput") { kind = .answerRequested }
            else if type == "active" { kind = .processing }
            else if type == "systemError" { kind = .failed }
            else { kind = .completed }
            return [AgentIngressEvent(
                provider: .codex,
                sessionID: sessionID,
                kind: kind,
                requestID: requestID,
                responseOwnerID: kind == .approvalRequested || kind == .answerRequested ? responseOwnerID : nil
            )]
        case "thread/archived":
            return [AgentIngressEvent(provider: .codex, sessionID: sessionID, kind: .archived)]
        case "turn/completed", "task/complete":
            return [AgentIngressEvent(
                provider: .codex,
                sessionID: sessionID,
                kind: .completed,
                message: string(params, "message"),
                usage: codexUsage(params)
            )]
        case "item/commandExecution/requestApproval", "item/fileChange/requestApproval", "item/permissions/requestApproval":
            let tool: String
            let title: String
            if method.contains("commandExecution") { tool = "exec_command"; title = "Approve command" }
            else if method.contains("fileChange") { tool = "file_change"; title = "Approve file changes" }
            else { tool = "permissions"; title = "Approve permissions" }
            let command = (params["command"] as? [String])?.joined(separator: " ")
            return [AgentIngressEvent(
                provider: .codex,
                sessionID: sessionID,
                kind: .approvalRequested,
                cwd: string(params, "cwd"),
                title: title,
                message: string(params, "reason") ?? command ?? string(params, "grantRoot"),
                toolName: tool,
                requestID: requestID,
                responseOwnerID: responseOwnerID
            )]
        case "item/tool/requestUserInput":
            let questions = parseQuestions(from: params)
            return [AgentIngressEvent(
                provider: .codex,
                sessionID: sessionID,
                kind: .answerRequested,
                title: "Codex needs input",
                message: questions.first?.prompt,
                toolName: "request_user_input",
                requestID: requestID,
                questions: questions,
                responseOwnerID: responseOwnerID
            )]
        default:
            return []
        }
    }
}

// MARK: - Shared parser helpers

private func string(_ dictionary: [String: Any], _ keys: String...) -> String? {
    for key in keys {
        if let value = dictionary[key] as? String {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        if let value = dictionary[key] as? NSNumber { return value.stringValue }
    }
    return nil
}

private func normalizedEventName(_ value: String) -> String {
    value.lowercased().filter(\.isLetter)
}

private func parseNavigation(_ root: [String: Any]) -> AgentNavigationContext? {
    let environment = (root["environment"] as? [String: Any])
        ?? (root["env"] as? [String: Any])
        ?? [:]
    let terminalBundle = string(
        root,
        "terminal_bundle_identifier",
        "terminalBundleIdentifier",
        "bundle_identifier"
    ) ?? string(environment, "__CFBundleIdentifier", "TERM_PROGRAM_BUNDLE_ID")
    let tmuxSession = string(root, "tmux_session", "tmuxSession")
    let tmuxWindow = string(root, "tmux_window", "tmuxWindow")
    let tmuxPane = string(root, "tmux_pane", "tmuxPane")
    let tmuxTarget = tmuxSession.flatMap {
        try? AgentTMUXTarget(session: $0, window: tmuxWindow, pane: tmuxPane)
    }
    let remoteHost = string(root, "remote_host", "remoteHost")
    guard terminalBundle != nil || tmuxTarget != nil || remoteHost != nil else { return nil }
    return AgentNavigationContext(
        terminalBundleIdentifier: terminalBundle,
        tmuxTarget: tmuxTarget,
        remoteHost: remoteHost
    )
}

private func date(_ value: Any?) -> Date? {
    guard let text = value as? String else { return nil }
    let fractional = ISO8601DateFormatter()
    fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return fractional.date(from: text) ?? ISO8601DateFormatter().date(from: text)
}

private func decodedObject(_ value: String?) -> [String: Any]? {
    guard let value, let data = value.data(using: .utf8) else { return nil }
    return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
}

private func textContent(_ value: Any?) -> String? {
    if let text = value as? String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
    guard let blocks = value as? [[String: Any]] else { return nil }
    let joined = blocks.compactMap { string($0, "text", "content") }.joined(separator: "\n")
    return joined.isEmpty ? nil : joined
}

private func textOnlyContent(_ value: Any?) -> String? {
    if let text = value as? String { return boundedString(text, limit: 16_384) }
    guard let blocks = value as? [[String: Any]] else { return nil }
    let joined = blocks.compactMap { block -> String? in
        let type = string(block, "type")?.lowercased()
        guard type == nil || type == "text" || type == "input_text" || type == "output_text" else {
            return nil
        }
        return string(block, "text", "content")
    }.joined(separator: "\n")
    return boundedString(joined, limit: 16_384)
}

private func toolResultContent(_ value: Any?) -> String? {
    if let text = value as? String { return boundedString(text, limit: 8_192) }
    if let blocks = value as? [[String: Any]] {
        let joined = blocks.compactMap { block in
            string(block, "text", "content") ?? jsonProjection(block, limit: 2_048)
        }.joined(separator: "\n")
        return boundedString(joined, limit: 8_192)
    }
    return jsonProjection(value, limit: 8_192)
}

private func jsonProjection(_ value: Any?, limit: Int) -> String? {
    guard let value, JSONSerialization.isValidJSONObject(value),
          let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
          let text = String(data: data, encoding: .utf8) else { return nil }
    return boundedString(text, limit: limit)
}

private func boundedString(_ value: String?, limit: Int) -> String? {
    guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
        return nil
    }
    guard trimmed.count > limit else { return trimmed }
    return String(trimmed.prefix(limit)) + "…"
}

private func parseQuestions(from root: [String: Any]) -> [AgentQuestion] {
    let toolInput = root["tool_input"] as? [String: Any]
        ?? root["toolInput"] as? [String: Any]
        ?? root
    let rawQuestions = toolInput["questions"] as? [[String: Any]] ?? []
    return rawQuestions.enumerated().compactMap { index, question in
        guard let prompt = string(question, "question", "prompt"), !prompt.isEmpty else { return nil }
        let options = (question["options"] as? [[String: Any]] ?? []).compactMap { option -> AgentQuestionOption? in
            guard let label = string(option, "label", "title") else { return nil }
            return AgentQuestionOption(label: label, description: string(option, "description"))
        }
        return AgentQuestion(
            id: string(question, "id") ?? "question-\(index)",
            header: string(question, "header", "title"),
            prompt: prompt,
            options: options,
            allowsMultiple: (question["multiSelect"] as? Bool) ?? false,
            allowsOther: (question["allowsOther"] as? Bool) ?? true
        )
    }
}

private func parseUsage(_ dictionary: [String: Any]) -> AgentUsage? {
    let input = int(dictionary, "input_tokens", "inputTokens")
    let cached = int(dictionary, "cache_read_input_tokens", "cached_input_tokens", "cachedInputTokens")
    let output = int(dictionary, "output_tokens", "outputTokens")
    guard input != nil || cached != nil || output != nil else { return nil }
    return AgentUsage(inputTokens: input ?? 0, cachedInputTokens: cached ?? 0, outputTokens: output ?? 0)
}

private func codexUsage(_ dictionary: [String: Any]) -> AgentUsage? {
    if let usage = parseUsage(dictionary) { return usage }
    if let usage = dictionary["usage"] as? [String: Any], let parsed = parseUsage(usage) { return parsed }
    if let info = dictionary["info"] as? [String: Any] {
        if let total = info["total_token_usage"] as? [String: Any], let parsed = parseUsage(total) { return parsed }
        if let last = info["last_token_usage"] as? [String: Any], let parsed = parseUsage(last) { return parsed }
    }
    return nil
}

private func parseClaudeUsageWindows(
    _ root: [String: Any],
    capturedAt: Date
) -> [AgentUsageWindow] {
    guard let limits = root["rate_limits"] as? [String: Any] else { return [] }
    return [("five_hour", "5h"), ("seven_day", "7d")].compactMap { key, label in
        guard let payload = limits[key] as? [String: Any],
              let used = double(payload, "used_percentage", "utilization") else { return nil }
        return AgentUsageWindow(
            key: key,
            label: label,
            usedPercentage: used,
            resetsAt: usageWindowDate(payload["resets_at"]),
            capturedAt: capturedAt
        )
    }
}

private func parseCodexUsageWindows(
    _ payload: [String: Any],
    capturedAt: Date
) -> [AgentUsageWindow] {
    guard let limits = payload["rate_limits"] as? [String: Any] else { return [] }
    return ["primary", "secondary"].compactMap { key in
        guard let window = limits[key] as? [String: Any],
              let used = double(window, "used_percent", "used_percentage"),
              let minutes = int(window, "window_minutes") else { return nil }
        return AgentUsageWindow(
            key: key,
            label: usageWindowLabel(minutes: minutes),
            usedPercentage: used,
            resetsAt: usageWindowDate(window["resets_at"]),
            capturedAt: capturedAt
        )
    }
}

private func usageWindowLabel(minutes: Int) -> String {
    let days = minutes / 1_440
    let hours = (minutes % 1_440) / 60
    let remainingMinutes = minutes % 60
    if days > 0, hours == 0, remainingMinutes == 0 { return "\(days)d" }
    if days > 0, hours > 0 { return "\(days)d \(hours)h" }
    if hours > 0, remainingMinutes == 0 { return "\(hours)h" }
    if hours > 0 { return "\(hours)h \(remainingMinutes)m" }
    return "\(minutes)m"
}

private func usageWindowDate(_ value: Any?) -> Date? {
    if let number = value as? NSNumber { return Date(timeIntervalSince1970: number.doubleValue) }
    if let string = value as? String {
        if let seconds = Double(string) { return Date(timeIntervalSince1970: seconds) }
        return date(string)
    }
    return nil
}

private func double(_ dictionary: [String: Any], _ keys: String...) -> Double? {
    for key in keys {
        if let value = dictionary[key] as? Double { return value }
        if let value = dictionary[key] as? NSNumber { return value.doubleValue }
        if let value = dictionary[key] as? String, let parsed = Double(value) { return parsed }
    }
    return nil
}

private func int(_ dictionary: [String: Any], _ keys: String...) -> Int? {
    for key in keys {
        if let value = dictionary[key] as? Int { return value }
        if let value = dictionary[key] as? NSNumber { return value.intValue }
    }
    return nil
}

private func subagentParentID(_ payload: [String: Any]) -> String? {
    guard let source = payload["source"] as? [String: Any],
          let subagent = source["subagent"] as? [String: Any],
          let spawn = subagent["thread_spawn"] as? [String: Any] else { return nil }
    return string(spawn, "parent_thread_id")
}
