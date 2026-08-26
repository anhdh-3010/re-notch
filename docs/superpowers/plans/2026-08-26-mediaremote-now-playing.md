# MediaRemote Now-Playing Fallback Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show any system now-playing media (Spotify web in Chrome, SoundCloud, etc.) in the music tab as a pure fallback behind the AppleScript sources, with play/pause/next/prev/seek controls.

**Architecture:** A new `MediaRemoteNowPlayingService` spawns the bundled `mediaremote-adapter` in `stream --micros --debounce=150` mode and diff-merges its JSON lines into a published snapshot. Pure logic (diff merge, snapshot mapping, fallback arbitration) lives in a new Models file with its own test binary. `AppModel` arbitrates `.local` vs `.remote` for the music tab; `MusicPlayerView` gains a degraded remote layout (variant A: left control pill ⏮ ⏯ ⏭, source badge replaces the volume slider).

**Tech Stack:** Swift 5 mode / SwiftPM, AppKit + SwiftUI, bundled perl `mediaremote-adapter` (Vendor/mediaremote-adapter), zsh test scripts compiling standalone `@main` test binaries.

**Spec:** `docs/superpowers/specs/2026-08-26-mediaremote-now-playing-design.md`

## Global Constraints

- macOS 13 floor (`Package.swift` platforms), Swift language mode v5.
- No new dependencies; only the already-vendored adapter.
- Tests are standalone `@main` binaries compiled by zsh scripts in `scripts/`, run via `scripts/test.sh` (see `scripts/test-mediaremote.sh` for the pattern). No XCTest.
- Adapter contract (Vendor/mediaremote-adapter/README.md): stream lines are `{"type":"data","diff":Bool,"payload":{…}}`; with `--micros` the payload uses `durationMicros`, `elapsedTimeMicros`, `timestampEpochMicros` (all numbers), plus `bundleIdentifier`, `playing`, `title`, `artist`, `album`, `artworkData` (base64 string), `artworkMimeType`. `diff:false` payload replaces all state; `diff:true` updates keys, `null` removes a key.
- `send` command IDs: play/pause toggle `2`, next `4`, previous `5`. `seek POSITION` takes positive integer microseconds.
- Excluded bundle IDs for the remote fallback: `com.apple.Music`, `com.spotify.client`.

---

### Task 1: MediaRemoteCommandService — previousTrack and seek

**Files:**
- Modify: `Sources/Renotch/Services/MediaRemoteCommandService.swift`
- Test: `Tests/MediaRemoteCommandServiceTests.swift`

**Interfaces:**
- Consumes: existing `MediaRemoteCommandService` (`Command` enum, `ProcessRunner` seam).
- Produces: `Command.previousTrack` (rawValue `"5"`), `func seek(to seconds: TimeInterval)` invoking `/usr/bin/perl [script, framework, "seek", "<micros>"]`. Task 5 calls both.

- [ ] **Step 1: Write the failing tests**

In `Tests/MediaRemoteCommandServiceTests.swift`, after the `nextTrack` assertions (line 57), add:

```swift
        available.send(.previousTrack)
        expect(invocations.count == 3, "previousTrack invokes runner once")
        if let call = invocations.last {
            expect(
                call.1 == [scriptURL.path, frameworkURL.path, "send", "5"],
                "previousTrack passes script, framework, send, 5"
            )
        }

        available.seek(to: 83.4)
        expect(invocations.count == 4, "seek invokes runner once")
        if let call = invocations.last {
            expect(
                call.1 == [scriptURL.path, frameworkURL.path, "seek", "83400000"],
                "seek passes whole microseconds"
            )
        }

        available.seek(to: -5)
        expect(invocations.count == 5, "negative seek clamps instead of skipping")
        if let call = invocations.last {
            expect(
                call.1 == [scriptURL.path, frameworkURL.path, "seek", "0"],
                "negative seek clamps to zero (adapter requires positive integer)"
            )
        }

        missingFramework.seek(to: 10)
        expect(missingFrameworkCalls == 0, "seek does not invoke runner when unavailable")
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `scripts/test-mediaremote.sh`
Expected: compile error — `previousTrack` and `seek` do not exist.

- [ ] **Step 3: Implement**

In `MediaRemoteCommandService.swift`, extend the enum and add `seek`:

```swift
    enum Command: String {
        case togglePlayPause = "2"
        case nextTrack = "4"
        case previousTrack = "5"
    }
```

```swift
    /// Seeks the now-playing app. The adapter's `seek` subcommand takes a
    /// positive integer position in microseconds.
    func seek(to seconds: TimeInterval) {
        guard let scriptURL, let frameworkURL else { return }
        let micros = max(0, Int((seconds * 1_000_000).rounded()))
        runner("/usr/bin/perl", [scriptURL.path, frameworkURL.path, "seek", String(micros)])
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `scripts/test-mediaremote.sh`
Expected: `MediaRemoteCommandServiceTests: all assertions passed`

- [ ] **Step 5: Commit**

```bash
git add Sources/Renotch/Services/MediaRemoteCommandService.swift Tests/MediaRemoteCommandServiceTests.swift
git commit -m "feat: add previousTrack and seek to MediaRemoteCommandService"
```

---

### Task 2: Now-playing models — snapshot, diff accumulator, fallback arbitrator

**Files:**
- Create: `Sources/Renotch/Models/MediaRemoteNowPlayingModels.swift`
- Create: `Tests/MediaRemoteNowPlayingTests.swift`
- Create: `scripts/test-nowplaying.sh`
- Modify: `scripts/test.sh` (add the new script at the end)

**Interfaces:**
- Consumes: `Comparable.clamped(to:)` (defined in `Sources/Renotch/Models/NotchModels.swift`).
- Produces (Tasks 3–5 rely on these exact names):
  - `struct MediaRemoteNowPlayingSnapshot: Equatable` with `bundleIdentifier, title, artist, album: String`, `duration, elapsedTime: TimeInterval`, `timestamp: Date`, `isPlaying: Bool`, `artworkData: Data?`, `func position(at now: Date) -> TimeInterval`.
  - `struct MediaRemoteStreamAccumulator` with `mutating func ingest(line: Data) -> MediaRemoteNowPlayingSnapshot??` — returns `nil` for ignored/malformed lines, `.some(nil)` when state became invalid (no title), `.some(snapshot)` on a valid update.
  - `enum MusicTabContent: Equatable { case local; case remote(MediaRemoteNowPlayingSnapshot) }`
  - `enum MusicTabArbitrator { static func resolve(musicIsPlaying: Bool, browserIsPlaying: Bool, remote: MediaRemoteNowPlayingSnapshot?) -> MusicTabContent }`

- [ ] **Step 1: Write the failing tests**

Create `Tests/MediaRemoteNowPlayingTests.swift`:

```swift
// Tests/MediaRemoteNowPlayingTests.swift
import Foundation

/// Covers the pure MediaRemote stream logic: diff/full payload merging,
/// snapshot mapping from --micros keys, position extrapolation, and the
/// music-tab fallback arbitration.
@main
struct MediaRemoteNowPlayingTests {
    static func line(_ object: [String: Any]) -> Data {
        try! JSONSerialization.data(withJSONObject: object)
    }

    static func main() {
        var failures: [String] = []
        func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
            if !condition() { failures.append(message) }
        }

        var acc = MediaRemoteStreamAccumulator()

        // Full payload (diff:false) replaces state and maps micros keys.
        let full = line([
            "type": "data", "diff": false,
            "payload": [
                "bundleIdentifier": "com.google.Chrome",
                "playing": true,
                "title": "Chăm Hoa",
                "artist": "Mono",
                "album": "Đẹp",
                "durationMicros": 232_000_000,
                "elapsedTimeMicros": 47_000_000,
                "timestampEpochMicros": 1_700_000_000_000_000
            ]
        ])
        guard case .some(.some(let snapshot)) = acc.ingest(line: full) else {
            print("MediaRemoteNowPlayingTests: full payload did not produce a snapshot")
            exit(1)
        }
        expect(snapshot.bundleIdentifier == "com.google.Chrome", "bundle id mapped")
        expect(snapshot.title == "Chăm Hoa", "title mapped")
        expect(snapshot.isPlaying, "playing mapped")
        expect(abs(snapshot.duration - 232) < 0.001, "duration micros converted to seconds")
        expect(abs(snapshot.elapsedTime - 47) < 0.001, "elapsed micros converted to seconds")
        expect(
            abs(snapshot.timestamp.timeIntervalSince1970 - 1_700_000_000) < 0.001,
            "timestamp epoch micros converted to Date"
        )
        expect(snapshot.artworkData == nil, "no artwork key -> nil data")

        // Position extrapolates while playing, clamps to duration.
        let now = snapshot.timestamp.addingTimeInterval(10)
        expect(abs(snapshot.position(at: now) - 57) < 0.001, "position extrapolates elapsed + delta")
        let far = snapshot.timestamp.addingTimeInterval(10_000)
        expect(snapshot.position(at: far) == 232, "position clamps to duration")

        // Diff payload updates only provided keys; artwork decodes from base64.
        let artworkBytes = Data([0x89, 0x50, 0x4E, 0x47])
        let diff = line([
            "type": "data", "diff": true,
            "payload": [
                "playing": false,
                "elapsedTimeMicros": 50_000_000,
                "artworkData": artworkBytes.base64EncodedString()
            ]
        ])
        guard case .some(.some(let updated)) = acc.ingest(line: diff) else {
            print("MediaRemoteNowPlayingTests: diff payload did not produce a snapshot")
            exit(1)
        }
        expect(updated.title == "Chăm Hoa", "diff keeps unmentioned keys")
        expect(!updated.isPlaying, "diff updates playing")
        expect(abs(updated.elapsedTime - 50) < 0.001, "diff updates elapsed")
        expect(updated.artworkData == artworkBytes, "artwork base64 decoded")
        expect(updated.position(at: far) == 50, "paused position does not extrapolate")

        // Diff null removes a key; losing the mandatory title invalidates state.
        let clear = line(["type": "data", "diff": true, "payload": ["title": NSNull()]])
        guard case .some(.none) = acc.ingest(line: clear) else {
            failures.append("null title should yield .some(nil) (state invalid)")
            report(failures); return
        }

        // Malformed and irrelevant lines are ignored (return nil), state untouched.
        expect(acc.ingest(line: Data("not json".utf8)) == nil, "malformed line ignored")
        expect(acc.ingest(line: line(["type": "other"])) == nil, "non-data line ignored")

        // Arbitration: remote only when nothing local plays, no playing
        // YouTube tab, and the remote app is not a desktop source echo.
        let remote = updated
        expect(
            MusicTabArbitrator.resolve(musicIsPlaying: false, browserIsPlaying: false, remote: remote)
                == .remote(remote),
            "remote wins when local sources idle"
        )
        expect(
            MusicTabArbitrator.resolve(musicIsPlaying: true, browserIsPlaying: false, remote: remote)
                == .local,
            "AppleScript playback always wins"
        )
        expect(
            MusicTabArbitrator.resolve(musicIsPlaying: false, browserIsPlaying: true, remote: remote)
                == .local,
            "playing YouTube tab keeps its own panel"
        )
        expect(
            MusicTabArbitrator.resolve(musicIsPlaying: false, browserIsPlaying: false, remote: nil)
                == .local,
            "no remote snapshot -> local"
        )
        let spotifyEcho = MediaRemoteNowPlayingSnapshot(
            bundleIdentifier: "com.spotify.client",
            title: "t", artist: "a", album: "b",
            duration: 10, elapsedTime: 0, timestamp: Date(),
            isPlaying: false, artworkData: nil
        )
        expect(
            MusicTabArbitrator.resolve(musicIsPlaying: false, browserIsPlaying: false, remote: spotifyEcho)
                == .local,
            "paused desktop app echo is excluded"
        )

        report(failures)
    }

    static func report(_ failures: [String]) {
        if failures.isEmpty {
            print("MediaRemoteNowPlayingTests: all assertions passed")
        } else {
            print("MediaRemoteNowPlayingTests: \(failures.count) failure(s)")
            failures.forEach { print("  - \($0)") }
            exit(1)
        }
    }
}
```

Create `scripts/test-nowplaying.sh` (mark executable):

```zsh
#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
TEST_BINARY="$PROJECT_DIR/.build/renotch-nowplaying-tests"

cd "$PROJECT_DIR"
swiftc \
    -swift-version 5 \
    Sources/Renotch/Models/NotchModels.swift \
    Sources/Renotch/Models/MediaRemoteNowPlayingModels.swift \
    Tests/MediaRemoteNowPlayingTests.swift \
    -framework AppKit \
    -o "$TEST_BINARY"
"$TEST_BINARY"
```

Append to `scripts/test.sh` after the `test-mediaremote.sh` line:

```zsh
"$SCRIPT_DIR/test-nowplaying.sh"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `chmod +x scripts/test-nowplaying.sh && scripts/test-nowplaying.sh`
Expected: compile error — `MediaRemoteNowPlayingModels.swift` does not exist.

- [ ] **Step 3: Implement the models**

Create `Sources/Renotch/Models/MediaRemoteNowPlayingModels.swift`:

```swift
import Foundation

/// One decoded now-playing state from the mediaremote-adapter stream.
/// Times are seconds; `timestamp` anchors `elapsedTime` so the UI can
/// extrapolate the current position without polling.
struct MediaRemoteNowPlayingSnapshot: Equatable {
    let bundleIdentifier: String
    let title: String
    let artist: String
    let album: String
    let duration: TimeInterval
    let elapsedTime: TimeInterval
    let timestamp: Date
    let isPlaying: Bool
    let artworkData: Data?

    func position(at now: Date) -> TimeInterval {
        let base = isPlaying ? elapsedTime + now.timeIntervalSince(timestamp) : elapsedTime
        return base.clamped(to: 0...max(duration, 0))
    }
}

/// Applies the adapter's stream contract (`diff:false` replaces state,
/// `diff:true` merges keys, `null` removes a key) over raw JSON lines.
struct MediaRemoteStreamAccumulator {
    private var state: [String: Any] = [:]

    /// - Returns: `nil` when the line is malformed or not a data event
    ///   (state unchanged); `.some(nil)` when the merged state is no longer
    ///   a valid now-playing item; `.some(snapshot)` on a valid update.
    mutating func ingest(line: Data) -> MediaRemoteNowPlayingSnapshot?? {
        guard
            let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
            object["type"] as? String == "data",
            let payload = object["payload"] as? [String: Any]
        else { return nil }

        if object["diff"] as? Bool == true {
            for (key, value) in payload {
                if value is NSNull {
                    state.removeValue(forKey: key)
                } else {
                    state[key] = value
                }
            }
        } else {
            state = payload.filter { !($0.value is NSNull) }
        }
        return .some(snapshot())
    }

    private func snapshot() -> MediaRemoteNowPlayingSnapshot? {
        guard
            let bundleIdentifier = state["bundleIdentifier"] as? String,
            let title = state["title"] as? String, !title.isEmpty
        else { return nil }

        func micros(_ key: String) -> TimeInterval {
            ((state[key] as? NSNumber)?.doubleValue ?? 0) / 1_000_000
        }

        let artworkData = (state["artworkData"] as? String)
            .flatMap { Data(base64Encoded: $0) }

        return MediaRemoteNowPlayingSnapshot(
            bundleIdentifier: bundleIdentifier,
            title: title,
            artist: state["artist"] as? String ?? "",
            album: state["album"] as? String ?? "",
            duration: micros("durationMicros"),
            elapsedTime: micros("elapsedTimeMicros"),
            timestamp: Date(timeIntervalSince1970: micros("timestampEpochMicros")),
            isPlaying: state["playing"] as? Bool ?? false,
            artworkData: artworkData
        )
    }
}

enum MusicTabContent: Equatable {
    case local
    case remote(MediaRemoteNowPlayingSnapshot)
}

/// Pure fallback: AppleScript sources keep absolute priority, a playing
/// YouTube tab keeps its dedicated panel, and echoes of the desktop apps
/// themselves are excluded so a paused Spotify.app never reappears as
/// "remote" media.
enum MusicTabArbitrator {
    private static let excludedBundleIdentifiers: Set<String> = [
        "com.apple.Music",
        "com.spotify.client",
    ]

    static func resolve(
        musicIsPlaying: Bool,
        browserIsPlaying: Bool,
        remote: MediaRemoteNowPlayingSnapshot?
    ) -> MusicTabContent {
        guard
            let remote,
            !musicIsPlaying,
            !browserIsPlaying,
            !excludedBundleIdentifiers.contains(remote.bundleIdentifier)
        else { return .local }
        return .remote(remote)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `scripts/test-nowplaying.sh`
Expected: `MediaRemoteNowPlayingTests: all assertions passed`

- [ ] **Step 5: Commit**

```bash
git add Sources/Renotch/Models/MediaRemoteNowPlayingModels.swift Tests/MediaRemoteNowPlayingTests.swift scripts/test-nowplaying.sh scripts/test.sh
git commit -m "feat: MediaRemote stream accumulator and music-tab arbitrator"
```

---

### Task 3: MediaRemoteNowPlayingService — stream process lifecycle

**Files:**
- Create: `Sources/Renotch/Services/MediaRemoteNowPlayingService.swift`

**Interfaces:**
- Consumes: `MediaRemoteStreamAccumulator`, `MediaRemoteNowPlayingSnapshot` (Task 2).
- Produces (Task 4 relies on): `final class MediaRemoteNowPlayingService: ObservableObject` with `@Published private(set) var snapshot: MediaRemoteNowPlayingSnapshot?`, `@Published private(set) var playbackActivationDate: Date`, `var isAvailable: Bool`, `func pause()`, `func resume()`.

No unit-test step: all decode/merge logic was tested in Task 2; this class is
process plumbing verified by the smoke run in Task 6. Keep every branch here
thin enough that a failure is visible in Console output.

- [ ] **Step 1: Implement the service**

Create `Sources/Renotch/Services/MediaRemoteNowPlayingService.swift`:

```swift
import Foundation

/// Streams system-wide now-playing metadata from the bundled
/// mediaremote-adapter (`stream --micros --debounce=150`). Diff-merging and
/// snapshot mapping live in MediaRemoteStreamAccumulator (Models); this
/// class only owns the child process: spawn, line-buffer stdout, restart
/// with backoff on unexpected death, and stop for good on a fatal
/// (non-zero) exit per the adapter docs.
final class MediaRemoteNowPlayingService: ObservableObject {
    @Published private(set) var snapshot: MediaRemoteNowPlayingSnapshot?
    @Published private(set) var playbackActivationDate = Date.distantPast

    private let scriptURL: URL?
    private let frameworkURL: URL?
    private var accumulator = MediaRemoteStreamAccumulator()
    private var process: Process?
    private var lineBuffer = Data()
    private var restartDelay: TimeInterval = 1
    private var isPaused = true
    private var isFatallyUnavailable = false

    var isAvailable: Bool {
        scriptURL != nil && frameworkURL != nil && !isFatallyUnavailable
    }

    init(bundle: Bundle = .main) {
        scriptURL = bundle.url(forResource: "mediaremote-adapter", withExtension: "pl")
        if let candidate = bundle.resourceURL?.appendingPathComponent("MediaRemoteAdapter.framework"),
           FileManager.default.fileExists(
               atPath: candidate.appendingPathComponent("MediaRemoteAdapter").path
           ) {
            frameworkURL = candidate
        } else {
            frameworkURL = nil
        }
    }

    deinit {
        process?.terminationHandler = nil
        process?.terminate()
    }

    func resume() {
        isPaused = false
        startStream()
    }

    func pause() {
        isPaused = true
        stopStream()
    }

    private func startStream() {
        guard isAvailable, !isPaused, process == nil,
              let scriptURL, let frameworkURL else { return }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        task.arguments = [
            scriptURL.path, frameworkURL.path,
            "stream", "--micros", "--debounce=150",
        ]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            DispatchQueue.main.async { self?.consume(data) }
        }
        task.terminationHandler = { [weak self] process in
            DispatchQueue.main.async { self?.handleTermination(of: process) }
        }

        do {
            try task.run()
            process = task
        } catch {
            NSLog("MediaRemoteNowPlayingService: failed to spawn stream: \(error)")
            isFatallyUnavailable = true
        }
    }

    private func stopStream() {
        guard let process else { return }
        process.terminationHandler = nil
        (process.standardOutput as? Pipe)?.fileHandleForReading.readabilityHandler = nil
        process.terminate()
        self.process = nil
        lineBuffer.removeAll()
    }

    private func consume(_ data: Data) {
        lineBuffer.append(data)
        while let newline = lineBuffer.firstIndex(of: UInt8(ascii: "\n")) {
            let line = lineBuffer[lineBuffer.startIndex..<newline]
            lineBuffer.removeSubrange(lineBuffer.startIndex...newline)
            guard let update = accumulator.ingest(line: Data(line)) else { continue }
            restartDelay = 1  // healthy output resets the backoff
            let becameActive = update?.isPlaying == true && snapshot?.isPlaying != true
            snapshot = update
            if becameActive {
                playbackActivationDate = Date()
            }
        }
    }

    private func handleTermination(of process: Process) {
        (process.standardOutput as? Pipe)?.fileHandleForReading.readabilityHandler = nil
        self.process = nil
        snapshot = nil
        lineBuffer.removeAll()
        accumulator = MediaRemoteStreamAccumulator()

        // Adapter docs: non-zero exit is fatal (e.g. macOS blocks
        // MediaRemote) — do not reinvoke for the rest of the session.
        guard process.terminationStatus == 0 else {
            NSLog("MediaRemoteNowPlayingService: adapter exited fatally (\(process.terminationStatus))")
            isFatallyUnavailable = true
            return
        }
        guard !isPaused else { return }

        let delay = restartDelay
        restartDelay = min(restartDelay * 2, 30)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.startStream()
        }
    }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Sources/Renotch/Services/MediaRemoteNowPlayingService.swift
git commit -m "feat: MediaRemote now-playing stream service"
```

---

### Task 4: AppModel wiring — musicTabContent and arbitration inputs

**Files:**
- Modify: `Sources/Renotch/State/AppModel.swift`

**Interfaces:**
- Consumes: `MediaRemoteNowPlayingService` (Task 3), `MusicTabArbitrator` / `MusicTabContent` (Task 2).
- Produces (Task 5 relies on): `let nowPlaying: MediaRemoteNowPlayingService` property and `var musicTabContent: MusicTabContent` computed on `AppModel`.

- [ ] **Step 1: Add the service property and construction**

Next to `let mediaRemote: MediaRemoteCommandService` (line 45) add:

```swift
    let nowPlaying: MediaRemoteNowPlayingService
```

Next to `mediaRemote = MediaRemoteCommandService()` in `init` (line 80) add:

```swift
        nowPlaying = MediaRemoteNowPlayingService()
```

- [ ] **Step 2: Add musicTabContent and feed the compact arbitrator**

Below `activeMediaSource` (after line 140) add:

```swift
    var musicTabContent: MusicTabContent {
        MusicTabArbitrator.resolve(
            musicIsPlaying: music.isPlaying,
            browserIsPlaying: browser.media?.isPlaying == true,
            remote: nowPlaying.snapshot
        )
    }

    /// Remote media that won the music tab counts as "music playing" for
    /// the compact-notch arbitration, so the waveform wing behaves the
    /// same as for desktop Spotify.
    private var remoteMediaIsPlaying: Bool {
        if case .remote(let snapshot) = musicTabContent { return snapshot.isPlaying }
        return false
    }
```

Change the `activeMediaSource` body (lines 133–139) to:

```swift
        AdaptiveMediaArbitrator.resolve(
            browserAvailable: browser.media != nil,
            browserIsPlaying: browser.media?.isPlaying == true,
            browserActivation: browser.playbackActivationDate,
            musicIsPlaying: music.isPlaying || remoteMediaIsPlaying,
            musicActivation: max(music.playbackActivationDate, nowPlaying.playbackActivationDate)
        )
```

- [ ] **Step 3: Wire pause/resume**

In `pauseServices()` (line 615) add `nowPlaying.pause()`; in `resumeServices()` (line 620) add `nowPlaying.resume()`:

```swift
    private func pauseServices() {
        music.pause()
        activity.pause()
        nowPlaying.pause()
    }

    private func resumeServices() {
        music.resume()
        activity.resume()
        nowPlaying.resume()
    }
```

Also call `nowPlaying.resume()` once at the end of `init` **only if** `resumeServices()` is not already invoked during startup — check with `grep -n resumeServices Sources/Renotch/State/AppModel.swift` first; if startup goes through `resumeServices()`, add nothing.

- [ ] **Step 4: Verify AppModel changes republish**

`AppModel` must re-render when `nowPlaying.snapshot` changes. Check how `AppModel` observes its child services (`grep -n "objectWillChange\|sink\|Publishers" Sources/Renotch/State/AppModel.swift`). Follow the existing pattern used for `music`/`browser` (e.g. if their `objectWillChange` is forwarded, forward `nowPlaying.objectWillChange` identically; if views observe services directly via `@ObservedObject`, no forwarding is needed).

- [ ] **Step 5: Build and run existing suites**

Run: `swift build && scripts/test-appmodel.sh`
Expected: build succeeds, AppModel tests still pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/Renotch/State/AppModel.swift
git commit -m "feat: arbitrate MediaRemote fallback into music tab and compact notch"
```

---

### Task 5: UI — remote mode in MusicPlayerView (variant A)

**Files:**
- Modify: `Sources/Renotch/UI/MusicPlayerView.swift`
- Modify: `Sources/Renotch/UI/ExpandedNotchView.swift:61-67`

**Interfaces:**
- Consumes: `AppModel.musicTabContent` (Task 4), `MediaRemoteCommandService.send/.seek` (Task 1), `MediaRemoteNowPlayingSnapshot.position(at:)` (Task 2), existing `AlbumArtworkView`, `PlayerControlButton`, `PlayerPressButtonStyle`, `Color.notchMuted`, `Color.musicAccent`.
- Produces: `struct RemoteMediaPlayerView: View` rendered by `ExpandedNotchView` for `.remote`.

- [ ] **Step 1: Add RemoteMediaPlayerView**

Append to `Sources/Renotch/UI/MusicPlayerView.swift`:

```swift
/// Variant A of the MediaRemote fallback player: identical geometry to
/// MusicPlayerView (82pt artwork, title row, seek row, left control pill)
/// with the unsupported controls removed — the source badge fills the
/// volume slider's slot so switching sources never shifts the layout.
struct RemoteMediaPlayerView: View {
    let snapshot: MediaRemoteNowPlayingSnapshot
    let commands: MediaRemoteCommandService
    @State private var draggedPosition: Double?

    var body: some View {
        HStack(spacing: 14) {
            AlbumArtworkView(artwork: artwork, cornerRadius: 12)
                .frame(width: 82, height: 82)
                .shadow(color: .black.opacity(0.45), radius: 10, y: 5)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(snapshot.title)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text(metadata)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Color.notchMuted)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 6)
                    HStack(spacing: 4) {
                        Circle()
                            .fill(snapshot.isPlaying ? Color.musicAccent : Color.white.opacity(0.28))
                            .frame(width: 5, height: 5)
                        Text(snapshot.isPlaying ? "Playing" : "Paused")
                    }
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(
                        "Playback status: \(snapshot.isPlaying ? "playing" : "paused")"
                    )
                }

                TimelineView(.periodic(from: .now, by: 1)) { context in
                    seekRow(now: context.date)
                }

                HStack(spacing: 8) {
                    HStack(spacing: 4) {
                        PlayerControlButton(
                            icon: "backward.fill",
                            title: "Previous",
                            size: 27,
                            action: { commands.send(.previousTrack) }
                        )
                        Button(action: { commands.send(.togglePlayPause) }) {
                            Image(systemName: snapshot.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.black)
                                .frame(width: 32, height: 32)
                                .background(Circle().fill(.white))
                                .contentShape(Circle())
                        }
                        .buttonStyle(PlayerPressButtonStyle())
                        .help(snapshot.isPlaying ? "Pause" : "Play")
                        PlayerControlButton(
                            icon: "forward.fill",
                            title: "Next",
                            size: 27,
                            action: { commands.send(.nextTrack) }
                        )
                    }
                    .padding(.horizontal, 4)
                    .frame(height: 36)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white.opacity(0.045))
                    )

                    Spacer(minLength: 8)

                    sourceBadge
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(.top, 8)
    }

    private func seekRow(now: Date) -> some View {
        let position = draggedPosition ?? snapshot.position(at: now)
        return HStack(spacing: 7) {
            Text(MusicService.formattedTime(position))
                .frame(width: 28, alignment: .leading)
            Slider(
                value: Binding(
                    get: { position },
                    set: { draggedPosition = $0 }
                ),
                in: 0...max(snapshot.duration, 1),
                onEditingChanged: { editing in
                    guard !editing, let draggedPosition else { return }
                    commands.seek(to: draggedPosition)
                    self.draggedPosition = nil
                }
            )
            .tint(Color.musicAccent)
            Text("−" + MusicService.formattedTime(max(0, snapshot.duration - position)))
                .frame(width: 36, alignment: .trailing)
        }
        .font(.system(size: 8, weight: .medium, design: .rounded))
        .monospacedDigit()
        .foregroundStyle(Color.notchMuted)
    }

    private var sourceBadge: some View {
        HStack(spacing: 5) {
            if let icon = sourceAppIcon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 13, height: 13)
            }
            Text(sourceAppName.uppercased())
                .font(.system(size: 8.5, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(Color.notchMuted)
        }
        .padding(.horizontal, 8)
        .frame(height: 24)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(Color.white.opacity(0.14), lineWidth: 1)
        )
        .accessibilityLabel("Source: \(sourceAppName)")
    }

    private var sourceAppURL: URL? {
        NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: snapshot.bundleIdentifier
        )
    }

    private var sourceAppName: String {
        guard let url = sourceAppURL else { return snapshot.bundleIdentifier }
        return FileManager.default.displayName(atPath: url.path)
            .replacingOccurrences(of: ".app", with: "")
    }

    private var sourceAppIcon: NSImage? {
        guard let url = sourceAppURL else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    private var artwork: NSImage? {
        snapshot.artworkData.flatMap(NSImage.init(data:))
    }

    private var metadata: String {
        [snapshot.artist, snapshot.album]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }
}
```

Note: `MusicPlayerView.swift` already imports SwiftUI; add `import AppKit` at the top if `NSWorkspace` fails to resolve.

- [ ] **Step 2: Route it in ExpandedNotchView**

Replace the `.music` case (`ExpandedNotchView.swift:61-67`):

```swift
        case .music:
            if model.activeMediaSource == .browser,
               let media = model.browser.media {
                ExpandedBrowserMediaView(media: media, artwork: model.browser.mediaArtwork)
            } else if case .remote(let snapshot) = model.musicTabContent,
                      model.mediaRemote.isAvailable {
                RemoteMediaPlayerView(snapshot: snapshot, commands: model.mediaRemote)
            } else {
                MusicPlayerView(music: model.music)
            }
```

- [ ] **Step 3: Build and run full suite**

Run: `swift build && scripts/test.sh`
Expected: build succeeds, every suite passes.

- [ ] **Step 4: Commit**

```bash
git add Sources/Renotch/UI/MusicPlayerView.swift Sources/Renotch/UI/ExpandedNotchView.swift
git commit -m "feat: remote media player UI for MediaRemote fallback"
```

---

### Task 6: End-to-end smoke test

**Files:** none (verification only)

- [ ] **Step 1: Build the app bundle**

Run: `scripts/build-app.sh`
Expected: bundle builds; confirm the adapter is inside:
`test -f <bundle>/Contents/Resources/mediaremote-adapter.pl && test -f <bundle>/Contents/Resources/MediaRemoteAdapter.framework/MediaRemoteAdapter && echo ok`

- [ ] **Step 2: Manual smoke checklist (launch the built app)**

1. Quit Spotify.app and pause Apple Music. Play Spotify web (open.spotify.com) in Chrome → music tab shows title/artist/artwork, ⏮ ⏯ ⏭, Chrome badge; no volume/shuffle/repeat.
2. Play/pause and next from the notch → Chrome tab reacts; UI updates within ~1 s.
3. Drag the seek bar → playback jumps in Chrome.
4. Start Spotify.app playback → tab switches to the full local player (AppleScript wins).
5. Pause Spotify.app, keep Spotify web playing → tab returns to remote mode (paused desktop echo excluded).
6. Play a YouTube video (extension installed) → YouTube panel appears, not the remote player.
7. Compact notch shows the music waveform wing while only Spotify web plays.

- [ ] **Step 3: Record results**

Note any deviation as a bug before closing out; do not patch the spec silently.
