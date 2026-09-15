import Foundation
import IOKit.ps

final class PowerReactionController {
    private var timer: Timer?
    private var lastCandidates: [String] = []

    var onCandidatesChange: (([String]) -> Void)?

    func start() {
        guard timer == nil else {
            refresh()
            return
        }

        refresh()
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        publish([])
    }

    private func refresh() {
        guard
            let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
            let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef]
        else {
            publish([])
            return
        }

        for source in sources {
            guard
                let description = IOPSGetPowerSourceDescription(snapshot, source)?
                    .takeUnretainedValue() as? [String: Any]
            else { continue }

            let isCharging = description[kIOPSIsChargingKey] as? Bool ?? false
            let capacity = description[kIOPSCurrentCapacityKey] as? Int
            let powerSource = description[kIOPSPowerSourceStateKey] as? String
            let usesBattery = powerSource == kIOPSBatteryPowerValue

            publish(Self.candidates(
                isCharging: isCharging,
                usesBattery: usesBattery,
                capacity: capacity
            ))
            return
        }

        publish([])
    }

    private func publish(_ candidates: [String]) {
        guard candidates != lastCandidates else { return }
        lastCandidates = candidates
        onCandidatesChange?(candidates)
    }

    static func candidates(isCharging: Bool, usesBattery: Bool, capacity: Int?) -> [String] {
        if isCharging {
            return ["charging", "happy", "tail_wag"]
        }
        if usesBattery, let capacity, capacity <= 15 {
            return ["low_battery", "sleep", "idle"]
        }
        return []
    }
}
