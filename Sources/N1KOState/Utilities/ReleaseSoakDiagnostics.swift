import Foundation

/// Content-free, count-only samples for WP6 release soaks. This recorder is
/// dormant unless the benchmark driver receives `N1KO_SOAK_SAMPLES_PATH`.
struct ReleaseSoakSample: Equatable {
    let wallTimeSeconds: Double
    let uptimeNanoseconds: UInt64
    let historyCPUCount: Int
    let historyMemoryCount: Int
    let historyNetDownCount: Int
    let historyNetUpCount: Int
    let agentSessionCount: Int
    let agentSockets: Int
    let agentWatchers: Int
    let agentTransports: Int
    let agentRegisteredTasks: Int
    let agentActiveTasks: Int
    let agentRegisteredSubprocesses: Int
    let agentActiveSubprocesses: Int
    let agentPendingResponseRoutes: Int
    let agentSnapshotObservers: Int
    let surfaceGlobalMonitors: Int
    let surfaceRetryTasks: Int
    let systemSleepEvents: Int
    let systemWakeEvents: Int
    let sessionInactiveEvents: Int
    let sessionActiveEvents: Int
    let screenSleepEvents: Int
    let screenWakeEvents: Int

    static let tsvHeader = [
        "wall_epoch_seconds", "uptime_nanoseconds", "history_cpu_count",
        "history_memory_count", "history_net_down_count", "history_net_up_count",
        "agent_session_count", "agent_sockets", "agent_watchers", "agent_transports",
        "agent_registered_tasks", "agent_active_tasks", "agent_registered_subprocesses",
        "agent_active_subprocesses", "agent_pending_response_routes",
        "agent_snapshot_observers", "surface_global_monitors", "surface_retry_tasks",
        "system_sleep_events", "system_wake_events", "session_inactive_events",
        "session_active_events", "screen_sleep_events", "screen_wake_events"
    ].joined(separator: "\t")

    var tsvRow: String {
        var values = [String]()
        values.reserveCapacity(24)
        values.append(String(format: "%.3f", wallTimeSeconds))
        values.append(String(uptimeNanoseconds))
        values.append(contentsOf: [
            historyCPUCount, historyMemoryCount, historyNetDownCount, historyNetUpCount,
            agentSessionCount, agentSockets, agentWatchers, agentTransports,
            agentRegisteredTasks, agentActiveTasks, agentRegisteredSubprocesses,
            agentActiveSubprocesses, agentPendingResponseRoutes, agentSnapshotObservers,
            surfaceGlobalMonitors, surfaceRetryTasks, systemSleepEvents, systemWakeEvents,
            sessionInactiveEvents, sessionActiveEvents, screenSleepEvents, screenWakeEvents
        ].map(String.init))
        return values.joined(separator: "\t")
    }
}

enum ReleaseSoakDiagnostics {
    private static let lock = NSLock()

    static func append(_ sample: ReleaseSoakSample, to url: URL) throws {
        lock.lock()
        defer { lock.unlock() }

        let parent = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: parent,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: parent.path)

        let row = sample.tsvRow + "\n"
        if !FileManager.default.fileExists(atPath: url.path) {
            try Data((ReleaseSoakSample.tsvHeader + "\n" + row).utf8).write(to: url, options: .atomic)
        } else {
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            handle.seekToEndOfFile()
            handle.write(Data(row.utf8))
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
