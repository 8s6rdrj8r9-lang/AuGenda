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
                .modelContainer(AppContainer.preview) // swap to .production when CloudKit is set up
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

    // Onboarding-completed flag also lives here so we can chain the three
    // first-launch sheets serially. Mirrors the @AppStorage in ContentView
    // (same key) — either site reads / writes the same UserDefault.
    @AppStorage("onboarding.completed") private var onboardingCompleted: Bool = false

    /// First-launch sequence is driven by a single Step enum routed through
    /// one `.sheet(item:)` modifier. Two `.sheet` modifiers on the same view
    /// race with each other AND with ContentView's own sheet attachments,
    /// which is what was breaking the original chain. One sheet = one
    /// guaranteed presentation at a time.
    enum FirstLaunchStep: String, Identifiable {
        case profileSetup
        case capacity
        case onboarding

        var id: String { rawValue }
    }
    @State private var firstLaunchStep: FirstLaunchStep? = nil

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
            }
            // Decide what (if anything) to show on launch. Only kicks off
            // if no step is currently active — handleStepDismiss owns mid-
            // flow transitions, this owner just picks the entry point.
            .onChange(of: profiles.isEmpty, initial: true) { _, isEmpty in
                guard firstLaunchStep == nil else { return }
                if isEmpty {
                    firstLaunchStep = .profileSetup
                } else if !onboardingCompleted
                       && profileManager.activePreferences?.densityPinned != nil {
                    // Existing profile with capacity already set but onboarding
                    // never finished — pick up at the tour. (Existing profile
                    // WITHOUT capacity pinned skips this and lands on the
                    // dashboard; settings has "Set capacity" for that.)
                    firstLaunchStep = .onboarding
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
                    OnboardingView(
                        isPresented: dismissBinding(for: .onboarding) {
                            onboardingCompleted = true
                        }
                    )
                }
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
    /// just-finished step would have written (profile exists, density pinned,
    /// onboarding flag set). Without those guards, finishing a step would
    /// loop us right back into it.
    private func handleStepDismiss() {
        // User bailed out of ProfileSetup → no profile, no chain. They can
        // re-trigger via Settings → Profiles → Add profile later.
        guard !profiles.isEmpty else { return }

        // Profile exists but capacity not pinned yet → step 2.
        if profileManager.activePreferences?.densityPinned == nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                firstLaunchStep = .capacity
            }
            return
        }

        // Capacity pinned but onboarding tour not finished → step 3.
        if !onboardingCompleted {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                firstLaunchStep = .onboarding
            }
            return
        }

        // All three steps complete — nothing more to do. handleStepDismiss
        // returns silently and the user lands on ContentView.
    }
}
