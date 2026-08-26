# Transient Events (Dynamic Island-style Peek) — Design

Date: 2026-08-26
Status: Approved for planning

## Goal

Re:notch briefly expands ("peeks") when a system event occurs — charger
plugged, AirPods connected, screenshot taken, Caps Lock toggled — then
collapses back to its previous state, mirroring iPhone Dynamic Island
behavior. This is sub-project 1 of the "experience & effects" track; the
peek presentation layer it introduces will later be reused by the HUD
replacement sub-project.

## Behavior Model (iPhone semantics)

- A new event **takes over immediately**, replacing any peek currently
  showing (latest wins; no queue).
- When the peek's duration elapses, the notch **restores its previous
  state** (compact or expanded dashboard, including pinned state).
- During `focusTakeover`, the mode does not change: `activePeekEvent` is
  rendered as a small one-line strip inside the takeover view (icon +
  short text, wings-equivalent for every event kind) and auto-clears
  after its duration. Hardware events still surface, as on iPhone during
  Focus, without disturbing the takeover.
- During `fileDrop`/`success`, events are dropped (short-lived modes;
  restore complexity not worth it). A screenshot event still adds to the
  Shelf when auto-add is enabled.
- Clicking a peek performs its action: screenshot → open image /
  `expand(section: .shelf)`; others → collapse the peek.
- Dragging a screenshot peek drags the real file (reuses Shelf drag).

## Architecture

```
PowerEventSource ──┐
BluetoothEventSource ─┤                         ┌→ AppModel.presentPeek(event)
ScreenshotEventSource ┼→ TransientEventService ─┤    mode = .peek, auto-dismiss timer
CapsLockEventSource ──┘  (merge + busy rules)   └→ restores previous mode
                                                      ↓
                                              PeekView (renders by event.kind)
```

### New units

**`TransientEvent`** (Models/TransientEventModels.swift)
- `kind`: `.charging(plugged: Bool, percent: Int)`, `.batteryLow(percent: Int)`,
  `.bluetooth(name: String, connected: Bool, batteries: BluetoothBatteries?)`,
  `.screenshot(url: URL)`, `.capsLock(on: Bool)`
- `presentationStyle: PeekStyle` (derived from kind): `.wings` or `.droop`
- `duration: TimeInterval` (derived from kind; see table below)

**`TransientEventSource`** (protocol, Services/TransientSources/)
- `func start(emit: @escaping (TransientEvent) -> Void)` / `func stop()`
- Sources know nothing about UI. One file per source.

**`TransientEventService`** (Services/TransientEventService.swift)
- Owns the sources; starts/stops each according to its Settings toggle.
- Hops events to the main actor and forwards to `AppModel`.
- Applies busy rules (focusTakeover → minimal; fileDrop/success → drop).

**`AppModel` changes** (State/AppModel.swift)
- `NotchMode` gains `case peek`.
- `@Published private(set) var activePeekEvent: TransientEvent?`
- `modeBeforePeek` + `peekWorkItem`, following the existing
  `modeBeforeFileDrop` idiom exactly.
- `presentPeek(_:)`: cancels any running peek timer, stores the previous
  mode (only when not already peeking), sets `.peek`, schedules dismiss.
- `dismissPeek()`: restores `modeBeforePeek`, clears state, fires
  `onPanelConfigurationChanged`.
- Peek tap handler: screenshot → `NSWorkspace.open` + optional
  `expand(section: .shelf)`; others → `dismissPeek()`.

**`PeekView`** (UI/PeekView.swift)
- Single view, `switch event.kind` → layout. Uses `NotchGeometry` to wrap
  the physical notch. Two sub-layouts:
  - `.wings`: height unchanged, symmetric horizontal growth; icon left,
    info right.
  - `.droop`: width and height grow below the menu bar with
    `interpolatingSpring` bounce.
- Honors Reduce Motion: fade only, no size spring.

### Event → presentation mapping

| Event | Style | Duration | Content |
|---|---|---|---|
| Charger plug/unplug | wings | 2.5s | ⚡ + battery %, green/normal |
| Battery low (20%/10%) | wings | 3s | battery % in red |
| Caps Lock | wings | 1.2s | ⇪ dot on right wing |
| Bluetooth/AirPods | droop | 3s | device name + L/R/case battery |
| Screenshot | droop | 3s | thumbnail + filename |

Droop arriving over wings replaces it (latest wins).

## Event sources

**`PowerEventSource`** — `IOPSNotificationCreateRunLoopSource` (IOKit.ps);
on change read `IOPSCopyPowerSourcesInfo` → plugged state + percent. Low
battery thresholds 20%/10%, each fires once until next charge. No
permissions required.

**`BluetoothEventSource`** — `IOBluetoothDevice.register(forConnectNotifications:)`
plus per-device disconnect notifications; filter to audio major class.
AirPods battery via Apple-specific IORegistry keys
(`BatteryPercentLeft/Right/Case`) — best-effort; when absent, show name
only (no "--%" placeholders). No TCC prompt.

**`ScreenshotEventSource`** — `NSMetadataQuery` on
`kMDItemIsScreenCapture == 1` (no screen-recording permission). New file →
verify it still exists (macOS floating preview may delete it), generate
thumbnail via `QLThumbnailGenerator` (fallback: generic image icon), emit.
Optional "auto-add to Shelf" setting, default **off**.

**`CapsLockEventSource`** — `NSEvent.addGlobalMonitorForEvents(.flagsChanged)`,
read `.capsLock` flag. Requires **Input Monitoring** TCC; the feature is
default **off**, permission requested only when the user enables the
toggle. If denied, the toggle flips back off and Settings shows an "Open
System Settings" link (same pattern as Calendar). Never re-prompts at
launch.

### Settings

`SettingsStore` gains four flags:
`peekChargingEnabled` (default on), `peekBluetoothEnabled` (on),
`peekScreenshotEnabled` (on), `peekCapsLockEnabled` (**off**), plus
`peekScreenshotAutoAddToShelf` (off). Toggling off→on restarts the source
(doubles as a manual reset if a source silently dies — accepted limitation,
no active health-check).

## Edge cases

- Multi-display: peek shows only on the active notch screen (existing
  `ScreenManager` behavior); never duplicated.
- No physical notch: works on the virtual notch like existing features.
- Machines without Bluetooth: source fails to start gracefully; no crash.

## Testing

- **`AppModelPeekTests`** (XCTest, alongside `AppModelFileDropTests`):
  present from compact → `.peek` → auto-restore to compact; present from
  expanded → restore to expanded (incl. pinned); replacement resets timer;
  focusTakeover → minimal path; fileDrop → dropped; screenshot tap →
  shelf expansion.
- **`TransientEventServiceTests`**: mock `TransientEventSource` → events
  forwarded on main actor; disabled toggle → source never started;
  latest-wins replacement.
- **Real sources**: hardware-dependent, covered by a manual checklist in
  the implementation plan (plug/unplug, AirPods, screenshot, Caps Lock).
- **Smoke**: service initialization crashes on no-Bluetooth/no-notch
  machines are covered by existing smoke test target.

## Out of scope (YAGNI)

- Event queue/history UI, notification-center features.
- Volume/brightness HUD (sub-project 2; will reuse `.peek`).
- Music ambient effects and gestures (sub-projects 3–4).
- Active health-checking of silently-dead event sources.
