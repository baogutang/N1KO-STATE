import Foundation

public enum AgentCapabilityError: Error, Equatable {
    case disabled(AgentIntegrationCapability)
    case invalidTMUXTarget
    case invalidMessage
    case invalidRemoteHost
    case invalidRemoteUser
    case invalidRemotePort
    case missingHostFingerprint
}

/// User-controlled capability gate. Constructing plans is side-effect free;
/// application code may request a system permission or launch a process only
/// after `require(_:)` succeeds in direct response to a user action.
public struct AgentCapabilityPolicy: Equatable, Sendable {
    public let enabled: Set<AgentIntegrationCapability>

    public init(enabled: Set<AgentIntegrationCapability> = []) {
        self.enabled = enabled
    }

    public func require(_ capability: AgentIntegrationCapability) throws {
        guard enabled.contains(capability) else {
            throw AgentCapabilityError.disabled(capability)
        }
    }
}

public struct AgentTMUXTarget: Codable, Equatable, Sendable {
    public let session: String
    public let window: String?
    public let pane: String?

    public init(session: String, window: String? = nil, pane: String? = nil) throws {
        let values = [session, window, pane].compactMap { $0 }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-.")
        guard !session.isEmpty,
              values.allSatisfy({ value in
                  !value.isEmpty && value.count <= 128
                      && value.unicodeScalars.allSatisfy(allowed.contains)
              }) else {
            throw AgentCapabilityError.invalidTMUXTarget
        }
        self.session = session
        self.window = window
        self.pane = pane
    }

    public var selector: String {
        [session, window, pane].compactMap { $0 }.joined(separator: ":")
    }

    public var focusArguments: [String] { ["select-pane", "-t", selector] }
}

/// Side-effect-free tmux follow-up plan matching Ping-Island's literal
/// `send-keys` + separate Enter behavior. Application code executes it only
/// after the user submits text and the tmux capability gate is enabled.
public struct AgentTMUXMessagePlan: Equatable, Sendable {
    public let executableURL: URL
    public let textArguments: [String]
    public let enterArguments: [String]

    public init(
        target: AgentTMUXTarget,
        message: String,
        policy: AgentCapabilityPolicy
    ) throws {
        try policy.require(.tmux)
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.count <= 16_384,
              !trimmed.unicodeScalars.contains(where: { $0.value == 0 }) else {
            throw AgentCapabilityError.invalidMessage
        }
        executableURL = AgentTMUXExecutableResolver.resolve()
            ?? URL(fileURLWithPath: "/usr/bin/tmux")
        textArguments = ["send-keys", "-t", target.selector, "-l", trimmed]
        enterArguments = ["send-keys", "-t", target.selector, "Enter"]
    }
}

public enum AgentTMUXExecutableResolver {
    public static func resolve(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        isExecutable: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) -> URL? {
        if let explicit = environment["N1KO_TMUX_PATH"], isExecutable(explicit) {
            return URL(fileURLWithPath: explicit)
        }
        let fromPath = (environment["PATH"] ?? "")
            .split(separator: ":")
            .map { "\($0)/tmux" }
        let candidates = fromPath + ["/opt/homebrew/bin/tmux", "/usr/local/bin/tmux", "/usr/bin/tmux"]
        return candidates.first(where: isExecutable).map { URL(fileURLWithPath: $0) }
    }
}

public struct AgentRemoteEndpoint: Codable, Equatable, Sendable {
    public let host: String
    public let user: String
    public let port: Int
    public let hostKeyFingerprint: String

    public init(host: String, user: String, port: Int = 22, hostKeyFingerprint: String) throws {
        let hostAllowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-_:")
        let userAllowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-.")
        guard !host.isEmpty, host.count <= 253,
              host.unicodeScalars.allSatisfy(hostAllowed.contains),
              !host.hasPrefix("-"), !host.contains("..") else {
            throw AgentCapabilityError.invalidRemoteHost
        }
        guard !user.isEmpty, user.count <= 64,
              user.unicodeScalars.allSatisfy(userAllowed.contains),
              !user.hasPrefix("-") else {
            throw AgentCapabilityError.invalidRemoteUser
        }
        guard (1...65_535).contains(port) else { throw AgentCapabilityError.invalidRemotePort }
        guard hostKeyFingerprint.hasPrefix("SHA256:"), hostKeyFingerprint.count > 16 else {
            throw AgentCapabilityError.missingHostFingerprint
        }
        self.host = host
        self.user = user
        self.port = port
        self.hostKeyFingerprint = hostKeyFingerprint
    }
}

/// A non-shell SSH plan. The host key remains mandatory and the caller must
/// verify it in its N1KO-owned known-hosts file before executing this plan.
public struct AgentRemoteCommandPlan: Equatable, Sendable {
    public let executableURL: URL
    public let arguments: [String]
    public let expectedHostKeyFingerprint: String

    public init(
        endpoint: AgentRemoteEndpoint,
        remoteArguments: [String],
        policy: AgentCapabilityPolicy
    ) throws {
        try policy.require(.remoteSSH)
        let remoteArgumentCharacters = CharacterSet(
            charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-./:=@"
        )
        guard !remoteArguments.isEmpty,
              remoteArguments.allSatisfy({ argument in
                  !argument.isEmpty && argument.count <= 4_096
                      && argument.unicodeScalars.allSatisfy(remoteArgumentCharacters.contains)
              }) else {
            throw AgentCapabilityError.invalidRemoteHost
        }
        executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        arguments = [
            "-o", "BatchMode=yes",
            "-o", "StrictHostKeyChecking=yes",
            "-o", "UpdateHostKeys=no",
            "-p", String(endpoint.port),
            "\(endpoint.user)@\(endpoint.host)",
            "--"
        ] + remoteArguments
        expectedHostKeyFingerprint = endpoint.hostKeyFingerprint
    }
}

public struct AgentSymbolicCompanionDescriptor: Equatable, Sendable {
    public let provider: AgentProvider
    public let systemSymbolName: String

    public init(provider: AgentProvider) {
        self.provider = provider
        switch provider {
        case .gemini: systemSymbolName = "sparkles"
        case .hermes: systemSymbolName = "paperplane.fill"
        case .openClaw: systemSymbolName = "bird.fill"
        case .qwen: systemSymbolName = "leaf.fill"
        case .kimi: systemSymbolName = "moon.stars.fill"
        case .copilot: systemSymbolName = "chevron.left.forwardslash.chevron.right"
        default: systemSymbolName = "terminal.fill"
        }
    }
}
