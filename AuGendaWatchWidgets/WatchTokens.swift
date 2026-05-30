// WatchTokens.swift
// AuGenda Watch
//
// Watch-side subset of the iOS/macOS Tokens system. Per Spec §17, this is
// an *extension* of the existing token surface (a watch density tier
// living alongside the iOS ones), not a fork. Values are tuned for the
// 41–49 mm OLED canvas: true-black backgrounds, denser spacing, larger
// minimum tap-targets relative to the screen.
//
// SHARED contract: keep the type/enum names aligned with AuGenda/DesignTokens.swift
// so a future Swift Package extraction is a straight lift.

import SwiftUI

// MARK: - DensityMode
//
// Same enum as the iOS app. The spec (§2, §11) explicitly endorses
// DensityMode as the watch's cognitive-state concept ("the phone/Mac owns
// cognitive state; the watch receives it"). The watch lives in .survival by
// default and only rarely modulates up.

enum DensityMode: String, CaseIterable, Sendable {
    case survival
    case low
    case functional
    case high

    static func autoFrom(energyLevel: Int) -> DensityMode {
        switch energyLevel {
        case ..<2:  return .survival
        case 2:     return .low
        case 3:     return .functional
        default:    return .high
        }
    }

    /// On the watch we surface NEXT only when capacity is at least Low.
    /// In Survival, NEXT collapses to a count.
    var watchShowsNext: Bool { self != .survival }

    /// Planning/High → watch shows a "Open iPhone for the full view" hand-off,
    /// not a planning surface. Watch can never *be* the planning tool.
    var watchDeferToPhone: Bool { self == .high }

    var label: String {
        switch self {
        case .survival:   return "Survival"
        case .low:        return "Low"
        case .functional: return "Functional"
        case .high:       return "High"
        }
    }
}

private struct DensityModeKey: EnvironmentKey {
    static let defaultValue: DensityMode = .survival   // Watch resting state
}

extension EnvironmentValues {
    var densityMode: DensityMode {
        get { self[DensityModeKey.self] }
        set { self[DensityModeKey.self] = newValue }
    }
}

// MARK: - WatchTokens

/// Watch-tuned token values. Names mirror iOS `Tokens.*` so the contract
/// stays familiar.
enum WatchTokens {

    enum Spacing {
        static let none: CGFloat = 0
        static let xs: CGFloat = 2
        static let sm: CGFloat = 4
        static let md: CGFloat = 6
        static let base: CGFloat = 8
        static let lg: CGFloat = 12
        static let xl: CGFloat = 16
        static let xxl: CGFloat = 24

        /// Minimum tap target — relative to watch screen rather than iOS 44pt rule
        static let touchMinimum: CGFloat = 36
    }

    enum Typography {
        // Watch uses system fonts only — no font family override. Sizes leave
        // room for Dynamic Type reflow (§14): each is a base size; SwiftUI
        // scales it via the system's text-size setting.
        static let nowTitle    = Font.system(.title2,   design: .default).weight(.semibold)
        static let nextTitle   = Font.system(.body,     design: .default).weight(.medium)
        static let anchorLabel = Font.system(.caption2, design: .default)
        static let actionLabel = Font.system(.body,     design: .default).weight(.semibold)
        static let metadata    = Font.system(.caption2, design: .default)
    }

    enum Color {
        // True-black background (§10) — native on OLED, calmest.
        static let background = SwiftUI.Color.black

        // Semantic surfaces (§10) — muted, used as accent tint only, never wash.
        static let manageable = SwiftUI.Color(red: 0.40, green: 0.70, blue: 0.50)   // muted green
        static let activation = SwiftUI.Color(red: 0.90, green: 0.65, blue: 0.30)   // muted amber
        static let admin      = SwiftUI.Color(red: 0.45, green: 0.60, blue: 0.85)   // muted blue
        static let creative   = SwiftUI.Color(red: 0.65, green: 0.50, blue: 0.85)   // muted purple
        static let paused     = SwiftUI.Color(white: 0.45)                          // gray

        // Text — primary stays full-bright for legibility; secondary dimmed.
        static let textPrimary   = SwiftUI.Color.white
        static let textSecondary = SwiftUI.Color(white: 0.65)
        static let textTertiary  = SwiftUI.Color(white: 0.45)

        // Accent — the muted activation tone, applied to primary action only.
        static let accent = activation
    }

    enum Border {
        static let radiusSmall: CGFloat = 6
        static let radiusMedium: CGFloat = 10
        static let radiusLarge: CGFloat = 14
        static let leadingBar: CGFloat = 3      // §6 thin leading accent
    }

    enum Animation {
        static let normalDuration: Double = 0.18

        /// Honors Reduce Motion: collapses to a near-instant cross-fade (§14).
        static func standardEase(reduce: Bool) -> SwiftUI.Animation {
            reduce ? .linear(duration: 0.001) : .easeInOut(duration: normalDuration)
        }
    }
}

// MARK: - Semantic Tint Resolver
//
// Maps an item's domain / friction signal to a single muted accent. The
// resolver lives here (not on the model) so the watch can change its tint
// strategy without touching shared model code.

enum WatchTint {
    /// Map a task's friction level + context to a muted semantic color.
    /// Color is never the sole carrier of meaning (§10) — pair with an
    /// SF Symbol or text label whenever used.
    static func resolve(frictionLevel: Int, contextTag: String) -> Color {
        if frictionLevel >= 4 { return WatchTokens.Color.activation }   // hard / activation
        if contextTag.contains("focus") { return WatchTokens.Color.creative }
        if contextTag.contains("phone") || contextTag.contains("email") {
            return WatchTokens.Color.admin
        }
        return WatchTokens.Color.manageable
    }
}
