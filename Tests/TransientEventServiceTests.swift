// Tests/TransientEventServiceTests.swift
import AppKit
import Foundation

/// Covers TransientEventService: sources start/stop per settings toggles,
/// events forward to AppModel on the main actor, restart on re-enable.
@main
struct TransientEventServiceTests {
    final class MockSource: TransientEventSource {
        var startCount = 0
        var stopCount = 0
        var emit: ((TransientEvent) -> Void)?
        func start(emit: @escaping (TransientEvent) -> Void) {
            startCount += 1
            self.emit = emit
        }
        func stop() {
            stopCount += 1
            emit = nil
        }
    }

    @MainActor
    static func main() {
        var failures: [String] = []
        func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
            if !condition() { failures.append(message) }
        }
        func waitUntil(
            timeout: TimeInterval = 2.0,
            _ condition: () -> Bool
        ) -> Bool {
            let deadline = Date().addingTimeInterval(timeout)
            while !condition() {
                if Date() >= deadline { return false }
                RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01))
            }
            return true
        }

        let defaultsSuiteName = "com.virtualnotch.tests.transient-service"
        defer { UserDefaults.standard.removePersistentDomain(forName: defaultsSuiteName) }
        UserDefaults.standard.removePersistentDomain(forName: defaultsSuiteName)
        let defaults = UserDefaults(suiteName: defaultsSuiteName)!
        defaults.set(true, forKey: "virtualNotch.didCompleteOnboarding")

        let model = AppModel(defaults: defaults)
        model.peekDismissalDelayOverride = 0.05

        let charging = MockSource()
        let capsLock = MockSource()
        let service = TransientEventService(
            appModel: model,
            sources: [.charging: charging, .capsLock: capsLock]
        )

        // Defaults: charging on, capsLock off.
        var settings = NotchSettings.default
        service.applySettings(settings)
        expect(charging.startCount == 1, "enabled source started")
        expect(capsLock.startCount == 0, "disabled source not started")

        // Re-applying identical settings must not restart sources.
        service.applySettings(settings)
        expect(charging.startCount == 1, "no restart when toggle unchanged")

        // Toggling off stops; toggling back on restarts.
        settings.peekChargingEnabled = false
        service.applySettings(settings)
        expect(charging.stopCount == 1, "source stopped when disabled")
        settings.peekChargingEnabled = true
        service.applySettings(settings)
        expect(charging.startCount == 2, "source restarted when re-enabled")

        // Emitted events reach the AppModel (hop to main actor allowed).
        charging.emit?(TransientEvent(kind: .charging(plugged: true, percent: 50)))
        expect(
            waitUntil { model.activePeekEvent != nil || model.mode == .peek },
            "event forwarded to AppModel"
        )

        if failures.isEmpty {
            print("TransientEventServiceTests: all assertions passed")
        } else {
            print("TransientEventServiceTests: \(failures.count) failure(s)")
            failures.forEach { print("  - \($0)") }
            exit(1)
        }
    }
}
