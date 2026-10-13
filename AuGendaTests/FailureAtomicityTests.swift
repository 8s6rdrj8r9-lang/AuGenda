import Foundation
import SwiftData
import Testing
@testable import AuGenda

@MainActor
struct FailureAtomicityTests {

    private enum InjectedFailure: Error {
        case save
        case persist
    }

    @Test func AIApplyRollsBackAndSuppressesLedgerAndMemoryOnSaveFailure() throws {
        let container = AppContainer.makeTestContainer()
        let context = container.mainContext
        context.autosaveEnabled = false
        let originalUpdatedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let task = AgendaTask(title: "Original", frictionLevel: 2)
        task.notes = "User note"
        task.updatedAt = originalUpdatedAt
        context.insert(task)
        try context.save()

        var usageCalls = 0
        var memoryCalls = 0
        let effects = AIEnrichmentPostCommitEffects(
            recordUsage: { _ in
                usageCalls += 1
                return true
            },
            recordMemory: { _, _ in
                memoryCalls += 1
                return true
            }
        )

        do {
            _ = try AIEnrichmentMutation.apply(
                enrichment(
                    title: "Provider title",
                    description: "Provider description",
                    subTasks: ["First step"],
                    usage: true
                ),
                to: task,
                allowInterestInference: true,
                in: context,
                save: { _ in throw InjectedFailure.save },
                effects: effects
            )
            Issue.record("Injected save failure unexpectedly succeeded")
        } catch {
            #expect(error is InjectedFailure)
        }

        let storedTasks = try context.fetch(FetchDescriptor<AgendaTask>())
        let storedSteps = try context.fetch(FetchDescriptor<TaskStep>())
        #expect(storedTasks.count == 1)
        #expect(storedTasks[0].title == "Original")
        #expect(storedTasks[0].notes == "User note")
        #expect(storedTasks[0].frictionLevel == 2)
        #expect(storedTasks[0].updatedAt == originalUpdatedAt)
        #expect(storedSteps.isEmpty)
        #expect(usageCalls == 0)
        #expect(memoryCalls == 0)
    }

    @Test func AIApplyPublishesEffectsOnlyAfterSuccessfulSave() throws {
        let container = AppContainer.makeTestContainer()
        let context = container.mainContext
        context.autosaveEnabled = false
        let task = AgendaTask(title: "Original", frictionLevel: 2)
        context.insert(task)
        try context.save()

        var saved = false
        var usageObservedAfterSave = false
        var memoryObservedAfterSave = false
        let effects = AIEnrichmentPostCommitEffects(
            recordUsage: { _ in
                usageObservedAfterSave = saved
                return true
            },
            recordMemory: { title, _ in
                memoryObservedAfterSave = saved && title == "Provider title"
                return true
            }
        )

        let outcome = try AIEnrichmentMutation.apply(
            enrichment(
                title: "Provider title",
                description: "Provider description",
                subTasks: ["First step"],
                usage: true
            ),
            to: task,
            allowInterestInference: false,
            in: context,
            save: {
                try $0.save()
                saved = true
            },
            effects: effects
        )

        #expect(outcome.failedEffects.isEmpty)
        #expect(task.title == "Provider title")
        #expect(task.notes == "Provider description")
        #expect(try context.fetch(FetchDescriptor<TaskStep>()).count == 1)
        #expect(usageObservedAfterSave)
        #expect(memoryObservedAfterSave)
    }

    @Test func InboxAICacheFailureLeavesModelAndViewDraftUnpublished() throws {
        let container = AppContainer.makeTestContainer()
        let context = container.mainContext
        context.autosaveEnabled = false
        let item = InboxItem(rawCapture: "Original capture")
        context.insert(item)
        try context.save()

        let priorDraft = InboxEnrichmentDraft(
            enrichment: enrichment(
                title: nil,
                description: nil,
                subTasks: nil,
                usage: false
            ),
            title: "Visible original",
            friction: 3,
            energy: 2,
            initiationCost: 0,
            sensoryLoad: 0,
            socialLoad: 0,
            contextTag: ""
        )
        let proposedDraft = InboxEnrichmentDraft(
            enrichment: enrichment(
                title: "Provider title",
                description: nil,
                subTasks: nil,
                usage: true
            ),
            title: priorDraft.title,
            friction: priorDraft.friction,
            energy: priorDraft.energy,
            initiationCost: priorDraft.initiationCost,
            sensoryLoad: priorDraft.sensoryLoad,
            socialLoad: priorDraft.socialLoad,
            contextTag: priorDraft.contextTag
        )
        var usageCalls = 0

        do {
            _ = try AIEnrichmentMutation.cache(
                enrichment(
                    title: "Provider title",
                    description: nil,
                    subTasks: nil,
                    usage: true
                ),
                on: item,
                draft: proposedDraft,
                in: context,
                save: { _ in throw InjectedFailure.save },
                effects: AIEnrichmentPostCommitEffects(
                    recordUsage: { _ in
                        usageCalls += 1
                        return true
                    },
                    recordMemory: { _, _ in true }
                )
            )
            Issue.record("Injected save failure unexpectedly succeeded")
        } catch {
            #expect(error is InjectedFailure)
        }

        #expect(item.aiSuggestedTitle == nil)
        #expect(item.aiSuggestedFriction == nil)
        #expect(priorDraft.title == "Visible original")
        #expect(usageCalls == 0)
    }

    @Test func EraseSaveFailureRollsBackAndSuppressesEveryExternalEffect() throws {
        let container = AppContainer.makeTestContainer()
        let context = container.mainContext
        context.autosaveEnabled = false
        context.insert(AgendaTask(title: "Keep on failure"))
        try context.save()
        var afterCommitCalls = 0

        do {
            _ = try EraseAllDataService.erase(
                in: context,
                save: { _ in throw InjectedFailure.save },
                afterCommit: {
                    afterCommitCalls += 1
                    return []
                }
            )
            Issue.record("Injected erase save failure unexpectedly succeeded")
        } catch {
            #expect(error is InjectedFailure)
        }

        #expect(try context.fetch(FetchDescriptor<AgendaTask>()).count == 1)
        #expect(afterCommitCalls == 0)
    }

    @Test func ProtectedCleanupAttemptsAllItemsAndReportsRetryTargets() {
        var apiAttempts: [AIProvider] = []
        var oauthAttempts: [AIProvider] = []
        var personalizationAttempts = 0
        var ledgerAttempts = 0

        let failures = ProtectedDataEraseService.erase(
            providers: [.openai, .gemini],
            using: ProtectedDataEraseDependencies(
                removeAPIKey: { provider in
                    apiAttempts.append(provider)
                    if provider == .openai {
                        throw InjectedFailure.persist
                    }
                },
                removeOAuthTokens: { provider in
                    oauthAttempts.append(provider)
                    return provider != .gemini
                },
                resetPersonalization: {
                    personalizationAttempts += 1
                    return false
                },
                clearUsageLedger: {
                    ledgerAttempts += 1
                    return true
                }
            )
        )

        #expect(apiAttempts == [.openai, .gemini])
        #expect(oauthAttempts == [.openai, .gemini])
        #expect(personalizationAttempts == 1)
        #expect(ledgerAttempts == 1)
        #expect(failures.contains("\(AIProvider.openai.displayName) API key"))
        #expect(failures.contains("\(AIProvider.gemini.displayName) OAuth tokens"))
        #expect(failures.contains("AI personalization files"))
        #expect(failures.contains("AI usage files") == false)
    }

    @Test func BackupReplacementValidationFailureNeverPublishesCandidate() throws {
        let originalUsage = [
            AIUsageEntry(
                provider: AIProvider.openai.rawValue,
                model: "original",
                promptTokens: 1,
                completionTokens: 1,
                estimatedCostUSD: 0,
                timestamp: .now
            )
        ]
        let replacementUsage = [
            AIUsageEntry(
                provider: AIProvider.openai.rawValue,
                model: "replacement",
                promptTokens: 2,
                completionTokens: 2,
                estimatedCostUSD: 0,
                timestamp: .now
            )
        ]
        var publishedUsage = originalUsage
        do {
            publishedUsage = try AIUsageLedger.validatedBackupReplacement(
                replacementUsage,
                persist: { _ in throw InjectedFailure.persist }
            )
            Issue.record("Injected ledger persistence failure unexpectedly succeeded")
        } catch {
            #expect(error is InjectedFailure)
        }
        #expect(publishedUsage[0].model == "original")

        let originalMemory = [
            PersonalizationContext.MemoryEntry(
                title: "Original",
                band: DifficultyBand.easy.rawValue,
                timestamp: .now
            )
        ]
        let replacementMemory = [
            PersonalizationContext.MemoryEntry(
                title: "Replacement",
                band: DifficultyBand.moderate.rawValue,
                timestamp: .now
            )
        ]
        var publishedMemory = originalMemory
        do {
            publishedMemory = try PersonalizationStore.validatedBackupMemoryReplacement(
                replacementMemory,
                persist: { _ in throw InjectedFailure.persist }
            )
            Issue.record("Injected memory persistence failure unexpectedly succeeded")
        } catch {
            #expect(error is InjectedFailure)
        }
        #expect(publishedMemory[0].title == "Original")
    }

    private func enrichment(
        title: String?,
        description: String?,
        subTasks: [String]?,
        usage: Bool
    ) -> TaskEnrichment {
        TaskEnrichment(
            title: title,
            taskDescription: description,
            subTasks: subTasks,
            friction: title == nil ? nil : 4,
            energy: title == nil ? nil : 3,
            sensoryLoad: nil,
            socialLoad: nil,
            initiationCost: nil,
            interest: nil,
            estimatedMinutes: nil,
            contextTag: nil,
            bestTimeOfDay: nil,
            confidence: nil,
            usage: usage
                ? TaskEnrichment.Usage(
                    provider: AIProvider.openai.rawValue,
                    model: "test-model",
                    promptTokens: 10,
                    completionTokens: 5
                )
                : nil
        )
    }
}
