import CryptoKit
import Foundation
import XCTest
import SwiftData
@testable import AuGenda

final class MigrationTests: XCTestCase {

    private static let frozenV1SHA256 =
        "2ca0c9baf8dfd8960e9cbad9b9566635b208d08531f8621b77cfc6d13c2e331b"

    private var frozenV1StoreURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/AuGendaV1.store")
    }

    private func sha256(of url: URL) throws -> String {
        let digest = SHA256.hash(data: try Data(contentsOf: url))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func makeTemporaryFixtureCopy() throws -> (directory: URL, store: URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "AuGendaFrozenMigration-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let destination = directory.appendingPathComponent("AuGendaV1.store")
        try FileManager.default.copyItem(at: frozenV1StoreURL, to: destination)
        return (directory, destination)
    }

    private func assertDate(
        _ actual: Date?,
        _ expected: Date,
        accuracy: TimeInterval = 0.001,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let actual else {
            XCTFail("Expected a date", file: file, line: line)
            return
        }
        XCTAssertEqual(
            actual.timeIntervalSince1970,
            expected.timeIntervalSince1970,
            accuracy: accuracy,
            file: file,
            line: line
        )
    }

    func testFrozenV1FixtureIsImmutableEvidence() throws {
        XCTAssertTrue(FileManager.default.fileExists(atPath: frozenV1StoreURL.path))
        XCTAssertEqual(try sha256(of: frozenV1StoreURL), Self.frozenV1SHA256)
    }

    @MainActor
    func testV1DataSurvivesV2Migration() throws {
        let fixture = try makeTemporaryFixtureCopy()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }

        let v2Schema = Schema(AuGendaSchemaV2.models)
        let configuration = ModelConfiguration(
            "FrozenV1",
            schema: v2Schema,
            url: fixture.store,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(
            for: v2Schema,
            migrationPlan: AuGendaMigrationPlan.self,
            configurations: [configuration]
        )
        let context = container.mainContext
        let baseDate = Date(timeIntervalSince1970: 1_700_000_000)

        let profiles = try context.fetch(FetchDescriptor<Profile>())
        XCTAssertEqual(profiles.count, 1)
        let profile = try XCTUnwrap(profiles.first)
        XCTAssertEqual(
            profile.clientID,
            UUID(uuidString: "00000000-0000-0000-0000-000000000001")
        )
        XCTAssertEqual(profile.name, "Legacy Profile")
        XCTAssertEqual(profile.role, .coordinator)
        XCTAssertEqual(profile.neurotypes, [.adhd, .autism])
        XCTAssertEqual(profile.avatarImageData, Data([1, 2, 3, 4]))
        XCTAssertEqual(profile.avatarColorHex, "#123456")
        XCTAssertEqual(profile.sortOrder, 7)
        assertDate(profile.createdAt, baseDate)
        assertDate(profile.updatedAt, baseDate.addingTimeInterval(1))

        let profilePreferences = try XCTUnwrap(profile.preferences)
        XCTAssertEqual(
            profilePreferences.clientID,
            UUID(uuidString: "00000000-0000-0000-0000-000000000002")
        )
        XCTAssertEqual(profilePreferences.profile?.clientID, profile.clientID)
        XCTAssertEqual(profilePreferences.currentEnergyLevel, 4)
        XCTAssertFalse(profilePreferences.energyTrackingEnabled)
        XCTAssertEqual(profilePreferences.lowEFMaxFriction, 4)
        XCTAssertEqual(profilePreferences.densityPinnedRaw, "high")
        XCTAssertEqual(profilePreferences.focusSessionMinutes, 47)
        XCTAssertEqual(profilePreferences.breakMinutes, 13)
        XCTAssertTrue(profilePreferences.hyperfocusGuard)
        XCTAssertEqual(profilePreferences.taskLanguageStyleRaw, "choiceOnly")
        XCTAssertEqual(profilePreferences.frictionLabelRaw, "effort")
        XCTAssertEqual(profilePreferences.transitionPrepMinutes, 11)
        XCTAssertTrue(profilePreferences.routineProtectionEnabled)
        XCTAssertTrue(profilePreferences.timeBlindnessWarningsEnabled)
        XCTAssertFalse(profilePreferences.deadlinePressureVisible)
        XCTAssertEqual(profilePreferences.notificationStyleRaw, "predictable")
        XCTAssertEqual(profilePreferences.maxNotificationsPerHour, 2)
        XCTAssertFalse(profilePreferences.notificationPrivacyStrict)
        XCTAssertEqual(profilePreferences.appFontRaw, "system")
        XCTAssertTrue(profilePreferences.minimalMode)
        XCTAssertTrue(profilePreferences.largeTouchTargets)
        XCTAssertTrue(profilePreferences.sensoryContextTagsEnabled)
        XCTAssertTrue(profilePreferences.highContrastMode)
        XCTAssertFalse(profilePreferences.showCheckInNudges)
        XCTAssertTrue(profilePreferences.lowStimulationMode)
        XCTAssertTrue(profilePreferences.reduceMotion)
        XCTAssertEqual(profilePreferences.uiScale, 1.5)
        XCTAssertEqual(profilePreferences.watchComplicationMode, "energy")
        XCTAssertEqual(profilePreferences.appliedPresetRaw, "adhd,autism")
        assertDate(profilePreferences.updatedAt, baseDate.addingTimeInterval(2))

        let agendaItems = try context.fetch(FetchDescriptor<AgendaItem>())
        XCTAssertEqual(agendaItems.count, 1)
        let agenda = try XCTUnwrap(agendaItems.first)
        XCTAssertEqual(
            agenda.clientID,
            UUID(uuidString: "00000000-0000-0000-0000-000000000010")
        )
        XCTAssertEqual(agenda.title, "Legacy agenda")
        XCTAssertEqual(agenda.notes, "Legacy agenda notes")
        assertDate(agenda.createdAt, baseDate.addingTimeInterval(10))
        assertDate(agenda.updatedAt, baseDate.addingTimeInterval(11))
        assertDate(agenda.scheduledDate, baseDate.addingTimeInterval(100))
        assertDate(agenda.dueDate, baseDate.addingTimeInterval(200))
        XCTAssertTrue(agenda.isAllDay)
        assertDate(agenda.snoozedUntil, baseDate.addingTimeInterval(150))
        XCTAssertEqual(agenda.frictionLevel, 4)
        XCTAssertEqual(agenda.energyRequired, 3)
        XCTAssertEqual(agenda.contextTag, "phone")
        XCTAssertTrue(agenda.needsBodyDouble)
        XCTAssertEqual(agenda.interestLevel, 5)
        XCTAssertEqual(agenda.sensoryLoad, 3)
        XCTAssertEqual(agenda.socialLoad, 2)
        XCTAssertEqual(agenda.initiationCost, 1)
        XCTAssertTrue(agenda.specialInterest)
        XCTAssertTrue(agenda.excludeFromAI)
        XCTAssertTrue(agenda.isComplete)
        assertDate(agenda.completedAt, baseDate.addingTimeInterval(175))
        XCTAssertEqual(agenda.priority, 2)
        XCTAssertEqual(agenda.sortOrder, 9)
        XCTAssertEqual(agenda.recurrenceRule, "weekly")
        XCTAssertEqual(
            agenda.recurrenceParentID,
            UUID(uuidString: "00000000-0000-0000-0000-000000000011")
        )
        XCTAssertEqual(agenda.assignedToProfileID, profile.clientID)
        XCTAssertEqual(
            agenda.assignedByProfileID,
            UUID(uuidString: "00000000-0000-0000-0000-000000000012")
        )
        let subTask = try XCTUnwrap(agenda.subTasks?.first)
        XCTAssertEqual(subTask.title, "Legacy subtask")
        XCTAssertTrue(subTask.isComplete)
        XCTAssertEqual(subTask.sortOrder, 3)
        XCTAssertEqual(subTask.parentItem?.clientID, agenda.clientID)
        assertDate(subTask.createdAt, baseDate.addingTimeInterval(13))

        let tasks = try context.fetch(FetchDescriptor<AgendaTask>())
        XCTAssertEqual(tasks.count, 1)
        let task = try XCTUnwrap(tasks.first)
        XCTAssertEqual(
            task.clientID,
            UUID(uuidString: "00000000-0000-0000-0000-000000000020")
        )
        XCTAssertEqual(task.title, "Legacy backlog task")
        XCTAssertEqual(task.notes, "Legacy task notes")
        assertDate(task.createdAt, baseDate.addingTimeInterval(20))
        assertDate(task.updatedAt, baseDate.addingTimeInterval(21))
        assertDate(task.scheduledDate, baseDate.addingTimeInterval(300))
        assertDate(task.dueDate, baseDate.addingTimeInterval(400))
        XCTAssertEqual(task.frictionLevel, 4)
        XCTAssertEqual(task.energyRequired, 3)
        XCTAssertEqual(task.estimatedMinutes, 91)
        XCTAssertEqual(task.contextTag, "computer")
        XCTAssertTrue(task.hyperfocusRisk)
        XCTAssertTrue(task.needsBodyDouble)
        XCTAssertEqual(task.waitingOn, "Legacy dependency")
        XCTAssertEqual(task.interestLevel, 5)
        XCTAssertEqual(task.sensoryLoad, 1)
        XCTAssertEqual(task.socialLoad, 2)
        XCTAssertEqual(task.initiationCost, 3)
        XCTAssertTrue(task.specialInterest)
        XCTAssertTrue(task.excludeFromAI)
        XCTAssertEqual(task.priority, 2)
        XCTAssertEqual(task.sortOrder, 8)
        XCTAssertTrue(task.isComplete)
        assertDate(task.completedAt, baseDate.addingTimeInterval(350))
        assertDate(task.isDeferredUntil, baseDate.addingTimeInterval(250))
        XCTAssertTrue(task.isAbandoned)
        assertDate(task.abandonedAt, baseDate.addingTimeInterval(360))
        XCTAssertEqual(task.abandonReason, "Legacy reason")
        XCTAssertEqual(task.recurrenceRule, "daily")
        XCTAssertEqual(task.recurrenceParentID, agenda.clientID)
        XCTAssertEqual(task.assignedToProfileID, profile.clientID)
        XCTAssertEqual(task.assignedByProfileID, agenda.assignedByProfileID)
        XCTAssertEqual(task.agendaItemID, agenda.clientID)
        let taskStep = try XCTUnwrap(task.steps?.first)
        XCTAssertEqual(taskStep.title, "Legacy task step")
        XCTAssertTrue(taskStep.isComplete)
        XCTAssertEqual(taskStep.sortOrder, 4)
        XCTAssertEqual(taskStep.estimatedMinutes, 17)
        XCTAssertEqual(taskStep.parentTask?.clientID, task.clientID)
        assertDate(taskStep.createdAt, baseDate.addingTimeInterval(22))

        let inboxItems = try context.fetch(FetchDescriptor<InboxItem>())
        XCTAssertEqual(inboxItems.count, 1)
        let inbox = try XCTUnwrap(inboxItems.first)
        XCTAssertEqual(
            inbox.clientID,
            UUID(uuidString: "00000000-0000-0000-0000-000000000030")
        )
        XCTAssertEqual(inbox.rawCapture, "Legacy inbox capture")
        XCTAssertEqual(inbox.source, .voiceCapture)
        XCTAssertEqual(inbox.stateRaw, "organized")
        XCTAssertEqual(inbox.aiSuggestedTitle, "Legacy suggestion")
        XCTAssertEqual(inbox.aiSuggestedFriction, 4)
        XCTAssertEqual(inbox.aiSuggestedEnergy, 3)
        XCTAssertEqual(inbox.aiSuggestedInitiationCost, 2)
        XCTAssertEqual(inbox.aiSuggestedSensoryLoad, 1)
        XCTAssertEqual(inbox.aiSuggestedSocialLoad, 2)
        XCTAssertEqual(inbox.aiSuggestedContextTag, "outside")
        XCTAssertEqual(inbox.resolvedTaskID, task.clientID)
        XCTAssertEqual(inbox.assignedToProfileID, profile.clientID)
        assertDate(inbox.createdAt, baseDate.addingTimeInterval(30))
        assertDate(inbox.updatedAt, baseDate.addingTimeInterval(31))

        let blocks = try context.fetch(FetchDescriptor<Block>())
        XCTAssertEqual(blocks.count, 1)
        let block = try XCTUnwrap(blocks.first)
        XCTAssertEqual(
            block.clientID,
            UUID(uuidString: "00000000-0000-0000-0000-000000000040")
        )
        XCTAssertEqual(block.type, .custom)
        XCTAssertEqual(block.customName, "Legacy block")
        XCTAssertEqual(block.sortOrder, 6)
        XCTAssertTrue(block.isActive)
        assertDate(block.startedAt, baseDate.addingTimeInterval(42))
        assertDate(block.completedAt, baseDate.addingTimeInterval(43))
        assertDate(block.lastCompletedDate, baseDate.addingTimeInterval(44))
        XCTAssertEqual(block.currentStreak, 5)
        XCTAssertEqual(block.longestStreak, 12)
        assertDate(block.lastStreakDate, baseDate.addingTimeInterval(45))
        XCTAssertTrue(block.weatherCheckEnabled)
        assertDate(block.createdAt, baseDate.addingTimeInterval(40))
        assertDate(block.updatedAt, baseDate.addingTimeInterval(41))
        let blockTask = try XCTUnwrap(block.tasks?.first)
        XCTAssertEqual(blockTask.title, "Legacy block task")
        XCTAssertEqual(blockTask.notes, "Legacy block notes")
        XCTAssertTrue(blockTask.isComplete)
        XCTAssertEqual(blockTask.sortOrder, 2)
        XCTAssertTrue(blockTask.isOptional)
        XCTAssertEqual(blockTask.block?.clientID, block.clientID)
        assertDate(blockTask.createdAt, baseDate.addingTimeInterval(46))
        assertDate(blockTask.completedAt, baseDate.addingTimeInterval(47))

        let attachedBundle = try XCTUnwrap(block.attachedBundles?.first)
        XCTAssertEqual(
            attachedBundle.clientID,
            UUID(uuidString: "00000000-0000-0000-0000-000000000060")
        )
        XCTAssertEqual(attachedBundle.name, "Legacy attached bundle")
        XCTAssertEqual(attachedBundle.icon, "archivebox")
        XCTAssertTrue(attachedBundle.isComplete)
        XCTAssertEqual(attachedBundle.block?.clientID, block.clientID)
        assertDate(attachedBundle.createdAt, baseDate.addingTimeInterval(60))
        let attachedItem = try XCTUnwrap(attachedBundle.items?.first)
        XCTAssertEqual(attachedItem.title, "Legacy attached item")
        XCTAssertTrue(attachedItem.isComplete)
        XCTAssertEqual(attachedItem.sortOrder, 3)
        XCTAssertEqual(attachedItem.bundle?.clientID, attachedBundle.clientID)

        let templates = try context.fetch(FetchDescriptor<BundleTemplate>())
        XCTAssertEqual(templates.count, 1)
        let template = try XCTUnwrap(templates.first)
        XCTAssertEqual(
            template.clientID,
            UUID(uuidString: "00000000-0000-0000-0000-000000000050")
        )
        XCTAssertEqual(template.type, .custom)
        XCTAssertEqual(template.customName, "Legacy template")
        XCTAssertEqual(template.sortOrder, 4)
        XCTAssertEqual(template.autoPromptBlockTypesRaw, "travel,shopping")
        assertDate(template.createdAt, baseDate.addingTimeInterval(50))
        assertDate(template.updatedAt, baseDate.addingTimeInterval(51))
        let templateItem = try XCTUnwrap(template.items?.first)
        XCTAssertEqual(templateItem.title, "Legacy template item")
        XCTAssertEqual(templateItem.sortOrder, 2)
        XCTAssertEqual(templateItem.template?.clientID, template.clientID)

        let userPreferences = try XCTUnwrap(
            context.fetch(FetchDescriptor<UserPreferences>()).first
        )
        XCTAssertEqual(
            userPreferences.clientID,
            UUID(uuidString: "00000000-0000-0000-0000-000000000070")
        )
        XCTAssertEqual(userPreferences.currentEnergyLevel, 5)
        XCTAssertEqual(userPreferences.lowEFMaxFriction, 4)
        XCTAssertEqual(userPreferences.focusSessionMinutes, 63)
        XCTAssertEqual(userPreferences.breakMinutes, 14)
        XCTAssertEqual(userPreferences.notificationStyle, "minimal")
        XCTAssertEqual(userPreferences.watchComplicationMode, "focus")
        XCTAssertEqual(userPreferences.theme, "dark")
        XCTAssertTrue(userPreferences.minimalMode)
        assertDate(userPreferences.updatedAt, baseDate.addingTimeInterval(70))

        XCTAssertTrue(try context.fetch(FetchDescriptor<FocusSession>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<TaskRelationship>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<Note>()).isEmpty)
        XCTAssertEqual(try sha256(of: frozenV1StoreURL), Self.frozenV1SHA256)
    }

    @MainActor
    func testCorruptFrozenStoreCopyFailsClosedWithoutMutatingFixture() throws {
        let fixture = try makeTemporaryFixtureCopy()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        try Data("intentionally corrupt migration copy".utf8).write(
            to: fixture.store,
            options: .atomic
        )

        let schema = Schema(AuGendaSchemaV2.models)
        let state = AppContainer.startupState {
            let configuration = ModelConfiguration(
                "FrozenV1",
                schema: schema,
                url: fixture.store,
                cloudKitDatabase: .none
            )
            return try ModelContainer(
                for: schema,
                migrationPlan: AuGendaMigrationPlan.self,
                configurations: [configuration]
            )
        }

        XCTAssertFalse(state.isReady)
        if case .failed(let failure) = state {
            XCTAssertTrue(failure.diagnosticCode.hasPrefix("AUG-PERSIST-"))
        } else {
            XCTFail("A corrupt migration source must never produce a writable store")
        }
        XCTAssertEqual(try sha256(of: frozenV1StoreURL), Self.frozenV1SHA256)
    }

    @MainActor
    func testV2ModelsQueryable() {
        let container = AppContainer.makeTestContainer()

        let session = FocusSession(plannedDurationMinutes: 30, taskTitle: "Test")
        container.mainContext.insert(session)

        let rel = TaskRelationship(sourceTaskID: UUID(), targetTaskID: UUID(), type: .blocks)
        container.mainContext.insert(rel)

        try? container.mainContext.save()

        let sessionDesc = FetchDescriptor<FocusSession>()
        let sessions = try? container.mainContext.fetch(sessionDesc)
        XCTAssertEqual(sessions?.count, 1)

        let relDesc = FetchDescriptor<TaskRelationship>()
        let rels = try? container.mainContext.fetch(relDesc)
        XCTAssertEqual(rels?.count, 1)
    }
}
