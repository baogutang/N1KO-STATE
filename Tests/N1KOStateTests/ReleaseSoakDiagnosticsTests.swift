import Foundation
import XCTest
@testable import N1KOState

final class ReleaseSoakDiagnosticsTests: XCTestCase {
    func testCountOnlySamplesAppendWithPrivatePermissions() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("n1ko-soak-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("internal-resources.tsv")
        let sample = ReleaseSoakSample(
            wallTimeSeconds: 1_700_000_000,
            uptimeNanoseconds: 42,
            historyCPUCount: 1,
            historyMemoryCount: 1,
            historyNetDownCount: 1,
            historyNetUpCount: 1,
            agentSessionCount: 200,
            agentSockets: 1,
            agentWatchers: 2,
            agentTransports: 0,
            agentRegisteredTasks: 0,
            agentActiveTasks: 0,
            agentRegisteredSubprocesses: 0,
            agentActiveSubprocesses: 0,
            agentPendingResponseRoutes: 0,
            agentSnapshotObservers: 1,
            surfaceGlobalMonitors: 0,
            surfaceRetryTasks: 0,
            systemSleepEvents: 1,
            systemWakeEvents: 1,
            sessionInactiveEvents: 1,
            sessionActiveEvents: 1,
            screenSleepEvents: 1,
            screenWakeEvents: 1
        )

        try ReleaseSoakDiagnostics.append(sample, to: url)
        try ReleaseSoakDiagnostics.append(sample, to: url)

        let lines = try String(contentsOf: url).split(separator: "\n")
        XCTAssertEqual(lines.count, 3)
        XCTAssertEqual(String(lines[0]), ReleaseSoakSample.tsvHeader)
        XCTAssertEqual(String(lines[1]), sample.tsvRow)
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }
}
