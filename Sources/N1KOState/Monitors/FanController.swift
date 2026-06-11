import Foundation
import Combine
import SMCKit

/// Shared serial queue for ALL SMC access. The SMC connection is global static
/// state in SMCKit, so every reader/writer (sensors + fans) must funnel through
/// one queue to avoid concurrent driver calls.
let smcAccessQueue = DispatchQueue(label: "com.n1ko.state.smc", qos: .utility)

/// Shared utility queue for network-adjacent work (ps, disk metadata, battery SMC).
let monitorWorkQueue = DispatchQueue(label: "com.n1ko.state.monitor.work", qos: .utility)

/// One fan's state for display.
struct FanInfo: Identifiable, Hashable {
    let id: Int
    let name: String
    let rpm: Int
    let targetRPM: Int
    let minRPM: Int
    let maxRPM: Int
    let forced: Bool

    var fraction: Double {
        let span = Double(maxRPM - minRPM)
        guard span > 0 else { return 0 }
        return min(max(Double(rpm - minRPM) / span, 0), 1)
    }
}

/// Thin alias so existing views keep using `FanController` on the hub.
typealias FanController = FanControlService
