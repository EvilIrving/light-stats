import Foundation
import IOKit
import IOKit.ps

struct BatteryPowerSnapshot {
    let percent: Int
    let onACPower: Bool
    let isCharging: Bool
    let isCharged: Bool
}

enum BatteryPowerSourceReader {
    static func current() -> BatteryPowerSnapshot? {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue()
                as? [CFTypeRef] else {
            return nil
        }

        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(snapshot, source)?
                .takeUnretainedValue() as? [String: Any] else {
                continue
            }
            if let type = description[kIOPSTypeKey] as? String,
               type != kIOPSInternalBatteryType {
                continue
            }

            let currentCapacity = (description[kIOPSCurrentCapacityKey] as? NSNumber)?.intValue ?? 0
            let maximumCapacity = (description[kIOPSMaxCapacityKey] as? NSNumber)?.intValue ?? 0
            guard maximumCapacity > 0 else { return nil }

            let percent = min(100, max(0, Int((Double(currentCapacity) /
                Double(maximumCapacity) * 100).rounded())))
            let onACPower = (description[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
            let isCharging = (description[kIOPSIsChargingKey] as? Bool) ?? false
            let isCharged = (description[kIOPSIsChargedKey] as? Bool) ?? false
            return BatteryPowerSnapshot(
                percent: percent,
                onACPower: onACPower,
                isCharging: isCharging,
                isCharged: isCharged
            )
        }

        return nil
    }
}
