import Foundation

public enum CodexAppServerTransportError: LocalizedError, Equatable, Sendable {
    case executableUnavailable
    case alreadyRunning
    case notRunning
    case initializationFailed
    case invalidResponse(String)
    case requestTimedOut(String)
    case remoteError(String)

    public var errorDescription: String? {
        switch self {
        case .executableUnavailable:
            return "Codex app-server executable is unavailable."
        case .alreadyRunning:
            return "Codex app-server transport is already running."
        case .notRunning:
            return "Codex app-server transport is not running."
        case .initializationFailed:
            return "Codex app-server initialization failed."
        case .invalidResponse(let method):
            return "Codex app-server returned an invalid response for \(method)."
        case .requestTimedOut(let method):
            return "Codex app-server request timed out: \(method)."
        case .remoteError(let message):
            return message
        }
    }
}

/// A private stdio JSON-RPC connection to `codex app-server`.
///
/// Stdio deliberately replaces the upstream fixed loopback WebSocket port:
/// N1KO owns the child process and both pipe endpoints, so no other local
/// process can inject notifications or response requests into this channel.
/// The child still uses the user's existing Codex authentication state; N1KO
/// never reads, copies, or persists credentials.
public final class CodexAppServerStdioTransport: CodexAppServerCommandTransport, AgentManagedSubprocess, @unchecked Sendable {
    public static let defaultOwnerID = "n1ko-codex-app-server"

    private typealias PendingCompletion = (Result<[String: Any], Error>) -> Void

    private let stateLock = NSLock()
    private let readQueue = DispatchQueue(label: "com.n1ko.state.agent.codex-stdio", qos: .utility)
    private let environment: [String: String]
    private let executableOverride: URL?
    private let requestTimeout: TimeInterval
    private let ownerID: String

    private var process: Process?
    private var standardInput: FileHandle?
    private var standardOutput: FileHandle?
    private var standardError: FileHandle?
    private var outputBuffer = Data()
    private var receiver: ((CodexAppServerMessage) -> Void)?
    private var pending: [String: PendingCompletion] = [:]
    private var requestSequence: UInt64 = 0
    private var stopping = false

    public init(
        executableURL: URL? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        ownerID: String = CodexAppServerStdioTransport.defaultOwnerID,
        requestTimeout: TimeInterval = 15
    ) {
        executableOverride = executableURL
        self.environment = environment
        self.ownerID = ownerID
        self.requestTimeout = max(requestTimeout, 1)
    }

    public var isRunning: Bool {
        stateLock.n1koWithLock { process?.isRunning == true }
    }

    public func start(receive: @escaping (CodexAppServerMessage) -> Void) throws {
        if isRunning {
            stateLock.n1koWithLock { receiver = receive }
            return
        }
        guard let executableURL = executableOverride ?? Self.resolveExecutable(environment: environment) else {
            // Codex is optional. An unavailable binary must not prevent the
            // rest of Agent Core (including Claude hooks) from starting.
            return
        }

        let process = Process()
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.executableURL = executableURL
        process.arguments = ["app-server", "--stdio"]
        process.environment = environment
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        let output = outputPipe.fileHandleForReading
        let errorOutput = errorPipe.fileHandleForReading
        output.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.readQueue.async { self?.consumeOutput(data) }
        }
        // Drain diagnostics so a verbose child can never block on a full pipe.
        // Content is intentionally not logged because it can contain user data.
        errorOutput.readabilityHandler = { handle in
            _ = handle.availableData
        }

        process.terminationHandler = { [weak self] terminated in
            self?.handleTermination(terminated)
        }

        try process.run()
        stateLock.n1koWithLock {
            stopping = false
            self.process = process
            standardInput = inputPipe.fileHandleForWriting
            standardOutput = output
            standardError = errorOutput
            receiver = receive
            outputBuffer.removeAll(keepingCapacity: true)
        }

        do {
            _ = try sendRequestBlocking(
                method: "initialize",
                params: [
                    "clientInfo": [
                        "name": "n1ko-state",
                        "title": "N1KO-STATE",
                        "version": Self.applicationVersion
                    ],
                    "capabilities": ["experimentalApi": true]
                ],
                timeout: min(requestTimeout, 8)
            )
        } catch {
            stop()
            // Treat a missing login, incompatible CLI, or failed child as an
            // unavailable optional transport; commands still surface a clear
            // `notRunning` error to the explicit user action.
            return
        }
    }

    public func stop() {
        let captured: (Process?, FileHandle?, FileHandle?, FileHandle?, [PendingCompletion]) = stateLock.n1koWithLock {
            stopping = true
            let callbacks = Array(pending.values)
            pending.removeAll()
            receiver = nil
            let value = (process, standardInput, standardOutput, standardError, callbacks)
            process = nil
            standardInput = nil
            standardOutput = nil
            standardError = nil
            outputBuffer.removeAll(keepingCapacity: false)
            return value
        }

        captured.2?.readabilityHandler = nil
        captured.3?.readabilityHandler = nil
        try? captured.1?.close()
        try? captured.2?.close()
        try? captured.3?.close()
        if captured.0?.isRunning == true { captured.0?.terminate() }
        captured.4.forEach { $0(.failure(CancellationError())) }
    }

    public func terminate() {
        stop()
    }

    public func startThread(cwd: String) async throws -> String {
        let response = try await sendRequest(
            method: "thread/start",
            params: [
                "cwd": cwd,
                "experimentalRawEvents": false,
                "persistExtendedHistory": true
            ]
        )
        guard let thread = response["thread"] as? [String: Any],
              let threadID = Self.nonEmptyString(thread["id"]) else {
            throw CodexAppServerTransportError.invalidResponse("thread/start")
        }
        return threadID
    }

    public func archiveThread(threadID: String) async throws {
        _ = try await sendRequest(
            method: "thread/archive",
            params: ["threadId": threadID]
        )
    }

    public func sendMessage(threadID: String, expectedTurnID: String?, text: String) async throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.utf8.count <= 64 * 1024 else {
            throw AgentCapabilityError.invalidMessage
        }
        let input: [[String: Any]] = [["type": "text", "text": trimmed]]
        var resolvedTurnID = Self.nonEmptyString(expectedTurnID)
        if resolvedTurnID == nil,
           let response = try? await sendRequest(
               method: "thread/read",
               params: ["threadId": threadID, "includeTurns": true]
           ),
           let thread = response["thread"] as? [String: Any],
           let status = thread["status"] as? [String: Any],
           Self.nonEmptyString(status["type"]) == "active",
           let turns = thread["turns"] as? [[String: Any]] {
            resolvedTurnID = turns.last.flatMap { Self.nonEmptyString($0["id"]) }
        }
        if let expectedTurnID = resolvedTurnID {
            _ = try await sendRequest(
                method: "turn/steer",
                params: [
                    "threadId": threadID,
                    "expectedTurnId": expectedTurnID,
                    "input": input
                ]
            )
        } else {
            _ = try await sendRequest(
                method: "turn/start",
                params: ["threadId": threadID, "input": input]
            )
        }
    }

    public static func resolveExecutable(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        isExecutable: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) -> URL? {
        if let explicit = nonEmptyString(environment["N1KO_CODEX_PATH"]), isExecutable(explicit) {
            return URL(fileURLWithPath: explicit)
        }
        let pathCandidates = (environment["PATH"] ?? "")
            .split(separator: ":")
            .map { "\($0)/codex" }
        let fixedCandidates = [
            "/Applications/Codex.app/Contents/Resources/codex",
            "/Applications/ChatGPT.app/Contents/Resources/codex",
            NSHomeDirectory() + "/.local/bin/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            "/usr/bin/codex"
        ]
        return (pathCandidates + fixedCandidates)
            .first(where: isExecutable)
            .map { URL(fileURLWithPath: $0) }
    }

    private func sendRequest(method: String, params: [String: Any]) async throws -> [String: Any] {
        try await withCheckedThrowingContinuation { continuation in
            do {
                let id = try enqueueRequest(method: method, params: params) { result in
                    continuation.resume(with: result)
                }
                scheduleTimeout(id: id, method: method)
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private func sendRequestBlocking(
        method: String,
        params: [String: Any],
        timeout: TimeInterval
    ) throws -> [String: Any] {
        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<[String: Any], Error>?
        let id = try enqueueRequest(method: method, params: params) {
            result = $0
            semaphore.signal()
        }
        guard semaphore.wait(timeout: .now() + timeout) == .success else {
            let completion = stateLock.n1koWithLock { pending.removeValue(forKey: id) }
            completion?(.failure(CodexAppServerTransportError.requestTimedOut(method)))
            throw CodexAppServerTransportError.requestTimedOut(method)
        }
        return try result?.get() ?? { throw CodexAppServerTransportError.invalidResponse(method) }()
    }

    @discardableResult
    private func enqueueRequest(
        method: String,
        params: [String: Any],
        completion: @escaping PendingCompletion
    ) throws -> String {
        let prepared: (String, FileHandle) = try stateLock.n1koWithLock {
            guard let standardInput, process?.isRunning == true, !stopping else {
                throw CodexAppServerTransportError.notRunning
            }
            requestSequence &+= 1
            let id = String(requestSequence)
            pending[id] = completion
            return (id, standardInput)
        }
        let payload: [String: Any] = [
            "jsonrpc": "2.0",
            "id": prepared.0,
            "method": method,
            "params": params
        ]
        do {
            var data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
            data.append(0x0A)
            try prepared.1.write(contentsOf: data)
        } catch {
            let callback = stateLock.n1koWithLock { pending.removeValue(forKey: prepared.0) }
            callback?(.failure(error))
            throw error
        }
        return prepared.0
    }

    private func scheduleTimeout(id: String, method: String) {
        readQueue.asyncAfter(deadline: .now() + requestTimeout) { [weak self] in
            guard let self else { return }
            let completion = self.stateLock.n1koWithLock { self.pending.removeValue(forKey: id) }
            completion?(.failure(CodexAppServerTransportError.requestTimedOut(method)))
        }
    }

    private func consumeOutput(_ data: Data) {
        outputBuffer.append(data)
        while let newline = outputBuffer.firstIndex(of: 0x0A) {
            let line = Data(outputBuffer[..<newline])
            outputBuffer.removeSubrange(...newline)
            guard !line.isEmpty else { continue }
            handleLine(line)
        }
    }

    private func handleLine(_ data: Data) {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        if root["method"] == nil, let id = Self.requestID(root["id"]) {
            let completion = stateLock.n1koWithLock { pending.removeValue(forKey: id) }
            guard let completion else { return }
            if let error = root["error"] as? [String: Any] {
                completion(.failure(CodexAppServerTransportError.remoteError(
                    Self.nonEmptyString(error["message"]) ?? "Unknown Codex app-server error"
                )))
            } else {
                completion(.success(root["result"] as? [String: Any] ?? [:]))
            }
            return
        }

        guard root["method"] != nil else { return }
        let channel = makeResponseChannel(for: root)
        let callback = stateLock.n1koWithLock { receiver }
        callback?(CodexAppServerMessage(data: data, responseChannel: channel))
    }

    private func makeResponseChannel(for root: [String: Any]) -> AgentResponseChannel? {
        guard let id = Self.requestID(root["id"]),
              let method = Self.nonEmptyString(root["method"]) else { return nil }
        let params = root["params"] as? [String: Any] ?? [:]
        return AgentResponseChannel(provider: .codex, ownerID: ownerID) { [weak self] action in
            guard let self, let result = Self.responsePayload(action: action, method: method, params: params) else {
                return false
            }
            return self.sendResponse(id: id, result: result)
        }
    }

    private func sendResponse(id: String, result: [String: Any]) -> Bool {
        let handle = stateLock.n1koWithLock { standardInput }
        guard let handle, isRunning else { return false }
        let payload: [String: Any] = ["jsonrpc": "2.0", "id": id, "result": result]
        guard var data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]) else {
            return false
        }
        data.append(0x0A)
        do {
            try handle.write(contentsOf: data)
            return true
        } catch {
            return false
        }
    }

    static func responsePayload(
        action: AgentResponseAction,
        method: String,
        params: [String: Any]
    ) -> [String: Any]? {
        switch method {
        case "item/commandExecution/requestApproval", "item/fileChange/requestApproval":
            switch action {
            case .approve(let scope):
                return ["decision": scope == "session" ? "acceptForSession" : "accept"]
            case .deny:
                return ["decision": "decline"]
            case .answer:
                return nil
            }
        case "item/permissions/requestApproval":
            switch action {
            case .approve(let scope):
                return [
                    "permissions": params["permissions"] as? [String: Any] ?? [:],
                    "scope": scope == "session" ? "session" : "turn"
                ]
            case .deny:
                return ["permissions": [:], "scope": "turn"]
            case .answer:
                return nil
            }
        case "item/tool/requestUserInput":
            guard case .answer(let answers) = action else { return nil }
            return [
                "answers": answers.reduce(into: [String: Any]()) { result, entry in
                    result[entry.key] = ["answers": entry.value]
                }
            ]
        default:
            return nil
        }
    }

    private func handleTermination(_ terminatedProcess: Process) {
        let callbacks: [PendingCompletion] = stateLock.n1koWithLock {
            guard process === terminatedProcess else { return [] }
            process = nil
            standardInput = nil
            standardOutput = nil
            standardError = nil
            receiver = nil
            let values = Array(pending.values)
            pending.removeAll()
            return values
        }
        callbacks.forEach { $0(.failure(CodexAppServerTransportError.notRunning)) }
    }

    private static func requestID(_ value: Any?) -> String? {
        if let value = value as? String { return nonEmptyString(value) }
        if let value = value as? NSNumber { return value.stringValue }
        return nil
    }

    private static func nonEmptyString(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static var applicationVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }
}

private extension NSLock {
    @discardableResult
    func n1koWithLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
