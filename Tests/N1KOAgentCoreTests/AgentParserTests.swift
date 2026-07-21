import Foundation
import XCTest
@testable import N1KOAgentCore

final class AgentParserTests: XCTestCase {
    func testClaudeHookParsesApprovalQuestionCompletionAndUsage() throws {
        let approval = Data(#"{"session_id":"claude-1","cwd":"/tmp/repo","hook_event_name":"PermissionRequest","tool_name":"Bash","tool_use_id":"tool-1","message":"Run tests?"}"#.utf8)
        let event = try XCTUnwrap(ClaudeHookParser.parse(approval, responseOwnerID: "socket-1").first)
        XCTAssertEqual(event.kind, .approvalRequested)
        XCTAssertEqual(event.requestID, "tool-1")
        XCTAssertEqual(event.responseOwnerID, "socket-1")

        let question = Data(#"{"session_id":"claude-1","hook_event_name":"PermissionRequest","tool_name":"AskUserQuestion","tool_use_id":"question-1","tool_input":{"questions":[{"id":"scope","header":"Scope","question":"Where?","options":[{"label":"Tests"},{"label":"UI"}],"multiSelect":false}]}}"#.utf8)
        let questionEvent = try XCTUnwrap(ClaudeHookParser.parse(question, responseOwnerID: "socket-1").first)
        XCTAssertEqual(questionEvent.kind, .answerRequested)
        XCTAssertEqual(questionEvent.questions.first?.prompt, "Where?")
        XCTAssertEqual(questionEvent.questions.first?.options.map(\.label), ["Tests", "UI"])

        let stop = Data(#"{"session_id":"claude-1","hook_event_name":"Stop","usage":{"input_tokens":10,"cache_read_input_tokens":4,"output_tokens":3},"rate_limits":{"five_hour":{"used_percentage":32,"resets_at":1800000000},"seven_day":{"utilization":71,"resets_at":"2030-01-01T00:00:00Z"}}}"#.utf8)
        let stopEvent = try XCTUnwrap(ClaudeHookParser.parse(stop, responseOwnerID: "socket-1").first)
        XCTAssertEqual(stopEvent.kind, .completed)
        XCTAssertEqual(stopEvent.usage, AgentUsage(inputTokens: 10, cachedInputTokens: 4, outputTokens: 3))
        XCTAssertEqual(stopEvent.usageWindows.map(\.label), ["5h", "7d"])
        XCTAssertEqual(stopEvent.usageWindows.map(\.usedPercentage), [32, 71])
    }

    func testClaudeTranscriptParsesConversationAndResult() throws {
        let transcript = Data("""
        {"sessionId":"claude-t","cwd":"/tmp/repo","type":"user","message":{"role":"user","content":"Run tests"}}
        {"sessionId":"claude-t","cwd":"/tmp/repo","type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"tool-q","name":"AskUserQuestion","input":{"questions":[{"id":"which","question":"Which suite?","options":[{"label":"Unit"}]}]}}]}}
        {"sessionId":"claude-t","type":"result","result":"done","usage":{"input_tokens":20,"output_tokens":5}}
        """.utf8)
        let events = try ClaudeTranscriptParser.parse(transcript)
        XCTAssertEqual(events.map(\.kind), [.promptSubmitted, .answerRequested, .completed])
        XCTAssertEqual(events[1].questions.first?.prompt, "Which suite?")
        XCTAssertEqual(events[2].usage?.totalTokens, 25)
    }

    func testCodexRolloutParsesRestoreQuestionResolutionCompletionAndUsage() throws {
        let rollout = Data("""
        {"timestamp":"2026-04-24T17:59:20Z","type":"session_meta","payload":{"id":"thread-1","cwd":"/tmp/repo","originator":"Codex Desktop","source":"desktop"}}
        {"timestamp":"2026-04-24T17:59:21Z","type":"event_msg","payload":{"type":"user_message","message":"Build it"}}
        {"timestamp":"2026-04-24T17:59:27Z","type":"response_item","payload":{"type":"function_call","name":"request_user_input","call_id":"call-q","arguments":"{\\"questions\\":[{\\"id\\":\\"scope\\",\\"question\\":\\"Where?\\",\\"options\\":[{\\"label\\":\\"Tests\\"}]}]}"}}
        {"timestamp":"2026-04-24T17:59:40Z","type":"response_item","payload":{"type":"function_call_output","call_id":"call-q","output":"ok"}}
        {"timestamp":"2026-04-24T17:59:45Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":30,"cached_input_tokens":6,"output_tokens":8}},"rate_limits":{"primary":{"used_percent":20,"window_minutes":300,"resets_at":1800000000},"secondary":{"used_percent":65,"window_minutes":10080,"resets_at":1800600000}}}}
        {"timestamp":"2026-04-24T17:59:46Z","type":"event_msg","payload":{"type":"agent_message","phase":"final","message":"Done"}}
        """.utf8)
        let events = try CodexRolloutParser.parse(rollout)
        XCTAssertEqual(events.first?.kind, .started)
        XCTAssertTrue(events.contains { $0.kind == .answerRequested && $0.questions.first?.prompt == "Where?" })
        XCTAssertTrue(events.contains {
            $0.kind == .toolResult && $0.requestID == "call-q" && $0.toolResult == "ok"
        })
        XCTAssertTrue(events.contains { $0.usage?.outputTokens == 8 })
        let usageEvent = try XCTUnwrap(events.first { !$0.usageWindows.isEmpty })
        XCTAssertEqual(usageEvent.usageWindows.map(\.label), ["5h", "7d"])
        XCTAssertEqual(usageEvent.usageWindows.map(\.remainingPercentage), [80, 35])
        XCTAssertEqual(events.last?.kind, .completed)
    }

    func testClaudeTranscriptProjectsToolInputAndAssociatesToolResult() throws {
        let transcript = Data("""
        {"timestamp":"2026-07-17T01:00:00Z","sessionId":"claude-tools","type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"tool-1","name":"Bash","input":{"command":"swift test"}}]}}
        {"timestamp":"2026-07-17T01:00:01Z","sessionId":"claude-tools","type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"tool-1","content":"All tests passed"}]}}
        """.utf8)

        let events = try ClaudeTranscriptParser.parse(transcript)
        XCTAssertEqual(events.map(\.kind), [.processing, .toolResult])
        XCTAssertEqual(events[0].requestID, "tool-1")
        XCTAssertEqual(events[0].toolInput, #"{"command":"swift test"}"#)
        XCTAssertEqual(events[1].requestID, "tool-1")
        XCTAssertEqual(events[1].toolResult, "All tests passed")
        XCTAssertEqual(events[1].toolSucceeded, true)
    }

    func testCodexRolloutIgnoresMemoryMaintenanceAndFindsCLIApproval() throws {
        let memory = Data("""
        {"type":"session_meta","payload":{"id":"memory-1","cwd":"/tmp/home/.codex/memories","originator":"Codex Desktop"}}
        """.utf8)
        XCTAssertTrue(try CodexRolloutParser.parse(memory).isEmpty)

        let cli = Data("""
        {"type":"session_meta","payload":{"id":"cli-1","cwd":"/tmp/repo","originator":"codex-tui","source":"cli"}}
        {"type":"response_item","payload":{"type":"function_call","name":"mcp__server__tool","call_id":"call-1","arguments":"{}"}}
        """.utf8)
        let events = try CodexRolloutParser.parse(cli)
        XCTAssertTrue(events.contains { $0.kind == .approvalRequested && $0.requestID == "call-1" })
    }

    func testCodexAppServerParsesThreadStatusRequestsAndArchive() throws {
        let started = Data(#"{"jsonrpc":"2.0","method":"thread/started","params":{"thread":{"id":"thread-2","cwd":"/tmp/repo","name":"Task"}}}"#.utf8)
        XCTAssertEqual(try CodexAppServerParser.parse(started, responseOwnerID: "ws-1").first?.kind, .started)

        let request = Data(#"{"jsonrpc":"2.0","id":"req-2","method":"item/commandExecution/requestApproval","params":{"threadId":"thread-2","command":["swift","test"],"cwd":"/tmp/repo"}}"#.utf8)
        let approval = try XCTUnwrap(CodexAppServerParser.parse(request, responseOwnerID: "ws-1").first)
        XCTAssertEqual(approval.kind, .approvalRequested)
        XCTAssertEqual(approval.requestID, "req-2")
        XCTAssertEqual(approval.responseOwnerID, "ws-1")

        let question = Data(#"{"jsonrpc":"2.0","id":"req-q","method":"item/tool/requestUserInput","params":{"threadId":"thread-2","questions":[{"id":"scope","question":"Which?","options":[{"label":"Tests"}]}]}}"#.utf8)
        XCTAssertEqual(try CodexAppServerParser.parse(question, responseOwnerID: "ws-1").first?.kind, .answerRequested)

        let archived = Data(#"{"jsonrpc":"2.0","method":"thread/archived","params":{"threadId":"thread-2"}}"#.utf8)
        XCTAssertEqual(try CodexAppServerParser.parse(archived, responseOwnerID: "ws-1").first?.kind, .archived)
    }
}
