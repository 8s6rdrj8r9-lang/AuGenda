// DesignTokens.swift
// AuGenda Design System
//
// Centralized design tokens: colors, spacing, typography, shadows
// Supports light/dark mode. Reference everywhere via Tokens.color.primary, etc.

import SwiftUI

// MARK: - Design Tokens (singleton access)

enum Tokens {

    // MARK: Colors

    enum Color {
        // Semantic colors (action, state, status)
        static let primary = AppColor.blue500
        static let secondary = AppColor.slate500
        static let tertiary = AppColor.slate400

        // Functional: backgrounds
        static let background = AppColor.white
        static let backgroundSecondary = AppColor.slate50
        static let surfaceCard = AppColor.white

        // Functional: text
        static let textPrimary = AppColor.slate900
        static let textSecondary = AppColor.slate600
        static let textTertiary = AppColor.slate500

        // Functional: borders
        static let border = AppColor.slate200
        static let borderLight = AppColor.slate100

        // State colors
        static let success = AppColor.green500
        static let warning = AppColor.amber500  // Not red; muted orange
        static let error = AppColor.amber500
        static let info = AppColor.blue500

        // Interactive
        static let focus = AppColor.blue500
        static let focusRing = AppColor.blue200
        static let hover = AppColor.slate100

        // Dark mode variants
        static let darkBackground = AppColor.slate900
        static let darkTextPrimary = AppColor.white
        static let darkTextSecondary = AppColor.slate400
        static let darkBorder = AppColor.slate700

        // Opacity helpers
        static func withOpacity(_ color: SwiftUI.Color, _ opacity: Double) -> SwiftUI.Color {
            color.opacity(opacity)
        }
    }

    // MARK: Spacing (Tailwind scale, 4px base)

    enum Spacing {
        static let none: CGFloat = 0
        static let xs: CGFloat = 4    // 1
        static let sm: CGFloat = 8    // 2
        static let md: CGFloat = 12   // 3
        static let base: CGFloat = 16 // 4
        static let lg: CGFloat = 24   // 6
        static let xl: CGFloat = 32   // 8
        static let xxl: CGFloat = 48  // 12
        static let xxxl: CGFloat = 64 // 16

        // Common uses
        static let buttonPaddingH: CGFloat = base
        static let buttonPaddingV: CGFloat = md
        static let cardPadding: CGFloat = lg
        static let sectionSpacing: CGFloat = lg
        static let elementSpacing: CGFloat = md
        static let formInputSpacing: CGFloat = lg
        static let betweenCards: CGFloat = xl

        // Minimum touch target (44px per iOS guidelines)
        static let touchMinimum: CGFloat = 44
    }

    // MARK: Typography

    enum Typography {
        // Sizes
        static let h1Size: CGFloat = 32
        static let h2Size: CGFloat = 20
        static let h3Size: CGFloat = 16
        static let bodySize: CGFloat = 16
        static let labelSize: CGFloat = 14
        static let captionSize: CGFloat = 12

        // Font weights
        static let weightBold: Font.Weight = .bold      // 700
        static let weightSemibold: Font.Weight = .semibold  // 600
        static let weightMedium: Font.Weight = .medium  // 500
        static let weightRegular: Font.Weight = .regular // 400

        // Line heights (as multipliers for readability)
        static let lineHeightTight: CGFloat = 1.2
        static let lineHeightNormal: CGFloat = 1.5
        static let lineHeightRelaxed: CGFloat = 1.6

        // Font family (system font for accessibility)
        static let fontFamily = "Helvetica Neue"

        // Predefined styles
        static let h1 = Font.system(size: h1Size, weight: .bold, design: .default)
        static let h2 = Font.system(size: h2Size, weight: .semibold, design: .default)
        static let h3 = Font.system(size: h3Size, weight: .semibold, design: .default)
        static let body = Font.system(size: bodySize, weight: .regular, design: .default)
        static let label = Font.system(size: labelSize, weight: .semibold, design: .default)
        static let caption = Font.system(size: captionSize, weight: .regular, design: .default)

        // Min/max text sizing
        static let minTextSize: CGFloat = 14
        static let maxTextSize: CGFloat = 32
        static let defaultTextSize: CGFloat = 16
    }

    // MARK: Corners & Borders

    enum Border {
        static let radiusSmall: CGFloat = 8
        static let radiusMedium: CGFloat = 12
        static let radiusLarge: CGFloat = 16

        static let widthDefault: CGFloat = 1
        static let widthBold: CGFloat = 2

        // Focus ring
        static let focusRingWidth: CGFloat = 4
        static let focusRingColor = AppColor.blue500
    }

    // MARK: Shadows

    enum Shadow {
        static let subtle = Shadow(
            color: SwiftUI.Color.black.opacity(0.05),
            radius: 2,
            x: 0,
            y: 1
        )

        static let normal = Shadow(
            color: SwiftUI.Color.black.opacity(0.1),
            radius: 4,
            x: 0,
            y: 2
        )

        static let elevated = Shadow(
            color: SwiftUI.Color.black.opacity(0.15),
            radius: 8,
            x: 0,
            y: 4
        )

        struct Shadow {
            let color: SwiftUI.Color
            let radius: CGFloat
            let x: CGFloat
            let y: CGFloat
        }
    }

    // MARK: Animation

    enum Animation {
        static let quickDuration: CGFloat = 0.15
        static let normalDuration: CGFloat = 0.25
        static let slowDuration: CGFloat = 0.4

        // Disable animations for reduced motion
        static func standardSpring(reduce: Bool = false) -> SwiftUI.Animation {
            if reduce {
                return .linear(duration: 0.001)
            }
            return .spring(response: 0.3, dampingFraction: 0.7)
        }

        static func standardEase(reduce: Bool = false) -> SwiftUI.Animation {
            if reduce {
                return .linear(duration: 0.001)
            }
            return .easeInOut(duration: normalDuration)
        }
    }

    // MARK: Layout Constraints

    enum Layout {
        // Max widths (for readable text columns)
        static let maxCardWidth: CGFloat = 600
        static let maxTextWidth: CGFloat = 60 * 8  // ~60 chars

        // Mobile vs desktop breakpoints
        static let mobileMaxWidth: CGFloat = 600
        static let tabletMinWidth: CGFloat = 768
        static let desktopMinWidth: CGFloat = 1024
    }

    // MARK: Accessibility

    enum Accessibility {
        // Text contrast ratios (WCAG AAA = 7:1)
        static let contrastRatioAAA: CGFloat = 7.0
        static let contrastRatioAA: CGFloat = 4.5

        // Button sizes
        static let minButtonHeight: CGFloat = Spacing.touchMinimum
        static let minTouchTarget: CGFloat = Spacing.touchMinimum

        // Focus indicators
        static let focusIndicatorWidth: CGFloat = Border.focusRingWidth

        // Reduced motion preference
        #if os(iOS)
        static let reduceMotion = UIAccessibility.isReduceMotionEnabled
        #else
        static let reduceMotion = false
        #endif
    }
}

// MARK: - Color Palette (Raw RGB values)

enum AppColor {
    // Blues (primary action)
    static let blue500 = SwiftUI.Color(red: 59/255, green: 130/255, blue: 246/255)    // #3B82F6
    static let blue400 = SwiftUI.Color(red: 96/255, green: 165/255, blue: 250/255)    // #60A5FA
    static let blue600 = SwiftUI.Color(red: 37/255, green: 99/255, blue: 235/255)     // #2563EB
    static let blue100 = SwiftUI.Color(red: 219/255, green: 234/255, blue: 254/255)   // #DBEAFE
    static let blue200 = SwiftUI.Color(red: 191/255, green: 219/255, blue: 254/255)   // #BFDBFE

    // Greens (success)
    static let green500 = SwiftUI.Color(red: 16/255, green: 185/255, blue: 129/255)   // #10B981
    static let green600 = SwiftUI.Color(red: 5/255, green: 150/255, blue: 105/255)    // #059669
    static let green100 = SwiftUI.Color(red: 209/255, green: 250/255, blue: 229/255)  // #D1FAE5

    // Ambers (warning, not red)
    static let amber500 = SwiftUI.Color(red: 245/255, green: 158/255, blue: 11/255)   // #F59E0B
    static let amber600 = SwiftUI.Color(red: 217/255, green: 119/255, blue: 6/255)    // #D97706
    static let amber100 = SwiftUI.Color(red: 254/255, green: 243/255, blue: 199/255)  // #FEF3C7

    // Slates (neutral, text, borders)
    static let slate50 = SwiftUI.Color(red: 250/255, green: 250/255, blue: 251/255)   // #FAFAFA
    static let slate100 = SwiftUI.Color(red: 241/255, green: 245/255, blue: 249/255)  // #F1F5F9
    static let slate200 = SwiftUI.Color(red: 226/255, green: 232/255, blue: 240/255)  // #E2E8F0
    static let slate400 = SwiftUI.Color(red: 148/255, green: 163/255, blue: 184/255)  // #94A3B8
    static let slate500 = SwiftUI.Color(red: 100/255, green: 116/255, blue: 139/255)  // #64748B
    static let slate600 = SwiftUI.Color(red: 71/255, green: 85/255, blue: 105/255)    // #475569
    static let slate700 = SwiftUI.Color(red: 51/255, green: 65/255, blue: 85/255)     // #334155
    static let slate800 = SwiftUI.Color(red: 30/255, green: 41/255, blue: 59/255)     // #1E293B
    static let slate900 = SwiftUI.Color(red: 15/255, green: 23/255, blue: 42/255)     // #0F172A

    // Whites & Blacks
    static let white = SwiftUI.Color.white
    static let black = SwiftUI.Color.black
}

// MARK: - Environment Keys (for passing tokens through view hierarchy)

struct ReduceMotionKey: EnvironmentKey {
    static let defaultValue: Bool = Tokens.Accessibility.reduceMotion
}

struct TextSizeMultiplierKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1.0  // Default: 100%
}

struct LowStimulationModeKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

extension EnvironmentValues {
    var reduceMotion: Bool {
        get { self[ReduceMotionKey.self] }
        set { self[ReduceMotionKey.self] = newValue }
    }

    var textSizeMultiplier: CGFloat {
        get { self[TextSizeMultiplierKey.self] }
        set { self[TextSizeMultiplierKey.self] = newValue }
    }

    var lowStimulationMode: Bool {
        get { self[LowStimulationModeKey.self] }
        set { self[LowStimulationModeKey.self] = newValue }
    }

    var densityMode: DensityMode {
        get { self[DensityModeKey.self] }
        set { self[DensityModeKey.self] = newValue }
    }
}

// MARK: - Density Mode (Adaptive Capacity)
//
// Drives adaptive density across Home (and any other adaptive surface).
// Default derivation is from `ProfilePreferences.currentEnergyLevel`; the
// user may pin a mode manually via the OrientationAnchor on Home.
//
// Mapping (per Session 1 strategic design):
//   energy 1   → .survival    (one card, max breath)
//   energy 2   → .low         (3–5 cards, energy-matched)
//   energy 3   → .functional  (full today view)
//   energy 4+  → .high        (everything: trends, spotlight, plan tools)

enum DensityMode: String, CaseIterable, Sendable {
    case survival
    case low
    case functional
    case high

    /// Default mapping from energy level (1–5+) to density mode.
    static func autoFrom(energyLevel: Int) -> DensityMode {
        switch energyLevel {
        case ..<2:  return .survival
        case 2:     return .low
        case 3:     return .functional
        default:    return .high
        }
    }

    /// Short, human-friendly label for the capacity badge.
    var label: String {
        switch self {
        case .survival:   return "Survival"
        case .low:        return "Low"
        case .functional: return "Functional"
        case .high:       return "High"
        }
    }

    /// Non-essential metadata (dots, flags, context) is hidden below this threshold.
    var showsFullMetadata: Bool {
        self == .functional || self == .high
    }

    /// Survival surfaces show only the Primary Action Zone — Momentum is hidden.
    var isMinimalSurface: Bool { self == .survival }

    /// High-capacity surfaces expose spotlight/tomorrow/trail sections.
    var showsExpandedSurface: Bool { self == .high }

    /// Suggested card count cap for the Momentum surface in this mode.
    var momentumCardLimit: Int {
        switch self {
        case .survival:   return 0
        case .low:        return 5
        case .functional: return 10
        case .high:       return 16
        }
    }
}

private struct DensityModeKey: EnvironmentKey {
    static let defaultValue: DensityMode = .functional
}

// MARK: - DensityMode neighbour helper

extension DensityMode {
    /// Step to the next mode in the given direction (-1 = lower / calmer,
    /// +1 = higher / busier). Returns nil at the edges.
    func next(direction: Int) -> DensityMode? {
        let all = DensityMode.allCases
        guard let idx = all.firstIndex(of: self) else { return nil }
        let target = idx + direction
        guard all.indices.contains(target) else { return nil }
        return all[target]
    }
}

// MARK: - Density Advisor (Pattern-Detected Suggestion)
//
// Pure logic — given the current density and the user's recent activity,
// produce an optional suggestion to drop (calmer) or raise (busier). Per
// Session 1's design: "automatic but ADVISORY — never auto-applied."
//
// Rules:
//   * 3+ snoozes in the last 15 min          → suggest dropping one level
//   * 3+ completions in 30 min, no snoozes   → suggest raising one level
//
// The view layer is responsible for dismissal (1-hour cooldown via
// AppStorage so it reactively re-renders); the advisor itself is stateless.

enum DensityAdvisor {

    struct Suggestion: Equatable {
        let target: DensityMode
        let reason: String
    }

    static func suggestion(currentDensity: DensityMode) -> Suggestion? {
        let recentSnoozes     = ActivityLog.snoozes(inLastMinutes: 15)
        let recentCompletions = ActivityLog.completions(inLastMinutes: 30)

        // Drop one level when snoozes are cascading.
        if recentSnoozes >= 3, let lower = currentDensity.next(direction: -1) {
            let plural = recentSnoozes == 1 ? "" : "s"
            return Suggestion(
                target: lower,
                reason: "You've snoozed \(recentSnoozes) task\(plural) recently. Try \(lower.label) capacity?"
            )
        }

        // Raise one level when there's sustained progress without snoozes.
        if recentCompletions >= 3, recentSnoozes == 0,
           let higher = currentDensity.next(direction: 1) {
            return Suggestion(
                target: higher,
                reason: "You're on a roll — \(recentCompletions) done. Open up to \(higher.label) capacity?"
            )
        }

        return nil
    }
}
