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
