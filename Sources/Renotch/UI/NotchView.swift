import AppKit
import SwiftUI

struct NotchView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    private var topCornerRadius: CGFloat {
        switch model.mode {
        case .compact:
            return CGFloat(model.settings.resolvedCompactCornerRadius)
        case .expanded, .fileDrop, .success, .peek:
            return 18
        case .focusTakeover:
            return 0
        }
    }

    private var bottomCornerRadius: CGFloat {
        switch model.mode {
        case .compact: return CGFloat(model.settings.resolvedCompactCornerRadius)
        case .expanded: return 26
        case .fileDrop, .success, .peek: return 30
        case .focusTakeover: return 0
        }
    }

    private var notchShape: AttachedNotchShape {
        AttachedNotchShape(
            topCornerRadius: topCornerRadius,
            bottomCornerRadius: bottomCornerRadius
        )
    }

    private var shadowOpacity: Double {
        switch model.mode {
        case .compact: return isHovering ? 0.18 : 0
        case .expanded: return 0.38
        case .fileDrop: return 0.62
        case .success, .peek: return 0.42
        case .focusTakeover: return 0.65
        }
    }

    private var shadowRadius: CGFloat {
        switch model.mode {
        case .compact: return isHovering ? 8 : 0
        case .expanded: return 14
        case .fileDrop: return 20
        case .success, .peek: return 16
        case .focusTakeover: return 32
        }
    }

    private var shadowColor: Color {
        if model.mode == .fileDrop || model.mode == .success || model.mode == .focusTakeover {
            return Color.notchAccent.opacity(shadowOpacity)
        }
        switch model.settings.resolvedAppearance {
        case .black:
            return .black.opacity(shadowOpacity)
        case .liquidGlass:
            return Color(red: 0.02, green: 0.06, blue: 0.1).opacity(shadowOpacity * 0.82)
        }
    }

    private var glassMaterial: Material {
        switch model.settings.resolvedGlassBlurRadius {
        case ..<10:
            return .ultraThinMaterial
        case ..<20:
            return .thinMaterial
        default:
            return .regularMaterial
        }
    }

    private var containerAnimation: Animation? {
        guard !reduceMotion else { return nil }
        switch model.mode {
        case .compact:
            // Snap back into the notch with a soft, springy settle.
            return .spring(response: 0.38, dampingFraction: 0.75)
        case .expanded:
            // Dynamic Island-style inflation with pronounced overshoot.
            return .spring(response: 0.5, dampingFraction: 0.62)
        case .fileDrop:
            return .spring(response: 0.28, dampingFraction: 0.78)
        case .success, .peek:
            return .spring(response: 0.28, dampingFraction: 0.82)
        case .focusTakeover:
            return .spring(response: 0.52, dampingFraction: 0.92)
        }
    }

    private var contentTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .opacity
                .combined(with: .notchBlur(radius: 12))
                .combined(with: .notchScale(x: 0.85, y: 0.72, anchor: .top)),
            removal: .opacity
                .combined(with: .notchScale(x: 0.97, y: 0.94, anchor: .top))
        )
    }

    private var notchWidth: CGFloat {
        model.currentSize.width
    }

    private var notchHeight: CGFloat {
        model.currentSize.height
    }

    var body: some View {
        ZStack(alignment: .top) {
            if model.mode == .focusTakeover {
                FocusTakeoverView(
                    timer: model.timer,
                    site: model.focusTakeoverSite,
                    appName: model.focusTakeoverAppName
                )
                .transition(.opacity)
            } else {
                notchSurface
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .preferredColorScheme(.dark)
    }

    private var notchContent: some View {
        ZStack(alignment: .top) {
            switch model.mode {
            case .expanded:
                ExpandedNotchView(timer: model.timer)
                    .transition(contentTransition)
            case .fileDrop:
                FileDropView(isTargeted: model.isDraggingFileOver)
                    .transition(contentTransition)
            case .success:
                FileDropSuccessView()
                    .transition(contentTransition)
            case .peek:
                // Placeholder; Task 4 replaces this with the real peek content view.
                FileDropSuccessView()
                    .transition(contentTransition)
            case .focusTakeover:
                EmptyView()
            case .compact:
                CompactNotchView(
                    music: model.music,
                    browser: model.browser,
                    timer: model.timer,
                    shelf: model.shelf,
                    activity: model.activity,
                    todos: model.todos
                )
                    .transition(contentTransition)
                    .onTapGesture {
                        model.notchClicked()
                    }
            }
        }
    }

    private var animatedNotchContent: some View {
        notchContent
            .frame(width: notchWidth, height: notchHeight, alignment: .top)
            .clipped()
    }

    @ViewBuilder
    private var styledNotchSurface: some View {
        switch model.settings.resolvedAppearance {
        case .black:
            animatedNotchContent
                .background(Color.black.padding(-50))
                .mask(notchShape.padding(.horizontal, 0.5))
                .shadow(color: shadowColor, radius: shadowRadius)
        case .liquidGlass:
            if #available(macOS 26.0, *) {
                animatedNotchContent
                    .glassEffect(.regular.interactive(), in: notchShape)
            } else {
                animatedNotchContent
                    .background(Rectangle().fill(glassMaterial).padding(-50))
                    .mask(notchShape.padding(.horizontal, 0.5))
                    .overlay {
                        notchShape
                            .stroke(Color.white.opacity(0.4), lineWidth: 0.8)
                            .padding(.horizontal, 0.8)
                            .allowsHitTesting(false)
                    }
                    .shadow(color: shadowColor, radius: shadowRadius)
            }
        }
    }

    private var notchSurface: some View {
        styledNotchSurface
            .contentShape(Rectangle())
            .onTapGesture {
                if model.mode == .compact {
                    model.notchClicked()
                }
            }
            .animation(containerAnimation, value: model.currentSize)
            .animation(containerAnimation, value: model.mode)
            .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.94), value: isHovering)
            .animation(.easeInOut(duration: 0.28), value: model.settings.resolvedAppearance)
            .animation(.easeOut(duration: 0.16), value: model.settings.resolvedGlassBlurRadius)
            .onHover { hovering in
                guard hovering != isHovering else { return }
                isHovering = hovering
                if hovering {
                    NSHapticFeedbackManager.defaultPerformer.perform(
                        .alignment,
                        performanceTime: .default
                    )
                }
                model.hoverChanged(hovering)
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                model.removeMissingShelfFiles()
            }
    }
}
