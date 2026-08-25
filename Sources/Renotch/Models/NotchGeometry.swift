import CoreGraphics
import Foundation

/// Size of the physical camera housing (hardware notch) of a screen, in points.
struct PhysicalNotchMetrics: Equatable {
    var width: CGFloat
    var height: CGFloat
}

/// Widths of the two content "wings" flanking the camera area in compact mode.
struct WingWidths: Equatable {
    var left: CGFloat
    var right: CGFloat
}

enum NotchGeometry {
    /// Stand-in for displays without a hardware notch so the compact bar
    /// looks identical on external monitors and non-notch Macs.
    static let fallbackNotch = PhysicalNotchMetrics(width: 200, height: 32)
    /// Square wing that holds a single glyph (artwork, waveform, state dot).
    static let iconWingWidth: CGFloat = 36
    /// Wider wing that holds short live text (timer countdown, download %).
    static let textWingWidth: CGFloat = 64
    /// Widest wing used while a transient message is displayed.
    static let messageWingWidth: CGFloat = 120

    /// Derives the hardware notch size from raw screen values.
    /// Returns nil when the screen has no notch.
    static func metrics(
        screenWidth: CGFloat,
        auxiliaryLeftWidth: CGFloat,
        auxiliaryRightWidth: CGFloat,
        safeAreaTop: CGFloat
    ) -> PhysicalNotchMetrics? {
        guard safeAreaTop > 0, auxiliaryLeftWidth > 0, auxiliaryRightWidth > 0 else {
            return nil
        }
        let width = screenWidth - auxiliaryLeftWidth - auxiliaryRightWidth
        guard width > 0 else { return nil }
        return PhysicalNotchMetrics(width: width, height: safeAreaTop)
    }

    static func wingWidths(
        presentation: AdaptiveCompactPresentation,
        configuredContent: CompactNotchContent,
        isTimerActive: Bool,
        hasTransientMessage: Bool
    ) -> WingWidths {
        if hasTransientMessage {
            return WingWidths(left: messageWingWidth, right: messageWingWidth)
        }
        switch presentation {
        case .download:
            return WingWidths(left: iconWingWidth, right: textWingWidth)
        case .codingGlance:
            return WingWidths(left: iconWingWidth, right: iconWingWidth)
        case .browserMedia, .music:
            return WingWidths(
                left: iconWingWidth,
                right: isTimerActive ? textWingWidth : iconWingWidth
            )
        case .configured:
            switch configuredContent {
            case .music, .timer:
                return WingWidths(
                    left: iconWingWidth,
                    right: isTimerActive ? textWingWidth : iconWingWidth
                )
            case .calendar:
                return WingWidths(left: iconWingWidth, right: textWingWidth)
            case .servers, .shelf, .todo:
                return WingWidths(left: iconWingWidth, right: iconWingWidth)
            }
        }
    }

    static func compactSize(
        notch: PhysicalNotchMetrics?,
        wings: WingWidths,
        leadingPadding: CGFloat,
        trailingPadding: CGFloat
    ) -> CGSize {
        let resolved = notch ?? fallbackNotch
        return CGSize(
            width: resolved.width + wings.left + wings.right + leadingPadding + trailingPadding,
            height: resolved.height
        )
    }
}
