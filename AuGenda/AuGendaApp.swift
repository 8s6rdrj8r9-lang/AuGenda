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
    @State private var showOnboarding = false

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
            // Show onboarding on first launch (no profiles) and if all profiles are deleted
            .onChange(of: profiles.isEmpty, initial: true) { _, isEmpty in
                if isEmpty { showOnboarding = true }
            }
            .fullScreenCover(isPresented: $showOnboarding) {
                ProfileSetupView(isPresented: $showOnboarding, isOnboarding: true)
            }
    }
}
