import AppKit
import SwiftUI

struct ExpandedBrowserMediaView: View {
    @EnvironmentObject private var model: AppModel
    let media: BrowserMediaActivity
    let artwork: NSImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 14) {
                thumbnail

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 5) {
                        Image(systemName: "play.rectangle.fill")
                        Text("YOUTUBE")
                            .tracking(0.8)
                        Circle()
                            .fill(media.isPlaying ? Color.red : Color.white.opacity(0.35))
                            .frame(width: 4, height: 4)
                        Text(media.isPlaying ? "Playing" : "Paused")
                    }
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(media.isPlaying ? Color.red : Color.notchMuted)

                    Text(media.title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .truncationMode(.tail)
                    Text(media.channel)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Color.notchMuted)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if model.mediaRemote.isAvailable {
                    controls
                }
            }
            .frame(maxHeight: .infinity, alignment: .center)

            if let progress = media.progress {
                HStack(spacing: 8) {
                    Text(formatted(media.position))
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.1))
                            Capsule().fill(Color.red).frame(width: proxy.size.width * progress)
                        }
                    }
                    .frame(height: 3)
                    Text("−\(formatted(max(0, media.duration - media.position)))")
                }
                .font(.system(size: 8, weight: .medium, design: .rounded))
                .foregroundStyle(Color.notchMuted)
                .monospacedDigit()
            }
        }
        .padding(.top, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var thumbnail: some View {
        Group {
            if let artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    Color(red: 0.78, green: 0.05, blue: 0.08)
                    Image(systemName: "play.fill")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
        }
        .frame(width: 160, height: 90)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 0.7)
        }
        .overlay(alignment: .topTrailing) {
            if let pageURL = media.pageURL {
                Button {
                    NSWorkspace.shared.open(pageURL)
                } label: {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 16, height: 16)
                        .background(Circle().fill(Color.black.opacity(0.55)))
                }
                .buttonStyle(.plain)
                .padding(3)
                .help("Open video")
                .accessibilityLabel("Open video")
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 6) {
            PlayerControlButton(
                icon: media.isPlaying ? "pause.fill" : "play.fill",
                title: media.isPlaying ? "Pause" : "Play",
                size: 26,
                iconSize: 11,
                action: { model.mediaRemote.send(.togglePlayPause) }
            )
            PlayerControlButton(
                icon: "forward.fill",
                title: "Next",
                size: 20,
                iconSize: 9,
                action: { model.mediaRemote.send(.nextTrack) }
            )
        }
    }

    private func formatted(_ value: TimeInterval) -> String {
        let seconds = max(0, Int(value.rounded(.down)))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
