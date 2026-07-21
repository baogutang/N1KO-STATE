import Darwin
import Foundation
import N1KOAgentCore

private enum BridgeError: Error {
    case invalidArguments
    case payloadTooLarge
    case socketPathTooLong
    case connectFailed(Int32)
    case writeFailed(Int32)
    case readFailed(Int32)
}

private struct Options {
    let provider: AgentProvider
    let expectsResponse: Bool
    let probe: Bool
    let runtimeDirectory: URL?
    let eventName: String?

    init(arguments: [String]) throws {
        var provider: AgentProvider?
        var expectsResponse = false
        var probe = false
        var runtimeDirectory: URL?
        var eventName: String?
        var index = 1
        while index < arguments.count {
            switch arguments[index] {
            case "--provider" where index + 1 < arguments.count:
                provider = AgentProvider(rawValue: arguments[index + 1])
                index += 2
            case "--expects-response":
                expectsResponse = true
                index += 1
            case "--probe":
                probe = true
                index += 1
            case "--runtime-directory" where index + 1 < arguments.count:
                runtimeDirectory = URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
                index += 2
            case "--event" where index + 1 < arguments.count:
                eventName = arguments[index + 1]
                index += 2
            case "--profile" where index + 1 < arguments.count:
                index += 2
            case "--managed-by" where index + 1 < arguments.count:
                // Metadata is embedded in managed hook commands for takeover,
                // downgrade, and identity audits. The bridge does not trust it
                // for authentication; the per-install secret remains required.
                index += 2
            case "--schema-version" where index + 1 < arguments.count:
                // Metadata is embedded in managed hook commands for takeover,
                // downgrade, and identity audits. The bridge does not trust it
                // for authentication; the per-install secret remains required.
                index += 2
            default:
                throw BridgeError.invalidArguments
            }
        }
        guard let provider else { throw BridgeError.invalidArguments }
        self.provider = provider
        self.expectsResponse = expectsResponse
        self.probe = probe
        self.runtimeDirectory = runtimeDirectory
        self.eventName = eventName
    }
}

private func readStandardInput(maximumBytes: Int = 1_048_576) throws -> Data {
    let data = FileHandle.standardInput.readDataToEndOfFile()
    guard data.count <= maximumBytes else { throw BridgeError.payloadTooLarge }
    return data
}

private func connect(to socketURL: URL) throws -> Int32 {
    let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { throw BridgeError.connectFailed(errno) }
    var address = sockaddr_un()
    address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
    address.sun_family = sa_family_t(AF_UNIX)
    let copied = socketURL.path.withCString { source in
        withUnsafeMutablePointer(to: &address.sun_path) { destination in
            destination.withMemoryRebound(to: CChar.self, capacity: 104) {
                strlcpy($0, source, 104)
            }
        }
    }
    guard copied < 104 else {
        Darwin.close(fd)
        throw BridgeError.socketPathTooLong
    }
    let result = withUnsafePointer(to: &address) { pointer in
        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
        }
    }
    guard result == 0 else {
        let code = errno
        Darwin.close(fd)
        throw BridgeError.connectFailed(code)
    }
    return fd
}

private func exchange(_ data: Data, socketURL: URL) throws -> Data {
    let fd = try connect(to: socketURL)
    defer { Darwin.close(fd) }
    try data.withUnsafeBytes { buffer in
        guard let base = buffer.baseAddress else { return }
        var offset = 0
        while offset < data.count {
            let count = Darwin.write(fd, base.advanced(by: offset), data.count - offset)
            if count > 0 { offset += count }
            else if errno != EINTR { throw BridgeError.writeFailed(errno) }
        }
    }

    var response = Data()
    var bytes = [UInt8](repeating: 0, count: 4_096)
    while response.count <= 1_048_576 {
        let count = Darwin.read(fd, &bytes, bytes.count)
        if count > 0 {
            response.append(bytes, count: count)
            if let newline = response.firstIndex(of: 0x0a) {
                return Data(response[..<newline])
            }
        } else if count == 0 {
            return response
        } else if errno != EINTR {
            throw BridgeError.readFailed(errno)
        }
    }
    throw BridgeError.payloadTooLarge
}

do {
    let options = try Options(arguments: CommandLine.arguments)
    let defaultPaths = AgentRuntimePaths.n1koDefault()
    let paths = AgentRuntimePaths(
        runtimeDirectory: options.runtimeDirectory ?? defaultPaths.runtimeDirectory,
        applicationSupportDirectory: defaultPaths.applicationSupportDirectory
    )
    let secret = try AgentInstallSecretStore(secretURL: paths.secretURL).loadOrCreate()
    let payloadData: Data
    if options.probe {
        payloadData = try JSONSerialization.data(withJSONObject: [
            "session_id": "n1ko-probe-\(UUID().uuidString)",
            "hook_event_name": "SessionStart",
            "title": "N1KO integration probe"
        ])
    } else {
        payloadData = try readStandardInput()
    }
    var payload = try JSONDecoder().decode(AgentJSONValue.self, from: payloadData)
    if let eventName = options.eventName, case .object(var object) = payload {
        object["hook_event_name"] = .string(eventName)
        payload = .object(object)
    }
    let envelope = AgentWireEnvelope(
        authentication: secret,
        provider: options.provider,
        responseOwnerID: "n1ko-agent-bridge-\(getpid())",
        expectsResponse: options.expectsResponse,
        payload: payload
    )
    var encoded = try JSONEncoder().encode(envelope)
    encoded.append(0x0a)
    let response = try exchange(encoded, socketURL: paths.socketURL)
    FileHandle.standardOutput.write(response)
    FileHandle.standardOutput.write(Data([0x0a]))
    guard let object = try? JSONSerialization.jsonObject(with: response) as? [String: Any],
          object["ok"] as? Bool == true else {
        exit(2)
    }
} catch {
    FileHandle.standardError.write(Data("n1ko-agent-bridge: \(error)\n".utf8))
    exit(1)
}
