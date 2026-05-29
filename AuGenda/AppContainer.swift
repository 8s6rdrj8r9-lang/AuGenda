// AppContainer.swift
// AUDHD Agenda App

import Foundation
import SwiftData

/// CloudKit container identifier. The value here MUST match the entry in
/// `AuGenda.entitlements` AND a container the Apple Developer Portal team
/// owns. For App Store ship, change the reverse-DNS prefix to your team's
/// actual bundle ID — typically `iCloud.<your-team>.AuGenda`.
private let cloudKitContainerID = "iCloud.com.augenda.AuGenda"

enum AppContainer {

    static var production: ModelContainer = {
        let schema = Schema([
            AgendaItem.self,
            SubTask.self,
            AgendaTask.self,
            TaskStep.self,
            UserPreferences.self,
            Block.self,
            BlockTask.self,
            BundleTemplate.self,
            BundleTemplateItem.self,
            AttachedBundle.self,
            AttachedBundleItem.self,
            Profile.self,
            ProfilePreferences.self
        ])

        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .private(cloudKitContainerID)
        )

        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to create production ModelContainer: \(error)")
        }
    }()

    static func makeTestContainer() -> ModelContainer {
        let schema = Schema([
            AgendaItem.self,
            SubTask.self,
            AgendaTask.self,
            TaskStep.self,
            UserPreferences.self,
            Block.self,
            BlockTask.self,
            BundleTemplate.self,
            BundleTemplateItem.self,
            AttachedBundle.self,
            AttachedBundleItem.self,
            Profile.self,
            ProfilePreferences.self
        ])

        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true
        )

        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to create test ModelContainer: \(error)")
        }
    }

    @MainActor
    static var preview: ModelContainer = {
        let container = makeTestContainer()
        SampleData.populate(context: container.mainContext)
        return container
    }()
}


// MARK: - UserPreferences

@Model
final class UserPreferences {

    var clientID: UUID = UUID()
    var updatedAt: Date = Date.now
    var currentEnergyLevel: Int = 3
    var lowEFMaxFriction: Int = 2
    var focusSessionMinutes: Int = 25
    var breakMinutes: Int = 10
    var notificationStyle: String = "standard"
    var watchComplicationMode: String = "next-task"
    var theme: String = "system"
    var minimalMode: Bool = false

    init() {
        self.clientID = UUID()
        self.updatedAt = .now
    }
}


// MARK: - Sample Data

enum SampleData {

    @MainActor
    static func populate(context: ModelContext) {
        let prefs = UserPreferences()
        prefs.currentEnergyLevel = 2
        context.insert(prefs)

        // Sample profiles
        let coordinator = Profile(name: "Arthur", role: .coordinator, neurotypes: [.adhd, .autism], sortOrder: 0)
        let coordPrefs = ProfilePreferences.makePreset(for: [.adhd, .autism])
        coordPrefs.currentEnergyLevel = 2
        coordinator.preferences = coordPrefs
        context.insert(coordinator)
        context.insert(coordPrefs)

        let partner = Profile(name: "Partner", role: .adult, neurotypes: [.autism], sortOrder: 1)
        let partnerPrefs = ProfilePreferences.makePreset(for: [.autism])
        partner.preferences = partnerPrefs
        context.insert(partner)
        context.insert(partnerPrefs)

        let child = Profile(name: "Kid", role: .child, neurotypes: [.adhd], sortOrder: 2)
        let childPrefs = ProfilePreferences.makePreset(for: [.adhd])
        childPrefs.largeTouchTargets = true
        child.preferences = childPrefs
        context.insert(child)
        context.insert(childPrefs)

        let items: [(String, Int, Int, String)] = [
            ("Morning meds", 1, 1, "home"),
            ("Review agenda", 2, 2, "focus"),
            ("Tile grouting — bathroom", 4, 3, "home"),
            ("Call re: PWD paperwork", 3, 2, "phone"),
            ("Order grout sealer", 2, 1, "computer")
        ]

        for (index, (title, friction, energy, contextTag)) in items.enumerated() {
            let item = AgendaItem(
                title: title,
                scheduledDate: Calendar.current.date(
                    byAdding: .hour, value: index, to: .now) ?? .now,
                priority: index == 0 ? 2 : 0,
                frictionLevel: friction,
                energyRequired: energy,
                contextTag: contextTag
            )
            context.insert(item)
        }

        let tasks: [(String, Int, Int, Int)] = [
            ("Research grout sealers", 2, 1, 4),
            ("Email landlord re: window repair", 4, 2, 2),
            ("Set up watch complications", 2, 1, 5),
            ("Tolerance break plan", 1, 1, 3)
        ]

        for (title, friction, energy, interest) in tasks {
            let task = AgendaTask(
                title: title,
                frictionLevel: friction,
                energyRequired: energy,
                estimatedMinutes: 20,
                interestLevel: interest
            )
            context.insert(task)
        }
    }
}
