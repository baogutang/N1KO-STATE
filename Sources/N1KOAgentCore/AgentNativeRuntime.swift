import Foundation

public struct AgentNativeSessionHandle: Codable, Equatable, Sendable {
    public let provider: AgentProvider
    public let sessionID: String
    public let cwd: String
    public let createdAt: Date

    public init(provider: AgentProvider, sessionID: String, cwd: String, createdAt: Date = Date()) {
        self.provider = provider
        self.sessionID = sessionID
        self.cwd = cwd
        self.createdAt = createdAt
    }
}

public enum AgentNativeRuntimeError: LocalizedError, Equatable, Sendable {
    case unsupportedProvider(AgentProvider)
    case invalidWorkingDirectory
    case executableUnavailable(AgentProvider)
    case sessionNotOwned(AgentProvider, String)
    case runtimeUnavailable

    public var errorDescription: String? {
        switch self {
        case .unsupportedProvider(let provider):
            return "Native sessions are not supported for \(provider.displayName)."
        case .invalidWorkingDirectory:
            return "Choose an existing readable working directory."
        case .executableUnavailable(let provider):
            return "The \(provider.displayName) executable is unavailable."
        case .sessionNotOwned(let provider, let sessionID):
            return "N1KO-STATE does not own native session \(provider.rawValue):\(sessionID)."
        case .runtimeUnavailable:
            return "The native Agent runtime is unavailable."
        }
    }
}

public protocol AgentNativeRuntimeControlling: AnyObject, AgentManagedSubprocess, Sendable {
    func start(eventHandler: @escaping (AgentIngressEvent) -> Void)
    func stop()
    func isAvailable(provider: AgentProvider) -> Bool
    func manages(provider: AgentProvider, sessionID: String) -> Bool
    func startSession(
        provider: AgentProvider,
        cwd: String,
        preferredSessionID: String?
    ) async throws -> AgentNativeSessionHandle
    func terminateSession(provider: AgentProvider, sessionID: String) async throws
    func sendMessage(
        provider: AgentProvider,
        sessionID: String,
        expectedTurnID: String?,
        text: String
    ) async throws
}

/// Coordinator-owned native Claude/Codex runtime.
///
/// Claude reuses its installed N1KO hook configuration and runs in a private
/// pseudo-terminal. Codex reuses the coordinator's authenticated stdio
/// app-server connection. Only sessions created by this instance can be
/// terminated or receive direct input.
public final class AgentNativeRuntimeController: AgentNativeRuntimeControlling, @unchecked Sendable {
    private struct ClaudeSession {
        let handle: AgentNativeSessionHandle
        let process: Process
        let input: FileHandle
        let output: FileHandle
        let errorOutput: FileHandle
    }

    private let stateLock = NSLock()
    private let codexTransport: (any CodexAppServerCommandTransport)?
    private let environment: [String: String]
    private var claudeSessions: [String: ClaudeSession] = [:]
    private var codexSessions: [String: AgentNativeSessionHandle] = [:]
    private var eventHandler: ((AgentIngressEvent) -> Void)?
    private var stopped = false

    public init(
        codexTransport: (any CodexAppServerCommandTransport)? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.codexTransport = codexTransport
        self.environment = environment
    }

    public var isRunning: Bool {
        stateLock.nativeLock {
            claudeSessions.values.contains(where: { $0.process.isRunning }) || !codexSessions.isEmpty
        }
    }

    public func start(eventHandler: @escaping (AgentIngressEvent) -> Void) {
        stateLock.nativeLock {
            stopped = false
            self.eventHandler = eventHandler
        }
    }

    public func stop() {
        let sessions: [ClaudeSession] = stateLock.nativeLock {
            stopped = true
            let current = Array(claudeSessions.values)
            claudeSessions.removeAll()
            codexSessions.removeAll()
            eventHandler = nil
            return current
        }
        for session in sessions {
            session.output.readabilityHandler = nil
            session.errorOutput.readabilityHandler = nil
            try? session.input.close()
            try? session.output.close()
            try? session.errorOutput.close()
            if session.process.isRunning { session.process.terminate() }
        }
    }

    public func terminate() {
        stop()
    }

    public func isAvailable(provider: AgentProvider) -> Bool {
        switch provider {
        case .claude:
            return Self.resolveClaudeExecutable(environment: environment) != nil
        case .codex:
            return codexTransport?.isRunning == true
        default:
            return false
        }
    }

    public func manages(provider: AgentProvider, sessionID: String) -> Bool {
        stateLock.nativeLock {
            switch provider {
            case .claude: return claudeSessions[sessionID] != nil
            case .codex: return codexSessions[sessionID] != nil
            default: return false
            }
        }
    }

    public func startSession(
        provider: AgentProvider,
        cwd: String,
        preferredSessionID: String? = nil
    ) async throws -> AgentNativeSessionHandle {
        let validatedCWD = try Self.validatedWorkingDirectory(cwd)
        switch provider {
        case .claude:
            return try startClaudeSession(cwd: validatedCWD, preferredSessionID: preferredSessionID)
        case .codex:
            guard let codexTransport else { throw AgentNativeRuntimeError.runtimeUnavailable }
            let sessionID = try await codexTransport.startThread(cwd: validatedCWD)
            let handle = AgentNativeSessionHandle(provider: .codex, sessionID: sessionID, cwd: validatedCWD)
            let handler: ((AgentIngressEvent) -> Void)? = stateLock.nativeLock {
                guard !stopped else { return nil }
                codexSessions[sessionID] = handle
                return eventHandler
            }
            guard let handler else {
                try? await codexTransport.archiveThread(threadID: sessionID)
                throw AgentNativeRuntimeError.runtimeUnavailable
            }
            handler(AgentIngressEvent(
                provider: .codex,
                sessionID: sessionID,
                kind: .started,
                cwd: validatedCWD,
                title: URL(fileURLWithPath: validatedCWD).lastPathComponent
            ))
            return handle
        default:
            throw AgentNativeRuntimeError.unsupportedProvider(provider)
        }
    }

    public func terminateSession(provider: AgentProvider, sessionID: String) async throws {
        switch provider {
        case .claude:
            guard let session = stateLock.nativeLock({ claudeSessions.removeValue(forKey: sessionID) }) else {
                throw AgentNativeRuntimeError.sessionNotOwned(provider, sessionID)
            }
            session.output.readabilityHandler = nil
            session.errorOutput.readabilityHandler = nil
            try? session.input.close()
            if session.process.isRunning { session.process.terminate() }
            publish(AgentIngressEvent(provider: .claude, sessionID: sessionID, kind: .ended))
        case .codex:
            guard stateLock.nativeLock({ codexSessions.removeValue(forKey: sessionID) != nil }) else {
                throw AgentNativeRuntimeError.sessionNotOwned(provider, sessionID)
            }
            guard let codexTransport else { throw AgentNativeRuntimeError.runtimeUnavailable }
            try await codexTransport.archiveThread(threadID: sessionID)
            publish(AgentIngressEvent(provider: .codex, sessionID: sessionID, kind: .archived))
        default:
            throw AgentNativeRuntimeError.unsupportedProvider(provider)
        }
    }

    public func sendMessage(
        provider: AgentProvider,
        sessionID: String,
        expectedTurnID: String?,
        text: String
    ) async throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.utf8.count <= 64 * 1024, !trimmed.contains("\0") else {
            throw AgentCapabilityError.invalidMessage
        }
        switch provider {
        case .claude:
            guard let session = stateLock.nativeLock({ claudeSessions[sessionID] }) else {
                throw AgentNativeRuntimeError.sessionNotOwned(provider, sessionID)
            }
            try session.input.write(contentsOf: Data((trimmed + "\n").utf8))
            publish(AgentIngressEvent(
                provider: .claude,
                sessionID: sessionID,
                kind: .promptSubmitted,
                message: trimmed
            ))
        case .codex:
            guard let codexTransport else { throw AgentNativeRuntimeError.runtimeUnavailable }
            try await codexTransport.sendMessage(
                threadID: sessionID,
                expectedTurnID: expectedTurnID,
                text: trimmed
            )
            publish(AgentIngressEvent(
                provider: .codex,
                sessionID: sessionID,
                kind: .promptSubmitted,
                message: trimmed
            ))
        default:
            throw AgentNativeRuntimeError.unsupportedProvider(provider)
        }
    }

    public static func resolveClaudeExecutable(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        isExecutable: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) -> URL? {
        if let explicit = nonEmpty(environment["N1KO_CLAUDE_PATH"]), isExecutable(explicit) {
            return URL(fileURLWithPath: explicit)
        }
        let pathCandidates = (environment["PATH"] ?? "")
            .split(separator: ":")
            .map { "\($0)/claude" }
        let fixedCandidates = [
            NSHomeDirectory() + "/.local/bin/claude",
            NSHomeDirectory() + "/.volta/bin/claude",
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
            "/usr/bin/claude"
        ]
        if let resolved = (pathCandidates + fixedCandidates).first(where: isExecutable) {
            return URL(fileURLWithPath: resolved)
        }
        guard let shellResolved = probeClaudeExecutable(environment: environment),
              isExecutable(shellResolved) else { return nil }
        return URL(fileURLWithPath: shellResolved)
    }

    private static func probeClaudeExecutable(environment: [String: String]) -> String? {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", "command -v claude 2>/dev/null || true"]
        process.environment = environment
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0,
                  let text = String(data: data, encoding: .utf8) else { return nil }
            return text.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first(where: { $0.hasPrefix("/") })
        } catch {
            return nil
        }
    }

    private func startClaudeSession(
        cwd: String,
        preferredSessionID: String?
    ) throws -> AgentNativeSessionHandle {
        guard let executable = Self.resolveClaudeExecutable(environment: environment) else {
            throw AgentNativeRuntimeError.executableUnavailable(.claude)
        }
        let sessionID = Self.validatedSessionID(preferredSessionID) ?? UUID().uuidString.lowercased()
        let process = Process()
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.currentDirectoryURL = URL(fileURLWithPath: cwd, isDirectory: true)
        process.executableURL = URL(fileURLWithPath: "/usr/bin/script")
        process.arguments = [
            "-q", "/dev/null", "/bin/zsh", "-lc",
            "cd \(Self.shellQuote(cwd)) && exec \(Self.shellQuote(executable.path)) --session-id \(Self.shellQuote(sessionID))"
        ]
        process.environment = environment
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        let output = outputPipe.fileHandleForReading
        let errorOutput = errorPipe.fileHandleForReading
        output.readabilityHandler = { handle in _ = handle.availableData }
        errorOutput.readabilityHandler = { handle in _ = handle.availableData }
        process.terminationHandler = { [weak self] terminated in
            self?.handleClaudeTermination(sessionID: sessionID, process: terminated)
        }

        try process.run()
        let handle = AgentNativeSessionHandle(provider: .claude, sessionID: sessionID, cwd: cwd)
        let session = ClaudeSession(
            handle: handle,
            process: process,
            input: inputPipe.fileHandleForWriting,
            output: output,
            errorOutput: errorOutput
        )
        let handler: ((AgentIngressEvent) -> Void)? = stateLock.nativeLock {
            guard !stopped else { return nil }
            claudeSessions[sessionID] = session
            return eventHandler
        }
        guard let handler else {
            process.terminate()
            throw AgentNativeRuntimeError.runtimeUnavailable
        }
        handler(AgentIngressEvent(
            provider: .claude,
            sessionID: sessionID,
            kind: .started,
            cwd: cwd,
            title: URL(fileURLWithPath: cwd).lastPathComponent
        ))
        return handle
    }

    private func handleClaudeTermination(sessionID: String, process: Process) {
        let removed: ClaudeSession? = stateLock.nativeLock {
            guard let current = claudeSessions[sessionID], current.process === process else { return nil }
            return claudeSessions.removeValue(forKey: sessionID)
        }
        guard let removed else { return }
        removed.output.readabilityHandler = nil
        removed.errorOutput.readabilityHandler = nil
        let kind: AgentEventKind = process.terminationStatus == 0 ? .ended : .failed
        publish(AgentIngressEvent(provider: .claude, sessionID: sessionID, kind: kind))
    }

    private func publish(_ event: AgentIngressEvent) {
        let handler = stateLock.nativeLock { eventHandler }
        handler?(event)
    }

    private static func validatedWorkingDirectory(_ path: String) throws -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.hasPrefix("/"), !trimmed.contains("\0") else {
            throw AgentNativeRuntimeError.invalidWorkingDirectory
        }
        let standardized = URL(fileURLWithPath: trimmed, isDirectory: true).standardizedFileURL.path
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: standardized, isDirectory: &isDirectory),
              isDirectory.boolValue,
              FileManager.default.isReadableFile(atPath: standardized) else {
            throw AgentNativeRuntimeError.invalidWorkingDirectory
        }
        return standardized
    }

    private static func validatedSessionID(_ value: String?) -> String? {
        guard let value = nonEmpty(value), value.utf8.count <= 256 else { return nil }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return value.unicodeScalars.allSatisfy(allowed.contains) ? value : nil
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}

private extension NSLock {
    @discardableResult
    func nativeLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
