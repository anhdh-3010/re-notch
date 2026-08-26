# Transient Events (Peek) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Re:notch briefly expands ("peek") on system events — charger, AirPods, screenshot, Caps Lock — then restores its previous state, Dynamic Island style.

**Architecture:** Pluggable `TransientEventSource` implementations feed a `TransientEventService`, which forwards events to `AppModel.handleTransientEvent`. `AppModel` gains a `.peek` mode following the existing `modeBeforeFileDrop` restore idiom. A single `PeekView` renders two styles: `.wings` (horizontal growth) and `.droop` (Dynamic Island inflation).

**Tech Stack:** Swift 6 toolchain in Swift-5 language mode, SwiftUI, AppKit, IOKit.ps, IOBluetooth, CoreGraphics (TCC preflight), NSMetadataQuery, QuickLookThumbnailing.

**Spec:** `docs/superpowers/specs/2026-08-26-transient-events-design.md`

## Global Constraints

- Platform floor: macOS 13 (`platforms: [.macOS(.v13)]`); guard newer APIs with `#available`.
- Language mode: Swift 5 (`.swiftLanguageMode(.v5)`); test scripts compile with `-swift-version 5`.
- Tests are `@main` struct executables compiled by zsh scripts in `scripts/` (NO XCTest target exists). Follow `Tests/AppModelFileDropTests.swift` + `scripts/test-appmodel.sh` exactly.
- New `NotchSettings` fields MUST be optional with defaults (`var x: Bool? = true`) so old stored settings still decode; expose `resolvedX` accessors.
- All user-facing copy in English. Code comments in English.
- Never run `scripts/build-app.sh` partially: it must reach the codesign step (see repo memory — unsigned builds poison TCC).
- Commit after each task on branch `feat/transient-events`.

---

### Task 1: TransientEvent model + settings flags

**Files:**
- Create: `Sources/Renotch/Models/TransientEventModels.swift`
- Modify: `Sources/Renotch/Models/NotchModels.swift` (add `peek` case + settings fields)

**Interfaces:**
- Produces: `TransientEvent` (struct: `kind`, `presentationStyle`, `duration`), `TransientEventKind`, `PeekStyle`, `BluetoothBatteries`, `NotchMode.peek`, `NotchSettings.resolvedPeekChargingEnabled` (+ bluetooth/screenshot/capsLock/screenshotAutoAddToShelf variants), `PeekSourceKind`.

- [ ] **Step 1: Create the model file**

```swift
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
```

- [ ] **Step 2: Add `peek` to `NotchMode`**

In `Sources/Renotch/Models/NotchModels.swift`, extend the existing enum:

```swift
enum NotchMode: String, Codable {
    case compact
    case expanded
    case fileDrop
    case success
    case focusTakeover
    case peek
}
```

- [ ] **Step 3: Add settings fields + resolved accessors to `NotchSettings`**

In `NotchModels.swift`, inside `struct NotchSettings`, after the existing optional fields (follow the same "Optional so settings written by older app versions continue to decode" comment style):

```swift
    /// Optional so settings written before peek notifications still decode.
    var peekChargingEnabled: Bool? = true
    var peekBluetoothEnabled: Bool? = true
    var peekScreenshotEnabled: Bool? = true
    var peekCapsLockEnabled: Bool? = false
    var peekScreenshotAutoAddToShelf: Bool? = false
```

And alongside the existing `resolved*` computed properties:

```swift
    var resolvedPeekChargingEnabled: Bool { peekChargingEnabled ?? true }
    var resolvedPeekBluetoothEnabled: Bool { peekBluetoothEnabled ?? true }
    var resolvedPeekScreenshotEnabled: Bool { peekScreenshotEnabled ?? true }
    var resolvedPeekCapsLockEnabled: Bool { peekCapsLockEnabled ?? false }
    var resolvedPeekScreenshotAutoAddToShelf: Bool { peekScreenshotAutoAddToShelf ?? false }

    func isPeekSourceEnabled(_ kind: PeekSourceKind) -> Bool {
        switch kind {
        case .charging: return resolvedPeekChargingEnabled
        case .bluetooth: return resolvedPeekBluetoothEnabled
        case .screenshot: return resolvedPeekScreenshotEnabled
        case .capsLock: return resolvedPeekCapsLockEnabled
        }
    }
```

- [ ] **Step 4: Fix exhaustive switches broken by the new case**

Run: `swift build 2>&1 | grep -E 'error' | head -30`

Every `switch` over `NotchMode` now fails to compile. Fix each with these values (they mirror `.compact` until Task 4 refines the UI):

- `AppModel.isExpanded` (`State/AppModel.swift:~113`): add `.peek` to the `return true` branch (`case .expanded, .fileDrop, .success, .focusTakeover, .peek:`).
- `AppModel.currentSize`: add `case .peek: return NSSize(width: NotchSettings.dragWidth, height: NotchSettings.dragHeight)` (placeholder; Task 4 replaces it).
- Any other non-compiling switch (e.g. `NotchView` corner radii/shadows, `AppModel` guards listing modes): treat `.peek` like `.success` for now. Do NOT change behavior of existing cases.

- [ ] **Step 5: Verify build passes**

Run: `swift build 2>&1 | tail -3`
Expected: `Build complete!`

- [ ] **Step 6: Commit**

```bash
git checkout -b feat/transient-events
git add Sources/Renotch/Models/TransientEventModels.swift Sources/Renotch/Models/NotchModels.swift docs/superpowers/specs/2026-08-26-transient-events-design.md docs/superpowers/plans/2026-08-26-transient-events.md
git commit -m "feat: add TransientEvent model, peek mode, and peek settings flags"
```

---

### Task 2: AppModel peek state machine

**Files:**
- Modify: `Sources/Renotch/State/AppModel.swift`
- Create: `Tests/AppModelPeekTests.swift`
- Create: `scripts/test-peek.sh`
- Modify: `scripts/test-appmodel.sh`, `scripts/test.sh` (add `Sources/Renotch/Models/TransientEventModels.swift` to the compile list)

**Interfaces:**
- Consumes: `TransientEvent`, `NotchMode.peek` (Task 1).
- Produces: `AppModel.handleTransientEvent(_ event: TransientEvent)`, `AppModel.dismissPeek()`, `AppModel.peekTapped()`, `@Published private(set) var activePeekEvent: TransientEvent?`, `var peekDismissalDelayOverride: TimeInterval?` (test hook).

- [ ] **Step 1: Write the failing test**

Create `Tests/AppModelPeekTests.swift`, mirroring the structure of `Tests/AppModelFileDropTests.swift` (same `expect`/`waitUntil`/`makeDefaults` helpers, suite name `com.virtualnotch.tests.appmodel-peek`):

```swift
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
            model.presentFocusTakeover(site: "example.com", appName: "Safari", targetApp: nil)
            expect(model.mode == .focusTakeover, "fixture: takeover entered")
            model.handleTransientEvent(chargingEvent)
            expect(model.mode == .focusTakeover, "mode preserved during takeover")
            expect(model.activePeekEvent == chargingEvent, "event published during takeover")
            expect(waitUntil { model.activePeekEvent == nil }, "event auto-clears during takeover")
            expect(model.mode == .focusTakeover, "takeover survives event clear")
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
```

Note: check the real signature of `presentFocusTakeover` in `AppModel.swift` before writing the fixture call and match it exactly (the method exists around line 228; adjust argument labels if they differ).

- [ ] **Step 2: Create the test runner script**

Copy `scripts/test-appmodel.sh` to `scripts/test-peek.sh`; change the output binary to `.build/renotch-peek-tests`, replace `Tests/AppModelFileDropTests.swift` with `Tests/AppModelPeekTests.swift`, and add `Sources/Renotch/Models/TransientEventModels.swift` to the compile list. `chmod +x scripts/test-peek.sh`.

- [ ] **Step 3: Run test to verify it fails**

Run: `./scripts/test-peek.sh`
Expected: FAIL to compile — `AppModel` has no `handleTransientEvent` / `peekDismissalDelayOverride`.

- [ ] **Step 4: Implement the peek state machine in AppModel**

In `Sources/Renotch/State/AppModel.swift`:

Add published/state properties next to the existing ones:

```swift
    @Published private(set) var activePeekEvent: TransientEvent?

    /// Test hook: overrides each event's own duration when set.
    var peekDismissalDelayOverride: TimeInterval?

    private var peekWorkItem: DispatchWorkItem?
    private var modeBeforePeek: NotchMode = .compact
```

Add the methods (near `fileDropTargetChanged` to keep transient-mode logic together):

```swift
    /// Entry point for TransientEventService. Applies side effects that must
    /// happen regardless of presentation (shelf auto-add), then the
    /// iPhone-style presentation rules: latest event wins, short-lived drop
    /// modes swallow events, focus takeover shows a minimal strip only.
    func handleTransientEvent(_ event: TransientEvent) {
        if case let .screenshot(url) = event.kind,
           settings.resolvedPeekScreenshotAutoAddToShelf {
            shelf.add([url])
        }

        switch mode {
        case .fileDrop, .success:
            return
        case .focusTakeover:
            // Keep the takeover mode; FocusTakeoverView renders the event
            // as a one-line strip and we only auto-clear the event.
            activePeekEvent = event
            schedulePeekDismissal(after: peekDismissalDelayOverride ?? event.duration)
            return
        case .compact, .expanded, .peek:
            break
        }

        if mode != .peek {
            modeBeforePeek = mode
            mode = .peek
        }
        activePeekEvent = event
        onPanelConfigurationChanged?()
        schedulePeekDismissal(after: peekDismissalDelayOverride ?? event.duration)
    }

    func dismissPeek() {
        peekWorkItem?.cancel()
        peekWorkItem = nil
        guard activePeekEvent != nil else { return }
        activePeekEvent = nil
        guard mode == .peek else { return }
        mode = modeBeforePeek
        onPanelConfigurationChanged?()
    }

    /// Click action for the peek surface: screenshots open and reveal the
    /// shelf, everything else just collapses early.
    func peekTapped() {
        guard let event = activePeekEvent else { return }
        if case let .screenshot(url) = event.kind {
            dismissPeek()
            NSWorkspace.shared.open(url)
            expand(section: .shelf)
            return
        }
        dismissPeek()
    }

    private func schedulePeekDismissal(after delay: TimeInterval) {
        peekWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.dismissPeek()
        }
        peekWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }
```

Guard existing entry points against the new mode, matching how they treat `.success`:
- In `expand(...)`, before `mode = .expanded`, cancel any peek: add `peekWorkItem?.cancel(); activePeekEvent = nil` if mode is `.peek` (expanding from a peek is legal — the user clicked through).
- In `collapse(force:)` nothing changes (`guard mode != .compact` already covers it), but verify a running peek timer can't resurrect: `dismissPeek()` checks `mode == .peek` before touching mode, so a peek dismissed by other transitions only clears the event. Confirm this reasoning against the final code.
- In `closeFromOutsideClick()` add `.peek` to the excluded modes list.
- In `fileDropTargetChanged(true)` (drag begins while peeking): before `modeBeforeFileDrop = mode`, if `mode == .peek` first call `dismissPeek()` so fileDrop restores to the true underlying mode, not `.peek`.

- [ ] **Step 5: Run tests to verify they pass**

Run: `./scripts/test-peek.sh && ./scripts/test-appmodel.sh && ./scripts/test.sh`
Expected: all three PASS (remember to add `TransientEventModels.swift` to the other two scripts' compile lists first).

- [ ] **Step 6: Commit**

```bash
git add Sources/Renotch/State/AppModel.swift Tests/AppModelPeekTests.swift scripts/test-peek.sh scripts/test-appmodel.sh scripts/test.sh
git commit -m "feat: add peek state machine to AppModel with latest-wins and busy rules"
```

---

### Task 3: TransientEventSource protocol + TransientEventService

**Files:**
- Create: `Sources/Renotch/Services/TransientSources/TransientEventSource.swift`
- Create: `Sources/Renotch/Services/TransientEventService.swift`
- Modify: `Sources/Renotch/App/RenotchApp.swift` (own + wire the service)
- Create: `Tests/TransientEventServiceTests.swift`
- Create: `scripts/test-transient-service.sh`

**Interfaces:**
- Consumes: `AppModel.handleTransientEvent` (Task 2), `NotchSettings.isPeekSourceEnabled` (Task 1).
- Produces: `protocol TransientEventSource: AnyObject { func start(emit: @escaping (TransientEvent) -> Void); func stop() }`; `TransientEventService(appModel:sources:)` where `sources: [PeekSourceKind: TransientEventSource]`; `TransientEventService.applySettings(_ settings: NotchSettings)`. Later tasks register real sources in `RenotchApp.makeTransientSources()`.

- [ ] **Step 1: Write the failing test**

```swift
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
```

- [ ] **Step 2: Create runner script + verify the test fails**

Copy `scripts/test-peek.sh` to `scripts/test-transient-service.sh`; output binary `.build/renotch-transient-service-tests`; test file `Tests/TransientEventServiceTests.swift`; add `Sources/Renotch/Services/TransientEventService.swift` and `Sources/Renotch/Services/TransientSources/TransientEventSource.swift` to the compile list. Run it.
Expected: FAIL — types don't exist.

- [ ] **Step 3: Implement protocol and service**

```swift
// Sources/Renotch/Services/TransientSources/TransientEventSource.swift
import Foundation

/// A pluggable producer of transient peek events. Sources are inert until
/// start(emit:) and must be safe to start/stop repeatedly. Sources may emit
/// from any thread; TransientEventService hops to the main actor.
protocol TransientEventSource: AnyObject {
    func start(emit: @escaping (TransientEvent) -> Void)
    func stop()
}
```

```swift
// Sources/Renotch/Services/TransientEventService.swift
import Foundation

/// Owns the transient event sources, starting and stopping each according
/// to its Settings toggle, and forwards emitted events to the AppModel on
/// the main actor. Toggling a source off and on restarts it, which doubles
/// as a manual reset if a source silently dies.
@MainActor
final class TransientEventService {
    private weak var appModel: AppModel?
    private let sources: [PeekSourceKind: TransientEventSource]
    private var runningKinds: Set<PeekSourceKind> = []

    init(appModel: AppModel, sources: [PeekSourceKind: TransientEventSource]) {
        self.appModel = appModel
        self.sources = sources
    }

    func applySettings(_ settings: NotchSettings) {
        for (kind, source) in sources {
            let shouldRun = settings.isPeekSourceEnabled(kind)
            let isRunning = runningKinds.contains(kind)
            guard shouldRun != isRunning else { continue }
            if shouldRun {
                runningKinds.insert(kind)
                source.start { [weak self] event in
                    Task { @MainActor in
                        self?.appModel?.handleTransientEvent(event)
                    }
                }
            } else {
                runningKinds.remove(kind)
                source.stop()
            }
        }
    }

    func stopAll() {
        for kind in runningKinds { sources[kind]?.stop() }
        runningKinds.removeAll()
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `./scripts/test-transient-service.sh`
Expected: PASS

- [ ] **Step 5: Wire the service in RenotchApp**

Read `Sources/Renotch/App/RenotchApp.swift` first and follow its structure. Where the `AppModel` is created and retained, add:

```swift
    // Transient peek events (charger, AirPods, screenshots, Caps Lock).
    // Sources are registered here as they are implemented (Tasks 5-8).
    private static func makeTransientSources() -> [PeekSourceKind: TransientEventSource] {
        [:]
    }
```

Create the service after the model exists, keep a strong reference, apply current settings once, and re-apply whenever settings change:

```swift
    transientEvents = TransientEventService(
        appModel: model,
        sources: Self.makeTransientSources()
    )
    transientEvents?.applySettings(model.settings)
    settingsCancellable = model.$settings
        .sink { [weak transientEvents] settings in
            Task { @MainActor in transientEvents?.applySettings(settings) }
        }
```

(Adapt property placement — e.g. on the AppDelegate/controller object RenotchApp already uses for long-lived state; do not create a new global.)

- [ ] **Step 6: Full check + commit**

Run: `swift build 2>&1 | tail -3 && ./scripts/test-transient-service.sh && ./scripts/test-peek.sh`
Expected: build + both suites pass.

```bash
git add Sources/Renotch/Services/TransientSources/TransientEventSource.swift Sources/Renotch/Services/TransientEventService.swift Sources/Renotch/App/RenotchApp.swift Tests/TransientEventServiceTests.swift scripts/test-transient-service.sh
git commit -m "feat: add TransientEventService with per-source settings toggles"
```

---

### Task 4: PeekView UI + notch integration

**Files:**
- Create: `Sources/Renotch/UI/PeekView.swift`
- Modify: `Sources/Renotch/UI/NotchView.swift` (render `.peek`, corner radii, shadows, animation)
- Modify: `Sources/Renotch/State/AppModel.swift` (`currentSize` for `.peek`)
- Modify: `Sources/Renotch/Models/NotchGeometry.swift` (peek sizing constants)
- Modify: `Sources/Renotch/UI/FocusTakeoverView.swift` (minimal event strip)

**Interfaces:**
- Consumes: `TransientEvent`, `AppModel.activePeekEvent`, `AppModel.peekTapped()`, `NotchGeometry` helpers.
- Produces: `PeekView(event:)` SwiftUI view; `NotchGeometry.peekWingWidth`, `NotchGeometry.peekDroopSize(notch:)`.

- [ ] **Step 1: Add sizing constants to NotchGeometry**

Follow the existing constant style in `NotchGeometry.swift` (it already has `messageWingWidth`):

```swift
    /// Width of each wing when a wings-style peek is showing.
    static let peekWingWidth: CGFloat = 104

    /// Size of a droop-style peek: wider and taller than the physical notch,
    /// Dynamic Island-style. Falls back to virtual-notch defaults when no
    /// hardware notch metrics are available.
    static func peekDroopSize(notch: PhysicalNotchMetrics?) -> CGSize {
        let notchWidth = notch?.width ?? 200
        let notchHeight = notch?.height ?? 32
        return CGSize(
            width: max(notchWidth + 150, 340),
            height: notchHeight + 34
        )
    }
```

Check the real property names on `PhysicalNotchMetrics` before using `width`/`height` and adapt (read the struct in `NotchGeometry.swift` / `NotchModels.swift`).

- [ ] **Step 2: Implement `currentSize` for `.peek`**

Replace the Task 1 placeholder in `AppModel.currentSize`:

```swift
        case .peek:
            guard let event = activePeekEvent else {
                return NSSize(width: NotchSettings.dragWidth, height: NotchSettings.dragHeight)
            }
            switch event.presentationStyle {
            case .wings:
                let size = NotchGeometry.compactSize(
                    notch: notchMetrics,
                    wings: WingWidths(
                        left: NotchGeometry.peekWingWidth,
                        right: NotchGeometry.peekWingWidth
                    ),
                    leadingPadding: CGFloat(settings.resolvedCompactContentLeadingPadding),
                    trailingPadding: CGFloat(settings.resolvedCompactContentTrailingPadding)
                )
                return NSSize(width: size.width, height: size.height)
            case .droop:
                let size = NotchGeometry.peekDroopSize(notch: notchMetrics)
                return NSSize(width: size.width, height: size.height)
            }
```

Also verify `NotchWindowController.panelSize` (`Window/NotchWindowController.swift:143`) already exceeds both peek sizes (expanded width ≥ 440 > 340; compact max already includes message wings — compare against `peekWingWidth` and bump the `WingWidths` used there to `max(messageWingWidth, peekWingWidth)` if peek wings are wider).

- [ ] **Step 3: Create PeekView**

```swift
// Sources/Renotch/UI/PeekView.swift
import SwiftUI

/// Renders the transient peek content for both styles. Wings: icon on the
/// left wing, info on the right wing, physical notch untouched between
/// them. Droop: a single row below the menu bar line.
struct PeekView: View {
    @EnvironmentObject private var model: AppModel
    let event: TransientEvent

    var body: some View {
        Group {
            switch event.presentationStyle {
            case .wings: wingsLayout
            case .droop: droopLayout
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { model.peekTapped() }
    }

    private var wingsLayout: some View {
        HStack {
            leadingContent
                .frame(width: NotchGeometry.peekWingWidth, alignment: .leading)
            Spacer(minLength: 0)
            trailingContent
                .frame(width: NotchGeometry.peekWingWidth, alignment: .trailing)
        }
        .padding(.horizontal, CGFloat(model.settings.resolvedCompactContentLeadingPadding))
        .font(.system(size: 12, weight: .semibold))
    }

    private var droopLayout: some View {
        HStack(spacing: 10) {
            leadingContent
            Spacer(minLength: 0)
            trailingContent
        }
        .padding(.horizontal, 18)
        .padding(.top, (model.notchMetrics?.height ?? 0))
        .font(.system(size: 13, weight: .semibold))
        .frame(maxHeight: .infinity)
    }

    @ViewBuilder private var leadingContent: some View {
        switch event.kind {
        case let .charging(plugged, _):
            Image(systemName: plugged ? "bolt.fill" : "bolt.slash.fill")
                .foregroundStyle(plugged ? Color.green : Color.secondary)
        case .batteryLow:
            Image(systemName: "battery.25")
                .foregroundStyle(Color.red)
        case let .bluetooth(name, connected, _):
            Label(name, systemImage: connected ? "airpods" : "airpods.chargingcase")
                .labelStyle(.titleAndIcon)
                .lineLimit(1)
        case let .screenshot(url):
            ScreenshotThumbnail(url: url)
        case .capsLock:
            EmptyView()
        }
    }

    @ViewBuilder private var trailingContent: some View {
        switch event.kind {
        case let .charging(plugged, percent):
            Text("\(percent)%")
                .foregroundStyle(plugged ? Color.green : Color.primary)
        case let .batteryLow(percent):
            Text("\(percent)%").foregroundStyle(Color.red)
        case let .bluetooth(_, connected, batteries):
            if connected, let batteries, batteries.hasAnyReading {
                HStack(spacing: 6) {
                    if let left = batteries.left { batteryBadge("L", left) }
                    if let right = batteries.right { batteryBadge("R", right) }
                    if let c = batteries.caseBattery { batteryBadge("C", c) }
                }
            } else {
                Text(connected ? "Connected" : "Disconnected")
                    .foregroundStyle(.secondary)
            }
        case let .screenshot(url):
            Text(url.lastPathComponent)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(.secondary)
        case let .capsLock(on):
            Label(on ? "Caps Lock On" : "Caps Lock Off", systemImage: "capslock.fill")
                .foregroundStyle(on ? Color.yellow : Color.secondary)
        }
    }

    private func batteryBadge(_ label: String, _ percent: Int) -> some View {
        HStack(spacing: 2) {
            Text(label).foregroundStyle(.secondary)
            Text("\(percent)%")
        }
        .font(.system(size: 11, weight: .semibold))
    }
}

/// Async QuickLook thumbnail with a generic-image fallback.
private struct ScreenshotThumbnail: View {
    let url: URL
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 34, height: 24)
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .task {
            image = await Self.thumbnail(for: url)
        }
        .draggable(url)
    }

    static func thumbnail(for url: URL) async -> NSImage? {
        // QLThumbnailGenerator import: QuickLookThumbnailing
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: 68, height: 48),
            scale: 2,
            representationTypes: .thumbnail
        )
        let generated = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request)
        return generated?.nsImage
    }
}
```

Add `import QuickLookThumbnailing` at the top. If `.draggable(url)` is unavailable on macOS 13, use `.onDrag { NSItemProvider(object: url as NSURL) }` instead — check with a build.

- [ ] **Step 4: Integrate `.peek` into NotchView**

In `Sources/Renotch/UI/NotchView.swift`:
- `topCornerRadius`: `.peek` → wings: same as `.compact` value; droop: `18`. Implement with `case .peek: return model.activePeekEvent?.presentationStyle == .droop ? 18 : CGFloat(model.settings.resolvedCompactCornerRadius)`.
- `bottomCornerRadius`: wings → compact value, droop → `22`.
- `shadowOpacity`: `case .peek: return 0.34`; `shadowRadius`: `case .peek: return 12` (between compact-hover and expanded).
- `containerAnimation`: `case .peek: return .spring(response: 0.45, dampingFraction: 0.65)` (Dynamic Island-style bounce; Reduce Motion already returns nil above the switch).
- `notchContent` switch: `case .peek:` render

```swift
            case .peek:
                if let event = model.activePeekEvent {
                    PeekView(event: event)
                        .transition(contentTransition)
                } else {
                    EmptyView()
                }
```

- [ ] **Step 5: Add the minimal strip to FocusTakeoverView**

Read `Sources/Renotch/UI/FocusTakeoverView.swift`; it already receives data via init parameters. Simplest consistent change: in `NotchView.body` where `FocusTakeoverView` is created, overlay the strip so FocusTakeoverView itself stays untouched:

```swift
                FocusTakeoverView(
                    timer: model.timer,
                    site: model.focusTakeoverSite,
                    appName: model.focusTakeoverAppName
                )
                .overlay(alignment: .top) {
                    if let event = model.activePeekEvent {
                        PeekView(event: event)
                            .frame(height: 30)
                            .padding(.top, 6)
                            .transition(.opacity)
                    }
                }
                .transition(.opacity)
```

- [ ] **Step 6: Build, run all suites, visual smoke**

Run: `swift build 2>&1 | tail -3 && ./scripts/test-peek.sh && ./scripts/test-appmodel.sh && ./scripts/test.sh && ./scripts/test-transient-service.sh`
Expected: all pass. (Real visual verification happens in Task 10 once sources exist.)

- [ ] **Step 7: Commit**

```bash
git add Sources/Renotch/UI/PeekView.swift Sources/Renotch/UI/NotchView.swift Sources/Renotch/State/AppModel.swift Sources/Renotch/Models/NotchGeometry.swift
git commit -m "feat: render peek events with wings and droop styles"
```

---

### Task 5: PowerEventSource

**Files:**
- Create: `Sources/Renotch/Services/TransientSources/PowerEventSource.swift`
- Modify: `Sources/Renotch/App/RenotchApp.swift` (register in `makeTransientSources`)

**Interfaces:**
- Consumes: `TransientEventSource` protocol, `TransientEvent`.
- Produces: `.charging(plugged:percent:)` on power source change; `.batteryLow(percent:)` at 20%/10%, each once per discharge cycle.

- [ ] **Step 1: Implement the source**

```swift
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
```

Note: desktops without a battery return `nil` from `readState()` — the source then never emits, which is the correct behavior.

- [ ] **Step 2: Register it**

In `RenotchApp.makeTransientSources()`:

```swift
        [.charging: PowerEventSource()]
```

- [ ] **Step 3: Build + manual verification**

Run: `swift build 2>&1 | tail -3` — expected `Build complete!`.
Manual (recorded in Task 10 checklist, executed there): unplug/replug the charger → wings peek with ⚡ and percent.

- [ ] **Step 4: Commit**

```bash
git add Sources/Renotch/Services/TransientSources/PowerEventSource.swift Sources/Renotch/App/RenotchApp.swift
git commit -m "feat: emit charger and low-battery peek events via IOKit"
```

---

### Task 6: BluetoothEventSource

**Files:**
- Create: `Sources/Renotch/Services/TransientSources/BluetoothEventSource.swift`
- Modify: `Sources/Renotch/App/RenotchApp.swift` (register)
- Modify: `scripts/test-peek.sh`, `scripts/test-appmodel.sh`, `scripts/test.sh`, `scripts/test-transient-service.sh` — only if compiling AppModel now pulls in IOBluetooth (it should not; sources are only referenced from RenotchApp. Verify and leave scripts untouched if so.)

**Interfaces:**
- Consumes: `TransientEventSource`, `TransientEvent`, `BluetoothBatteries`.
- Produces: `.bluetooth(name:connected:batteries:)` on audio-device connect/disconnect.

- [ ] **Step 1: Implement the source**

```swift
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
```

Note: `kIOMainPortDefault` requires macOS 12+; fine under the macOS 13 floor. If `BluetoothDeviceClassMajor(...)` comparison fails to compile, compare raw values: `device.deviceClassMajor == UInt32(kBluetoothDeviceClassMajorAudio.rawValue)` — adjust to whatever the SDK expects.

- [ ] **Step 2: Register + build**

Add `.bluetooth: BluetoothEventSource()` to `makeTransientSources()`.
Run: `swift build 2>&1 | tail -3` — expected `Build complete!`. Also run `./scripts/test.sh` to confirm the smoke compile list doesn't need IOBluetooth (RenotchApp.swift isn't in the smoke compile list; if it is, add `-framework IOBluetooth`).

- [ ] **Step 3: Commit**

```bash
git add Sources/Renotch/Services/TransientSources/BluetoothEventSource.swift Sources/Renotch/App/RenotchApp.swift
git commit -m "feat: emit Bluetooth audio connect/disconnect peek events"
```

---

### Task 7: ScreenshotEventSource

**Files:**
- Create: `Sources/Renotch/Services/TransientSources/ScreenshotEventSource.swift`
- Modify: `Sources/Renotch/App/RenotchApp.swift` (register)

**Interfaces:**
- Consumes: `TransientEventSource`, `TransientEvent`.
- Produces: `.screenshot(url:)` for each new screenshot file.

- [ ] **Step 1: Implement the source**

```swift
// Sources/Renotch/Services/TransientSources/ScreenshotEventSource.swift
import AppKit
import Foundation

/// Watches Spotlight metadata for new screenshot files
/// (kMDItemIsScreenCapture). No screen-recording permission needed.
final class ScreenshotEventSource: TransientEventSource {
    private var query: NSMetadataQuery?
    private var emit: ((TransientEvent) -> Void)?
    private var observer: NSObjectProtocol?
    private var startedAt = Date()
    private var seenPaths: Set<String> = []

    func start(emit: @escaping (TransientEvent) -> Void) {
        stop()
        self.emit = emit
        startedAt = Date()

        let query = NSMetadataQuery()
        query.predicate = NSPredicate(format: "kMDItemIsScreenCapture == 1")
        query.searchScopes = [NSMetadataQueryUserHomeScope]
        self.query = query

        observer = NotificationCenter.default.addObserver(
            forName: .NSMetadataQueryDidUpdate,
            object: query,
            queue: .main
        ) { [weak self] notification in
            let added = notification.userInfo?[NSMetadataQueryUpdateAddedItemsKey]
                as? [NSMetadataItem] ?? []
            self?.handleAdded(added)
        }
        query.start()
    }

    func stop() {
        query?.stop()
        query = nil
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        emit = nil
        seenPaths.removeAll()
    }

    private func handleAdded(_ items: [NSMetadataItem]) {
        for item in items {
            guard let path = item.value(forAttribute: NSMetadataItemPathKey) as? String,
                  !seenPaths.contains(path) else { continue }
            let created = item.value(forAttribute: NSMetadataItemFSCreationDateKey) as? Date
            // Ignore pre-existing screenshots indexed at query start.
            guard let created, created > startedAt else { continue }
            seenPaths.insert(path)

            let url = URL(fileURLWithPath: path)
            // The floating macOS preview can delete the file moments later;
            // only peek if it still exists when we fire.
            guard FileManager.default.fileExists(atPath: path) else { continue }
            emit?(TransientEvent(kind: .screenshot(url: url)))
        }
    }
}
```

- [ ] **Step 2: Register + build**

Add `.screenshot: ScreenshotEventSource()` to `makeTransientSources()`.
Run: `swift build 2>&1 | tail -3` — expected `Build complete!`.

- [ ] **Step 3: Commit**

```bash
git add Sources/Renotch/Services/TransientSources/ScreenshotEventSource.swift Sources/Renotch/App/RenotchApp.swift
git commit -m "feat: emit screenshot peek events via Spotlight metadata"
```

---

### Task 8: CapsLockEventSource

**Files:**
- Create: `Sources/Renotch/Services/TransientSources/CapsLockEventSource.swift`
- Modify: `Sources/Renotch/App/RenotchApp.swift` (register)

**Interfaces:**
- Consumes: `TransientEventSource`, `TransientEvent`.
- Produces: `.capsLock(on:)` on toggle; `static CapsLockEventSource.hasListenPermission: Bool` and `static requestListenPermission()` used by the Settings UI (Task 9).

- [ ] **Step 1: Implement the source**

```swift
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
```

- [ ] **Step 2: Register + build**

Add `.capsLock: CapsLockEventSource()` to `makeTransientSources()`.
Run: `swift build 2>&1 | tail -3` — expected `Build complete!`.

- [ ] **Step 3: Commit**

```bash
git add Sources/Renotch/Services/TransientSources/CapsLockEventSource.swift Sources/Renotch/App/RenotchApp.swift
git commit -m "feat: emit Caps Lock peek events behind Input Monitoring permission"
```

---

### Task 9: Settings UI for peek toggles

**Files:**
- Modify: `Sources/Renotch/UI/SettingsView.swift`

**Interfaces:**
- Consumes: `NotchSettings` peek fields (Task 1), `CapsLockEventSource.hasListenPermission` / `requestListenPermission()` (Task 8).

- [ ] **Step 1: Read SettingsView and add a "Peek Notifications" section**

Read `Sources/Renotch/UI/SettingsView.swift` first; replicate the exact section/Toggle style it already uses (it binds to `model.settings.x` via `$model.settings`). Add a section with this content (adapt container syntax to the file's idiom):

```swift
    // Peek Notifications
    Toggle("Charger & battery", isOn: Binding(
        get: { model.settings.resolvedPeekChargingEnabled },
        set: { model.settings.peekChargingEnabled = $0 }
    ))
    Toggle("Bluetooth audio devices", isOn: Binding(
        get: { model.settings.resolvedPeekBluetoothEnabled },
        set: { model.settings.peekBluetoothEnabled = $0 }
    ))
    Toggle("Screenshots", isOn: Binding(
        get: { model.settings.resolvedPeekScreenshotEnabled },
        set: { model.settings.peekScreenshotEnabled = $0 }
    ))
    Toggle("Add screenshots to File Shelf", isOn: Binding(
        get: { model.settings.resolvedPeekScreenshotAutoAddToShelf },
        set: { model.settings.peekScreenshotAutoAddToShelf = $0 }
    ))
    .disabled(!model.settings.resolvedPeekScreenshotEnabled)
    Toggle("Caps Lock", isOn: Binding(
        get: { model.settings.resolvedPeekCapsLockEnabled },
        set: { enabled in
            if enabled && !CapsLockEventSource.hasListenPermission {
                CapsLockEventSource.requestListenPermission()
                // Permission not granted synchronously — leave the toggle
                // off; the user re-enables after granting.
                if !CapsLockEventSource.hasListenPermission {
                    model.settings.peekCapsLockEnabled = false
                    return
                }
            }
            model.settings.peekCapsLockEnabled = enabled
        }
    ))
    if model.settings.resolvedPeekCapsLockEnabled == false && !CapsLockEventSource.hasListenPermission {
        Button("Open System Settings…") {
            NSWorkspace.shared.open(URL(
                string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
            )!)
        }
        .font(.caption)
    }
```

Match the Calendar permission section's existing copy/style for the fallback button (search `SettingsView.swift` for the Calendar "System Settings" link and reuse its wording and modifiers).

- [ ] **Step 2: Build + all suites**

Run: `swift build 2>&1 | tail -3 && ./scripts/test-peek.sh && ./scripts/test-appmodel.sh && ./scripts/test-transient-service.sh && ./scripts/test.sh`
Expected: all pass.

- [ ] **Step 3: Commit**

```bash
git add Sources/Renotch/UI/SettingsView.swift
git commit -m "feat: add peek notification toggles to Settings"
```

---

### Task 10: Integration build + manual verification

**Files:**
- None created; runs the real app.

- [ ] **Step 1: Build and install the signed app**

```bash
./scripts/build-app.sh
codesign -dvv dist/Re:notch.app 2>&1 | grep -E 'Authority|Signature'   # must NOT be adhoc
pkill -f "Re:notch.app/Contents/MacOS/Renotch" || true
ditto dist/Re:notch.app /Applications/Re:notch.app
open "/Applications/Re:notch.app"
```

- [ ] **Step 2: Manual checklist (requires the user at the machine)**

Ask the user to verify and report:
1. Unplug charger → wings peek "⚡ n%" appears ~2.5s, notch returns to previous state. Replug → same with green bolt.
2. Open the dashboard (expanded), unplug charger → peek shows, then returns to the *expanded* dashboard.
3. Connect AirPods → droop peek with name (+ L/R/case battery if available).
4. Press ⌘⇧3 → droop peek with screenshot thumbnail; click it → image opens and shelf section expands.
5. Enable Caps Lock toggle in Settings → Input Monitoring prompt appears once; after granting and re-enabling, Caps Lock key shows the wings indicator.
6. Toggle each peek type off in Settings → that event type stops appearing.
7. With Reduce Motion enabled (System Settings → Accessibility), peeks fade without spring.

- [ ] **Step 3: Fix anything the checklist surfaces, re-run suites, final commit**

Run: `./scripts/test-peek.sh && ./scripts/test-appmodel.sh && ./scripts/test-transient-service.sh && ./scripts/test.sh`

```bash
git add -A
git commit -m "feat: transient peek events — integration fixes from manual verification"
```
