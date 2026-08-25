import SwiftUI

/// Building blocks for the two compact "wings" flanking the hardware notch,
/// Dynamic Island style. Each view fills its wing (36 pt icon wing or 64 pt
/// text wing) at hardware-notch height.

struct WingSymbol: View {
    let systemName: String
    var tint: Color = .white

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct WingMusicArtwork: View {
    @ObservedObject var music: MusicService

    var body: some View {
        AlbumArtworkView(artwork: music.artwork, cornerRadius: 5)
            .frame(width: 20, height: 20)
            .overlay(alignment: .bottomLeading) {
                if music.activeSource == .appleMusic {
                    AppleMusicBadge(size: 9)
                        .padding(1)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct WingBrowserArtwork: View {
    let artwork: NSImage?

    var body: some View {
        if let artwork {
            Image(nsImage: artwork)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 20, height: 20)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            WingSymbol(systemName: "play.rectangle.fill", tint: .white.opacity(0.85))
        }
    }
}

struct WingWaveform: View {
    let isPlaying: Bool

    var body: some View {
        AudioWaveform(isPlaying: isPlaying, barCount: 5)
            .frame(width: 20, height: 11)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct WingTimerRing: View {
    @ObservedObject var timer: TimerService

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.14), lineWidth: 1.8)
            Circle()
                .trim(from: 0, to: timer.isActive ? timer.progress : 0)
                .stroke(
                    timer.currentMode.tint,
                    style: StrokeStyle(lineWidth: 1.8, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.25), value: timer.progress)
            Image(systemName: timer.isActive && timer.isPaused ? "pause.fill" : timer.currentMode.icon)
                .font(.system(size: 7.5, weight: .bold))
                .foregroundStyle(timer.currentMode.tint)
        }
        .frame(width: 18, height: 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct WingTimerCountdown: View {
    @ObservedObject var timer: TimerService

    var body: some View {
        Text(TimerService.formatted(timer.remaining))
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(timer.currentMode.tint)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct WingProgressText: View {
    let text: String
    var tint: Color = .white

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(tint)
            .lineLimit(1)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct WingCount: View {
    let count: Int

    var body: some View {
        Text("\(count)")
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.white)
            .contentTransition(.numericText())
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct WingDateTile: View {
    @ObservedObject var service: AppleCalendarService

    var body: some View {
        let date = (service.accessState == .authorized ? service.nextEvent?.startDate : nil) ?? Date()
        VStack(spacing: -1) {
            Text(date.formatted(.dateTime.weekday(.narrow)).uppercased())
                .font(.system(size: 5.5, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.notchAccent)
            Text(date.formatted(.dateTime.day()))
                .font(.system(size: 9.5, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(width: 20, height: 20)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color.notchAccent.opacity(0.14))
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct WingEventTime: View {
    @ObservedObject var service: AppleCalendarService

    var body: some View {
        Text(service.accessState == .authorized ? (service.nextEvent?.shortTime ?? "—") : "—")
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundStyle(Color.notchAccent)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct WingTodoRing: View {
    @ObservedObject var store: TodoStore

    private var progress: Double {
        guard !store.items.isEmpty else { return 0 }
        return Double(store.items.count - store.remainingCount) / Double(store.items.count)
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.12), lineWidth: 1.5)
            Circle()
                .trim(from: 0, to: CGFloat(progress))
                .stroke(
                    Color.notchAccent,
                    style: StrokeStyle(lineWidth: 1.5, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            Image(systemName: "checklist")
                .font(.system(size: 6.5, weight: .bold))
                .foregroundStyle(Color.notchAccent)
        }
        .frame(width: 15, height: 15)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct WingMessageText: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Color.notchAccent)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
