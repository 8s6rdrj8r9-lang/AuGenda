// TaskImportExportTests.swift
// AuGendaTests
//
// Locks the spec's explicit beta success criterion: "YAML export round-trips
// (export → human-readable → re-importable)." Also covers JSON and the
// strict import and whole-product backup contracts. These were entirely
// untested before.

import Testing
import SwiftData
import Foundation
import CryptoKit
@testable import AuGenda

@MainActor
struct TaskImportExportTests {

    /// Build a task that exercises the tricky serialization cases: quotes,
    /// a colon, an ampersand, and an embedded newline in `notes`.
    private func sampleTask() -> AgendaTask {
        let t = AgendaTask(
            title: "Call insurance: claim #42",
            frictionLevel: 4,
            energyRequired: 3,
            estimatedMinutes: 25,
            contextTag: "phone",
            priority: 2,
            interestLevel: 2
        )
        t.notes = "Ask about \"deductible\" & timeline\nsecond line"
        t.waitingOn = "callback from rep"
        t.hyperfocusRisk = true
        t.needsBodyDouble = true
        return t
    }

    private func legacyEncryptedPayload(
        _ plaintext: String,
        password: String
    ) throws -> String {
        let salt = Data(repeating: 0x5A, count: 32)
        let nonceData = Data(repeating: 0xA5, count: 12)
        var keyMaterial = Data(password.utf8)
        keyMaterial.append(salt)
        let key = SymmetricKey(data: Data(SHA256.hash(data: keyMaterial)))
        let nonce = try AES.GCM.Nonce(data: nonceData)
        let box = try AES.GCM.seal(Data(plaintext.utf8), using: key, nonce: nonce)
        var combined = salt
        combined.append(nonceData)
        combined.append(box.ciphertext)
        combined.append(box.tag)
        return combined.base64EncodedString()
    }

    private func encodedBackupPayload(
        _ payload: AuGendaBackupPayload
    ) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(payload)
    }

    // MARK: - YAML round-trip (the spec criterion)

    @Test func yamlRoundTripPreservesFields() throws {
        let original = sampleTask()
        let yaml = try TaskExporter.export([original], as: .yaml)
        let parsed = TaskImporter.parse(yaml, as: .yaml)

        #expect(parsed.count == 1)
        guard let r = parsed.first else { return }

        #expect(r.title == original.title)                 // colon + '#' survive
        #expect(r.notes == original.notes)                 // quotes, &, newline survive
        #expect(r.frictionLevel == original.frictionLevel)
        #expect(r.energyRequired == original.energyRequired)
        #expect(r.estimatedMinutes == original.estimatedMinutes)
        #expect(r.contextTag == original.contextTag)
        #expect(r.interestLevel == original.interestLevel)
        #expect(r.priority == original.priority)
        #expect(r.hyperfocusRisk == original.hyperfocusRisk)
        #expect(r.needsBodyDouble == original.needsBodyDouble)
        #expect(r.waitingOn == original.waitingOn)
        #expect(r.isComplete == original.isComplete)
        #expect(r.clientID == original.clientID)
    }

    @Test func yamlIsHumanReadable() throws {
        let yaml = try TaskExporter.export([sampleTask()], as: .yaml)
        // Sanity: the format is the documented key: value shape, not JSON.
        #expect(yaml.contains("version: 2"))
        #expect(yaml.contains("kind: activeTaskList"))
        #expect(yaml.contains("tasks:"))
        #expect(yaml.contains("- title:"))
        #expect(yaml.contains("frictionLevel: 4"))
    }

    @Test func multipleTasksRoundTrip() throws {
        let a = AgendaTask(title: "First", frictionLevel: 1, interestLevel: 5)
        let b = AgendaTask(title: "Second", frictionLevel: 4, interestLevel: 1)
        let yaml = try TaskExporter.export([a, b], as: .yaml)
        let parsed = TaskImporter.parse(yaml, as: .yaml)
        #expect(parsed.count == 2)
        #expect(parsed.map(\.title).sorted() == ["First", "Second"])
    }

    // MARK: - JSON round-trip

    @Test func jsonRoundTripPreservesCoreFields() throws {
        let original = sampleTask()
        original.sensoryLoad = 3
        original.sortOrder = 42
        let step = TaskStep(title: "First step", estimatedMinutes: 4)
        step.parentTask = original
        original.steps = [step]

        let json = try TaskExporter.export([original], as: .json)
        let parsed = TaskImporter.parse(json, as: .json)
        #expect(parsed.count == 1)
        guard let r = parsed.first else { return }
        #expect(r.title == original.title)
        #expect(r.notes == original.notes)
        #expect(r.frictionLevel == original.frictionLevel)
        #expect(r.priority == original.priority)
        #expect(r.clientID == original.clientID)
        #expect(r.sensoryLoad == 3)
        #expect(r.sortOrder == 42)
        #expect(r.estimatedMinutes == original.estimatedMinutes)
        #expect(r.totalEstimatedMinutes == original.totalEstimatedMinutes)
        #expect(r.steps?.first?.title == "First step")
    }

    @Test func yamlEscapingDistinguishesLiteralBackslashNFromNewline() throws {
        let original = sampleTask()
        original.notes = "literal \\n marker\r\nactual second line"

        let yaml = try TaskExporter.export([original], as: .yaml)
        let parsed = TaskImporter.parse(yaml, as: .yaml)

        #expect(parsed.first?.notes == original.notes)
    }

    @Test func csvRoundTripPreservesMultilineNotes() throws {
        let original = sampleTask()
        let csv = try TaskExporter.export([original], as: .csv)
        let parsed = TaskImporter.parse(csv, as: .csv)

        #expect(parsed.count == 1)
        guard let r = parsed.first else { return }
        #expect(r.title == original.title)
        #expect(r.notes == original.notes)
        #expect(r.waitingOn == original.waitingOn)
        #expect(r.clientID == original.clientID)
    }

    @Test func encryptedExportUsesVersionedEnvelopeAndRoundTrips() throws {
        let payload = try TaskExporter.export([sampleTask()], as: .json)
        let encrypted = try TaskExporter.encrypt(payload, password: "correct horse battery staple")

        #expect(encrypted.hasPrefix("AuGendaExportV2:"))
        #expect(try TaskExporter.decrypt(encrypted, password: "correct horse battery staple") == payload)

        do {
            _ = try TaskExporter.decrypt(encrypted, password: "wrong password")
            Issue.record("Wrong-password decrypt unexpectedly succeeded")
        } catch {
            #expect(error is TaskPortabilityError)
        }

        do {
            _ = try TaskExporter.encrypt(payload, password: "")
            Issue.record("Empty-password encryption unexpectedly succeeded")
        } catch {
            #expect(error is TaskPortabilityError)
        }
    }

    @Test func csvNeutralizesFormulaPrefixesAndRoundTripsLiteralText() throws {
        let original = AgendaTask(title: "=HYPERLINK(\"https://example.test\")")
        original.notes = "'=A literal apostrophe-prefixed formula"
        original.waitingOn = "   +SUM(1,1)"
        let csv = try TaskExporter.export([original], as: .csv)

        #expect(csv.contains("auGendaCSVVersion"))
        #expect(csv.contains("'=HYPERLINK"))
        #expect(csv.contains("''=A literal"))
        #expect(csv.contains("'   +SUM"))

        let parsed = TaskImporter.parse(csv, as: .csv)
        #expect(parsed.first?.title == original.title)
        #expect(parsed.first?.notes == original.notes)
        #expect(parsed.first?.waitingOn == original.waitingOn)
        let preview = try TaskImporter.previewImport(
            csv,
            as: .csv,
            password: ""
        )
        #expect(preview.diagnostics.contains { $0.field == "steps" })
    }

    @Test func strictImporterRejectsMismatchedOrMalformedFormats() {
        do {
            _ = try TaskImporter.validatedImport(
                "title,notes\n\"unclosed",
                as: .csv,
                password: ""
            )
            Issue.record("Malformed CSV unexpectedly imported")
        } catch {
            #expect(error is TaskPortabilityError)
        }

        do {
            _ = try TaskImporter.validatedImport(
                #"{"version":99,"kind":"activeTaskList","exportedAt":"2026-01-01T00:00:00Z","tasks":[]}"#,
                as: .json,
                password: ""
            )
            Issue.record("Unsupported JSON version unexpectedly imported")
        } catch {
            #expect(error is TaskPortabilityError)
        }
    }

    @Test func legacyEncryptedPlainTextIsDecryptedBeforeTitleParsing() throws {
        let encrypted = try legacyEncryptedPayload(
            "Recovered secret task\n",
            password: "legacy password"
        )

        let preview = try TaskImporter.previewImport(
            encrypted,
            as: .plainText,
            password: "legacy password"
        )
        #expect(preview.tasks.map(\.title) == ["Recovered secret task"])
        #expect(preview.diagnostics.contains { $0.severity == .warning })

        do {
            _ = try TaskImporter.validatedImport(
                encrypted,
                as: .plainText,
                password: "wrong"
            )
            Issue.record("Legacy ciphertext was imported as a plain-text title")
        } catch {
            #expect(error is TaskPortabilityError)
        }
    }

    @Test func strictStructuredParsersRejectUnknownAndMalformedFields() {
        let unknownYAML = """
        version: 2
        kind: activeTaskList
        tasks:
          - title: "Task"
            frictionLevel: 2
            energyRequired: 2
            estimatedMinutes: 15
            energiiRequired: 4
        """
        do {
            _ = try TaskImporter.validatedImport(
                unknownYAML,
                as: .yaml,
                password: ""
            )
            Issue.record("Unknown YAML field unexpectedly imported")
        } catch TaskPortabilityError.validationFailed(let diagnostics) {
            #expect(diagnostics.contains { $0.field == "energiiRequired" })
        } catch {
            Issue.record("Expected YAML field diagnostic, got \(error)")
        }

        let malformedYAML = """
        version: 2
        kind: activeTaskList
        tasks:
          - title: "Unclosed
            frictionLevel: 2
            energyRequired: 2
            estimatedMinutes: 15
        """
        #expect(throws: TaskPortabilityError.self) {
            _ = try TaskImporter.validatedImport(
                malformedYAML,
                as: .yaml,
                password: ""
            )
        }

        let unknownCSV = """
        title,frictionLevel,energyRequired,estimatedMinutes,mystery
        Task,2,2,15,value
        """
        #expect(throws: TaskPortabilityError.self) {
            _ = try TaskImporter.validatedImport(
                unknownCSV,
                as: .csv,
                password: ""
            )
        }

        let malformedMarkdown = """
        - [ ] Task — *friction:2 · energy:2 · 15m · mystery*
        """
        do {
            _ = try TaskImporter.validatedImport(
                malformedMarkdown,
                as: .markdown,
                password: ""
            )
            Issue.record("Unknown Markdown metadata unexpectedly imported")
        } catch TaskPortabilityError.validationFailed(let diagnostics) {
            #expect(diagnostics.contains { $0.field == "metadata" })
        } catch {
            Issue.record("Expected Markdown metadata diagnostic, got \(error)")
        }

        let duplicateJSON = """
        {
          "version": 2,
          "version": 2,
          "kind": "activeTaskList",
          "exportedAt": "2026-01-01T00:00:00Z",
          "tasks": []
        }
        """
        #expect(throws: TaskPortabilityError.self) {
            _ = try TaskImporter.validatedImport(
                duplicateJSON,
                as: .json,
                password: ""
            )
        }

        let unknownJSON = """
        {
          "version": 2,
          "kind": "activeTaskList",
          "exportedAt": "2026-01-01T00:00:00Z",
          "tasks": [{
            "title": "Task",
            "notes": "",
            "frictionLevel": 2,
            "energyRequired": 2,
            "estimatedMinutes": 15,
            "contextTag": "",
            "interestLevel": 3,
            "priority": 0,
            "hyperfocusRisk": false,
            "needsBodyDouble": false,
            "waitingOn": "",
            "isComplete": false,
            "mystery": true
          }]
        }
        """
        do {
            _ = try TaskImporter.validatedImport(
                unknownJSON,
                as: .json,
                password: ""
            )
            Issue.record("Unknown JSON field unexpectedly imported")
        } catch TaskPortabilityError.validationFailed(let diagnostics) {
            #expect(diagnostics.contains { $0.field == "mystery" })
        } catch {
            Issue.record("Expected JSON field diagnostic, got \(error)")
        }

        let duplicateYAMLEnvelope = """
        version: 2
        version: 2
        kind: activeTaskList
        tasks:
        """
        #expect(throws: TaskPortabilityError.self) {
            _ = try TaskImporter.validatedImport(
                duplicateYAMLEnvelope,
                as: .yaml,
                password: ""
            )
        }
    }

    @Test func repeatedImportIsIdempotentAndSaveFailureIsAtomic() throws {
        let source = sampleTask()
        let json = try TaskExporter.export([source], as: .json)
        let firstBatch = try TaskImporter.validatedImport(json, as: .json, password: "")
        let container = AppContainer.makeTestContainer()

        enum InjectedFailure: Error { case save }
        do {
            _ = try TaskImportService.apply(
                firstBatch,
                assignedTo: nil,
                using: container,
                save: { _ in throw InjectedFailure.save }
            )
            Issue.record("Injected import save failure unexpectedly succeeded")
        } catch {
            #expect(error is InjectedFailure)
        }
        #expect(try container.mainContext.fetch(FetchDescriptor<AgendaTask>()).isEmpty)

        let successfulBatch = try TaskImporter.validatedImport(json, as: .json, password: "")
        let first = try TaskImportService.apply(
            successfulBatch,
            assignedTo: nil,
            using: container
        )
        #expect(first == TaskImportSummary(insertedCount: 1, skippedDuplicateCount: 0))

        let repeatedBatch = try TaskImporter.validatedImport(json, as: .json, password: "")
        let repeated = try TaskImportService.apply(
            repeatedBatch,
            assignedTo: nil,
            using: container
        )
        #expect(repeated == TaskImportSummary(insertedCount: 0, skippedDuplicateCount: 1))
        #expect(try container.mainContext.fetch(FetchDescriptor<AgendaTask>()).count == 1)
    }

    @Test func taskImportRejectsExistingStepIdentityCollision() throws {
        let container = AppContainer.makeTestContainer()
        let existingTask = AgendaTask(title: "Existing")
        let existingStep = TaskStep(title: "Existing step")
        existingStep.parentTask = existingTask
        existingTask.steps = [existingStep]
        container.mainContext.insert(existingTask)
        container.mainContext.insert(existingStep)
        try container.mainContext.save()

        let incomingTask = AgendaTask(title: "Incoming")
        let incomingStep = TaskStep(title: "Incoming step")
        incomingStep.clientID = existingStep.clientID
        incomingStep.parentTask = incomingTask
        incomingTask.steps = [incomingStep]

        do {
            _ = try TaskImportService.apply(
                [incomingTask],
                assignedTo: nil,
                using: container
            )
            Issue.record("Colliding step identity unexpectedly imported")
        } catch TaskPortabilityError.validationFailed(let diagnostics) {
            #expect(diagnostics.contains { $0.field == "steps.clientID" })
        } catch {
            Issue.record("Expected step identity diagnostic, got \(error)")
        }

        #expect(
            try container.mainContext.fetch(FetchDescriptor<AgendaTask>())
                .count == 1
        )
        #expect(
            try container.mainContext.fetch(FetchDescriptor<TaskStep>())
                .count == 1
        )
    }

    // MARK: - Strict typed diagnostics

    @Test func importRejectsOutOfRangeValuesWithoutCoercion() {
        let yaml = """
        version: 2
        kind: activeTaskList
        exportedAt: 2026-01-01T00:00:00Z
        tasks:
          - title: "Drifted"
            notes: ""
            frictionLevel: 99
            energyRequired: -3
            estimatedMinutes: 0
            contextTag: ""
            interestLevel: 50
            priority: 9
            hyperfocusRisk: perhaps
            needsBodyDouble: false
            waitingOn: ""
            isComplete: false
            dueDate: yesterday
            clientID: not-a-uuid
        """

        do {
            _ = try TaskImporter.validatedImport(yaml, as: .yaml, password: "")
            Issue.record("Invalid typed values unexpectedly imported")
        } catch TaskPortabilityError.validationFailed(let diagnostics) {
            #expect(diagnostics.count >= 8)
            #expect(diagnostics.allSatisfy { $0.row == 5 })
            #expect(diagnostics.contains { $0.field == "frictionLevel" })
            #expect(diagnostics.contains { $0.field == "energyRequired" })
            #expect(diagnostics.contains { $0.field == "estimatedMinutes" })
            #expect(diagnostics.contains { $0.field == "hyperfocusRisk" })
            #expect(diagnostics.contains { $0.field == "dueDate" })
            #expect(diagnostics.contains { $0.field == "clientID" })
        } catch {
            Issue.record("Expected typed validation diagnostics, got \(error)")
        }
        #expect(TaskImporter.parse(yaml, as: .yaml).isEmpty)
    }

    @Test func adversarialStructuredValuesNeverDefaultOrClamp() {
        let hostileValues = [
            ("frictionLevel", "nan"),
            ("frictionLevel", "1.5"),
            ("frictionLevel", "999999999999999999999999"),
            ("energyRequired", "-1"),
            ("estimatedMinutes", "0"),
            ("estimatedMinutes", "525601"),
            ("priority", "3"),
            ("interestLevel", ""),
            ("isComplete", "yes"),
            ("dueDate", "2026-99-99"),
            ("clientID", "0000")
        ]

        for (field, value) in hostileValues {
            let headers = [
                "title", "frictionLevel", "energyRequired", "estimatedMinutes",
                "priority", "interestLevel", "isComplete", "dueDate", "clientID"
            ]
            var values = ["Hostile", "2", "2", "15", "0", "3", "false", "", ""]
            values[headers.firstIndex(of: field)!] = value
            let mutated = headers.joined(separator: ",") + "\n"
                + values.joined(separator: ",") + "\n"
            do {
                _ = try TaskImporter.validatedImport(mutated, as: .csv, password: "")
                Issue.record("\(field)=\(value) unexpectedly imported")
            } catch TaskPortabilityError.validationFailed(let diagnostics) {
                #expect(diagnostics.contains { $0.field == field })
            } catch {
                Issue.record("Expected diagnostics for \(field)=\(value), got \(error)")
            }
        }
    }

    // MARK: - Whole-product backup / restore

    @Test func encryptedWholeBackupRestoresEveryEntityRelationshipAndPreference() throws {
        let sourceContainer = AppContainer.makeTestContainer()
        let fixture = try seedWholeProductFixture(in: sourceContainer.mainContext)
        let sourceSuite = "AuGendaTests.Backup.Source.\(UUID().uuidString)"
        let sourceDefaults = UserDefaults(suiteName: sourceSuite)!
        defer { sourceDefaults.removePersistentDomain(forName: sourceSuite) }
        sourceDefaults.set(fixture.profileID.uuidString, forKey: "activeProfileID")
        sourceDefaults.set([1.0, 2.0, 3.0], forKey: "activity.snoozes")
        sourceDefaults.set("quiet, literal context", forKey: "ai.personalization.aboutMe")
        sourceDefaults.set(
            AIConsentPolicy.currentDisclosureVersion,
            forKey: AIConsentPolicy.consentKey(for: .openai)
        )
        sourceDefaults.set("must-never-export", forKey: "openai_api_key")
        let usageHistory = [
            AIUsageEntry(
                provider: AIProvider.openai.rawValue,
                model: "recovery-model",
                promptTokens: 123,
                completionTokens: 45,
                estimatedCostUSD: 0.0123,
                timestamp: Date(
                    timeIntervalSince1970: 1_700_003_000.654_321
                )
            ),
            AIUsageEntry(
                provider: AIProvider.mistral.rawValue,
                model: "intentionally-earlier-second",
                promptTokens: 9,
                completionTokens: 8,
                estimatedCostUSD: 0.001,
                timestamp: Date(
                    timeIntervalSince1970: 1_600_003_000.111_222
                )
            )
        ]
        let personalizationMemory = [
            PersonalizationContext.MemoryEntry(
                title: "Remembered exact task",
                band: DifficultyBand.hard.rawValue,
                timestamp: Date(
                    timeIntervalSince1970: 1_700_004_000.234_567
                )
            ),
            PersonalizationContext.MemoryEntry(
                title: "Earlier timestamp kept second",
                band: DifficultyBand.moderate.rawValue,
                timestamp: Date(
                    timeIntervalSince1970: 1_600_004_000.333_444
                )
            )
        ]

        let archive = try AuGendaBackupService.encryptedArchive(
            from: sourceContainer.mainContext,
            defaults: sourceDefaults,
            password: "correct horse battery staple",
            aiUsageHistory: usageHistory,
            personalizationMemory: personalizationMemory
        )
        #expect(archive.hasPrefix(AuGendaBackupService.encryptedPrefix))
        #expect(!archive.contains("Whole backup task"))
        #expect(!archive.contains("must-never-export"))

        do {
            _ = try AuGendaBackupService.decodeEncryptedArchive(
                archive,
                password: "wrong"
            )
            Issue.record("Wrong-password backup decrypt unexpectedly succeeded")
        } catch {
            #expect(error is AuGendaBackupError)
        }

        let envelope = try AuGendaBackupService.decodeEncryptedArchive(
            archive,
            password: "correct horse battery staple"
        )
        #expect(envelope.completeness.expectedEntityTypes.count == 17)
        #expect(envelope.completeness.entityCounts["AgendaTask"] == 2)
        #expect(envelope.completeness.entityCounts.values.allSatisfy { $0 >= 1 })
        #expect(envelope.completeness.historyCounts["AIUsageEntry"] == 2)
        #expect(
            envelope.completeness.historyCounts["PersonalizationMemoryEntry"] == 2
        )
        #expect(
            envelope.payload.aiUsageHistory.map(\.model)
                == usageHistory.map(\.model)
        )
        #expect(
            envelope.payload.aiUsageHistory.map(\.timestamp)
                == usageHistory.map(\.timestamp)
        )
        #expect(
            envelope.payload.personalizationMemory.map(\.title)
                == personalizationMemory.map(\.title)
        )
        #expect(
            envelope.payload.personalizationMemory.map(\.timestamp)
                == personalizationMemory.map(\.timestamp)
        )
        #expect(envelope.completeness.preferenceKeys.contains("activeProfileID"))
        #expect(!envelope.completeness.preferenceKeys.contains("openai_api_key"))
        #expect(
            !envelope.completeness.preferenceKeys.contains(
                AIConsentPolicy.consentKey(for: .openai)
            )
        )

        let targetContainer = AppContainer.makeTestContainer()
        let staleTask = AgendaTask(title: "Stale target data")
        targetContainer.mainContext.insert(staleTask)
        try targetContainer.mainContext.save()

        let targetSuite = "AuGendaTests.Backup.Target.\(UUID().uuidString)"
        let targetDefaults = UserDefaults(suiteName: targetSuite)!
        defer { targetDefaults.removePersistentDomain(forName: targetSuite) }
        targetDefaults.set("stale", forKey: "activeProfileID")
        targetDefaults.set(
            AIConsentPolicy.currentDisclosureVersion,
            forKey: AIConsentPolicy.consentKey(for: .openai)
        )
        var restoredUsageHistory = [
            AIUsageEntry(
                provider: "old",
                model: "old",
                promptTokens: 1,
                completionTokens: 1,
                estimatedCostUSD: 1,
                timestamp: .distantPast
            )
        ]
        var restoredPersonalizationMemory = [
            PersonalizationContext.MemoryEntry(
                title: "old",
                band: DifficultyBand.easy.rawValue,
                timestamp: .distantPast
            )
        ]

        var commitOrder: [String] = []
        let firstSummary = try AuGendaBackupService.restore(
            envelope,
            in: targetContainer.mainContext,
            defaults: targetDefaults,
            save: {
                try $0.save()
                commitOrder.append("save")
            },
            currentAIUsageHistory: { restoredUsageHistory },
            currentPersonalizationMemory: { restoredPersonalizationMemory },
            replaceAIUsageHistory: { restoredUsageHistory = $0 },
            replacePersonalizationMemory: {
                restoredPersonalizationMemory = $0
            },
            reloadPersonalizationPreferences: {},
            afterCommit: { commitOrder.append("post-commit-side-effects") }
        )
        #expect(commitOrder == ["save", "post-commit-side-effects"])
        #expect(firstSummary.restoredEntityCount == envelope.totalEntityCount)
        #expect(firstSummary.restoredPreferenceCount == 3)
        try assertWholeProductFixture(
            fixture,
            in: targetContainer.mainContext,
            defaults: targetDefaults
        )
        #expect(
            targetDefaults.object(
                forKey: AIConsentPolicy.consentKey(for: .openai)
            ) == nil
        )
        #expect(restoredUsageHistory.first?.model == "recovery-model")
        #expect(
            restoredUsageHistory.first?.timestamp == usageHistory.first?.timestamp
        )
        #expect(
            restoredPersonalizationMemory.first?.title == "Remembered exact task"
        )
        #expect(
            restoredPersonalizationMemory.first?.timestamp
                == personalizationMemory.first?.timestamp
        )
        let reexportedEnvelope = try AuGendaBackupService.makeEnvelope(
            from: targetContainer.mainContext,
            defaults: targetDefaults,
            now: envelope.createdAt,
            backupID: envelope.backupID,
            aiUsageHistory: restoredUsageHistory,
            personalizationMemory: restoredPersonalizationMemory
        )
        #expect(
            try encodedBackupPayload(reexportedEnvelope.payload)
                == encodedBackupPayload(envelope.payload)
        )

        // Replacement restore is idempotent: same stable IDs and counts,
        // with no duplicate graph on a repeated restore.
        let repeatedSummary = try AuGendaBackupService.restore(
            envelope,
            in: targetContainer.mainContext,
            defaults: targetDefaults,
            save: { try $0.save() },
            currentAIUsageHistory: { restoredUsageHistory },
            currentPersonalizationMemory: { restoredPersonalizationMemory },
            replaceAIUsageHistory: { restoredUsageHistory = $0 },
            replacePersonalizationMemory: {
                restoredPersonalizationMemory = $0
            },
            reloadPersonalizationPreferences: {}
        )
        #expect(repeatedSummary == firstSummary)
        try assertWholeProductFixture(
            fixture,
            in: targetContainer.mainContext,
            defaults: targetDefaults
        )
    }

    @Test func wholeBackupSaveFailureRollsBackModelsAndPreferences() throws {
        let sourceContainer = AppContainer.makeTestContainer()
        _ = try seedWholeProductFixture(in: sourceContainer.mainContext)
        let sourceSuite = "AuGendaTests.Backup.Atomic.Source.\(UUID().uuidString)"
        let sourceDefaults = UserDefaults(suiteName: sourceSuite)!
        defer { sourceDefaults.removePersistentDomain(forName: sourceSuite) }
        sourceDefaults.set("restored", forKey: "ai.personalization.aboutMe")
        let envelope = try AuGendaBackupService.makeEnvelope(
            from: sourceContainer.mainContext,
            defaults: sourceDefaults,
            aiUsageHistory: [
                AIUsageEntry(
                    provider: "new",
                    model: "new",
                    promptTokens: 2,
                    completionTokens: 3,
                    estimatedCostUSD: 0.5,
                    timestamp: .now
                )
            ],
            personalizationMemory: [
                .init(
                    title: "new",
                    band: DifficultyBand.moderate.rawValue,
                    timestamp: .now
                )
            ]
        )

        let targetContainer = AppContainer.makeTestContainer()
        let sentinel = AgendaTask(title: "Keep me")
        targetContainer.mainContext.insert(sentinel)
        try targetContainer.mainContext.save()
        let sentinelID = sentinel.clientID

        let targetSuite = "AuGendaTests.Backup.Atomic.Target.\(UUID().uuidString)"
        let targetDefaults = UserDefaults(suiteName: targetSuite)!
        defer { targetDefaults.removePersistentDomain(forName: targetSuite) }
        targetDefaults.set("original", forKey: "ai.personalization.aboutMe")

        enum InjectedFailure: Error { case save }
        var postCommitEffectCount = 0
        var currentUsage = [
            AIUsageEntry(
                provider: "old",
                model: "old",
                promptTokens: 1,
                completionTokens: 1,
                estimatedCostUSD: 0.1,
                timestamp: .distantPast
            )
        ]
        var currentMemory = [
            PersonalizationContext.MemoryEntry(
                title: "old",
                band: DifficultyBand.easy.rawValue,
                timestamp: .distantPast
            )
        ]
        let originalUsageModel = currentUsage.first?.model
        let originalMemoryTitle = currentMemory.first?.title
        do {
            _ = try AuGendaBackupService.restore(
                envelope,
                in: targetContainer.mainContext,
                defaults: targetDefaults,
                save: { _ in throw InjectedFailure.save },
                currentAIUsageHistory: { currentUsage },
                currentPersonalizationMemory: { currentMemory },
                replaceAIUsageHistory: { currentUsage = $0 },
                replacePersonalizationMemory: { currentMemory = $0 },
                reloadPersonalizationPreferences: {},
                afterCommit: { postCommitEffectCount += 1 }
            )
            Issue.record("Injected backup save failure unexpectedly succeeded")
        } catch {
            #expect(error is InjectedFailure)
        }

        let remaining = try targetContainer.mainContext.fetch(
            FetchDescriptor<AgendaTask>()
        )
        #expect(remaining.count == 1)
        #expect(remaining.first?.clientID == sentinelID)
        #expect(
            targetDefaults.string(forKey: "ai.personalization.aboutMe")
                == "original"
        )
        #expect(postCommitEffectCount == 0)
        #expect(currentUsage.first?.model == originalUsageModel)
        #expect(currentMemory.first?.title == originalMemoryTitle)
    }

    @Test func wholeBackupDetectsAuthenticatedPayloadTampering() throws {
        let container = AppContainer.makeTestContainer()
        _ = try seedWholeProductFixture(in: container.mainContext)
        let envelope = try AuGendaBackupService.makeEnvelope(
            from: container.mainContext,
            aiUsageHistory: [],
            personalizationMemory: []
        )
        let cleartext = try AuGendaBackupService.encodeEnvelope(envelope)
        let tampered = cleartext.replacingOccurrences(
            of: "Whole backup task",
            with: "Altered backup task"
        )
        #expect(tampered != cleartext)

        let reencrypted = try TaskExporter.encrypt(
            tampered,
            password: "tamper-test"
        )
        let archive = AuGendaBackupService.encryptedPrefix
            + reencrypted.dropFirst(TaskExporter.encryptedExportV2Prefix.count)
        do {
            _ = try AuGendaBackupService.decodeEncryptedArchive(
                archive,
                password: "tamper-test"
            )
            Issue.record("Payload with stale digest unexpectedly validated")
        } catch AuGendaBackupError.integrityMismatch {
            // Expected.
        } catch {
            Issue.record("Expected integrity mismatch, got \(error)")
        }
    }

    @Test func wholeBackupRejectsDanglingDomainReferences() throws {
        let container = AppContainer.makeTestContainer()
        let fixture = try seedWholeProductFixture(in: container.mainContext)
        let tasks = try container.mainContext.fetch(FetchDescriptor<AgendaTask>())
        let source = tasks.first { $0.clientID == fixture.taskID }
        source?.agendaItemID = UUID()
        try container.mainContext.save()

        do {
            _ = try AuGendaBackupService.makeEnvelope(
                from: container.mainContext,
                aiUsageHistory: [],
                personalizationMemory: []
            )
            Issue.record("Dangling agendaItemID unexpectedly backed up")
        } catch AuGendaBackupError.invalidRelationship(let detail) {
            #expect(detail.contains("AgendaTask.agendaItemID"))
        } catch {
            Issue.record("Expected invalid relationship, got \(error)")
        }
    }

    @Test func wholeBackupRejectsInvalidRelationshipTypesAndRecurrenceCycles() throws {
        let invalidTypeContainer = AppContainer.makeTestContainer()
        _ = try seedWholeProductFixture(in: invalidTypeContainer.mainContext)
        let relationships = try invalidTypeContainer.mainContext.fetch(
            FetchDescriptor<TaskRelationship>()
        )
        relationships.first?.typeRaw = "unknown-blocking-type"
        try invalidTypeContainer.mainContext.save()

        do {
            _ = try AuGendaBackupService.makeEnvelope(
                from: invalidTypeContainer.mainContext,
                aiUsageHistory: [],
                personalizationMemory: []
            )
            Issue.record("Invalid relationship type unexpectedly backed up")
        } catch AuGendaBackupError.invalidRelationship(let detail) {
            #expect(detail.contains("unsupported type"))
        } catch {
            Issue.record("Expected invalid relationship type, got \(error)")
        }

        let recurrenceContainer = AppContainer.makeTestContainer()
        _ = try seedWholeProductFixture(in: recurrenceContainer.mainContext)
        let tasks = try recurrenceContainer.mainContext.fetch(
            FetchDescriptor<AgendaTask>()
        )
        #expect(tasks.count >= 2)
        guard tasks.count >= 2 else { return }
        tasks[0].recurrenceParentID = tasks[1].clientID
        tasks[1].recurrenceParentID = tasks[0].clientID
        try recurrenceContainer.mainContext.save()

        do {
            _ = try AuGendaBackupService.makeEnvelope(
                from: recurrenceContainer.mainContext,
                aiUsageHistory: [],
                personalizationMemory: []
            )
            Issue.record("Recurrence cycle unexpectedly backed up")
        } catch AuGendaBackupError.invalidRelationship(let detail) {
            #expect(detail.contains("recurrence"))
            #expect(detail.contains("cycle"))
        } catch {
            Issue.record("Expected recurrence-cycle rejection, got \(error)")
        }
    }

    @Test func wholeBackupRejectsUnsupportedDataModelVersion() throws {
        let container = AppContainer.makeTestContainer()
        _ = try seedWholeProductFixture(in: container.mainContext)
        let envelope = try AuGendaBackupService.makeEnvelope(
            from: container.mainContext,
            aiUsageHistory: [],
            personalizationMemory: []
        )
        let encoded = try AuGendaBackupService.encodeEnvelope(envelope)
        let encodedData = try #require(encoded.data(using: .utf8))
        var object = try #require(
            JSONSerialization.jsonObject(with: encodedData)
                as? [String: Any]
        )
        object["dataModelVersion"] = "999.0.0"
        let alteredData = try JSONSerialization.data(withJSONObject: object)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let altered = try decoder.decode(
            AuGendaBackupEnvelope.self,
            from: alteredData
        )

        do {
            try AuGendaBackupService.validate(altered)
            Issue.record("Unsupported data-model version unexpectedly validated")
        } catch AuGendaBackupError.unsupportedDataModelVersion(let version) {
            #expect(version == "999.0.0")
        } catch {
            Issue.record("Expected data-model version rejection, got \(error)")
        }
    }

    @Test func wholeBackupReportsHistoryRollbackFailureAndStillAttemptsBothRollbacks() throws {
        let source = AppContainer.makeTestContainer()
        source.mainContext.insert(AgendaTask(title: "Replacement"))
        try source.mainContext.save()
        let envelope = try AuGendaBackupService.makeEnvelope(
            from: source.mainContext,
            aiUsageHistory: [],
            personalizationMemory: []
        )

        let target = AppContainer.makeTestContainer()
        let sentinel = AgendaTask(title: "Sentinel")
        target.mainContext.insert(sentinel)
        try target.mainContext.save()
        let sentinelID = sentinel.clientID

        enum InjectedFailure: Error {
            case save
            case usageRollback
        }
        var usage = [
            AIUsageEntry(
                provider: "old",
                model: "old",
                promptTokens: 1,
                completionTokens: 1,
                estimatedCostUSD: 0,
                timestamp: .distantPast
            )
        ]
        var memory = [
            PersonalizationContext.MemoryEntry(
                title: "old",
                band: DifficultyBand.easy.rawValue,
                timestamp: .distantPast
            )
        ]
        var usageReplacementCount = 0
        var memoryReplacementCount = 0
        var postCommitCount = 0

        do {
            _ = try AuGendaBackupService.restore(
                envelope,
                in: target.mainContext,
                save: { _ in throw InjectedFailure.save },
                currentAIUsageHistory: { usage },
                currentPersonalizationMemory: { memory },
                replaceAIUsageHistory: { replacement in
                    usageReplacementCount += 1
                    if usageReplacementCount == 2 {
                        throw InjectedFailure.usageRollback
                    }
                    usage = replacement
                },
                replacePersonalizationMemory: { replacement in
                    memoryReplacementCount += 1
                    memory = replacement
                },
                reloadPersonalizationPreferences: {},
                afterCommit: { postCommitCount += 1 }
            )
            Issue.record("History rollback failure unexpectedly succeeded")
        } catch AuGendaBackupError.historyRollbackFailed {
            // Expected.
        } catch {
            Issue.record("Expected history rollback failure, got \(error)")
        }

        #expect(usageReplacementCount == 2)
        #expect(memoryReplacementCount == 2)
        #expect(memory.first?.title == "old")
        #expect(usage.isEmpty)
        #expect(postCommitCount == 0)
        let remaining = try target.mainContext.fetch(
            FetchDescriptor<AgendaTask>()
        )
        #expect(remaining.map(\.clientID) == [sentinelID])
    }

    // MARK: - Empty / malformed input is safe

    @Test func emptyInputYieldsNoTasks() {
        #expect(TaskImporter.parse("", as: .yaml).isEmpty)
        #expect(TaskImporter.parse("not yaml at all", as: .yaml).isEmpty)
    }

    private struct BackupFixture {
        let profileID: UUID
        let profilePreferencesID: UUID
        let agendaItemID: UUID
        let subTaskID: UUID
        let taskID: UUID
        let secondTaskID: UUID
        let taskStepID: UUID
        let blockID: UUID
        let blockTaskID: UUID
        let templateID: UUID
        let templateItemID: UUID
        let attachedBundleID: UUID
        let attachedBundleItemID: UUID
        let focusSessionID: UUID
        let relationshipID: UUID
        let noteID: UUID
        let inboxID: UUID
        let userPreferencesID: UUID
        let fractionalTaskCreatedAt: Date
    }

    private func seedWholeProductFixture(
        in context: ModelContext
    ) throws -> BackupFixture {
        let profile = Profile(
            name: "Recovery profile",
            role: .coordinator,
            neurotypes: [.adhd, .autism],
            sortOrder: 4
        )
        profile.avatarImageData = Data([0x01, 0x02, 0x03])
        let profilePreferences = ProfilePreferences()
        profilePreferences.currentEnergyLevel = 4
        profilePreferences.focusSessionMinutes = 37
        profilePreferences.largeTouchTargets = true
        profilePreferences.uiScale = 1.5
        profile.preferences = profilePreferences
        profilePreferences.profile = profile

        let agendaItem = AgendaItem(
            title: "Whole backup agenda item",
            scheduledDate: Date(timeIntervalSince1970: 1_700_000_000),
            priority: 2,
            frictionLevel: 4,
            energyRequired: 3,
            contextTag: "recovery",
            recurrenceRule: "weekly"
        )
        agendaItem.notes = "Agenda notes"
        agendaItem.assignedToProfileID = profile.clientID
        let subTask = SubTask(title: "Agenda child", sortOrder: 2)
        subTask.isComplete = true
        subTask.parentItem = agendaItem
        agendaItem.subTasks = [subTask]

        let task = AgendaTask(
            title: "Whole backup task",
            frictionLevel: 4,
            energyRequired: 3,
            estimatedMinutes: 61,
            contextTag: "computer",
            priority: 2,
            interestLevel: 5
        )
        let fractionalTaskCreatedAt = Date(
            timeIntervalSince1970: 1_700_000_000.123_456
        )
        task.createdAt = fractionalTaskCreatedAt
        task.notes = "Task notes"
        task.isAbandoned = true
        task.abandonedAt = Date(timeIntervalSince1970: 1_700_001_000)
        task.abandonReason = "Fixture history"
        task.agendaItemID = agendaItem.clientID
        task.assignedToProfileID = profile.clientID
        let step = TaskStep(title: "Persistent step", estimatedMinutes: 7, sortOrder: 3)
        step.isComplete = true
        step.parentTask = task
        task.steps = [step]

        let secondTask = AgendaTask(title: "Dependency target")
        secondTask.assignedToProfileID = profile.clientID
        let relationship = TaskRelationship(
            sourceTaskID: task.clientID,
            targetTaskID: secondTask.clientID,
            type: .blocks
        )

        let inbox = InboxItem(rawCapture: "Unprocessed recovery capture")
        inbox.aiSuggestedTitle = "Suggested"
        inbox.aiSuggestedFriction = 2
        inbox.assignedToProfileID = profile.clientID

        let userPreferences = UserPreferences()
        userPreferences.currentEnergyLevel = 4
        userPreferences.theme = "dark"

        let block = Block(type: .custom, customName: "Recovery block", sortOrder: 8)
        block.currentStreak = 6
        block.isActive = true
        let blockTask = BlockTask(title: "Block child", sortOrder: 1, isOptional: true)
        blockTask.isComplete = true
        blockTask.block = block
        block.tasks = [blockTask]

        let template = BundleTemplate(type: .custom, customName: "Recovery kit")
        template.autoPromptBlockTypesRaw = "startup,travel"
        let templateItem = BundleTemplateItem(title: "Template child", sortOrder: 5)
        templateItem.template = template
        template.items = [templateItem]

        let attachedBundle = AttachedBundle(name: "Attached recovery kit", icon: "bag")
        attachedBundle.isComplete = true
        attachedBundle.block = block
        let attachedItem = AttachedBundleItem(title: "Packed item", sortOrder: 4)
        attachedItem.isComplete = true
        attachedItem.bundle = attachedBundle
        attachedBundle.items = [attachedItem]
        block.attachedBundles = [attachedBundle]

        let focus = FocusSession(
            plannedDurationMinutes: 37,
            taskID: task.clientID,
            taskTitle: task.title,
            profileID: profile.clientID
        )
        focus.stateRaw = FocusSessionState.completed.rawValue
        focus.wasCompleted = true
        focus.endTime = Date(timeIntervalSince1970: 1_700_002_000)
        focus.interruptionCount = 2
        focus.interruptionTimestamps = [
            Date(timeIntervalSince1970: 1_700_001_500),
            Date(timeIntervalSince1970: 1_700_001_700)
        ]
        focus.interruptionReasons = ["noise", "message"]

        let note = Note(
            title: "Recovery note",
            body: "Standalone note body",
            relatedTaskID: task.clientID,
            relatedItemID: agendaItem.clientID
        )
        note.tags = "backup,recovery"

        context.insert(profile)
        context.insert(profilePreferences)
        context.insert(agendaItem)
        context.insert(subTask)
        context.insert(task)
        context.insert(step)
        context.insert(secondTask)
        context.insert(relationship)
        context.insert(inbox)
        context.insert(userPreferences)
        context.insert(block)
        context.insert(blockTask)
        context.insert(template)
        context.insert(templateItem)
        context.insert(attachedBundle)
        context.insert(attachedItem)
        context.insert(focus)
        context.insert(note)
        try context.save()

        return BackupFixture(
            profileID: profile.clientID,
            profilePreferencesID: profilePreferences.clientID,
            agendaItemID: agendaItem.clientID,
            subTaskID: subTask.clientID,
            taskID: task.clientID,
            secondTaskID: secondTask.clientID,
            taskStepID: step.clientID,
            blockID: block.clientID,
            blockTaskID: blockTask.clientID,
            templateID: template.clientID,
            templateItemID: templateItem.clientID,
            attachedBundleID: attachedBundle.clientID,
            attachedBundleItemID: attachedItem.clientID,
            focusSessionID: focus.clientID,
            relationshipID: relationship.clientID,
            noteID: note.clientID,
            inboxID: inbox.clientID,
            userPreferencesID: userPreferences.clientID,
            fractionalTaskCreatedAt: fractionalTaskCreatedAt
        )
    }

    private func assertWholeProductFixture(
        _ fixture: BackupFixture,
        in context: ModelContext,
        defaults: UserDefaults
    ) throws {
        let profiles = try context.fetch(FetchDescriptor<Profile>())
        let profilePreferences = try context.fetch(
            FetchDescriptor<ProfilePreferences>()
        )
        let agendaItems = try context.fetch(FetchDescriptor<AgendaItem>())
        let subTasks = try context.fetch(FetchDescriptor<SubTask>())
        let tasks = try context.fetch(FetchDescriptor<AgendaTask>())
        let taskSteps = try context.fetch(FetchDescriptor<TaskStep>())
        let blocks = try context.fetch(FetchDescriptor<Block>())
        let blockTasks = try context.fetch(FetchDescriptor<BlockTask>())
        let templates = try context.fetch(FetchDescriptor<BundleTemplate>())
        let templateItems = try context.fetch(FetchDescriptor<BundleTemplateItem>())
        let attached = try context.fetch(FetchDescriptor<AttachedBundle>())
        let attachedItems = try context.fetch(FetchDescriptor<AttachedBundleItem>())
        let focus = try context.fetch(FetchDescriptor<FocusSession>())
        let relationships = try context.fetch(FetchDescriptor<TaskRelationship>())
        let notes = try context.fetch(FetchDescriptor<Note>())
        let inbox = try context.fetch(FetchDescriptor<InboxItem>())
        let preferences = try context.fetch(FetchDescriptor<UserPreferences>())

        #expect(profiles.count == 1)
        #expect(profilePreferences.count == 1)
        #expect(agendaItems.count == 1)
        #expect(subTasks.count == 1)
        #expect(tasks.count == 2)
        #expect(taskSteps.count == 1)
        #expect(blocks.count == 1)
        #expect(blockTasks.count == 1)
        #expect(templates.count == 1)
        #expect(templateItems.count == 1)
        #expect(attached.count == 1)
        #expect(attachedItems.count == 1)
        #expect(focus.count == 1)
        #expect(relationships.count == 1)
        #expect(notes.count == 1)
        #expect(inbox.count == 1)
        #expect(preferences.count == 1)

        #expect(profiles.first?.clientID == fixture.profileID)
        #expect(profiles.first?.preferences?.clientID == fixture.profilePreferencesID)
        #expect(profilePreferences.first?.profile?.clientID == fixture.profileID)
        #expect(agendaItems.first?.clientID == fixture.agendaItemID)
        #expect(subTasks.first?.clientID == fixture.subTaskID)
        #expect(subTasks.first?.parentItem?.clientID == fixture.agendaItemID)
        #expect(tasks.contains { $0.clientID == fixture.taskID && $0.isAbandoned })
        #expect(tasks.contains { $0.clientID == fixture.secondTaskID })
        #expect(
            tasks.first { $0.clientID == fixture.taskID }?.createdAt
                == fixture.fractionalTaskCreatedAt
        )
        #expect(taskSteps.first?.clientID == fixture.taskStepID)
        #expect(taskSteps.first?.parentTask?.clientID == fixture.taskID)
        #expect(blocks.first?.clientID == fixture.blockID)
        #expect(blockTasks.first?.clientID == fixture.blockTaskID)
        #expect(blockTasks.first?.block?.clientID == fixture.blockID)
        #expect(templates.first?.clientID == fixture.templateID)
        #expect(templateItems.first?.clientID == fixture.templateItemID)
        #expect(templateItems.first?.template?.clientID == fixture.templateID)
        #expect(attached.first?.clientID == fixture.attachedBundleID)
        #expect(attached.first?.block?.clientID == fixture.blockID)
        #expect(attachedItems.first?.clientID == fixture.attachedBundleItemID)
        #expect(attachedItems.first?.bundle?.clientID == fixture.attachedBundleID)
        #expect(focus.first?.clientID == fixture.focusSessionID)
        #expect(focus.first?.interruptionReasons == ["noise", "message"])
        #expect(relationships.first?.clientID == fixture.relationshipID)
        #expect(notes.first?.clientID == fixture.noteID)
        #expect(notes.first?.body == "Standalone note body")
        #expect(inbox.first?.clientID == fixture.inboxID)
        #expect(preferences.first?.clientID == fixture.userPreferencesID)

        #expect(defaults.string(forKey: "activeProfileID") == fixture.profileID.uuidString)
        #expect(defaults.array(forKey: "activity.snoozes") as? [Double] == [1, 2, 3])
        #expect(
            defaults.string(forKey: "ai.personalization.aboutMe")
                == "quiet, literal context"
        )
    }
}
