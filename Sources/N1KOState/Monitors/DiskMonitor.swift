import Foundation
import Combine
import IOKit
import AppKit
import Darwin
import DiskArbitration

struct VolumeInfo: Identifiable, Equatable {
    let id: String        // mount path
    let name: String
    let total: Double
    let free: Double
    var used: Double { max(total - free, 0) }
    var fraction: Double { total > 0 ? used / total : 0 }
}

struct DiskModuleSnapshot: Equatable {
    let volumes: [VolumeInfo]?
    let readRate: Double
    let writeRate: Double
    let readHistory: [Double]
    let writeHistory: [Double]
}

struct VolumeFilterTraits {
    let mountPath: String
    let totalCapacity: Int
    let isRoot: Bool
    let isRemovable: Bool
    let isEjectable: Bool
    let isReadOnly: Bool
    let mountFromName: String?
    let diskArbitrationDescription: [String]
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
    private lazy var readHistoryBuffer = RingBuffer<Double>(capacity: historyCapacity)
    private lazy var writeHistoryBuffer = RingBuffer<Double>(capacity: historyCapacity)

    private var lastRead: UInt64 = 0
    private var lastWrite: UInt64 = 0
    private var lastTime = Date()
    private var primed = false
    private var sampledReadRate: Double = 0
    private var sampledWriteRate: Double = 0
    private let volumeRefreshInterval: TimeInterval = 60
    private var nextVolumeReadUptimeNanoseconds: UInt64 = 0
    private let volumeQueue = DispatchQueue(label: "com.n1ko-state.disk-volumes", qos: .utility)
    private var workspaceObservers: [NSObjectProtocol] = []

    func startVolumeWatching() {
        refreshVolumesNow()
        let nc = NSWorkspace.shared.notificationCenter
        let handler: (Notification) -> Void = { [weak self] _ in self?.refreshVolumesNow() }
        workspaceObservers = [
            nc.addObserver(forName: NSWorkspace.didMountNotification, object: nil, queue: .main, using: handler),
            nc.addObserver(forName: NSWorkspace.didUnmountNotification, object: nil, queue: .main, using: handler),
            nc.addObserver(forName: NSWorkspace.didRenameVolumeNotification, object: nil, queue: .main, using: handler)
        ]
    }

    func refreshVolumesNow() {
        volumeQueue.async { [weak self] in
            let volumes = PerformanceDiagnostics.measure(.samplerDisk) {
                DiskMonitor.readVolumes()
            }
            DispatchQueue.main.async {
                self?.applyVolumes(volumes)
            }
        }
    }

    private func applyVolumes(_ values: [VolumeInfo]) {
        objectWillChange.send()
        volumes = values
    }

    /// IO throughput only (volume list is event-driven + 60s free-space refresh).
    func sampleIO(includeVolumes: Bool = false) -> DiskModuleSnapshot {
        PerformanceDiagnostics.measure(.samplerDisk) {
            let (r, w) = DiskMonitor.totalIO()
            let now = Date()
            let dt = now.timeIntervalSince(lastTime)
            var nextReadRate = sampledReadRate
            var nextWriteRate = sampledWriteRate
            if primed && dt > 0 {
                nextReadRate = r >= lastRead ? Double(r - lastRead) / dt : 0
                nextWriteRate = w >= lastWrite ? Double(w - lastWrite) / dt : 0
            }
            sampledReadRate = nextReadRate
            sampledWriteRate = nextWriteRate
            lastRead = r; lastWrite = w; lastTime = now; primed = true

            readHistoryBuffer.append(nextReadRate)
            writeHistoryBuffer.append(nextWriteRate)
            let uptime = DispatchTime.now().uptimeNanoseconds
            let shouldReadVolumes = includeVolumes || uptime >= nextVolumeReadUptimeNanoseconds
            if shouldReadVolumes {
                nextVolumeReadUptimeNanoseconds = uptime &+ UInt64(volumeRefreshInterval * 1_000_000_000)
            }
            return DiskModuleSnapshot(
                volumes: shouldReadVolumes ? DiskMonitor.readVolumes() : nil,
                readRate: nextReadRate,
                writeRate: nextWriteRate,
                readHistory: readHistoryBuffer.elements,
                writeHistory: writeHistoryBuffer.elements
            )
        }
    }

    func apply(_ sample: DiskModuleSnapshot, publish: Bool = true) {
        if publish { objectWillChange.send() }
        if let volumes = sample.volumes {
            self.volumes = volumes
        }
        readRate = sample.readRate
        writeRate = sample.writeRate
        readHistory = sample.readHistory
        writeHistory = sample.writeHistory
    }

    func refreshIO() { apply(sampleIO()) }

    func resetBaseline() {
        primed = false
        sampledReadRate = 0
        sampledWriteRate = 0
    }

    /// Legacy full refresh (popover open / tests).
    func refresh() {
        refreshIO()
    }

    deinit {
        let nc = NSWorkspace.shared.notificationCenter
        workspaceObservers.forEach { nc.removeObserver($0) }
    }

    static func readVolumes() -> [VolumeInfo] {
        let keys: [URLResourceKey] = [
            .volumeNameKey, .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey,
            .volumeIsBrowsableKey, .volumeIsLocalKey,
            .volumeIsRootFileSystemKey, .volumeIsRemovableKey,
            .volumeIsEjectableKey, .volumeIsReadOnlyKey
        ]
        guard let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) else { return [] }

        let session = DASessionCreate(kCFAllocatorDefault)
        var result: [VolumeInfo] = []
        for url in urls {
            guard let v = try? url.resourceValues(forKeys: Set(keys)),
                  v.volumeIsLocal == true, v.volumeIsBrowsable == true,
                  let total = v.volumeTotalCapacity, total > 0 else { continue }
            let mountFromName = mountFromName(for: url.path)
            let traits = VolumeFilterTraits(
                mountPath: url.path,
                totalCapacity: total,
                isRoot: v.volumeIsRootFileSystem == true || url.path == "/",
                isRemovable: v.volumeIsRemovable == true,
                isEjectable: v.volumeIsEjectable == true,
                isReadOnly: v.volumeIsReadOnly == true,
                mountFromName: mountFromName,
                diskArbitrationDescription: diskArbitrationDescription(
                    forMountFromName: mountFromName,
                    session: session
                )
            )
            guard shouldIncludeVolume(traits) else { continue }
            let free = v.volumeAvailableCapacityForImportantUsage.map { Double($0) }
                ?? Double(v.volumeAvailableCapacity ?? 0)
            let name = v.volumeName ?? url.lastPathComponent
            result.append(VolumeInfo(id: url.path, name: name, total: Double(total), free: free))
        }
        return result.sorted { ($0.id == "/" ? 0 : 1) < ($1.id == "/" ? 0 : 1) }
    }

    static func shouldIncludeVolume(_ traits: VolumeFilterTraits) -> Bool {
        if traits.isRoot { return true }
        if isDiskImage(traits) { return false }
        if traits.isRemovable { return true }

        let smallInstallerVolumeLimit = 512 * 1024 * 1024
        if traits.isReadOnly,
           traits.isEjectable,
           !traits.isRemovable,
           traits.totalCapacity > 0,
           traits.totalCapacity < smallInstallerVolumeLimit {
            return false
        }

        return true
    }

    private static func isDiskImage(_ traits: VolumeFilterTraits) -> Bool {
        let candidates = ([traits.mountFromName].compactMap { $0 } + traits.diskArbitrationDescription)
            .map { $0.lowercased() }
        return candidates.contains { value in
            value.contains("disk image") || value.contains("diskimage")
        }
    }

    private static func mountFromName(for path: String) -> String? {
        var fs = statfs()
        guard statfs(path, &fs) == 0 else { return nil }
        var mountName = fs.f_mntfromname
        let capacity = MemoryLayout.size(ofValue: mountName)
        return withUnsafePointer(to: &mountName) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: capacity) {
                String(cString: $0)
            }
        }
    }

    private static func diskArbitrationDescription(forMountFromName mountFromName: String?,
                                                   session: DASession?) -> [String] {
        guard let session,
              let mountFromName,
              mountFromName.hasPrefix("/dev/") else { return [] }
        let bsdName = String(mountFromName.dropFirst("/dev/".count))
        guard let disk = DADiskCreateFromBSDName(kCFAllocatorDefault, session, bsdName),
              let raw = DADiskCopyDescription(disk) as? [CFString: Any] else {
            return []
        }
        let keys: [CFString] = [
            kDADiskDescriptionDeviceProtocolKey,
            kDADiskDescriptionDeviceModelKey,
            kDADiskDescriptionMediaNameKey,
            kDADiskDescriptionMediaKindKey
        ]
        return keys.compactMap { raw[$0] as? String }
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
