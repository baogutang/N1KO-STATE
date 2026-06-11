import Foundation
import IOHIDSensorBridge

/// Reads on-die temperature sensors through the private IOHIDEventSystem API.
///
/// On Apple Silicon the legacy SMC temperature keys are empty, but the SoC,
/// battery, SSD and other thermal sensors are still published through the HID
/// event system under the Apple-vendor temperature usage. This surfaces them.
final class IOHIDSensors {

    // kIOHIDEventTypeTemperature == 15; the float field for an event of type T
    // is `T << 16` (IOHIDEventFieldBase).
    private static let temperatureEventType: Int64 = 15
    private static let temperatureField: Int32 = Int32(15 << 16)

    // Apple-vendor temperature sensors: usage page 0xFF00, usage 0x0005.
    private static let appleVendorPage = 0xff00
    private static let temperatureUsage = 0x0005

    private let client: AnyObject
    private let services: [AnyObject]

    /// Fails (returns nil) when the platform exposes no HID temperature
    /// services — e.g. older Intel Macs, where the SMC path is used instead.
    init?() {
        guard let c = N1KO_IOHIDEventSystemClientCreate(kCFAllocatorDefault) else {
            DiagLog.log("IOHIDSensors", "IOHIDEventSystemClientCreate unavailable — falling back to SMC")
            return nil
        }
        let matching: CFDictionary = [
            "PrimaryUsagePage": Self.appleVendorPage,
            "PrimaryUsage": Self.temperatureUsage
        ] as CFDictionary
        N1KO_IOHIDEventSystemClientSetMatching(c, matching)

        guard let svc = N1KO_IOHIDEventSystemClientCopyServices(c) as? [AnyObject], !svc.isEmpty else {
            DiagLog.log("IOHIDSensors", "no HID temperature services")
            return nil
        }
        client = c
        services = svc
    }

    /// Snapshot of every sensor that currently reports a plausible value.
    func readAll() -> [(name: String, celsius: Double)] {
        var out: [(String, Double)] = []
        out.reserveCapacity(services.count)
        for service in services {
            guard let event = N1KO_IOHIDServiceClientCopyEvent(service,
                                                               Self.temperatureEventType,
                                                               0, 0) else { continue }
            let value = N1KO_IOHIDEventGetFloatValue(event, Self.temperatureField)
            guard value > 0, value < 150 else { continue }
            let name = (N1KO_IOHIDServiceClientCopyProperty(service, "Product" as CFString) as? String)
                ?? "Sensor"
            out.append((name, value))
        }
        return out
    }
}
