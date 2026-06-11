import Foundation
import Combine
import Darwin

final class NetworkMonitor: ObservableObject {

    private(set) var downloadRate: Double = 0
    private(set) var uploadRate: Double = 0
    private(set) var downHistory: [Double] = []
    private(set) var upHistory: [Double] = []
    private(set) var primaryInterface: String?
    private(set) var localIP: String?
    private(set) var isConnected = false

    let historyCapacity = 300

    private var lastDown: UInt64 = 0
    private var lastUp: UInt64 = 0
    private var lastTime = Date()
    private var primed = false
    private var refreshCount = 0

    func refresh(includeInterfaceInfo: Bool = true) {
        sampleAll(updateInterfaceInfo: includeInterfaceInfo)
        objectWillChange.send()
    }

    func refreshRatesOnly() {
        sampleAll(updateInterfaceInfo: false)
        objectWillChange.send()
    }

    private func sampleAll(updateInterfaceInfo: Bool) {
        refreshCount += 1
        let updateInfo = updateInterfaceInfo || refreshCount % 10 == 1
        let snapshot = NetworkMonitor.interfaceSnapshot(updateInterfaceInfo: updateInfo)
        let now = Date()
        let dt = now.timeIntervalSince(lastTime)

        // A forced refresh (popover opening) can land right after a timer tick;
        // dividing a few bytes by a near-zero dt would print absurd rate spikes,
        // so keep the previous rates until a meaningful interval has passed.
        if primed && dt >= 0.2 {
            let dDown = snapshot.rx >= lastDown ? Double(snapshot.rx - lastDown) : 0
            let dUp = snapshot.tx >= lastUp ? Double(snapshot.tx - lastUp) : 0
            downloadRate = dDown / dt
            uploadRate = dUp / dt
            lastDown = snapshot.rx
            lastUp = snapshot.tx
            lastTime = now
        } else if !primed {
            lastDown = snapshot.rx
            lastUp = snapshot.tx
            lastTime = now
            primed = true
        }

        if updateInfo {
            localIP = snapshot.localIP
            primaryInterface = snapshot.primaryInterface
            isConnected = snapshot.localIP != nil
        }

        downHistory.append(downloadRate)
        if downHistory.count > historyCapacity { downHistory.removeFirst(downHistory.count - historyCapacity) }
        upHistory.append(uploadRate)
        if upHistory.count > historyCapacity { upHistory.removeFirst(upHistory.count - historyCapacity) }
    }

    private struct InterfaceSnapshot {
        var rx: UInt64 = 0
        var tx: UInt64 = 0
        var primaryInterface: String?
        var localIP: String?
    }

    private static func interfaceSnapshot(updateInterfaceInfo: Bool) -> InterfaceSnapshot {
        var snap = InterfaceSnapshot()
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return snap }
        defer { freeifaddrs(ifaddr) }

        var ptr = ifaddr
        while let cur = ptr {
            defer { ptr = cur.pointee.ifa_next }
            let name = String(cString: cur.pointee.ifa_name)
            guard !name.hasPrefix("lo") else { continue }

            if let addr = cur.pointee.ifa_addr, Int32(addr.pointee.sa_family) == AF_LINK,
               let data = cur.pointee.ifa_data {
                let d = data.assumingMemoryBound(to: if_data.self)
                snap.rx &+= UInt64(d.pointee.ifi_ibytes)
                snap.tx &+= UInt64(d.pointee.ifi_obytes)
            }

            if updateInterfaceInfo,
               let addr = cur.pointee.ifa_addr, Int32(addr.pointee.sa_family) == AF_INET,
               name.hasPrefix("en"), snap.localIP == nil {
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                guard getnameinfo(addr, socklen_t(addr.pointee.sa_len),
                                  &host, socklen_t(host.count),
                                  nil, 0, NI_NUMERICHOST) == 0 else { continue }
                let ip = String(cString: host)
                if !ip.isEmpty {
                    snap.localIP = ip
                    snap.primaryInterface = name
                }
            }
        }
        return snap
    }
}
