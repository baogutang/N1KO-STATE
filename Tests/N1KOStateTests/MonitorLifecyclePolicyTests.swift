import XCTest
import AppKit
@testable import N1KOState

final class MonitorLifecyclePolicyTests: XCTestCase {
    func testPresentationSuspendsForSleepAndInactiveSession() {
        var state = MonitorLifecycleState()
        XCTAssertTrue(state.presentationAllowed)

        state.screenSleeping = true
        XCTAssertFalse(state.presentationAllowed)

        state.screenSleeping = false
        state.sessionActive = false
        XCTAssertFalse(state.presentationAllowed)
    }

    func testWakeGraceUsesMonotonicDeadline() {
        var state = MonitorLifecycleState()
        state.wakeGraceUntilUptimeNanoseconds = 3_000_000_000

        XCTAssertTrue(state.isInWakeGrace(now: 2_999_999_999))
        XCTAssertFalse(state.isInWakeGrace(now: 3_000_000_000))
    }

    func testPublicWorkspaceSleepWakeNotificationsDrivePolicy() {
        let policy = MonitorLifecyclePolicy()
        var transitions: [MonitorLifecycleState] = []
        policy.onChange = { _, current in transitions.append(current) }
        policy.start()
        defer { policy.stop() }

        let center = NSWorkspace.shared.notificationCenter
        center.post(name: NSWorkspace.screensDidSleepNotification, object: nil)
        center.post(name: NSWorkspace.screensDidWakeNotification, object: nil)

        XCTAssertEqual(transitions.count, 2)
        XCTAssertTrue(transitions[0].screenSleeping)
        XCTAssertFalse(transitions[1].screenSleeping)
        XCTAssertTrue(transitions[1].isInWakeGrace())
    }

    func testWakeRecoveryResetsRatesAndCommitsFullGenerationWithinTwoSeconds() {
        let hub = MonitorHub()
        let completed = expectation(description: "full wake generation")
        let started = DispatchTime.now().uptimeNanoseconds

        hub.recoverAfterWake { snapshot in
            let elapsed = Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000_000
            XCTAssertGreaterThan(snapshot.generationID, 0)
            XCTAssertEqual(snapshot.networkDownloadRate, 0)
            XCTAssertEqual(snapshot.networkUploadRate, 0)
            XCTAssertEqual(snapshot.diskReadRate, 0)
            XCTAssertEqual(snapshot.diskWriteRate, 0)
            XCTAssertLessThan(elapsed, 2)
            completed.fulfill()
        }

        wait(for: [completed], timeout: 2)
    }

    func testConcurrentWakeRequestsCoalesceWithoutDroppingCompletion() {
        let hub = MonitorHub()
        let completed = expectation(description: "coalesced wake completions")
        completed.expectedFulfillmentCount = 2
        var generations: [UInt64] = []

        let record: (MonitorDisplaySnapshot) -> Void = { snapshot in
            generations.append(snapshot.generationID)
            completed.fulfill()
        }
        hub.recoverAfterWake(completion: record)
        hub.recoverAfterWake(completion: record)

        wait(for: [completed], timeout: 2)
        XCTAssertEqual(Set(generations).count, 1)
        XCTAssertGreaterThan(generations.first ?? 0, 0)
    }
}
