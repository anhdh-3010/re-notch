import Foundation

/// Sends one-shot MediaRemote commands to the system's now-playing app
/// via the bundled mediaremote-adapter (perl + framework). Used to
/// control browser media (YouTube etc.) that the app cannot script.
final class MediaRemoteCommandService {
    enum Command: String {
        case togglePlayPause = "2"
        case nextTrack = "4"
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
        frameworkURL = bundle.resourceURL?.appendingPathComponent("MediaRemoteAdapter.framework")
        self.runner = runner ?? Self.defaultRunner
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
}
