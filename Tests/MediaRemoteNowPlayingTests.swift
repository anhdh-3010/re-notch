// Tests/MediaRemoteNowPlayingTests.swift
import AppKit
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
