// Tests/MediaRemoteCommandServiceTests.swift
import Foundation

/// Covers MediaRemoteCommandService: availability reflects whether the
/// bundled adapter resources were found, and send() shells out to perl
/// with exactly the expected arguments (or does nothing when unavailable).
@main
struct MediaRemoteCommandServiceTests {
    static func main() {
        var failures: [String] = []
        func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
            if !condition() { failures.append(message) }
        }

        // Bundle.main in a plain command-line test binary has no
        // mediaremote-adapter.pl / MediaRemoteAdapter.framework resources,
        // so the default init must report unavailable and never invoke the
        // runner.
        var mainBundleRunnerCalls = 0
        let unavailableService = MediaRemoteCommandService(
            bundle: .main,
            runner: { _, _ in mainBundleRunnerCalls += 1 }
        )
        expect(!unavailableService.isAvailable, "unavailable when bundle lacks adapter resources")
        unavailableService.send(.togglePlayPause)
        expect(mainBundleRunnerCalls == 0, "send does not invoke runner when resources are missing")

        // Explicit resource URLs (test seam) with a mock runner: send()
        // must call perl with [script, framework, "send", code].
        let scriptURL = URL(fileURLWithPath: "/tmp/fake/mediaremote-adapter.pl")
        let frameworkURL = URL(fileURLWithPath: "/tmp/fake/MediaRemoteAdapter.framework")
        var invocations: [(String, [String])] = []
        let available = MediaRemoteCommandService(
            scriptURL: scriptURL,
            frameworkURL: frameworkURL,
            runner: { launchPath, arguments in invocations.append((launchPath, arguments)) }
        )
        expect(available.isAvailable, "available when both resource URLs are present")

        available.send(.togglePlayPause)
        expect(invocations.count == 1, "togglePlayPause invokes runner once")
        if let call = invocations.first {
            expect(call.0 == "/usr/bin/perl", "togglePlayPause launches perl")
            expect(
                call.1 == [scriptURL.path, frameworkURL.path, "send", "2"],
                "togglePlayPause passes script, framework, send, 2"
            )
        }

        available.send(.nextTrack)
        expect(invocations.count == 2, "nextTrack invokes runner once")
        if let call = invocations.last {
            expect(
                call.1 == [scriptURL.path, frameworkURL.path, "send", "4"],
                "nextTrack passes script, framework, send, 4"
            )
        }

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

        // Missing framework URL (script present) must also short-circuit.
        var missingFrameworkCalls = 0
        let missingFramework = MediaRemoteCommandService(
            scriptURL: scriptURL,
            frameworkURL: nil,
            runner: { _, _ in missingFrameworkCalls += 1 }
        )
        expect(!missingFramework.isAvailable, "unavailable when framework URL is nil")
        missingFramework.send(.nextTrack)
        expect(missingFrameworkCalls == 0, "send does not invoke runner when framework URL is nil")
        missingFramework.seek(to: 10)
        expect(missingFrameworkCalls == 0, "seek does not invoke runner when unavailable")

        // bundle-based init: a bundle whose resourceURL resolves fine (it
        // always does) but whose MediaRemoteAdapter.framework was never
        // actually built/copied in must report unavailable, not just
        // "present" because the path string could be constructed.
        let fm = FileManager.default
        let scriptOnlyDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mrcs-test-script-only-\(UUID().uuidString)")
        try? fm.createDirectory(at: scriptOnlyDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: scriptOnlyDir) }
        fm.createFile(atPath: scriptOnlyDir.appendingPathComponent("mediaremote-adapter.pl").path, contents: Data())
        if let scriptOnlyBundle = Bundle(path: scriptOnlyDir.path) {
            let scriptOnlyService = MediaRemoteCommandService(bundle: scriptOnlyBundle)
            expect(
                !scriptOnlyService.isAvailable,
                "unavailable when framework directory was never built/copied into the bundle"
            )
        } else {
            failures.append("could not construct test bundle for script-only fixture")
        }

        // Same bundle shape, but with the framework's inner binary present:
        // must report available.
        let fullBundleDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mrcs-test-full-\(UUID().uuidString)")
        let frameworkDir = fullBundleDir.appendingPathComponent("MediaRemoteAdapter.framework")
        try? fm.createDirectory(at: frameworkDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: fullBundleDir) }
        fm.createFile(atPath: fullBundleDir.appendingPathComponent("mediaremote-adapter.pl").path, contents: Data())
        fm.createFile(atPath: frameworkDir.appendingPathComponent("MediaRemoteAdapter").path, contents: Data())
        if let fullBundle = Bundle(path: fullBundleDir.path) {
            let fullService = MediaRemoteCommandService(bundle: fullBundle)
            expect(
                fullService.isAvailable,
                "available when both the script and the framework's inner binary exist on disk"
            )
        } else {
            failures.append("could not construct test bundle for full fixture")
        }

        if failures.isEmpty {
            print("MediaRemoteCommandServiceTests: all assertions passed")
        } else {
            print("MediaRemoteCommandServiceTests: \(failures.count) failure(s)")
            failures.forEach { print("  - \($0)") }
            exit(1)
        }
    }
}
