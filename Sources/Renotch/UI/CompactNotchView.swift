import SwiftUI

/// Dynamic Island-style compact bar: an adaptive wing on each side of the
/// hardware camera notch, with the camera area itself left empty.
struct CompactNotchView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var music: MusicService
    @ObservedObject var browser: BrowserActivityService
    @ObservedObject var timer: TimerService
    @ObservedObject var shelf: ShelfStore
    @ObservedObject var activity: DeveloperActivityService
    @ObservedObject var todos: TodoStore

    var body: some View {
        HStack(spacing: 0) {
            leftWing
                .frame(width: wings.left)
            Color.clear
                .frame(width: notchGapWidth)
            rightWing
                .frame(width: wings.right)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
        .id(presentationID)
        .transition(.identity)
        .animation(.spring(response: 0.32, dampingFraction: 0.92), value: presentationID)
        .padding(.leading, CGFloat(model.settings.resolvedCompactContentLeadingPadding))
        .padding(.trailing, CGFloat(model.settings.resolvedCompactContentTrailingPadding))
        .padding(.top, CGFloat(model.settings.resolvedCompactContentTopPadding))
        .padding(.bottom, CGFloat(model.settings.resolvedCompactContentBottomPadding))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .clipped()
    }

    private var presentation: AdaptiveCompactPresentation {
        model.compactPresentation
    }

    private var wings: WingWidths {
        NotchGeometry.wingWidths(
            presentation: presentation,
            configuredContent: model.settings.resolvedCompactContent,
            isTimerActive: timer.isActive,
            hasTransientMessage: model.transientMessage != nil
        )
    }

    private var notchGapWidth: CGFloat {
        (model.notchMetrics ?? NotchGeometry.fallbackNotch).width
    }

    @ViewBuilder
    private var leftWing: some View {
        if let message = model.transientMessage {
            WingMessageText(text: message)
        } else {
            switch presentation {
            case .download:
                WingSymbol(systemName: "arrow.down.circle.fill", tint: Color.notchAccent)
            case .codingGlance:
                if let glance = activity.glance {
                    WingSymbol(systemName: glance.kind.symbol, tint: glance.kind.tint)
                }
            case .browserMedia:
                if timer.isActive {
                    WingTimerRing(timer: timer)
                } else {
                    WingBrowserArtwork(artwork: browser.mediaArtwork)
                }
            case .music:
                musicLeftWing
            case .configured:
                configuredLeftWing
            }
        }
    }

    @ViewBuilder
    private var configuredLeftWing: some View {
        switch model.settings.resolvedCompactContent {
        case .music:
            musicLeftWing
        case .servers:
            WingSymbol(
                systemName: activity.primaryServerActivity.kind.symbol,
                tint: activity.primaryServerActivity.kind.tint
            )
        case .timer:
            WingTimerRing(timer: timer)
        case .calendar:
            WingDateTile(service: model.calendar)
        case .shelf:
            WingSymbol(systemName: "tray.full.fill", tint: Color.notchAccent)
        case .todo:
            WingTodoRing(store: todos)
        }
    }

    /// Music-style left wing: the timer ring takes over while a session runs.
    @ViewBuilder
    private var musicLeftWing: some View {
        if timer.isActive {
            WingTimerRing(timer: timer)
        } else {
            WingMusicArtwork(music: music)
        }
    }

    @ViewBuilder
    private var rightWing: some View {
        if model.transientMessage != nil {
            WingSymbol(systemName: "info.circle.fill", tint: Color.notchAccent)
        } else {
            switch presentation {
            case .download:
                if let download = browser.activeDownload {
                    WingProgressText(
                        text: "\(Int((download.progress ?? 0) * 100))%",
                        tint: Color.notchAccent
                    )
                }
            case .codingGlance:
                if let glance = activity.glance {
                    ActivityStateDot(state: glance.state)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            case .browserMedia:
                mediaRightWing(isPlaying: browser.media?.isPlaying == true)
            case .music:
                mediaRightWing(isPlaying: music.isPlaying)
            case .configured:
                configuredRightWing
            }
        }
    }

    @ViewBuilder
    private func mediaRightWing(isPlaying: Bool) -> some View {
        if timer.isActive {
            WingTimerCountdown(timer: timer)
        } else {
            WingWaveform(isPlaying: isPlaying)
        }
    }

    @ViewBuilder
    private var configuredRightWing: some View {
        switch model.settings.resolvedCompactContent {
        case .music:
            mediaRightWing(isPlaying: music.isPlaying)
        case .servers:
            ActivityStateDot(state: activity.primaryServerActivity.state)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .timer:
            if timer.isActive {
                WingTimerCountdown(timer: timer)
            } else {
                WingSymbol(systemName: "timer", tint: .white.opacity(0.6))
            }
        case .calendar:
            WingEventTime(service: model.calendar)
        case .shelf:
            WingCount(count: shelf.items.count)
        case .todo:
            WingCount(count: todos.remainingCount)
        }
    }

    private var presentationID: String {
        if let message = model.transientMessage {
            return "message-\(message)"
        }
        switch presentation {
        case .download:
            return "download-\(browser.activeDownload?.id ?? 0)"
        case .codingGlance:
            return "coding-glance-\(activity.glance?.id.uuidString ?? "")"
        case .browserMedia:
            return "browser-media-\(browser.media?.sessionID ?? "unknown")-\(timer.isActive ? "timer" : "media")"
        case .music:
            return "music-\(music.track?.id ?? "unknown")-\(timer.isActive ? "timer" : "media")"
        case .configured:
            return "configured-\(model.settings.resolvedCompactContent.rawValue)-\(timer.isActive ? "active" : "idle")"
        }
    }

    /// VoiceOver description of the current presentation. The wings are
    /// decorative glyphs (`.accessibilityElement(children: .ignore)` above),
    /// so this single label carries all the semantic content that used to
    /// live on the individual compact row views.
    private var accessibilityDescription: String {
        if let message = model.transientMessage {
            return message
        }
        switch presentation {
        case .download:
            guard let download = browser.activeDownload else { return "Download" }
            let percent = Int(((download.progress ?? 0) * 100).rounded())
            return "\(download.displayName), \(percent)%"
        case .codingGlance:
            guard let glance = activity.glance else { return "Activity" }
            return "\(glance.title), \(glance.state.compactLabel)"
        case .browserMedia:
            guard let media = browser.media else { return "Browser media" }
            let base = "\(media.title), \(media.isPlaying ? "playing" : "paused")"
            return timerPrefixedDescription(base)
        case .music:
            let title = music.track?.title ?? "Music"
            let base = "\(title), \(music.isPlaying ? "playing" : "paused")"
            return timerPrefixedDescription(base)
        case .configured:
            return configuredAccessibilityDescription
        }
    }

    private var configuredAccessibilityDescription: String {
        switch model.settings.resolvedCompactContent {
        case .music:
            let title = music.track?.title ?? "Music"
            return timerPrefixedDescription("\(title), \(music.isPlaying ? "playing" : "paused")")
        case .servers:
            let server = activity.primaryServerActivity
            return "\(server.title), \(server.state.compactLabel)"
        case .timer:
            guard timer.isActive else { return "Timer ready" }
            return "\(timer.currentMode.title) timer, \(TimerService.formatted(timer.remaining)) remaining"
        case .calendar:
            guard model.calendar.accessState == .authorized, let nextEvent = model.calendar.nextEvent else {
                return "No upcoming events"
            }
            return "Next event: \(nextEvent.title), \(nextEvent.shortTime)"
        case .shelf:
            let count = shelf.items.count
            return "\(count) \(count == 1 ? "file" : "files") in shelf"
        case .todo:
            let remaining = todos.remainingCount
            return "\(remaining) \(remaining == 1 ? "task" : "tasks") remaining"
        }
    }

    /// Prepends the running timer state so VoiceOver announces the ring first.
    private func timerPrefixedDescription(_ base: String) -> String {
        guard timer.isActive else { return base }
        return "\(timer.currentMode.title) timer, \(TimerService.formatted(timer.remaining)) remaining. \(base)"
    }
}
