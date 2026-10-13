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

// MARK: - Check-in frequency

enum CognitiveCheckInFrequency: String, CaseIterable, Identifiable {
    case never           = "never"
    case daily           = "daily"
    case everyAppLaunch  = "everyAppLaunch"
    case everyForeground = "everyForeground"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .never:           return "Never"
        case .daily:           return "Once daily"
        case .everyAppLaunch:  return "Every app launch"
        case .everyForeground: return "Every time app comes to foreground"
        }
    }

    var description: String {
        switch self {
        case .never:           return "Disable check-in prompts"
        case .daily:           return "Show once per day if available"
        case .everyAppLaunch:  return "Every time you restart the app"
        case .everyForeground: return "Every time the app comes from background"
        }
    }
}

// MARK: - Tracker

enum CognitiveCheckInTracker {
    private static let lastCheckInKey = "cognitiveCheckIn.lastTimestamp"
    private static let frequencyKey = "cognitiveCheckIn.frequency"
    private static let dailyRollingKey = "cognitiveCheckIn.dailyRolling24h"

    /// Defaults to `.never` — the user opts in during onboarding (or on a
    /// later launch if they were overwhelmed on first launch and skipped the
    /// onboarding tour). Nothing prompts until they explicitly choose.
    static var frequency: CognitiveCheckInFrequency {
        get {
            let raw = UserDefaults.standard.string(forKey: frequencyKey) ?? "never"
            return CognitiveCheckInFrequency(rawValue: raw) ?? .never
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: frequencyKey) }
    }

    /// Only meaningful when `frequency == .daily`.
    /// • false (default) → "first use of the day": re-asks the first time the
    ///   app is opened each calendar day (resets at midnight).
    /// • true → 24-hour rolling window: re-asks only once a full 24 hours has
    ///   elapsed since the last check-in (11pm → 11pm the next night).
    static var dailyUsesRollingWindow: Bool {
        get { UserDefaults.standard.bool(forKey: dailyRollingKey) }
        set { UserDefaults.standard.set(newValue, forKey: dailyRollingKey) }
    }

    static func shouldPrompt(scenePhase: ScenePhase) -> Bool {
        let freq = frequency
        guard freq != .never else { return false }

        let lastTime = UserDefaults.standard.double(forKey: lastCheckInKey)
        let lastDate = lastTime > 0 ? Date(timeIntervalSince1970: lastTime) : nil

        switch freq {
        case .never:
            return false
        case .daily:
            guard let last = lastDate else { return true }
            if dailyUsesRollingWindow {
                // Rolling window: a full 24 hours must elapse since the last
                // check-in (a check-in at 11pm won't re-prompt until 11pm the
                // next night). Opt-in alternative to the calendar-day reset.
                return Date.now.timeIntervalSince(last) >= 24 * 60 * 60
            }
            // Default: first use of the day — re-asks the first time the app
            // is opened each calendar day (resets at midnight), regardless of
            // how late the previous check-in was.
            return !Calendar.current.isDateInToday(last)
        case .everyAppLaunch:
            // Always prompt on fresh app launch (scenePhase transitions to active from nothing)
            // We'll let the caller decide based on initialization
            return true
        case .everyForeground:
            // Always prompt when foreground (every scenePhase == .active)
            return scenePhase == .active
        }
    }

    static func record() {
        UserDefaults.standard.set(Date.now.timeIntervalSince1970, forKey: lastCheckInKey)
    }

    static func reset() {
        UserDefaults.standard.removeObject(forKey: lastCheckInKey)
    }
}

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

    /// First-launch fallback when this view runs BEFORE a profile exists.
    /// The chosen mode is parked here; `ProfileSetupView.saveProfile` reads
    /// the value when it creates the profile and applies it to the new
    /// ProfilePreferences, then clears the key.
    @AppStorage("firstLaunch.pendingDensityRaw") private var pendingDensityRaw: String = ""

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
                    .font(.title3)
                    .foregroundColor(Color.appTextSecondary)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
            .accessibilityHint("Keeps the current capacity setting")
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
                .accessibilityIdentifier("capacity.title")

            Text("No wrong answers. You can change this any time from settings or by tapping the badge on Today.")
                .font(Tokens.Typography.body)
                .foregroundColor(Color.appTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The big calm escape button. Maps "I'm overwhelmed" → Survival.
    /// Visually distinct from the picker below — full-width, warm tinted
    /// background, large vertical padding. The intentionally warm palette
    /// (peach/ember) reads as inviting rather than the cool blue accent,
    /// which carries an admin/info emotion in the design system.
    private var survivalButton: some View {
        Button {
            apply(.survival)
        } label: {
            VStack(alignment: .leading, spacing: Tokens.Spacing.sm) {
                HStack(spacing: Tokens.Spacing.sm) {
                    Image(systemName: "leaf.fill")
                        .font(.title3)
                        .foregroundStyle(Color.warmEmber)
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
            .background(Color.warmEmber.opacity(0.18))
            .overlay(
                RoundedRectangle(cornerRadius: Tokens.Border.radiusLarge)
                    .strokeBorder(Color.warmEmber.opacity(0.45), lineWidth: 1)
            )
            .foregroundColor(Color.appTextPrimary)
            .cornerRadius(Tokens.Border.radiusLarge)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("I'm overwhelmed. Set Survival mode — show me just one thing.")
        .accessibilityIdentifier("capacity.survival")
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
                    .font(.headline)
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
        current = profileManager.activePreferences?.effectiveDensity ?? .functional
    }

    /// Commit a mode. Two code paths:
    ///
    /// • Settings mode (profile already exists) → write directly to the
    ///   active profile's ProfilePreferences and save the model context.
    /// • First-launch mode (no profile yet — capacity runs BEFORE profile
    ///   setup) → stash the choice in `pendingDensityRaw`. ProfileSetupView
    ///   will pick it up when it creates the profile.
    ///
    /// Under Option A a check-in is a SIGNAL, never a pin: we write
    /// `currentEnergyLevel` only (via the shared `representativeEnergyLevel`
    /// mapping) so `effectiveDensity` resolves to this mode while leaving the
    /// user free to be re-nudged by the advisor. The density picker sheet is
    /// the only surface that pins.
    private func apply(_ mode: DensityMode) {
        current = mode

        if let prefs = profileManager.activePreferences {
            prefs.currentEnergyLevel = mode.representativeEnergyLevel
            prefs.updatedAt = .now
            do {
                try modelContext.save()
            } catch {
                modelContext.rollback()
                current = prefs.effectiveDensity
                ErrorBannerController.shared.show("Couldn't save: \(error.localizedDescription)")
                return
            }
        } else {
            // No active profile yet — first-launch flow. Park the choice;
            // ProfileSetupView reads + applies + clears it on save.
            pendingDensityRaw = mode.rawValue
        }

        // Record the check-in so the stale-energy dot on the dashboard
        // anchor clears immediately.
        EnergyCheckInTracker.record()

        // Record the capacity check-in timestamp so the "Once daily"
        // frequency mode can throttle correctly. Harmless for the other
        // modes (they ignore the timestamp).
        CognitiveCheckInTracker.record()

        isPresented = false
    }
}

// MARK: - Check-in frequency chooser (reusable)
//
// The four-option picker shared by the onboarding card and the standalone
// first-launch step. Writes straight to the tracker on each tap so the
// choice persists immediately; the surrounding flow marks "offered" when it
// closes. Defaults its highlight to whatever the tracker currently holds
// (.never for a fresh install).

struct CheckInFrequencyChooser: View {

    @State private var selection: CognitiveCheckInFrequency = CognitiveCheckInTracker.frequency

    var body: some View {
        VStack(spacing: Tokens.Spacing.sm) {
            ForEach(CognitiveCheckInFrequency.allCases) { freq in
                Button {
                    selection = freq
                    CognitiveCheckInTracker.frequency = freq
                } label: {
                    HStack(alignment: .top, spacing: Tokens.Spacing.md) {
                        Image(systemName: selection == freq ? "circle.inset.filled" : "circle")
                            .font(.headline)
                            .foregroundColor(selection == freq ? Color.appAccent : Color.appBorder)
                            .padding(.top, 2)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(freq.displayName)
                                .font(Tokens.Typography.label)
                                .foregroundColor(Color.appTextPrimary)
                            Text(freq.description)
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
                        selection == freq
                            ? Color.appAccent.opacity(0.08)
                            : Color.appBackgroundSecondary
                    )
                    .cornerRadius(Tokens.Border.radiusMedium)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(freq.displayName). \(freq.description)")
            }
        }
    }
}

// MARK: - Standalone check-in preference step
//
// Shown as its own first-launch sheet when the user skipped the onboarding
// tour (declared overwhelm on first launch) and therefore never saw the
// in-onboarding chooser. Surfaces the same choice on the next launch.

struct CheckInPreferenceStep: View {

    @Binding var isPresented: Bool

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Tokens.Spacing.xl) {
                    VStack(alignment: .leading, spacing: Tokens.Spacing.sm) {
                        Text("Capacity check-ins")
                            .font(Tokens.Typography.h1)
                            .foregroundColor(Color.appTextPrimary)
                            .fixedSize(horizontal: false, vertical: true)

                        Text("When you open AuGenda, it can ask how you're doing and match the view to your capacity. It's off for now — pick what suits you. You can change this anytime in Settings.")
                            .font(Tokens.Typography.body)
                            .foregroundColor(Color.appTextSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    CheckInFrequencyChooser()
                }
                .padding(.horizontal, Tokens.Spacing.xl)
                .padding(.vertical, Tokens.Spacing.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button {
                isPresented = false
            } label: {
                Text("Done")
                    .font(Tokens.Typography.label)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Tokens.Spacing.base)
                    .background(Color.appAccent, in: RoundedRectangle(cornerRadius: Tokens.Border.radiusLarge))
                    .foregroundColor(.black)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)
            .padding(.horizontal, Tokens.Spacing.xl)
            .padding(.bottom, Tokens.Spacing.lg)
        }
        .background(Color.appBackground)
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
