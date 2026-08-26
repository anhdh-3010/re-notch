// Sources/Renotch/Services/TransientSources/PowerEventSource.swift
import Foundation
import IOKit.ps

/// Emits charger plug/unplug and low-battery events via IOKit power-source
/// notifications. No permissions required.
final class PowerEventSource: TransientEventSource {
    private var runLoopSource: CFRunLoopSource?
    private var emit: ((TransientEvent) -> Void)?
    private var lastPlugged: Bool?
    private var firedLowThresholds: Set<Int> = []
    private static let lowThresholds = [20, 10]

    func start(emit: @escaping (TransientEvent) -> Void) {
        stop()
        self.emit = emit
        lastPlugged = Self.readState()?.plugged

        let context = Unmanaged.passUnretained(self).toOpaque()
        let callback: IOPowerSourceCallbackType = { context in
            guard let context else { return }
            Unmanaged<PowerEventSource>.fromOpaque(context)
                .takeUnretainedValue()
                .powerSourcesChanged()
        }
        guard let source = IOPSNotificationCreateRunLoopSource(callback, context)?
            .takeRetainedValue() else { return }
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
    }

    func stop() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .defaultMode)
        }
        runLoopSource = nil
        emit = nil
        firedLowThresholds.removeAll()
    }

    private func powerSourcesChanged() {
        guard let state = Self.readState() else { return }

        if state.plugged != lastPlugged {
            lastPlugged = state.plugged
            emit?(TransientEvent(kind: .charging(plugged: state.plugged, percent: state.percent)))
        }

        if state.plugged {
            firedLowThresholds.removeAll()
        } else {
            for threshold in Self.lowThresholds
            where state.percent <= threshold && !firedLowThresholds.contains(threshold) {
                firedLowThresholds.insert(threshold)
                emit?(TransientEvent(kind: .batteryLow(percent: state.percent)))
            }
        }
    }

    private static func readState() -> (plugged: Bool, percent: Int)? {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }
        for source in sources {
            guard let info = IOPSGetPowerSourceDescription(snapshot, source)?
                .takeUnretainedValue() as? [String: Any],
                  info[kIOPSTypeKey] as? String == kIOPSInternalBatteryType
            else { continue }
            let plugged = (info[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
            let percent = info[kIOPSCurrentCapacityKey] as? Int ?? 0
            return (plugged, percent)
        }
        return nil
    }
}
