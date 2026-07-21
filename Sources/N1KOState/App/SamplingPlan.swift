import Foundation

enum SamplingTask: Hashable, CaseIterable {
    case cpu
    case memory
    case network
    case networkInterfaceInfo
    case gpu
    case diskIO
    case diskVolumes
    case battery
    case sensors
    case fans
    case processes
    case history
    case alerts
    case snapshot
}

struct SamplingPlan: Equatable {
    var tasks: Set<SamplingTask> = []
    var isFullRefresh = false

    func contains(_ task: SamplingTask) -> Bool {
        tasks.contains(task)
    }
}

struct SamplingPlanInput {
    var fullRefresh = false
    var refreshInterval: TimeInterval
    var presentationAllowed = true
    var visibility: MonitorVisibility
    var alertMetrics: Set<AlertManager.RequiredMetric>
    var fanSafetyActive = false
    var fanCurveEnabled = false
    var batteryPresent = false
}

/// Converts visibility/safety needs into explicit monotonic deadlines. The
/// configured interval still controls freshness, but cadence no longer depends
/// on a mutable tick counter or on wall-clock adjustments.
final class SamplingPlanner {
    private var nextDeadlines: [SamplingTask: UInt64] = [:]

    func reset() {
        nextDeadlines.removeAll()
    }

    func makePlan(input: SamplingPlanInput,
                  now: UInt64 = DispatchTime.now().uptimeNanoseconds) -> SamplingPlan {
        let interval = max(input.refreshInterval, 0.1)
        let visibility = input.visibility
        let popoverVisible = (visibility.popoverOpen || visibility.settingsOpen)
            && input.presentationAllowed
        let full = input.fullRefresh

        let menuCadence = input.refreshInterval < 0.75 ? interval : max(interval, 2.0)
        let menuDue = due(.snapshot, every: menuCadence, now: now, force: full || popoverVisible)
        let historyDue = due(.history, every: 30, now: now, force: full)

        let menuCPU = visibility.menuBarMetrics.contains(.cpu) && menuDue
        let menuMemory = visibility.menuBarMetrics.contains(.memory) && menuDue
        let menuNetwork = visibility.menuBarMetrics.contains(.network) && menuDue
        let menuGPU = visibility.menuBarMetrics.contains(.gpu) && menuDue
        let menuBattery = visibility.menuBarMetrics.contains(.battery)

        let popoverCPU = popoverVisible && visibility.popoverModules.contains(.cpu)
        let popoverMemory = popoverVisible && visibility.popoverModules.contains(.memory)
        let popoverNetwork = popoverVisible && visibility.popoverModules.contains(.network)
        let popoverGPU = popoverVisible && visibility.popoverModules.contains(.gpu)
        let popoverDisk = popoverVisible && visibility.popoverModules.contains(.disk)
        let popoverBattery = popoverVisible && visibility.popoverModules.contains(.battery)
        let popoverSensors = popoverVisible && visibility.popoverModules.contains(.sensors)

        var tasks = Set<SamplingTask>()

        if full || popoverCPU || menuCPU || input.alertMetrics.contains(.cpu) || historyDue {
            tasks.insert(.cpu)
        }
        if full || popoverMemory || menuMemory || input.alertMetrics.contains(.memory) || historyDue {
            tasks.insert(.memory)
        }
        if full || popoverNetwork || menuNetwork || historyDue {
            tasks.insert(.network)
            if due(.networkInterfaceInfo, every: interval * 10, now: now, force: full) {
                tasks.insert(.networkInterfaceInfo)
            }
        }
        if full || popoverGPU || menuGPU {
            tasks.insert(.gpu)
        }
        if (full || popoverDisk),
           due(.diskIO, every: interval * 3, now: now, force: full) {
            tasks.insert(.diskIO)
        }
        if full || (input.alertMetrics.contains(.disk)
                    && due(.diskVolumes, every: interval * 60, now: now)) {
            tasks.insert(.diskVolumes)
        }
        if input.batteryPresent,
           (full || popoverBattery || menuBattery || input.alertMetrics.contains(.battery)),
           due(.battery,
               every: popoverBattery ? interval * 2 : interval * 30,
               now: now,
               force: full) {
            tasks.insert(.battery)
        }

        let safetyNeedsSensors = input.fanSafetyActive
            || input.fanCurveEnabled
            || input.alertMetrics.contains(.temperature)
        if full || popoverSensors || safetyNeedsSensors {
            let cadence = popoverSensors ? interval : interval * 3
            if due(.sensors, every: cadence, now: now, force: full) {
                tasks.insert(.sensors)
            }
            if due(.fans, every: cadence, now: now, force: full) {
                tasks.insert(.fans)
            }
        }

        if (full || popoverCPU || popoverMemory),
           due(.processes, every: interval * 5, now: now, force: full) {
            tasks.insert(.processes)
        }
        if historyDue { tasks.insert(.history) }
        if !input.alertMetrics.isEmpty { tasks.insert(.alerts) }

        let displayChanged = full || popoverVisible || menuCPU || menuMemory || menuNetwork || menuGPU
            || tasks.contains(.battery) || tasks.contains(.diskIO)
        if displayChanged { tasks.insert(.snapshot) }

        return SamplingPlan(tasks: tasks, isFullRefresh: full)
    }

    private func due(_ task: SamplingTask,
                     every interval: TimeInterval,
                     now: UInt64,
                     force: Bool = false) -> Bool {
        let nanoseconds = UInt64(max(interval, 0.001) * 1_000_000_000)
        if force || nextDeadlines[task].map({ now >= $0 }) != false {
            nextDeadlines[task] = now &+ nanoseconds
            return true
        }
        return false
    }
}
