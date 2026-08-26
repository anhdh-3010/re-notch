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
