// WatchAppContainer.swift
// AuGenda Watch
//
// Offline-first SwiftData container for the watchOS app (and, eventually,
// the widget extension once the App Group capability is configured).
//
// The watch owns its own ModelContainer (Spec §12, §18: "own SwiftData +
// CloudKit store on the watch — true offline, independent sync"). When
// the iCloud capability is configured on the watch target, this container
// will sync against `iCloud.com.augenda.AuGenda` — the same container
// the iOS app uses — so records converge transparently.
//
// SHARED schema contract: the @Model class declarations in AgendaItem.swift,
// AgendaTask.swift, and ProfileModels.swift in this directory MUST stay in
// sync with the iOS app's copies under AuGenda/. Future v2: extract to a
// Swift Package and drop the duplicates.

import Foundation
import SwiftData

/// CloudKit container identifier — must match `AuGenda/AppContainer.swift`
/// and the entitlements of every target that talks to this store.
private let cloudKitContainerID = "iCloud.com.augenda.AuGenda"

enum WatchAppContainer {

    /// Production container. Once iCloud capability is wired on the watch
    /// target, swap the `cloudKitDatabase` argument back in (commented out
    /// below) to enable transparent cross-device sync.
    @MainActor static let production: ModelContainer = {
        let schema = Schema([
            AgendaItem.self,
            SubTask.self,
            AgendaTask.self,
            TaskStep.self,
            Profile.self,
            ProfilePreferences.self
        ])

        // TODO(watch v2): once the iCloud capability is configured on the
        // AuGendaWatch target, change `cloudKitDatabase:` to `.private(...)`
        // so the watch syncs against the same private CloudKit container
        // the iOS app uses.
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false
            // cloudKitDatabase: .private(cloudKitContainerID)
        )

        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            // Watch falls back to in-memory rather than crashing — the
            // orientation anchor must keep functioning even if persistent
            // setup fails (Spec §1, §15: never block the glance).
            return Self.inMemoryFallback()
        }
    }()

    @MainActor static func inMemoryFallback() -> ModelContainer {
        let schema = Schema([
            AgendaItem.self,
            SubTask.self,
            AgendaTask.self,
            TaskStep.self,
            Profile.self,
            ProfilePreferences.self
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        // If even the in-memory container fails, the watch is in an
        // unrecoverable state — but we keep the cast non-throwing so the
        // app boots with a quiet error rather than a crash dialog.
        return (try? ModelContainer(for: schema, configurations: [config])) ?? Self.emergency()
    }

    @MainActor private static func emergency() -> ModelContainer {
        // Last-resort empty container so the app type-checks. UI handles
        // empty-state gracefully via the "Nothing scheduled" copy.
        let schema = Schema([AgendaItem.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            // Absolute last resort — this should never happen for in-memory.
            fatalError("WatchWidgetContainer: even in-memory emergency fallback failed: \(error)")
        }
    }

    /// Seed a single demo item so the watch always shows *something* on first
    /// run with no iPhone paired — keeps the win condition honest (§goal).
    @MainActor static func seedIfEmpty(_ context: ModelContext) {
        let descriptor = FetchDescriptor<AgendaItem>()
        let count = (try? context.fetchCount(descriptor)) ?? 0
        guard count == 0 else { return }

        let now = Date.now
        let in15min = now.addingTimeInterval(15 * 60)
        let demo = AgendaItem(
            title: "Welcome — tap to mark done",
            scheduledDate: in15min,
            priority: 0,
            frictionLevel: 2,
            energyRequired: 1,
            contextTag: "home"
        )
        context.insert(demo)
        try? context.save()
    }
}
