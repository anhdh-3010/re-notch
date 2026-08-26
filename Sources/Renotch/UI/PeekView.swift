// Sources/Renotch/UI/PeekView.swift
import SwiftUI
import QuickLookThumbnailing

/// Renders the transient peek content for both styles. Wings: icon on the
/// left wing, info on the right wing, physical notch untouched between
/// them. Droop: a single row below the menu bar line.
struct PeekView: View {
    @EnvironmentObject private var model: AppModel
    let event: TransientEvent

    var body: some View {
        Group {
            switch event.presentationStyle {
            case .wings: wingsLayout
            case .droop: droopLayout
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { model.peekTapped() }
    }

    private var wingsLayout: some View {
        HStack {
            leadingContent
                .frame(width: NotchGeometry.peekWingWidth, alignment: .leading)
            Spacer(minLength: 0)
            trailingContent
                .frame(width: NotchGeometry.peekWingWidth, alignment: .trailing)
        }
        .padding(.leading, CGFloat(model.settings.resolvedCompactContentLeadingPadding))
        .padding(.trailing, CGFloat(model.settings.resolvedCompactContentTrailingPadding))
        .font(.system(size: 12, weight: .semibold))
    }

    private var droopLayout: some View {
        HStack(spacing: 10) {
            leadingContent
            Spacer(minLength: 0)
            trailingContent
        }
        .padding(.horizontal, 18)
        .padding(.top, (model.notchMetrics?.height ?? 0))
        .font(.system(size: 13, weight: .semibold))
        .frame(maxHeight: .infinity)
    }

    @ViewBuilder private var leadingContent: some View {
        switch event.kind {
        case let .charging(plugged, _):
            Image(systemName: plugged ? "bolt.fill" : "bolt.slash.fill")
                .foregroundStyle(plugged ? Color.green : Color.secondary)
        case .batteryLow:
            Image(systemName: "battery.25")
                .foregroundStyle(Color.red)
        case let .bluetooth(name, connected, _):
            Label(name, systemImage: connected ? "airpods" : "airpods.chargingcase")
                .labelStyle(.titleAndIcon)
                .lineLimit(1)
        case let .screenshot(url):
            ScreenshotThumbnail(url: url)
        case .capsLock:
            EmptyView()
        }
    }

    @ViewBuilder private var trailingContent: some View {
        switch event.kind {
        case let .charging(plugged, percent):
            Text("\(percent)%")
                .foregroundStyle(plugged ? Color.green : Color.primary)
        case let .batteryLow(percent):
            Text("\(percent)%").foregroundStyle(Color.red)
        case let .bluetooth(_, connected, batteries):
            if connected, let batteries, batteries.hasAnyReading {
                HStack(spacing: 6) {
                    if let left = batteries.left { batteryBadge("L", left) }
                    if let right = batteries.right { batteryBadge("R", right) }
                    if let c = batteries.caseBattery { batteryBadge("C", c) }
                }
            } else {
                Text(connected ? "Connected" : "Disconnected")
                    .foregroundStyle(.secondary)
            }
        case let .screenshot(url):
            Text(url.lastPathComponent)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(.secondary)
        case let .capsLock(on):
            Label(on ? "Caps Lock On" : "Caps Lock Off", systemImage: "capslock.fill")
                .foregroundStyle(on ? Color.yellow : Color.secondary)
                .lineLimit(1)
        }
    }

    private func batteryBadge(_ label: String, _ percent: Int) -> some View {
        HStack(spacing: 2) {
            Text(label).foregroundStyle(.secondary)
            Text("\(percent)%")
        }
        .font(.system(size: 11, weight: .semibold))
    }
}

/// Async QuickLook thumbnail with a generic-image fallback.
private struct ScreenshotThumbnail: View {
    let url: URL
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 34, height: 24)
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .task {
            image = await Self.thumbnail(for: url)
        }
        .draggable(url)
    }

    static func thumbnail(for url: URL) async -> NSImage? {
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: 68, height: 48),
            scale: 2,
            representationTypes: .thumbnail
        )
        let generated = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request)
        return generated?.nsImage
    }
}
