// Sources/Renotch/Models/TransientEventModels.swift
import Foundation

enum PeekStyle: String, Codable {
    case wings
    case droop
}

/// Which pluggable source a peek event originates from. Used by
/// TransientEventService to map Settings toggles to sources.
enum PeekSourceKind: String, CaseIterable {
    case charging
    case bluetooth
    case screenshot
    case capsLock
}

struct BluetoothBatteries: Equatable {
    var left: Int?
    var right: Int?
    var caseBattery: Int?

    var hasAnyReading: Bool {
        left != nil || right != nil || caseBattery != nil
    }
}

enum TransientEventKind: Equatable {
    case charging(plugged: Bool, percent: Int)
    case batteryLow(percent: Int)
    case bluetooth(name: String, connected: Bool, batteries: BluetoothBatteries?)
    case screenshot(url: URL)
    case capsLock(on: Bool)
}

struct TransientEvent: Equatable {
    let kind: TransientEventKind

    var presentationStyle: PeekStyle {
        switch kind {
        case .charging, .batteryLow, .capsLock:
            return .wings
        case .bluetooth, .screenshot:
            return .droop
        }
    }

    var duration: TimeInterval {
        switch kind {
        case .capsLock: return 1.2
        case .charging: return 2.5
        case .batteryLow, .bluetooth, .screenshot: return 3.0
        }
    }

    var sourceKind: PeekSourceKind {
        switch kind {
        case .charging, .batteryLow: return .charging
        case .bluetooth: return .bluetooth
        case .screenshot: return .screenshot
        case .capsLock: return .capsLock
        }
    }
}
