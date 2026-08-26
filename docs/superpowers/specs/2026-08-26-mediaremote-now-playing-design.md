# MediaRemote Now-Playing Source for the Music Tab

Date: 2026-08-26
Status: Approved design, pending implementation plan

## Problem

The music tab only supports Apple Music.app and Spotify.app via AppleScript
(`MusicService`). Media playing in a browser — Spotify web player, SoundCloud,
etc. — never appears: no matching bundle is running, so the tab shows the
empty state. The browser extension pipeline covers youtube.com only.

## Solution Overview

Add a third now-playing source backed by the bundled
`mediaremote-adapter` (Vendor/mediaremote-adapter), which already ships in the
app bundle for one-shot commands (`MediaRemoteCommandService`). Its `stream`
command emits system-wide now-playing updates (title, artist, album, duration,
elapsed time, playback state, bundle identifier, artwork) as JSON lines. This
covers any app or site that publishes a macOS media session — no browser
extension required.

The MediaRemote source is a **pure fallback**: the AppleScript sources keep
absolute priority because they offer richer control (volume, shuffle, repeat).

## Components

### MediaRemoteNowPlayingService (new, `Sources/Renotch/Services/`)

- Spawns `/usr/bin/perl mediaremote-adapter.pl <framework-path> stream
  --debounce=150` as a long-lived child process.
- Parses stdout line-by-line as JSON. Applies the adapter's diff contract:
  - `diff == false`: payload replaces the whole state.
  - `diff == true`: payload keys update the state; a key with value `null`
    is removed.
- Publishes a snapshot (`@Published`):
  - `title, artist, album: String`
  - `duration: TimeInterval`
  - `elapsedTime: TimeInterval` and `timestamp: Date` (for extrapolation)
  - `isPlaying: Bool`
  - `bundleIdentifier: String`
  - `artwork: NSImage?` (decoded from base64 `artworkData` + `artworkMimeType`)
- Position shown in UI is extrapolated: `elapsedTime + (now − timestamp)`
  while playing; no polling loop.
- Lifecycle mirrors `MusicService.pause()/resume()`: SIGTERM the stream when
  the notch does not need it, respawn on resume.
- Availability gate identical to `MediaRemoteCommandService`: script and
  framework binary must exist in the bundle.

### MediaRemoteCommandService (extend)

- Add `previousTrack` command.
- Add `seek(to seconds: TimeInterval)` using the adapter's `seek` subcommand
  (positive integer microseconds).

### AppModel (extend)

- New computed `musicTabContent`:
  - `.local` — render `MusicPlayerView` from `MusicService` (current behavior).
  - `.remote(snapshot)` — render the remote mode.
- Selection rule (all conditions required for `.remote`):
  1. Neither Apple Music.app nor Spotify.app is `playing` (AppleScript wins).
  2. MediaRemote snapshot has a track and its `bundleIdentifier` is not
     `com.apple.Music` or `com.spotify.client` (avoid echoing a paused
     desktop app).
  3. `browser.media?.isPlaying != true` (a playing YouTube tab keeps its
     dedicated panel via the existing arbitrator).
- Compact notch: MediaRemote playing counts as "music playing" in
  `AdaptiveMediaArbitrator` inputs so the waveform wing appears, same as
  desktop Spotify.

## UI (`MusicPlayerView`, remote mode — approved variant A)

Reuse the existing layout; same positions, degraded control set:

- Artwork (82×82), title, artist — unchanged.
- Seek bar remains draggable; release maps to `MediaRemoteCommandService.seek`.
- Control pill keeps its left-aligned position with only ⏮ ⏯ ⏭
  (shuffle and repeat hidden).
- Source badge (app icon dot + name from `bundleIdentifier`, e.g. "CHROME")
  replaces the volume slider slot on the right — no layout jump when the
  source switches.
- Hidden entirely in remote mode: volume slider, shuffle, repeat,
  "Open Spotify/Music" affordances.

## Error Handling

- Malformed JSON line: skip the line, keep streaming.
- Unexpected process death: restart with exponential backoff 1 s → 30 s cap.
- Non-zero exit code (fatal per adapter docs, e.g. macOS blocks MediaRemote):
  mark the service unavailable for the rest of the session; the music tab
  behaves exactly as today.
- Missing bundled framework/script: service never starts.

## Testing

- Unit tests for the diff-merge parser: full payload replace, diff update,
  `null` key removal, malformed line skip.
- Unit tests for payload → snapshot mapping (microsecond durations, artwork
  decode gated).
- Pure-function tests for the fallback selection rule, same style as existing
  `AdaptiveMediaArbitrator` tests in `Tests/SmokeTests.swift`.
- Extend `MediaRemoteCommandServiceTests` for `previousTrack` and `seek`
  argument construction via the existing `ProcessRunner` test seam.
- Smoke: fake process feeding JSON lines through the service, assert published
  snapshots.

## Out of Scope

- Replacing the AppleScript path (kept for volume/shuffle/repeat).
- Extending the browser extension to open.spotify.com.
- Like/dislike, queue, or lyrics.
