// CognitiveStateSelector.swift
// AuGenda
//
// A calm, minimal cognitive-state picker. Surfaced in two flows:
//
//   1. First launch — after ProfileSetupView, before ContentView. The
//      large primary button is the path of lowest executive load
//      ("I'm overwhelmed → Survival mode"). The picker below offers the
//      other three modes for users who can self-assess more granularly.
//
//   2. Settings — re-tap your capacity any time from Profile Settings →
//      "Set capacity". Same component, `isFirstLaunch: false`.
//
// The selector writes the user's chosen mode to the active profile's
// `ProfilePreferences` in two places:
//   - `currentEnergyLevel` is set so the auto-derivation also lands on
//     this density mode if the pin is later cleared
//   - `densityPinnedRaw` is set so the user's explicit choice persists
//     (a manual pin survives later energy fluctuations)
//
// Per the AuGenda design system, every value comes from `Tokens.*`. No
// hardcoded spacing/color/typography. The presentation is shaped for
// the moment of overwhelm: large tap target, generous breathing room,
// no required decisions beyond a single tap.

import SwiftUI
import SwiftData

struct CognitiveStateSelector: View {

    @Binding var isPresented: Bool

    /// First-launch mode hides the small "Skip" link entirely — the
    /// user MUST commit to a state before reaching the dashboard. In
    /// settings mode a small Close/Cancel is offered.
    var isFirstLaunch: Bool = false

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var profileManager: ActiveProfileManager

    /// Currently-selected mode (mirrors the active profile's pin/derive).
    @State private var current: DensityMode = .functional

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {

            // Top close — settings mode only, never on first launch
            if !isFirstLaunch {
                topBar
            }

            ScrollView {
                VStack(alignment: .leading, spacing: Tokens.Spacing.xl) {

                    headerCopy

                    survivalButton

                    otherStatesPicker
                }
                .padding(.horizontal, Tokens.Spacing.xl)
                .padding(.vertical, Tokens.Spacing.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(Color.appBackground)
        .onAppear(perform: hydrate)
    }

    // MARK: - Subviews

    private var topBar: some View {
        HStack {
            Spacer()
            Button {
                isPresented = false
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundColor(Color.appTextSecondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
        .padding(.horizontal, Tokens.Spacing.lg)
        .padding(.top, Tokens.Spacing.base)
    }

    private var headerCopy: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.sm) {
            Text(isFirstLaunch ? "How are you?" : "Reset capacity")
                .font(Tokens.Typography.h1)
                .foregroundColor(Color.appTextPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Text("No wrong answers. You can change this any time from settings or by tapping the badge on Today.")
                .font(Tokens.Typography.body)
                .foregroundColor(Color.appTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The big calm escape button. Maps "I'm overwhelmed" → Survival.
    /// Visually distinct from the picker below — full-width, accent
    /// background, large vertical padding. This is the path designed
    /// to feel like an exhale.
    private var survivalButton: some View {
        Button {
            apply(.survival)
        } label: {
            VStack(alignment: .leading, spacing: Tokens.Spacing.sm) {
                HStack(spacing: Tokens.Spacing.sm) {
                    Image(systemName: "leaf.fill")
                        .font(.system(size: 20, weight: .regular))
                    Text("I'm overwhelmed")
                        .font(Tokens.Typography.h2)
                        .fontWeight(.semibold)
                }
                Text("Show me just one thing. Hide the rest.")
                    .font(Tokens.Typography.body)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, Tokens.Spacing.lg)
            .padding(.vertical, Tokens.Spacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.appAccent.opacity(0.18))
            .overlay(
                RoundedRectangle(cornerRadius: Tokens.Border.radiusLarge)
                    .strokeBorder(Color.appAccent.opacity(0.5), lineWidth: 1)
            )
            .foregroundColor(Color.appTextPrimary)
            .cornerRadius(Tokens.Border.radiusLarge)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("I'm overwhelmed. Set Survival mode — show me just one thing.")
    }

    /// Quieter dropdown of the other three states. Vertical list, each
    /// row a single-line tap target. The currently-selected mode (if
    /// any) gets a subtle highlight.
    private var otherStatesPicker: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.md) {
            Text("Or pick a different state")
                .font(Tokens.Typography.caption)
                .foregroundColor(Color.appTextSecondary)
                .padding(.leading, Tokens.Spacing.xs)

            VStack(spacing: Tokens.Spacing.sm) {
                pickerRow(.low,        title: "Low capacity",   subtitle: "Energy-matched picks. Minimal metadata.")
                pickerRow(.functional, title: "Functional",     subtitle: "Full day view. Standard density.")
                pickerRow(.high,       title: "High capacity",  subtitle: "Everything — backlog, tomorrow, completed.")
            }
        }
    }

    private func pickerRow(_ mode: DensityMode, title: String, subtitle: String) -> some View {
        Button {
            apply(mode)
        } label: {
            HStack(alignment: .top, spacing: Tokens.Spacing.md) {
                Image(systemName: current == mode ? "circle.inset.filled" : "circle")
                    .font(.system(size: 18))
                    .foregroundColor(current == mode ? Color.appAccent : Color.appBorder)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(Tokens.Typography.label)
                        .foregroundColor(Color.appTextPrimary)
                    Text(subtitle)
                        .font(Tokens.Typography.caption)
                        .foregroundColor(Color.appTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(Tokens.Spacing.base)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: Tokens.Spacing.touchMinimum)
            .background(
                current == mode
                    ? Color.appAccent.opacity(0.08)
                    : Color.appBackgroundSecondary
            )
            .cornerRadius(Tokens.Border.radiusMedium)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title). \(subtitle)")
    }

    // MARK: - Actions

    /// On first appearance, mirror the active profile's pin (if any) or
    /// the auto-derived mode (if not). Drives the picker's selection
    /// indicator so the user can see where they stand before changing.
    private func hydrate() {
        guard let prefs = profileManager.activePreferences else {
            current = .functional
            return
        }
        if let pinned = prefs.densityPinned {
            current = pinned
        } else {
            current = DensityMode.autoFrom(energyLevel: prefs.currentEnergyLevel)
        }
    }

    /// Commit a mode: update the active profile's preferences, save the
    /// model context, and dismiss. We set BOTH `currentEnergyLevel` (so
    /// auto-derivation also lands on this mode) and `densityPinnedRaw`
    /// (so the explicit choice persists past later energy fluctuations).
    private func apply(_ mode: DensityMode) {
        current = mode

        if let prefs = profileManager.activePreferences {
            prefs.currentEnergyLevel = energyLevel(for: mode)
            prefs.densityPinned = mode
            prefs.updatedAt = .now
            try? modelContext.save()
        }

        // Record the check-in so the stale-energy dot on the dashboard
        // anchor clears immediately.
        EnergyCheckInTracker.record()

        isPresented = false
    }

    /// Inverse of `DensityMode.autoFrom` — pick a representative energy
    /// level so the two fields stay in sync if the pin is later cleared.
    private func energyLevel(for mode: DensityMode) -> Int {
        switch mode {
        case .survival:   return 1
        case .low:        return 2
        case .functional: return 3
        case .high:       return 4
        }
    }
}

#Preview("First launch") {
    CognitiveStateSelector(isPresented: .constant(true), isFirstLaunch: true)
        .environmentObject(ActiveProfileManager.shared)
}

#Preview("Settings") {
    CognitiveStateSelector(isPresented: .constant(true), isFirstLaunch: false)
        .environmentObject(ActiveProfileManager.shared)
}
