import XCTest
@testable import N1KOState

final class SamplingPlannerTests: XCTestCase {
    func testMenuOnlyUsesMonotonicTwoSecondCadence() {
        let planner = SamplingPlanner()
        var visibility = MonitorVisibility()
        visibility.menuBarMetrics = [.cpu]
        let input = SamplingPlanInput(refreshInterval: 1,
                                      visibility: visibility,
                                      alertMetrics: [])

        let first = planner.makePlan(input: input, now: 1_000_000_000)
        let early = planner.makePlan(input: input, now: 2_000_000_000)
        let due = planner.makePlan(input: input, now: 3_000_000_000)

        XCTAssertTrue(first.contains(.cpu))
        XCTAssertFalse(early.contains(.cpu))
        XCTAssertTrue(due.contains(.cpu))
    }

    func testSafetySamplingContinuesWhenPresentationIsSuspended() {
        let planner = SamplingPlanner()
        let input = SamplingPlanInput(refreshInterval: 1,
                                      presentationAllowed: false,
                                      visibility: MonitorVisibility(),
                                      alertMetrics: [.temperature],
                                      fanSafetyActive: true)

        let plan = planner.makePlan(input: input, now: 1_000_000_000)
        XCTAssertTrue(plan.contains(.sensors))
        XCTAssertTrue(plan.contains(.fans))
        XCTAssertTrue(plan.contains(.alerts))
        XCTAssertFalse(plan.contains(.processes))
    }

    func testVisibleSettingsUsesTheSameModuleSamplingPlanAsQuickPanel() {
        let planner = SamplingPlanner()
        var visibility = MonitorVisibility()
        visibility.settingsOpen = true
        visibility.popoverModules = [.cpu, .memory, .network, .gpu, .disk]
        let plan = planner.makePlan(
            input: SamplingPlanInput(refreshInterval: 1,
                                     visibility: visibility,
                                     alertMetrics: []),
            now: 1_000_000_000
        )

        for task in [SamplingTask.cpu, .memory, .network, .gpu, .diskIO, .processes, .snapshot] {
            XCTAssertTrue(plan.contains(task), "Missing \(task)")
        }
    }

    func testFullRefreshIncludesEveryMachineSampler() {
        let planner = SamplingPlanner()
        let input = SamplingPlanInput(fullRefresh: true,
                                      refreshInterval: 2,
                                      visibility: MonitorVisibility(),
                                      alertMetrics: [],
                                      batteryPresent: true)
        let plan = planner.makePlan(input: input, now: 1)

        for task in [SamplingTask.cpu, .memory, .network, .gpu, .diskIO,
                     .diskVolumes, .battery, .sensors, .fans, .processes,
                     .history, .snapshot] {
            XCTAssertTrue(plan.contains(task), "Missing \(task)")
        }
    }
}
