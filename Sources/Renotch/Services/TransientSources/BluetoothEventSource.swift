// Sources/Renotch/Services/TransientSources/BluetoothEventSource.swift
import Foundation
import IOBluetooth

/// Emits connect/disconnect events for Bluetooth audio devices. AirPods
/// battery levels are read best-effort from IORegistry Apple-specific keys;
/// absent readings produce a nil batteries payload (UI shows name only).
final class BluetoothEventSource: NSObject, TransientEventSource {
    private var emit: ((TransientEvent) -> Void)?
    private var connectNotification: IOBluetoothUserNotification?
    private var disconnectNotifications: [String: IOBluetoothUserNotification] = [:]

    func start(emit: @escaping (TransientEvent) -> Void) {
        stop()
        self.emit = emit
        connectNotification = IOBluetoothDevice.register(
            forConnectNotifications: self,
            selector: #selector(deviceConnected(_:device:))
        )
    }

    func stop() {
        connectNotification?.unregister()
        connectNotification = nil
        disconnectNotifications.values.forEach { $0.unregister() }
        disconnectNotifications.removeAll()
        emit = nil
    }

    @objc private func deviceConnected(
        _ notification: IOBluetoothUserNotification,
        device: IOBluetoothDevice
    ) {
        guard Self.isAudioDevice(device) else { return }
        let name = device.name ?? "Bluetooth Device"
        let address = device.addressString ?? name

        if disconnectNotifications[address] == nil {
            disconnectNotifications[address] = device.register(
                forDisconnectNotification: self,
                selector: #selector(deviceDisconnected(_:device:))
            )
        }

        // Battery keys appear in IORegistry slightly after connection.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            let batteries = Self.readBatteries()
            self?.emit?(TransientEvent(
                kind: .bluetooth(name: name, connected: true, batteries: batteries)
            ))
        }
    }

    @objc private func deviceDisconnected(
        _ notification: IOBluetoothUserNotification,
        device: IOBluetoothDevice
    ) {
        guard Self.isAudioDevice(device) else { return }
        let address = device.addressString ?? (device.name ?? "Bluetooth Device")
        // Disconnect notifications are one-shot; drop the spent entry so a
        // future reconnect re-registers a fresh one.
        disconnectNotifications.removeValue(forKey: address)?.unregister()
        emit?(TransientEvent(kind: .bluetooth(
            name: device.name ?? "Bluetooth Device",
            connected: false,
            batteries: nil
        )))
    }

    private static func isAudioDevice(_ device: IOBluetoothDevice) -> Bool {
        BluetoothDeviceClassMajor(device.deviceClassMajor) == kBluetoothDeviceClassMajorAudio
    }

    /// Best-effort AirPods battery from IORegistry. Returns nil when no
    /// readable values exist so the UI can hide the battery cluster.
    private static func readBatteries() -> BluetoothBatteries? {
        var iterator = io_iterator_t()
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("AppleDeviceManagementHIDEventService"),
            &iterator
        ) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }

        var entry = IOIteratorNext(iterator)
        while entry != 0 {
            defer { IOObjectRelease(entry); entry = IOIteratorNext(iterator) }
            func intProperty(_ key: String) -> Int? {
                IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?
                    .takeRetainedValue() as? Int
            }
            let batteries = BluetoothBatteries(
                left: intProperty("BatteryPercentLeft"),
                right: intProperty("BatteryPercentRight"),
                caseBattery: intProperty("BatteryPercentCase")
            )
            if batteries.hasAnyReading { return batteries }
        }
        return nil
    }
}
