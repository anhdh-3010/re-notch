// Sources/Renotch/Services/TransientSources/ScreenshotEventSource.swift
import AppKit
import Foundation

/// Watches Spotlight metadata for new screenshot files
/// (kMDItemIsScreenCapture). No screen-recording permission needed.
final class ScreenshotEventSource: TransientEventSource {
    private var query: NSMetadataQuery?
    private var emit: ((TransientEvent) -> Void)?
    private var observer: NSObjectProtocol?
    private var startedAt = Date()
    private var seenPaths: Set<String> = []

    func start(emit: @escaping (TransientEvent) -> Void) {
        stop()
        self.emit = emit
        startedAt = Date()

        let query = NSMetadataQuery()
        query.predicate = NSPredicate(format: "kMDItemIsScreenCapture == 1")
        query.searchScopes = [NSMetadataQueryUserHomeScope]
        self.query = query

        observer = NotificationCenter.default.addObserver(
            forName: .NSMetadataQueryDidUpdate,
            object: query,
            queue: .main
        ) { [weak self] notification in
            let added = notification.userInfo?[NSMetadataQueryUpdateAddedItemsKey]
                as? [NSMetadataItem] ?? []
            self?.handleAdded(added)
        }
        query.start()
    }

    func stop() {
        query?.stop()
        query = nil
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        emit = nil
        seenPaths.removeAll()
    }

    private func handleAdded(_ items: [NSMetadataItem]) {
        for item in items {
            guard let path = item.value(forAttribute: NSMetadataItemPathKey) as? String,
                  !seenPaths.contains(path) else { continue }
            let created = item.value(forAttribute: NSMetadataItemFSCreationDateKey) as? Date
            // Ignore pre-existing screenshots indexed at query start.
            guard let created, created > startedAt else { continue }
            seenPaths.insert(path)

            let url = URL(fileURLWithPath: path)
            // The floating macOS preview can delete the file moments later;
            // only peek if it still exists when we fire.
            guard FileManager.default.fileExists(atPath: path) else { continue }
            emit?(TransientEvent(kind: .screenshot(url: url)))
        }
    }
}
