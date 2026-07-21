import Foundation

public protocol AgentCancellableTask: AnyObject {
    var isCancelled: Bool { get }
    func cancel()
}

public protocol AgentManagedSubprocess: AnyObject {
    var isRunning: Bool { get }
    func terminate()
}

public struct AgentShutdownReport: Equatable, Sendable {
    public let socketsClosed: Int
    public let watchersClosed: Int
    public let transportsClosed: Int
    public let tasksCancelled: Int
    public let subprocessesTerminated: Int
    public let responseChannelsClosed: Int
    public let remainingRunningResources: Int
}

/// Lightweight ownership snapshot used by release soaks and local diagnostics.
/// It contains counts only and deliberately excludes paths, payloads, response
/// capabilities, prompts, and other user content.
public struct AgentRuntimeResourceSnapshot: Codable, Equatable, Sendable {
    public let coordinatorStarted: Bool
    public let sockets: Int
    public let watchers: Int
    public let transports: Int
    public let registeredTasks: Int
    public let activeTasks: Int
    public let registeredSubprocesses: Int
    public let activeSubprocesses: Int
    public let pendingResponseRoutes: Int
    public let snapshotObservers: Int

    public init(
        coordinatorStarted: Bool,
        sockets: Int,
        watchers: Int,
        transports: Int,
        registeredTasks: Int,
        activeTasks: Int,
        registeredSubprocesses: Int,
        activeSubprocesses: Int,
        pendingResponseRoutes: Int,
        snapshotObservers: Int
    ) {
        self.coordinatorStarted = coordinatorStarted
        self.sockets = sockets
        self.watchers = watchers
        self.transports = transports
        self.registeredTasks = registeredTasks
        self.activeTasks = activeTasks
        self.registeredSubprocesses = registeredSubprocesses
        self.activeSubprocesses = activeSubprocesses
        self.pendingResponseRoutes = pendingResponseRoutes
        self.snapshotObservers = snapshotObservers
    }
}

public final class AgentIngressCoordinator {
    private let sources: [AgentIngressSource]
    private var handler: AgentIngressHandler?
    private(set) var isStarted = false

    public init(sources: [AgentIngressSource]) {
        self.sources = sources
    }

    public func start(handler: @escaping AgentIngressHandler) throws {
        guard !isStarted else { return }
        self.handler = handler
        var started: [AgentIngressSource] = []
        do {
            for source in sources {
                try source.start(handler: handler)
                started.append(source)
            }
            isStarted = true
        } catch {
            started.forEach { $0.stop() }
            self.handler = nil
            throw error
        }
    }

    public func apply(_ policy: AgentEnergyPolicy) {
        guard isStarted else { return }
        for source in sources {
            let shouldRun: Bool
            switch source.resourceKind {
            case .socket: shouldRun = policy.socketEnabled
            case .watcher: shouldRun = policy.watchersEnabled
            case .transport: shouldRun = policy.subprocessesAllowed
            }
            source.setSuspended(!shouldRun)
        }
    }

    public func resourceCounts() -> (sockets: Int, watchers: Int, transports: Int) {
        var sockets = 0
        var watchers = 0
        var transports = 0
        for source in sources {
            switch source.resourceKind {
            case .socket: sockets += source.diagnosticResourceCount
            case .watcher: watchers += source.diagnosticResourceCount
            case .transport: transports += source.diagnosticResourceCount
            }
        }
        return (sockets, watchers, transports)
    }

    public func shutdown() -> (sockets: Int, watchers: Int, transports: Int, remaining: Int) {
        let socketCount = sources.filter { $0.resourceKind == .socket && $0.isRunning }.count
        let watcherCount = sources.filter { $0.resourceKind == .watcher && $0.isRunning }.count
        let transportCount = sources.filter { $0.resourceKind == .transport && $0.isRunning }.count
        sources.forEach { $0.stop() }
        isStarted = false
        handler = nil
        let remaining = sources.filter(\.isRunning).count
        return (socketCount, watcherCount, transportCount, remaining)
    }
}

public struct AgentCoreConfiguration: Sendable {
    public let enabled: Bool
    public let runtimePaths: AgentRuntimePaths
    public let codexRolloutRoot: URL

    public init(
        enabled: Bool = true,
        runtimePaths: AgentRuntimePaths = .n1koDefault(),
        codexRolloutRoot: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/sessions", isDirectory: true)
    ) {
        self.enabled = enabled
        self.runtimePaths = runtimePaths
        self.codexRolloutRoot = codexRolloutRoot
    }
}

private struct PendingResponseRoute {
    let provider: AgentProvider
    let sessionID: String
    let requestID: String
    let ownerID: String
    let capability: String
    let channel: AgentResponseChannel
}

/// N1KO-STATE's sole Agent lifecycle owner. It has no presentation, preference,
/// updater, analytics-service, or monitor-sampling dependency.
public final class AgentSessionCoordinator: @unchecked Sendable {
    public let configuration: AgentCoreConfiguration
    public let ingressCoordinator: AgentIngressCoordinator

    private let store: AgentSessionStore
    private let queue = DispatchQueue(label: "com.n1ko.state.agent.coordinator", qos: .utility)
    private let queueKey = DispatchSpecificKey<UInt8>()
    private let publicationQueue: DispatchQueue
    private var pendingRoutes: [AgentSessionKey: PendingResponseRoute] = [:]
    private var cancellableTasks: [AgentCancellableTask] = []
    private var subprocesses: [AgentManagedSubprocess] = []
    private let nativeRuntime: (any AgentNativeRuntimeControlling)?
    private let primarySnapshotHandlerID = UUID()
    private var snapshotHandlers: [UUID: (AgentSnapshot) -> Void] = [:]
    private var _snapshot: AgentSnapshot
    private var started = false
    private var shutDown = false

    public convenience init(
        configuration: AgentCoreConfiguration = AgentCoreConfiguration(),
        extraSources: [AgentIngressSource] = [],
        nativeRuntime: (any AgentNativeRuntimeControlling)? = nil,
        publicationQueue: DispatchQueue = .main
    ) throws {
        try configuration.runtimePaths.prepare()
        let persistence = AgentJSONSessionPersistence(fileURL: configuration.runtimePaths.stateURL)
        var sources = extraSources
        if configuration.enabled {
            let secret = try AgentInstallSecretStore(
                secretURL: configuration.runtimePaths.secretURL
            ).loadOrCreate()
            sources.insert(
                AgentHookSocketServer(
                    paths: configuration.runtimePaths,
                    expectedSecret: secret
                ),
                at: 0
            )
            sources.append(CodexRolloutIngressSource(rootURL: configuration.codexRolloutRoot))
        }
        self.init(
            configuration: configuration,
            store: AgentSessionStore(persistence: persistence),
            ingressCoordinator: AgentIngressCoordinator(sources: sources),
            nativeRuntime: nativeRuntime,
            publicationQueue: publicationQueue
        )
    }

    public init(
        configuration: AgentCoreConfiguration,
        store: AgentSessionStore,
        ingressCoordinator: AgentIngressCoordinator,
        nativeRuntime: (any AgentNativeRuntimeControlling)? = nil,
        publicationQueue: DispatchQueue = .main
    ) {
        self.configuration = configuration
        self.store = store
        self.ingressCoordinator = ingressCoordinator
        self.nativeRuntime = nativeRuntime
        self.publicationQueue = publicationQueue
        _snapshot = store.snapshot()
        if let nativeRuntime {
            subprocesses.append(nativeRuntime)
        }
        queue.setSpecific(key: queueKey, value: 1)
    }

    public var snapshot: AgentSnapshot {
        syncOnQueue { _snapshot }
    }

    public var isStarted: Bool { syncOnQueue { started } }

    public var resourceSnapshot: AgentRuntimeResourceSnapshot {
        syncOnQueue {
            let ingress = ingressCoordinator.resourceCounts()
            return AgentRuntimeResourceSnapshot(
                coordinatorStarted: started,
                sockets: ingress.sockets,
                watchers: ingress.watchers,
                transports: ingress.transports,
                registeredTasks: cancellableTasks.count,
                activeTasks: cancellableTasks.filter { !$0.isCancelled }.count,
                registeredSubprocesses: subprocesses.count,
                activeSubprocesses: subprocesses.filter(\.isRunning).count,
                pendingResponseRoutes: pendingRoutes.count,
                snapshotObservers: snapshotHandlers.count
            )
        }
    }

    public func setSnapshotHandler(_ handler: ((AgentSnapshot) -> Void)?) {
        syncOnQueue { snapshotHandlers[primarySnapshotHandlerID] = handler }
        if let handler {
            let current = snapshot
            publicationQueue.async { handler(current) }
        }
    }

    @discardableResult
    public func addSnapshotObserver(_ handler: @escaping (AgentSnapshot) -> Void) -> UUID {
        let id = UUID()
        syncOnQueue { snapshotHandlers[id] = handler }
        let current = snapshot
        publicationQueue.async { handler(current) }
        return id
    }

    public func removeSnapshotObserver(_ id: UUID) {
        _ = syncOnQueue { snapshotHandlers.removeValue(forKey: id) }
    }

    public func start() throws {
        try syncOnQueue {
            guard !started else { return }
            shutDown = false
            try ingressCoordinator.start { [weak self] events, responseChannel in
                self?.queue.async {
                    _ = self?.ingestBatchOnQueue(
                        events,
                        responseChannel: responseChannel,
                        includeTranscript: true
                    )
                }
            }
            nativeRuntime?.start { [weak self] event in
                self?.queue.async {
                    _ = self?.ingestBatchOnQueue(
                        [event],
                        responseChannel: nil,
                        includeTranscript: true
                    )
                }
            }
            started = true
            publish(store.snapshot())
        }
    }

    @discardableResult
    public func ingest(
        _ event: AgentIngressEvent,
        responseChannel: AgentResponseChannel? = nil
    ) -> AgentSnapshot {
        syncOnQueue {
            ingestBatchOnQueue([event], responseChannel: responseChannel, includeTranscript: true)
        }
    }

    @discardableResult
    public func associate(
        provider: AgentProvider,
        externalID: String,
        sessionID: String
    ) -> AgentSnapshot {
        syncOnQueue {
            let value = store.associate(provider: provider, externalID: externalID, sessionID: sessionID)
            publish(value)
            return value
        }
    }

    @discardableResult
    public func archive(provider: AgentProvider, sessionID: String, at date: Date = Date()) -> AgentSnapshot {
        ingest(AgentIngressEvent(
            provider: provider,
            sessionID: sessionID,
            kind: .archived,
            timestamp: date
        ))
    }

    @discardableResult
    public func importLegacy(_ payload: AgentLegacyImportPayload) -> AgentSnapshot {
        syncOnQueue {
            let value = store.importLegacy(
                associations: payload.associations,
                usage: payload.usage
            )
            publish(value)
            return value
        }
    }

    public func respond(
        provider: AgentProvider,
        sessionID: String,
        requestID: String,
        ownerID: String,
        capability: String,
        action: AgentResponseAction
    ) throws {
        try syncOnQueue {
            let key = AgentSessionKey(provider: provider, sessionID: sessionID)
            guard let route = pendingRoutes[key] else {
                AgentCoreDiagnostics.event(.responseRejected)
                throw AgentResponseRoutingError.noPendingIntervention
            }
            guard route.provider == provider else {
                AgentCoreDiagnostics.event(.responseRejected)
                throw AgentResponseRoutingError.providerMismatch
            }
            guard route.requestID == requestID else {
                AgentCoreDiagnostics.event(.responseRejected)
                throw AgentResponseRoutingError.requestMismatch
            }
            guard route.ownerID == ownerID, route.channel.ownerID == ownerID else {
                AgentCoreDiagnostics.event(.responseRejected)
                throw AgentResponseRoutingError.ownerMismatch
            }
            guard AgentAuthentication.constantTimeEqual(route.capability, capability) else {
                AgentCoreDiagnostics.event(.responseRejected)
                throw AgentResponseRoutingError.authenticationFailed
            }
            guard route.channel.send(action) else {
                pendingRoutes.removeValue(forKey: key)
                AgentCoreDiagnostics.event(.responseRejected)
                throw AgentResponseRoutingError.channelClosed
            }

            pendingRoutes.removeValue(forKey: key)
            route.channel.close()
            AgentCoreDiagnostics.event(.responseRouted)
            let value = store.process(AgentIngressEvent(
                provider: provider,
                sessionID: sessionID,
                kind: .interventionResolved,
                requestID: requestID
            ))
            publish(value)
        }
    }

    public func applyLifecycle(_ state: AgentLifecycleState) {
        syncOnQueue {
            guard started else { return }
            ingressCoordinator.apply(.policy(for: state))
            if state != .active {
                cancellableTasks.filter { !$0.isCancelled }.forEach { $0.cancel() }
                subprocesses.filter(\.isRunning).forEach { $0.terminate() }
            }
        }
    }

    public func register(task: AgentCancellableTask) {
        syncOnQueue { cancellableTasks.append(task) }
    }

    public func register(subprocess: AgentManagedSubprocess) {
        syncOnQueue { subprocesses.append(subprocess) }
    }

    public func nativeRuntimeAvailable(provider: AgentProvider) -> Bool {
        nativeRuntime?.isAvailable(provider: provider) == true
    }

    public func managesNativeSession(provider: AgentProvider, sessionID: String) -> Bool {
        nativeRuntime?.manages(provider: provider, sessionID: sessionID) == true
    }

    public func startNativeSession(
        provider: AgentProvider,
        cwd: String,
        preferredSessionID: String? = nil
    ) async throws -> AgentNativeSessionHandle {
        guard let nativeRuntime else { throw AgentNativeRuntimeError.runtimeUnavailable }
        return try await nativeRuntime.startSession(
            provider: provider,
            cwd: cwd,
            preferredSessionID: preferredSessionID
        )
    }

    public func terminateNativeSession(provider: AgentProvider, sessionID: String) async throws {
        guard let nativeRuntime else { throw AgentNativeRuntimeError.runtimeUnavailable }
        try await nativeRuntime.terminateSession(provider: provider, sessionID: sessionID)
    }

    public func sendNativeMessage(
        provider: AgentProvider,
        sessionID: String,
        expectedTurnID: String? = nil,
        text: String
    ) async throws {
        guard let nativeRuntime else { throw AgentNativeRuntimeError.runtimeUnavailable }
        try await nativeRuntime.sendMessage(
            provider: provider,
            sessionID: sessionID,
            expectedTurnID: expectedTurnID,
            text: text
        )
    }

    @discardableResult
    public func shutdown() -> AgentShutdownReport {
        syncOnQueue {
            guard !shutDown else {
                return AgentShutdownReport(
                    socketsClosed: 0, watchersClosed: 0, transportsClosed: 0,
                    tasksCancelled: 0, subprocessesTerminated: 0,
                    responseChannelsClosed: 0, remainingRunningResources: 0
                )
            }
            shutDown = true
            started = false
            let stopped = ingressCoordinator.shutdown()

            let tasksToCancel = cancellableTasks.filter { !$0.isCancelled }
            tasksToCancel.forEach { $0.cancel() }
            let processesToTerminate = subprocesses.filter(\.isRunning)
            processesToTerminate.forEach { $0.terminate() }
            let routes = Array(pendingRoutes.values)
            routes.forEach { $0.channel.close() }
            pendingRoutes.removeAll()
            cancellableTasks.removeAll()
            subprocesses.removeAll()
            snapshotHandlers.removeAll()
            store.flush()

            return AgentShutdownReport(
                socketsClosed: stopped.sockets,
                watchersClosed: stopped.watchers,
                transportsClosed: stopped.transports,
                tasksCancelled: tasksToCancel.count,
                subprocessesTerminated: processesToTerminate.count,
                responseChannelsClosed: routes.count,
                remainingRunningResources: stopped.remaining
            )
        }
    }

    private func ingestBatchOnQueue(
        _ events: [AgentIngressEvent],
        responseChannel: AgentResponseChannel?,
        includeTranscript: Bool
    ) -> AgentSnapshot {
        var batch: [(event: AgentIngressEvent, responseCapability: String?)] = []
        batch.reserveCapacity(events.count)

        for event in events {
            AgentCoreDiagnostics.event(.ingress)

            if includeTranscript,
               event.provider.usesClaudeCompatibleHooks,
               let path = event.transcriptPath,
               let data = boundedTranscriptData(path: path),
               let transcriptEvents = try? ClaudeTranscriptParser.parse(
                   data,
                   fallbackSessionID: event.sessionID,
                   provider: event.provider
               ) {
                for transcriptEvent in transcriptEvents {
                    AgentCoreDiagnostics.event(.ingress)
                    batch.append((transcriptEvent, nil))
                }
            }

            var capability: String?
            if event.kind == .approvalRequested || event.kind == .answerRequested,
               let channel = responseChannel,
               channel.provider == event.provider,
               channel.ownerID == event.responseOwnerID {
                capability = try? AgentAuthentication.randomCapability()
                if let capability, let requestID = event.requestID {
                    let resolvedID = store.resolvedSessionID(
                        provider: event.provider,
                        externalID: event.sessionID
                    )
                    let key = AgentSessionKey(provider: event.provider, sessionID: resolvedID)
                    pendingRoutes[key]?.channel.close()
                    pendingRoutes[key] = PendingResponseRoute(
                        provider: event.provider,
                        sessionID: resolvedID,
                        requestID: requestID,
                        ownerID: channel.ownerID,
                        capability: capability,
                        channel: channel
                    )
                }
            }

            batch.append((event, capability))
        }

        let value = store.process(batch)
        if value.generation != _snapshot.generation {
            publish(value)
        }
        return value
    }

    private func boundedTranscriptData(path: String) -> Data? {
        let url = URL(fileURLWithPath: path)
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
              let size = values.fileSize,
              size >= 0 else { return nil }
        let tailLimit = 4 * 1_024 * 1_024
        if size <= tailLimit {
            return try? Data(contentsOf: url, options: [.mappedIfSafe])
        }

        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        handle.seek(toFileOffset: UInt64(size - tailLimit))
        let rawTail = handle.readData(ofLength: tailLimit)
        guard let firstNewline = rawTail.firstIndex(of: 0x0a),
              firstNewline < rawTail.endIndex else { return nil }
        return Data(rawTail[rawTail.index(after: firstNewline)...])
    }

    private func publish(_ value: AgentSnapshot) {
        _snapshot = value
        AgentCoreDiagnostics.event(.snapshotPublication)
        let handlers = Array(snapshotHandlers.values)
        guard !handlers.isEmpty else { return }
        publicationQueue.async {
            for handler in handlers { handler(value) }
        }
    }

    private func syncOnQueue<T>(_ body: () throws -> T) rethrows -> T {
        if DispatchQueue.getSpecific(key: queueKey) != nil { return try body() }
        return try queue.sync(execute: body)
    }
}
