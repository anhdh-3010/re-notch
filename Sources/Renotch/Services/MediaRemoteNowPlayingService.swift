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
