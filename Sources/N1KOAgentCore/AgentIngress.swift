import Darwin
import Foundation

public enum AgentIngressResourceKind: String, Codable, Sendable {
    case socket
    case watcher
    case transport
}

/// Sources deliver one atomic parser/file batch at a time. Batching prevents a
/// historical rollout scan from encoding and publishing the entire session
/// store once per projected conversation event.
public typealias AgentIngressHandler = ([AgentIngressEvent], AgentResponseChannel?) -> Void

public protocol AgentIngressSource: AnyObject {
    var resourceKind: AgentIngressResourceKind { get }
    var isRunning: Bool { get }
    /// Number of live resources represented by this source. Most sources own
    /// one socket/watcher/transport; multi-watch sources override this with
    /// their actual live resource count for release-soak diagnostics.
    var diagnosticResourceCount: Int { get }
    func start(handler: @escaping AgentIngressHandler) throws
    func setSuspended(_ suspended: Bool)
    func stop()
}

public extension AgentIngressSource {
    var diagnosticResourceCount: Int { isRunning ? 1 : 0 }
}

public final class AgentResponseChannel: @unchecked Sendable {
    public let provider: AgentProvider
    public let ownerID: String

    private let lock = NSLock()
    private var sender: ((AgentResponseAction) -> Bool)?

    public init(provider: AgentProvider, ownerID: String, sender: @escaping (AgentResponseAction) -> Bool) {
        self.provider = provider
        self.ownerID = ownerID
        self.sender = sender
    }

    @discardableResult
    public func send(_ action: AgentResponseAction) -> Bool {
        lock.lock()
        let current = sender
        lock.unlock()
        return current?(action) ?? false
    }

    public func close() {
        lock.lock()
        sender = nil
        lock.unlock()
    }
}

public enum AgentSocketServerError: Error, Equatable {
    case alreadyRunning
    case createFailed(Int32)
    case bindFailed(Int32)
    case listenFailed(Int32)
    case permissionsFailed
}

/// Authenticated, per-user Unix socket ingress. The parent directory is 0700,
/// the socket is 0600, and every accepted peer must match the current UID.
public final class AgentHookSocketServer: AgentIngressSource {
    public let resourceKind: AgentIngressResourceKind = .socket
    public var isRunning: Bool { stateLock.withLock { serverFD >= 0 } }
    public var activeConnectionCount: Int { stateLock.withLock { clients.count } }
    public var diagnosticResourceCount: Int {
        stateLock.withLock { (serverFD >= 0 ? 1 : 0) + clients.count }
    }

    private let paths: AgentRuntimePaths
    private let expectedSecret: String
    private let expectedUID: uid_t
    private let queue: DispatchQueue
    private let stateLock = NSLock()
    private var serverFD: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    private var clients: [Int32: SocketClient] = [:]
    private var handler: AgentIngressHandler?
    private var suspended = false

    public init(
        paths: AgentRuntimePaths,
        expectedSecret: String,
        expectedUID: uid_t = getuid(),
        queue: DispatchQueue = DispatchQueue(label: "com.n1ko.state.agent.socket", qos: .utility)
    ) {
        self.paths = paths
        self.expectedSecret = expectedSecret
        self.expectedUID = expectedUID
        self.queue = queue
    }

    public func start(handler: @escaping AgentIngressHandler) throws {
        self.handler = handler
        suspended = false
        try openSocketIfNeeded()
    }

    public func setSuspended(_ suspended: Bool) {
        self.suspended = suspended
        if suspended {
            closeSocket(clearHandler: false)
        } else if let handler {
            try? start(handler: handler)
        }
    }

    public func stop() {
        suspended = true
        closeSocket(clearHandler: true)
    }

    public static func peerUIDAccepted(actual: uid_t, expected: uid_t) -> Bool {
        actual == expected
    }

    private func openSocketIfNeeded() throws {
        guard !suspended else { return }
        try paths.prepare()
        if isRunning { throw AgentSocketServerError.alreadyRunning }
        unlink(paths.socketURL.path)

        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw AgentSocketServerError.createFailed(errno) }
        _ = fcntl(fd, F_SETFL, O_NONBLOCK)

        var address = sockaddr_un()
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        address.sun_family = sa_family_t(AF_UNIX)
        let copied = paths.socketURL.path.withCString { source in
            withUnsafeMutablePointer(to: &address.sun_path) { destination in
                destination.withMemoryRebound(to: CChar.self, capacity: 104) {
                    strlcpy($0, source, 104)
                }
            }
        }
        guard copied < 104 else {
            Darwin.close(fd)
            throw AgentRuntimeSecurityError.socketPathTooLong
        }

        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult == 0 else {
            let code = errno
            Darwin.close(fd)
            throw AgentSocketServerError.bindFailed(code)
        }
        guard chmod(paths.socketURL.path, 0o600) == 0 else {
            Darwin.close(fd)
            unlink(paths.socketURL.path)
            throw AgentSocketServerError.permissionsFailed
        }
        guard Darwin.listen(fd, 16) == 0 else {
            let code = errno
            Darwin.close(fd)
            unlink(paths.socketURL.path)
            throw AgentSocketServerError.listenFailed(code)
        }

        stateLock.withLock { serverFD = fd }
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in self?.acceptPendingConnections() }
        source.setCancelHandler { Darwin.close(fd) }
        stateLock.withLock { acceptSource = source }
        source.resume()
    }

    private func acceptPendingConnections() {
        while true {
            let listeningFD = stateLock.withLock { serverFD }
            guard listeningFD >= 0 else { return }
            let clientFD = Darwin.accept(listeningFD, nil, nil)
            if clientFD < 0 {
                if errno == EAGAIN || errno == EWOULDBLOCK { return }
                return
            }
            _ = fcntl(clientFD, F_SETFL, O_NONBLOCK)

            var peerUID: uid_t = 0
            var peerGID: gid_t = 0
            guard getpeereid(clientFD, &peerUID, &peerGID) == 0,
                  Self.peerUIDAccepted(actual: peerUID, expected: expectedUID) else {
                AgentCoreDiagnostics.event(.authenticationFailure)
                Darwin.close(clientFD)
                continue
            }

            let client = SocketClient(fd: clientFD, queue: queue) { [weak self] fd, data in
                self?.receive(data: data, from: fd)
            } onClose: { [weak self] fd in
                self?.stateLock.withLock { self?.clients.removeValue(forKey: fd) }
            }
            stateLock.withLock { clients[clientFD] = client }
            client.start()
        }
    }

    private func receive(data: Data, from fd: Int32) {
        guard let envelope = try? JSONDecoder().decode(AgentWireEnvelope.self, from: data),
              envelope.version == 1,
              AgentAuthentication.constantTimeEqual(envelope.authentication, expectedSecret) else {
            AgentCoreDiagnostics.event(.authenticationFailure)
            stateLock.withLock { clients[fd] }?.sendErrorAndClose("authentication_failed")
            return
        }
        guard let payload = try? envelope.payloadData() else {
            AgentCoreDiagnostics.event(.parseFailure)
            stateLock.withLock { clients[fd] }?.sendErrorAndClose("invalid_payload")
            return
        }

        let events: [AgentIngressEvent]
        do {
            events = try AgentManagedHookParser.parse(
                payload,
                provider: envelope.provider,
                responseOwnerID: envelope.responseOwnerID
            )
        } catch {
            AgentCoreDiagnostics.event(.parseFailure)
            stateLock.withLock { clients[fd] }?.sendErrorAndClose("parse_failed")
            return
        }

        let responseChannel: AgentResponseChannel?
        if envelope.expectsResponse,
           events.contains(where: { $0.kind == .approvalRequested || $0.kind == .answerRequested }),
           let client = stateLock.withLock({ clients[fd] }) {
            responseChannel = AgentResponseChannel(
                provider: envelope.provider,
                ownerID: envelope.responseOwnerID
            ) { action in
                client.send(action: action)
            }
        } else {
            responseChannel = nil
        }

        handler?(events, responseChannel)
        if responseChannel == nil {
            stateLock.withLock { clients[fd] }?.sendAcknowledgementAndClose()
        }
    }

    private func closeSocket(clearHandler: Bool) {
        let resources: (DispatchSourceRead?, [SocketClient]) = stateLock.withLock {
            let source = acceptSource
            let currentClients = Array(clients.values)
            acceptSource = nil
            serverFD = -1
            clients.removeAll()
            if clearHandler { handler = nil }
            return (source, currentClients)
        }
        resources.0?.cancel()
        resources.1.forEach { $0.close() }
        unlink(paths.socketURL.path)
    }
}

private final class SocketClient {
    let fd: Int32
    private let queue: DispatchQueue
    private let onData: (Int32, Data) -> Void
    private let onClose: (Int32) -> Void
    private let lock = NSLock()
    private var source: DispatchSourceRead?
    private var buffer = Data()
    private var closed = false
    private let maximumBytes = 1_048_576

    init(
        fd: Int32,
        queue: DispatchQueue,
        onData: @escaping (Int32, Data) -> Void,
        onClose: @escaping (Int32) -> Void
    ) {
        self.fd = fd
        self.queue = queue
        self.onData = onData
        self.onClose = onClose
    }

    func start() {
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in self?.readAvailable() }
        source.setCancelHandler { [weak self] in
            guard let self else { return }
            Darwin.close(self.fd)
            self.onClose(self.fd)
        }
        lock.withLock { self.source = source }
        source.resume()
    }

    func send(action: AgentResponseAction) -> Bool {
        let payload: [String: Any]
        switch action {
        case .approve(let scope):
            payload = ["ok": true, "decision": "approve", "scope": scope ?? "once"]
        case .deny(let reason):
            payload = ["ok": true, "decision": "deny", "reason": reason ?? ""]
        case .answer(let answers):
            payload = ["ok": true, "decision": "answer", "answers": answers]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return false }
        return sendAndClose(data + Data([0x0a]))
    }

    func sendAcknowledgementAndClose() {
        _ = sendAndClose(Data("{\"ok\":true}\n".utf8))
    }

    func sendErrorAndClose(_ code: String) {
        let safeCode = code.replacingOccurrences(of: "\"", with: "")
        _ = sendAndClose(Data("{\"ok\":false,\"error\":\"\(safeCode)\"}\n".utf8))
    }

    func close() {
        let current = lock.withLock { () -> DispatchSourceRead? in
            guard !closed else { return nil }
            closed = true
            let value = source
            source = nil
            return value
        }
        current?.cancel()
    }

    private func readAvailable() {
        var bytes = [UInt8](repeating: 0, count: 16_384)
        while true {
            let count = Darwin.read(fd, &bytes, bytes.count)
            if count > 0 {
                buffer.append(bytes, count: count)
                if buffer.count > maximumBytes {
                    sendErrorAndClose("payload_too_large")
                    return
                }
                if let newline = buffer.firstIndex(of: 0x0a) {
                    let message = Data(buffer[..<newline])
                    buffer.removeAll(keepingCapacity: false)
                    onData(fd, message)
                    return
                }
            } else if count == 0 {
                close()
                return
            } else if errno == EAGAIN || errno == EWOULDBLOCK {
                return
            } else {
                close()
                return
            }
        }
    }

    private func sendAndClose(_ data: Data) -> Bool {
        let didSend = data.withUnsafeBytes { rawBuffer -> Bool in
            guard let base = rawBuffer.baseAddress else { return false }
            var offset = 0
            while offset < data.count {
                let count = Darwin.write(fd, base.advanced(by: offset), data.count - offset)
                if count > 0 { offset += count; continue }
                if errno == EINTR { continue }
                return false
            }
            return true
        }
        close()
        return didSend
    }
}

extension NSLock {
    @discardableResult
    fileprivate func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
