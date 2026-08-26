import Foundation

/// Sends one-shot MediaRemote commands to the system's now-playing app
/// via the bundled mediaremote-adapter (perl + framework). Used to
/// control browser media (YouTube etc.) that the app cannot script.
final class MediaRemoteCommandService {
    enum Command: String {
        case togglePlayPause = "2"
        case nextTrack = "4"
        case previousTrack = "5"
    }

    /// Test seam: (launchPath, arguments) -> Void. Default spawns the task.
    typealias ProcessRunner = (String, [String]) -> Void

    private let runner: ProcessRunner
    private let scriptURL: URL?
    private let frameworkURL: URL?

    init(
        bundle: Bundle = .main,
        runner: ProcessRunner? = nil
    ) {
        scriptURL = bundle.url(forResource: "mediaremote-adapter", withExtension: "pl")
        frameworkURL = Self.resolvedFrameworkURL(in: bundle)
        self.runner = runner ?? Self.defaultRunner
    }

    /// `bundle.resourceURL` is non-nil even when nothing was bundled (it's
    /// just the Resources directory path), so appending the framework name
    /// alone always yields a URL — it never proves the framework was
    /// actually built and copied in. Confirm the inner binary exists on
    /// disk before treating the framework as present.
    private static func resolvedFrameworkURL(in bundle: Bundle) -> URL? {
        guard let candidate = bundle.resourceURL?.appendingPathComponent("MediaRemoteAdapter.framework") else {
            return nil
        }
        let binaryPath = candidate.appendingPathComponent("MediaRemoteAdapter").path
        guard FileManager.default.fileExists(atPath: binaryPath) else { return nil }
        return candidate
    }

    /// Test seam: construct with explicit resource URLs, bypassing bundle
    /// lookup entirely (Bundle.main has no adapter resources in test binaries).
    init(
        scriptURL: URL?,
        frameworkURL: URL?,
        runner: ProcessRunner? = nil
    ) {
        self.scriptURL = scriptURL
        self.frameworkURL = frameworkURL
        self.runner = runner ?? Self.defaultRunner
    }

    private static let defaultRunner: ProcessRunner = { launchPath, arguments in
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        try? process.run()
    }

    var isAvailable: Bool { scriptURL != nil && frameworkURL != nil }

    func send(_ command: Command) {
        guard let scriptURL, let frameworkURL else { return }
        runner("/usr/bin/perl", [scriptURL.path, frameworkURL.path, "send", command.rawValue])
    }

    /// Seeks the now-playing app. The adapter's `seek` subcommand takes a
    /// positive integer position in microseconds.
    func seek(to seconds: TimeInterval) {
        guard let scriptURL, let frameworkURL else { return }
        let micros = max(0, Int((seconds * 1_000_000).rounded()))
        runner("/usr/bin/perl", [scriptURL.path, frameworkURL.path, "seek", String(micros)])
    }
}
