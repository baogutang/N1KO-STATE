import Foundation
import Combine
import IOKit
import AppKit

struct VolumeInfo: Identifiable {
    let id: String        // mount path
    let name: String
    let total: Double
    let free: Double
    var used: Double { max(total - free, 0) }
    var fraction: Double { total > 0 ? used / total : 0 }
}

/// Disk capacity per mounted volume + aggregate read/write throughput via
/// `IOBlockStorageDriver` statistics.
final class DiskMonitor: ObservableObject {

    private(set) var volumes: [VolumeInfo] = []
    private(set) var readRate: Double = 0
    private(set) var writeRate: Double = 0
    private(set) var readHistory: [Double] = []
    private(set) var writeHistory: [Double] = []

    let historyCapacity = 300

    private var lastRead: UInt64 = 0
    private var lastWrite: UInt64 = 0
    private var lastTime = Date()
    private var primed = false
    private var lastVolumeRefresh = Date.distantPast
    private let volumeRefreshInterval: TimeInterval = 60
    private var workspaceObservers: [NSObjectProtocol] = []

    func startVolumeWatching() {
        volumes = DiskMonitor.readVolumes()
        lastVolumeRefresh = Date()
        let nc = NSWorkspace.shared.notificationCenter
        let handler: (Notification) -> Void = { [weak self] _ in self?.refreshVolumesNow() }
        workspaceObservers = [
            nc.addObserver(forName: NSWorkspace.didMountNotification, object: nil, queue: .main, using: handler),
            nc.addObserver(forName: NSWorkspace.didUnmountNotification, object: nil, queue: .main, using: handler),
            nc.addObserver(forName: NSWorkspace.didRenameVolumeNotification, object: nil, queue: .main, using: handler)
        ]
    }

    func refreshVolumesNow() {
        volumes = DiskMonitor.readVolumes()
        lastVolumeRefresh = Date()
        objectWillChange.send()
    }

    /// IO throughput only (volume list is event-driven + 60s free-space refresh).
    func refreshIO() {
        let (r, w) = DiskMonitor.totalIO()
        let now = Date()
        let dt = now.timeIntervalSince(lastTime)
        if primed && dt > 0 {
            readRate = r >= lastRead ? Double(r - lastRead) / dt : 0
            writeRate = w >= lastWrite ? Double(w - lastWrite) / dt : 0
        }
        lastRead = r; lastWrite = w; lastTime = now; primed = true

        readHistory.append(readRate); trim(&readHistory)
        writeHistory.append(writeRate); trim(&writeHistory)

        if now.timeIntervalSince(lastVolumeRefresh) >= volumeRefreshInterval {
            refreshVolumesNow()
        } else {
            objectWillChange.send()
        }
    }

    /// Legacy full refresh (popover open / tests).
    func refresh() {
        refreshIO()
    }

    private func trim(_ a: inout [Double]) {
        if a.count > historyCapacity { a.removeFirst(a.count - historyCapacity) }
    }

    deinit {
        let nc = NSWorkspace.shared.notificationCenter
        workspaceObservers.forEach { nc.removeObserver($0) }
    }

    static func readVolumes() -> [VolumeInfo] {
        let keys: [URLResourceKey] = [
            .volumeNameKey, .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey,
            .volumeIsBrowsableKey, .volumeIsLocalKey
        ]
        guard let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) else { return [] }

        var result: [VolumeInfo] = []
        for url in urls {
            guard let v = try? url.resourceValues(forKeys: Set(keys)),
                  v.volumeIsLocal == true, v.volumeIsBrowsable == true,
                  let total = v.volumeTotalCapacity, total > 0 else { continue }
            let free = v.volumeAvailableCapacityForImportantUsage.map { Double($0) }
                ?? Double(v.volumeAvailableCapacity ?? 0)
            let name = v.volumeName ?? url.lastPathComponent
            result.append(VolumeInfo(id: url.path, name: name, total: Double(total), free: free))
        }
        return result.sorted { ($0.id == "/" ? 0 : 1) < ($1.id == "/" ? 0 : 1) }
    }

    static func totalIO() -> (read: UInt64, write: UInt64) {
        autoreleasepool {
            var read: UInt64 = 0
            var write: UInt64 = 0
            guard let matching = IOServiceMatching("IOBlockStorageDriver") else { return (0, 0) }
            var iterator: io_iterator_t = 0
            guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
                return (0, 0)
            }
            defer { IOObjectRelease(iterator) }

            var service = IOIteratorNext(iterator)
            while service != 0 {
                if let stats = IORegistryEntryCreateCFProperty(
                    service, "Statistics" as CFString, kCFAllocatorDefault, 0
                )?.takeRetainedValue() as? [String: Any] {
                    if let rb = (stats["Bytes (Read)"] as? NSNumber)?.uint64Value { read &+= rb }
                    if let wb = (stats["Bytes (Write)"] as? NSNumber)?.uint64Value { write &+= wb }
                }
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }
            return (read, write)
        }
    }
}
