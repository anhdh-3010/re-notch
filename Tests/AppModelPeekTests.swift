import AppKit
import Foundation

/// Covers AppModel peek state transitions: entry from compact and expanded,
/// timed restore, latest-wins replacement, busy-mode rules, and tap actions.
@main
struct AppModelPeekTests {
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

        let defaultsSuiteName = "com.virtualnotch.tests.appmodel-peek"
        defer { UserDefaults.standard.removePersistentDomain(forName: defaultsSuiteName) }

        func makeDefaults() -> UserDefaults {
            UserDefaults.standard.removePersistentDomain(forName: defaultsSuiteName)
            let defaults = UserDefaults(suiteName: defaultsSuiteName)!
            defaults.set(true, forKey: "virtualNotch.didCompleteOnboarding")
            return defaults
        }

        func makeModel() -> AppModel {
            let model = AppModel(defaults: makeDefaults())
            model.peekDismissalDelayOverride = 0.05
            return model
        }

        let chargingEvent = TransientEvent(kind: .charging(plugged: true, percent: 78))
        let bluetoothEvent = TransientEvent(
            kind: .bluetooth(name: "AirPods Pro", connected: true, batteries: nil)
        )

        // Peek from compact enters .peek and restores to compact.
        do {
            let model = makeModel()
            expect(model.mode == .compact, "starts compact")
            model.handleTransientEvent(chargingEvent)
            expect(model.mode == .peek, "peek entered from compact")
            expect(model.activePeekEvent == chargingEvent, "event stored")
            expect(waitUntil { model.mode == .compact }, "auto-restores to compact")
            expect(model.activePeekEvent == nil, "event cleared after restore")
        }

        // Peek from expanded restores to expanded.
        do {
            let model = makeModel()
            model.expand()
            model.handleTransientEvent(chargingEvent)
            expect(model.mode == .peek, "peek entered from expanded")
            expect(waitUntil { model.mode == .expanded }, "auto-restores to expanded")
        }

        // Latest event wins and resets the timer.
        do {
            let model = makeModel()
            model.handleTransientEvent(chargingEvent)
            model.handleTransientEvent(bluetoothEvent)
            expect(model.mode == .peek, "still peeking after replacement")
            expect(model.activePeekEvent == bluetoothEvent, "newest event replaces current")
            expect(waitUntil { model.mode == .compact }, "restores after replacement")
        }

        // Manual dismiss restores immediately.
        do {
            let model = makeModel()
            model.handleTransientEvent(chargingEvent)
            model.dismissPeek()
            expect(model.mode == .compact, "dismissPeek restores immediately")
            expect(model.activePeekEvent == nil, "dismissPeek clears event")
        }

        // Events during fileDrop are dropped.
        do {
            let model = makeModel()
            model.fileDropTargetChanged(true)
            expect(model.mode == .fileDrop, "fixture: fileDrop entered")
            model.handleTransientEvent(chargingEvent)
            expect(model.mode == .fileDrop, "event dropped during fileDrop")
            expect(model.activePeekEvent == nil, "no event stored during fileDrop")
        }

        // During focusTakeover: mode unchanged, event still published, auto-clears.
        do {
            let model = makeModel()
            model.triggerFocusTakeover(site: "example.com", appName: "Safari", targetApp: nil)
            expect(model.mode == .focusTakeover, "fixture: takeover entered")
            model.handleTransientEvent(chargingEvent)
            expect(model.mode == .focusTakeover, "mode preserved during takeover")
            expect(model.activePeekEvent == chargingEvent, "event published during takeover")
            expect(waitUntil { model.activePeekEvent == nil }, "event auto-clears during takeover")
            expect(model.mode == .focusTakeover, "takeover survives event clear")
        }

        // Focus takeover starting while peeking must not strand the notch in
        // .peek: it should capture the mode that was active before the peek
        // began, clear the peek state, and restore that mode on dismissal.
        do {
            let model = makeModel()
            model.handleTransientEvent(chargingEvent)
            expect(model.mode == .peek, "fixture: peek entered from compact")
            model.triggerFocusTakeover(site: "example.com", appName: "Safari", targetApp: nil)
            expect(model.mode == .focusTakeover, "takeover entered from peek")
            expect(model.activePeekEvent == nil, "peek event cleared when takeover starts from peek")
            model.dismissFocusTakeover()
            expect(model.mode == .compact, "takeover restores the pre-peek mode, not .peek")
            expect(
                !waitUntil(timeout: 0.2) { model.mode == .peek },
                "no stray peek timer resurrects peek mode after takeover ends"
            )
        }

        do {
            let model = makeModel()
            model.expand()
            model.handleTransientEvent(chargingEvent)
            expect(model.mode == .peek, "fixture: peek entered from expanded")
            model.triggerFocusTakeover(site: "example.com", appName: "Safari", targetApp: nil)
            model.dismissFocusTakeover()
            expect(model.mode == .expanded, "takeover restores expanded mode when peek began from expanded")
        }

        // Hover-out during an active peek must not force an immediate collapse
        // (peeks auto-dismiss on their own timer, mirroring iPhone semantics).
        do {
            let model = makeModel()
            model.expand()
            model.handleTransientEvent(chargingEvent)
            expect(model.mode == .peek, "fixture: peek entered from expanded")
            model.hoverChanged(false)
            expect(model.mode == .peek, "hover-out does not collapse an active peek")
            expect(model.activePeekEvent == chargingEvent, "hover-out leaves the peek event intact")
            expect(waitUntil { model.mode == .expanded }, "peek still auto-restores to expanded after hover-out")
        }

        // Tapping a screenshot peek expands the shelf.
        do {
            let model = makeModel()
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("peek-test-\(UUID().uuidString).png")
            FileManager.default.createFile(atPath: url.path, contents: Data([0x89]))
            defer { try? FileManager.default.removeItem(at: url) }
            model.handleTransientEvent(TransientEvent(kind: .screenshot(url: url)))
            model.peekTapped()
            expect(model.mode == .expanded, "screenshot tap expands")
            expect(model.selectedSection == .shelf, "screenshot tap selects shelf")
        }

        // Tapping a non-screenshot peek dismisses it.
        do {
            let model = makeModel()
            model.handleTransientEvent(chargingEvent)
            model.peekTapped()
            expect(model.mode == .compact, "charging tap dismisses")
        }

        if failures.isEmpty {
            print("AppModelPeekTests: all assertions passed")
        } else {
            print("AppModelPeekTests: \(failures.count) failure(s)")
            failures.forEach { print("  - \($0)") }
            exit(1)
        }
    }
}
