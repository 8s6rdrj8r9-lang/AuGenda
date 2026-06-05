// AuGendaApp.swift
// AUDHD Agenda App

import SwiftUI
import SwiftData
import UserNotifications
#if canImport(WatchConnectivity)
import WatchConnectivity
#endif

@main
struct AuGendaApp: App {

    @StateObject private var notificationManager = NotificationManager.shared
    @StateObject private var blockManager = BlockManager.shared
    @StateObject private var profileManager = ActiveProfileManager.shared
    #if canImport(WatchConnectivity)
    @StateObject private var watchManager = WatchConnectivityManager.shared
    #endif

    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                // .dev = file-backed, no CloudKit yet. Fresh installs start
                // empty so the first-launch flow (ProfileSetup → capacity →
                // onboarding tour) fires correctly. Swap to .production once
                // the CloudKit container ID is real (see AppContainer.swift).
                .modelContainer(AppContainer.dev)
                .environmentObject(notificationManager)
                .environmentObject(blockManager)
                .environmentObject(profileManager)
                #if canImport(WatchConnectivity)
                .environmentObject(watchManager)
                #endif
        }
        .onChange(of: scenePhase) { _, newPhase in
            #if canImport(WatchConnectivity)
            switch newPhase {
            case .active:
                watchManager.sendSyncSnapshot()
                UNUserNotificationCenter.current().setBadgeCount(0)
            case .background:
                watchManager.sendSyncSnapshot()
            default:
                break
            }
            #else
            if newPhase == .active {
                UNUserNotificationCenter.current().setBadgeCount(0)
            }
            #endif
        }
    }
}


// MARK: - RootView
// Separate from ContentView so we can inject modelContext into managers on appear

struct RootView: View {

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var blockManager: BlockManager
    @EnvironmentObject private var profileManager: ActiveProfileManager
    #if canImport(WatchConnectivity)
    @EnvironmentObject private var watchManager: WatchConnectivityManager
    #endif

    @Query private var profiles: [Profile]

    @AppStorage("onboarding.completed") private var onboardingCompleted: Bool = false

    /// Mirrors the same key CognitiveStateSelector + ProfileSetupView use.
    /// Non-empty between capacity dismissal and ProfileSetupView's save —
    /// drives both the next-step decision in handleStepDismiss AND the
    /// minimal-mode rendering inside ProfileSetupView.
    @AppStorage("firstLaunch.pendingDensityRaw") private var pendingDensityRaw: String = ""

    /// Whether the user has been offered the capacity check-in frequency
    /// choice yet. Set true when onboarding closes (the choice lives on the
    /// final onboarding card) OR when the standalone `.checkInPreference`
    /// step is dismissed. Users who declared overwhelm on first launch skip
    /// onboarding, so this stays false for them until a later launch surfaces
    /// the standalone step — that's the "second launch" path.
    @AppStorage("checkIn.preferenceOffered") private var checkInPreferenceOffered: Bool = false

    @State private var showCheckInSelector = false

    /// First-launch sequence is driven by a single Step enum routed through
    /// one `.sheet(item:)` modifier. One sheet at a time, no sibling races.
    ///
    /// Order: capacity → profileSetup → onboarding (which carries the
    /// check-in choice on its final card). `checkInPreference` is a
    /// late-bound step shown on a later launch only for users who skipped
    /// onboarding and so never saw that card.
    enum FirstLaunchStep: String, Identifiable {
        case capacity
        case profileSetup
        case onboarding
        case checkInPreference

        var id: String { rawValue }
    }
    @State private var firstLaunchStep: FirstLaunchStep? = nil

    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ContentView()
            .onAppear {
                blockManager.modelContext = modelContext
                blockManager.seedDefaultsIfNeeded()

                // Give profileManager its context — triggers loadActiveProfile()
                profileManager.modelContext = modelContext

                #if canImport(WatchConnectivity)
                watchManager.modelContext = modelContext
                #endif

                // On a cold launch, a launch IS a foreground — so let
                // shouldPrompt decide for every mode (never / daily /
                // everyAppLaunch / everyForeground). The first-launch
                // capacity sheet owns brand-new installs, so this only
                // applies once a profile exists.
                if !profiles.isEmpty,
                   CognitiveCheckInTracker.shouldPrompt(scenePhase: .active) {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        showCheckInSelector = true
                    }
                }
            }
            // Check for recurring cognitive check-ins based on frequency
            .onChange(of: scenePhase) { _, newPhase in
                guard !profiles.isEmpty && firstLaunchStep == nil && !showCheckInSelector else { return }
                let freq = CognitiveCheckInTracker.frequency

                if newPhase == .active {
                    if (freq == .everyForeground || freq == .daily)
                        && CognitiveCheckInTracker.shouldPrompt(scenePhase: newPhase) {
                        showCheckInSelector = true
                    }
                }
            }

            // Decide what (if anything) to show on launch. Only kicks off
            // if no step is currently active — handleStepDismiss owns
            // mid-flow transitions, this just picks the entry point.
            .onChange(of: profiles.isEmpty, initial: true) { _, isEmpty in
                guard firstLaunchStep == nil else { return }
                if isEmpty {
                    // Brand-new install — start with the overwhelm check.
                    firstLaunchStep = .capacity
                } else if !onboardingCompleted
                       && profileManager.activePreferences?.densityPinned != nil
                       && profileManager.activePreferences?.densityPinned != .survival {
                    // Returning user who has a profile + capacity pin but
                    // never finished onboarding (and isn't in survival mode,
                    // since survival users skip onboarding entirely).
                    firstLaunchStep = .onboarding
                } else if onboardingCompleted && !checkInPreferenceOffered {
                    // Skipped onboarding (declared overwhelm on first launch)
                    // so never saw the in-onboarding check-in choice — offer
                    // it now, on this later launch. Also catches users from
                    // before this feature existed (one-time introduction).
                    firstLaunchStep = .checkInPreference
                }
            }
            .sheet(item: $firstLaunchStep, onDismiss: handleStepDismiss) { step in
                switch step {
                case .profileSetup:
                    ProfileSetupView(
                        isPresented: dismissBinding(for: .profileSetup),
                        isOnboarding: true
                    )
                case .capacity:
                    CognitiveStateSelector(
                        isPresented: dismissBinding(for: .capacity),
                        isFirstLaunch: true
                    )
                case .onboarding:
                    // Mark completion in the binding's set closure so
                    // handleStepDismiss can read it correctly on the next
                    // tick — otherwise the dismiss handler would see
                    // !onboardingCompleted still true and re-present.
                    // The final onboarding card carries the check-in choice,
                    // so reaching the end counts as "offered."
                    OnboardingView(
                        isPresented: dismissBinding(for: .onboarding) {
                            onboardingCompleted = true
                            checkInPreferenceOffered = true
                        }
                    )
                case .checkInPreference:
                    CheckInPreferenceStep(
                        isPresented: dismissBinding(for: .checkInPreference) {
                            checkInPreferenceOffered = true
                        }
                    )
                }
            }
            .sheet(isPresented: $showCheckInSelector) {
                CognitiveStateSelector(
                    isPresented: $showCheckInSelector,
                    isFirstLaunch: false
                )
            }
    }

    /// Reusable binding for each step's `isPresented` parameter. On dismiss
    /// (set to false), runs an optional callback BEFORE clearing the step —
    /// useful for committing per-step completion flags (like
    /// `onboardingCompleted = true`) before `handleStepDismiss` reads them.
    private func dismissBinding(
        for step: FirstLaunchStep,
        onClose: (() -> Void)? = nil
    ) -> Binding<Bool> {
        Binding(
            get: { firstLaunchStep == step },
            set: { newValue in
                if !newValue {
                    onClose?()
                    firstLaunchStep = nil
                }
            }
        )
    }

    /// Sheet onDismiss handler — runs after each step closes. Each branch
    /// guards against re-triggering by checking the side-effect that the
    /// just-finished step would have written (pendingDensity stashed,
    /// profile created, onboarding flag set).
    ///
    /// New order: capacity → profileSetup → (maybe) onboarding.
    /// Survival/Low capacity skips onboarding entirely — these users are
    /// asking the app to leave them alone.
    private func handleStepDismiss() {
        // Capacity just dismissed: a mode is parked in pendingDensityRaw,
        // no profile yet → profileSetup. CognitiveStateSelector in first-
        // launch mode can't be dismissed without committing, so this branch
        // always fires after the capacity step.
        if !pendingDensityRaw.isEmpty && profiles.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                firstLaunchStep = .profileSetup
            }
            return
        }

        // ProfileSetup may have been cancelled — no profile created.
        // Bail out; user can re-enter via Settings → Add profile.
        guard !profiles.isEmpty else { return }

        // Profile just created → onboarding decision based on chosen mode.
        if !onboardingCompleted {
            let mode = profileManager.activePreferences?.densityPinned
                ?? DensityMode.autoFrom(
                    energyLevel: profileManager.activePreferences?.currentEnergyLevel ?? 3
                )

            // Survival + Low capacity users skip the onboarding tour — the
            // whole point of declaring overwhelm is to NOT be tour-walked.
            // Mark complete so we never offer it again unless they reset.
            if mode == .survival || mode == .low {
                onboardingCompleted = true
                return
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                firstLaunchStep = .onboarding
            }
            return
        }

        // Onboarding just dismissed — no next step.
    }
}
