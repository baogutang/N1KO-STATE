import Darwin
import Foundation

/// Event-driven Codex rollout ingress. It watches existing session directories
/// with vnode sources and rescans only after filesystem events; there is no
/// polling timer or display link.
public final class CodexRolloutIngressSource: AgentIngressSource {
    public let resourceKind: AgentIngressResourceKind = .watcher
    public var isRunning: Bool { lock.withCriticalSection { !directorySources.isEmpty } }
    public var diagnosticResourceCount: Int { lock.withCriticalSection { directorySources.count } }

    private struct FileStamp: Equatable {
        let size: UInt64
        let modificationDate: Date
    }

    private let rootURL: URL
    private let queue: DispatchQueue
    private let maximumInitialFiles: Int
    private let lock = NSLock()
    private var handler: AgentIngressHandler?
    private var directorySources: [String: DispatchSourceFileSystemObject] = [:]
    private var directoryFDs: [String: Int32] = [:]
    private var fileStamps: [String: FileStamp] = [:]
    private var suspended = false
    private var scanScheduled = false

    public init(
        rootURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/sessions", isDirectory: true),
        maximumInitialFiles: Int = 200,
        queue: DispatchQueue = DispatchQueue(label: "com.n1ko.state.agent.codex-rollouts", qos: .utility)
    ) {
        self.rootURL = rootURL
        self.maximumInitialFiles = max(maximumInitialFiles, 1)
        self.queue = queue
    }

    public func start(handler: @escaping AgentIngressHandler) throws {
        lock.withCriticalSection {
            self.handler = handler
            suspended = false
        }
        try FileManager.default.createDirectory(
            at: rootURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        queue.async { [weak self] in self?.scanAndRebuildWatches(initial: true) }
    }

    public func setSuspended(_ suspended: Bool) {
        lock.withCriticalSection { self.suspended = suspended }
        if suspended {
            cancelWatches(clearHandler: false)
        } else if let handler = lock.withCriticalSection({ self.handler }) {
            try? start(handler: handler)
        }
    }

    public func stop() {
        lock.withCriticalSection { suspended = true }
        cancelWatches(clearHandler: true)
    }

    private func scheduleScan() {
        let shouldSchedule = lock.withCriticalSection { () -> Bool in
            guard !suspended, !scanScheduled else { return false }
            scanScheduled = true
            return true
        }
        guard shouldSchedule else { return }
        queue.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self else { return }
            self.lock.withCriticalSection { self.scanScheduled = false }
            self.scanAndRebuildWatches(initial: false)
        }
    }

    private func scanAndRebuildWatches(initial: Bool) {
        guard !lock.withCriticalSection({ suspended }) else { return }
        let scan = discoverDirectoriesAndFiles()
        rebuildWatches(for: scan.directories)

        var files = scan.files
        var scanEvents: [AgentIngressEvent] = []
        if initial && files.count > maximumInitialFiles {
            files = Array(files.sorted { $0.stamp.modificationDate > $1.stamp.modificationDate }
                .prefix(maximumInitialFiles))
        }
        for file in files {
            let previous = lock.withCriticalSection { fileStamps[file.url.path] }
            guard previous != file.stamp else { continue }
            lock.withCriticalSection { fileStamps[file.url.path] = file.stamp }
            let projectedEvents: [AgentIngressEvent]? = autoreleasepool {
                guard let data = Self.boundedRolloutData(from: file.url, size: file.stamp.size),
                      let parsedEvents = try? CodexRolloutParser.parse(
                        data,
                        fallbackSessionID: Self.sessionID(from: file.url)
                      ) else { return nil }
                return Self.restorationProjection(parsedEvents)
            }
            guard let projectedEvents else {
                AgentCoreDiagnostics.event(.parseFailure)
                continue
            }
            scanEvents.append(contentsOf: projectedEvents)
        }
        if !scanEvents.isEmpty {
            let currentHandler = lock.withCriticalSection { handler }
            currentHandler?(scanEvents, nil)
        }
    }

    private func discoverDirectoriesAndFiles() -> (
        directories: [URL],
        files: [(url: URL, stamp: FileStamp)]
    ) {
        var directories = [rootURL]
        var files: [(URL, FileStamp)] = []
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey]
        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return (directories, files) }

        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: keys) else { continue }
            if values.isDirectory == true {
                directories.append(url)
            } else if url.pathExtension == "jsonl" {
                files.append((url, FileStamp(
                    size: UInt64(values.fileSize ?? 0),
                    modificationDate: values.contentModificationDate ?? .distantPast
                )))
            }
        }
        return (directories, files)
    }

    private func rebuildWatches(for directories: [URL]) {
        let desired = Set(directories.map(\.path))
        let stale = lock.withCriticalSection { Set(directorySources.keys).subtracting(desired) }
        for path in stale { removeWatch(path: path) }

        for directory in directories {
            let exists = lock.withCriticalSection { directorySources[directory.path] != nil }
            guard !exists else { continue }
            let fd = Darwin.open(directory.path, O_EVTONLY)
            guard fd >= 0 else { continue }
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd,
                eventMask: [.write, .delete, .rename, .extend, .attrib],
                queue: queue
            )
            source.setEventHandler { [weak self] in self?.scheduleScan() }
            source.setCancelHandler { Darwin.close(fd) }
            lock.withCriticalSection {
                directoryFDs[directory.path] = fd
                directorySources[directory.path] = source
            }
            source.resume()
        }
    }

    private func removeWatch(path: String) {
        let source = lock.withCriticalSection { () -> DispatchSourceFileSystemObject? in
            directoryFDs.removeValue(forKey: path)
            return directorySources.removeValue(forKey: path)
        }
        source?.cancel()
    }

    private func cancelWatches(clearHandler: Bool) {
        let sources = lock.withCriticalSection { () -> [DispatchSourceFileSystemObject] in
            let values = Array(directorySources.values)
            directorySources.removeAll()
            directoryFDs.removeAll()
            scanScheduled = false
            if clearHandler { handler = nil }
            return values
        }
        sources.forEach { $0.cancel() }
    }

    private static func sessionID(from url: URL) -> String? {
        let name = url.deletingPathExtension().lastPathComponent
        guard let range = name.range(of: "rollout-", options: .backwards) else { return nil }
        let suffix = String(name[range.upperBound...])
        return suffix.isEmpty ? nil : suffix
    }

    /// Historical JSONL can contain tens of thousands of commentary/tool
    /// updates. Keep identity, latest cumulative usage, and the bounded recent
    /// semantic history needed by the Ping-style detail view.
    static func restorationProjection(_ events: [AgentIngressEvent]) -> [AgentIngressEvent] {
        guard !events.isEmpty else { return [] }
        let started = events.first { $0.kind == .started }
        let usage = events.last { $0.usage != nil || $0.kind == .usage }
        let recentHistory = events.filter {
            $0.kind != .started && $0.kind != .usage
        }.suffix(80)
        var result: [AgentIngressEvent] = []
        if let started { result.append(started) }
        for event in recentHistory where !result.contains(event) {
            result.append(event)
        }
        if let usage, !result.contains(usage) {
            result.append(usage)
        }
        return result.sorted { $0.timestamp < $1.timestamp }
    }

    /// Rollouts can grow to many megabytes. Session identity lives in the first
    /// JSONL record while the latest lifecycle/usage lives near the tail, so a
    /// full historical read would allocate conversation content that WP3 never
    /// stores. Keep one complete first line and at most the last MiB.
    static func boundedRolloutData(from url: URL, size: UInt64) -> Data? {
        let tailLimit = 1_048_576
        let firstLineLimit = 65_536
        if size <= UInt64(tailLimit + firstLineLimit) {
            return try? Data(contentsOf: url, options: [.mappedIfSafe])
        }

        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let prefix = handle.readData(ofLength: firstLineLimit)
        guard let newline = prefix.firstIndex(of: 0x0a) else { return nil }
        let firstLine = Data(prefix[...newline])

        let tailOffset = size - UInt64(tailLimit)
        handle.seek(toFileOffset: tailOffset)
        let rawTail = handle.readData(ofLength: tailLimit)
        let tail: Data
        if let firstTailNewline = rawTail.firstIndex(of: 0x0a), firstTailNewline < rawTail.endIndex {
            tail = Data(rawTail[rawTail.index(after: firstTailNewline)...])
        } else {
            tail = Data()
        }

        var result = firstLine
        result.append(tail)
        return result
    }
}

public struct CodexAppServerMessage: @unchecked Sendable {
    public let data: Data
    public let responseChannel: AgentResponseChannel?

    public init(data: Data, responseChannel: AgentResponseChannel?) {
        self.data = data
        self.responseChannel = responseChannel
    }
}

public protocol CodexAppServerTransport: AnyObject {
    var isRunning: Bool { get }
    func start(receive: @escaping (CodexAppServerMessage) -> Void) throws
    func stop()
}

/// Command half of the Codex app-server transport. The same authenticated,
/// coordinator-owned connection carries inbound notifications, approval
/// responses, native thread creation, and non-tmux follow-up messages.
public protocol CodexAppServerCommandTransport: CodexAppServerTransport, Sendable {
    func startThread(cwd: String) async throws -> String
    func archiveThread(threadID: String) async throws
    func sendMessage(threadID: String, expectedTurnID: String?, text: String) async throws
}

/// Protocol adapter only. A concrete Codex connection can be supplied without
/// coupling the domain to URLSession, a subprocess, or an upstream singleton.
public final class CodexAppServerIngressSource: AgentIngressSource {
    public let resourceKind: AgentIngressResourceKind = .transport
    public var isRunning: Bool { transport.isRunning }

    private let transport: CodexAppServerTransport
    private let ownerID: String
    private var handler: AgentIngressHandler?
    private var suspended = false

    public init(transport: CodexAppServerTransport, ownerID: String = "codex-app-server") {
        self.transport = transport
        self.ownerID = ownerID
    }

    public func start(handler: @escaping AgentIngressHandler) throws {
        self.handler = handler
        suspended = false
        try transport.start { [weak self] message in
            guard let self, !self.suspended else { return }
            do {
                let events = try CodexAppServerParser.parse(message.data, responseOwnerID: self.ownerID)
                self.handler?(events, message.responseChannel)
            } catch {
                AgentCoreDiagnostics.event(.parseFailure)
            }
        }
    }

    public func setSuspended(_ suspended: Bool) {
        self.suspended = suspended
        if suspended {
            transport.stop()
        } else if let handler {
            try? start(handler: handler)
        }
    }

    public func stop() {
        suspended = true
        transport.stop()
        handler = nil
    }
}

private extension NSLock {
    @discardableResult
    func withCriticalSection<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
