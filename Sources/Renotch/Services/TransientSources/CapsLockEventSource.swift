// Sources/Renotch/Services/TransientSources/CapsLockEventSource.swift
import AppKit
import CoreGraphics

/// Emits Caps Lock toggles via a global flagsChanged monitor. Requires the
/// Input Monitoring TCC permission; the Settings UI is responsible for
/// prompting (this source silently does nothing without permission).
final class CapsLockEventSource: TransientEventSource {
    private var monitor: Any?
    private var lastState = false
    private var emit: ((TransientEvent) -> Void)?

    static var hasListenPermission: Bool {
        CGPreflightListenEventAccess()
    }

    /// Triggers the one-time system prompt (or returns false if previously
    /// denied — the caller should then deep-link to System Settings).
    @discardableResult
    static func requestListenPermission() -> Bool {
        CGRequestListenEventAccess()
    }

    func start(emit: @escaping (TransientEvent) -> Void) {
        stop()
        guard Self.hasListenPermission else { return }
        self.emit = emit
        lastState = NSEvent.modifierFlags.contains(.capsLock)
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            guard let self else { return }
            let on = event.modifierFlags.contains(.capsLock)
            guard on != self.lastState else { return }
            self.lastState = on
            self.emit?(TransientEvent(kind: .capsLock(on: on)))
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        emit = nil
    }
}
