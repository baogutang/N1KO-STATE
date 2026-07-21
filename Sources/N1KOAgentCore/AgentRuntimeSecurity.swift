import Foundation
import Security

public struct AgentRuntimePaths: Equatable, Sendable {
    public let runtimeDirectory: URL
    public let socketURL: URL
    public let secretURL: URL
    public let applicationSupportDirectory: URL
    public let stateURL: URL

    public init(
        runtimeDirectory: URL,
        applicationSupportDirectory: URL
    ) {
        self.runtimeDirectory = runtimeDirectory
        socketURL = runtimeDirectory.appendingPathComponent("agent.sock")
        secretURL = runtimeDirectory.appendingPathComponent("auth.secret")
        self.applicationSupportDirectory = applicationSupportDirectory
        stateURL = applicationSupportDirectory.appendingPathComponent("sessions.json")
    }

    public static func n1koDefault(
        temporaryDirectory: URL = FileManager.default.temporaryDirectory,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        uid: uid_t = getuid()
    ) -> AgentRuntimePaths {
        let runtime = temporaryDirectory.appendingPathComponent(
            "com.n1ko.state.agent.\(uid)",
            isDirectory: true
        )
        let support = homeDirectory
            .appendingPathComponent("Library/Application Support/N1KO-STATE/AgentCore", isDirectory: true)
        return AgentRuntimePaths(runtimeDirectory: runtime, applicationSupportDirectory: support)
    }

    public func prepare() throws {
        try createPrivateDirectory(runtimeDirectory)
        try createPrivateDirectory(applicationSupportDirectory)
        let maximumUnixPathBytes = 103
        guard socketURL.path.utf8.count <= maximumUnixPathBytes else {
            throw AgentRuntimeSecurityError.socketPathTooLong
        }
    }

    private func createPrivateDirectory(_ url: URL) throws {
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
    }
}

public enum AgentRuntimeSecurityError: Error, Equatable {
    case socketPathTooLong
    case randomGenerationFailed
    case invalidSecret
    case invalidRuntimePermissions
}

public final class AgentInstallSecretStore {
    public let secretURL: URL

    public init(secretURL: URL) {
        self.secretURL = secretURL
    }

    public func loadOrCreate() throws -> String {
        if let data = try? Data(contentsOf: secretURL),
           let secret = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           secret.utf8.count >= 64 {
            try enforcePermissions()
            return secret
        }

        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw AgentRuntimeSecurityError.randomGenerationFailed
        }
        let secret = bytes.map { String(format: "%02x", $0) }.joined()
        try Data(secret.utf8).write(to: secretURL, options: [.atomic])
        try enforcePermissions()
        return secret
    }

    private func enforcePermissions() throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: secretURL.path)
        let attributes = try FileManager.default.attributesOfItem(atPath: secretURL.path)
        let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue ?? -1
        guard permissions & 0o077 == 0 else { throw AgentRuntimeSecurityError.invalidRuntimePermissions }
    }
}

public enum AgentAuthentication {
    public static func constantTimeEqual(_ lhs: String, _ rhs: String) -> Bool {
        let left = Array(lhs.utf8)
        let right = Array(rhs.utf8)
        var difference = UInt8(truncatingIfNeeded: left.count ^ right.count)
        let count = max(left.count, right.count)
        for index in 0..<count {
            let l = index < left.count ? left[index] : 0
            let r = index < right.count ? right[index] : 0
            difference |= l ^ r
        }
        return difference == 0
    }

    public static func randomCapability() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 24)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw AgentRuntimeSecurityError.randomGenerationFailed
        }
        return Data(bytes).base64EncodedString()
    }
}

public enum AgentDiagnosticRedactor {
    private static let sensitiveKeys: Set<String> = [
        "authentication", "authorization", "token", "secret", "api_key", "apikey",
        "prompt", "message", "question", "questions", "answers", "tool_input", "toolinput",
        "arguments", "password", "passphrase", "credential", "credentials", "cookie",
        "set-cookie", "session", "session_id", "sessionid", "response_owner_id",
        "responseownerid", "response_capability", "responsecapability", "capability"
    ]

    public static func redact(json data: Data, homeDirectory: String = NSHomeDirectory()) -> Data {
        guard let object = try? JSONSerialization.jsonObject(with: data) else { return Data("<redacted>".utf8) }
        let redacted = redactValue(object, homeDirectory: homeDirectory)
        return (try? JSONSerialization.data(withJSONObject: redacted, options: [.sortedKeys])) ?? Data("<redacted>".utf8)
    }

    public static func redact(text: String, homeDirectory: String = NSHomeDirectory()) -> String {
        var value = text
        if !homeDirectory.isEmpty {
            value = value.replacingOccurrences(of: homeDirectory, with: "~")
        }
        let patterns = [
            (#"(?i)((?:bearer|basic)\s+)[A-Za-z0-9._~+\-/=]+"#, "$1<redacted>"),
            (#"(?i)((?:authorization|token|secret|api[_-]?key|password|passphrase|credential|cookie|set-cookie|capability|response[_-]?owner[_-]?id|session[_-]?id)\s*[=:]\s*)[^\s,;]+"#, "$1<redacted>"),
            (#"(?i)([a-z][a-z0-9+.-]*://)[^\s/@:]+:[^\s/@]+@"#, "$1<redacted>@"),
            (#"/Users/[^/\s]+"#, "~")
        ]
        for (pattern, replacement) in patterns {
            value = value.replacingOccurrences(
                of: pattern,
                with: replacement,
                options: .regularExpression
            )
        }
        return value
    }

    private static func redactValue(_ value: Any, homeDirectory: String) -> Any {
        if let dictionary = value as? [String: Any] {
            var result: [String: Any] = [:]
            for (key, nested) in dictionary {
                if sensitiveKeys.contains(key.lowercased()) {
                    result[key] = "<redacted>"
                } else {
                    result[key] = redactValue(nested, homeDirectory: homeDirectory)
                }
            }
            return result
        }
        if let array = value as? [Any] {
            return array.map { redactValue($0, homeDirectory: homeDirectory) }
        }
        if let string = value as? String {
            return redact(text: string, homeDirectory: homeDirectory)
        }
        return value
    }
}

public enum AgentJSONValue: Codable, Equatable, Sendable {
    case object([String: AgentJSONValue])
    case array([AgentJSONValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([String: AgentJSONValue].self) { self = .object(value) }
        else if let value = try? container.decode([AgentJSONValue].self) { self = .array(value) }
        else { throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value") }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}

public struct AgentWireEnvelope: Codable, Equatable, Sendable {
    public let version: Int
    public let authentication: String
    public let provider: AgentProvider
    public let responseOwnerID: String
    public let expectsResponse: Bool
    public let payload: AgentJSONValue

    public init(
        version: Int = 1,
        authentication: String,
        provider: AgentProvider,
        responseOwnerID: String,
        expectsResponse: Bool,
        payload: AgentJSONValue
    ) {
        self.version = version
        self.authentication = authentication
        self.provider = provider
        self.responseOwnerID = responseOwnerID
        self.expectsResponse = expectsResponse
        self.payload = payload
    }

    public func payloadData() throws -> Data { try JSONEncoder().encode(payload) }
}
