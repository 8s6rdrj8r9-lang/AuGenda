// AIEnrichmentMutation.swift
// AuGenda
//
// Failure-atomic command boundaries for applying provider suggestions.
// SwiftData mutations are saved (or rolled back) before usage, memory, or
// other observable post-commit effects are published.

import Foundation
import SwiftData

struct AIEnrichmentPostCommitResult: Equatable {
    enum FailedEffect: String, Equatable {
        case usageLedger
        case personalizationMemory
    }

    var failedEffects: [FailedEffect] = []

    var userFacingWarning: String? {
        guard !failedEffects.isEmpty else { return nil }
        let labels = failedEffects.map {
            switch $0 {
            case .usageLedger: return "AI usage history"
            case .personalizationMemory: return "AI personalization memory"
            }
        }
        return "The task was saved, but \(labels.joined(separator: " and ")) could not be updated."
    }
}

@MainActor
struct AIEnrichmentPostCommitEffects {
    var recordUsage: (TaskEnrichment) -> Bool
    var recordMemory: (String, DifficultyBand) -> Bool

    static var live: Self {
        Self(
            recordUsage: { AIUsageLedger.shared.record($0) },
            recordMemory: {
                PersonalizationStore.shared.recordEnrichment(title: $0, band: $1)
            }
        )
    }
}

struct InboxEnrichmentDraft: Equatable {
    var title: String
    var friction: Int
    var energy: Int
    var initiationCost: Int
    var sensoryLoad: Int
    var socialLoad: Int
    var contextTag: String

    init(
        enrichment: TaskEnrichment,
        title: String,
        friction: Int,
        energy: Int,
        initiationCost: Int,
        sensoryLoad: Int,
        socialLoad: Int,
        contextTag: String
    ) {
        self.title = enrichment.title?.isEmpty == false ? enrichment.title! : title
        self.friction = enrichment.friction ?? friction
        self.energy = enrichment.energy ?? energy
        self.initiationCost = enrichment.initiationCost ?? initiationCost
        self.sensoryLoad = enrichment.sensoryLoad ?? sensoryLoad
        self.socialLoad = enrichment.socialLoad ?? socialLoad
        self.contextTag = enrichment.contextTag?.isEmpty == false
            ? enrichment.contextTag!
            : contextTag
    }
}

@MainActor
enum AIEnrichmentMutation {

    private struct AgendaTaskSnapshot {
        let title: String
        let notes: String
        let frictionLevel: Int
        let energyRequired: Int
        let sensoryLoad: Int
        let socialLoad: Int
        let initiationCost: Int
        let interestLevel: Int
        let estimatedMinutes: Int
        let contextTag: String
        let updatedAt: Date

        init(_ task: AgendaTask) {
            title = task.title
            notes = task.notes
            frictionLevel = task.frictionLevel
            energyRequired = task.energyRequired
            sensoryLoad = task.sensoryLoad
            socialLoad = task.socialLoad
            initiationCost = task.initiationCost
            interestLevel = task.interestLevel
            estimatedMinutes = task.estimatedMinutes
            contextTag = task.contextTag
            updatedAt = task.updatedAt
        }

        func restore(_ task: AgendaTask) {
            task.title = title
            task.notes = notes
            task.frictionLevel = frictionLevel
            task.energyRequired = energyRequired
            task.sensoryLoad = sensoryLoad
            task.socialLoad = socialLoad
            task.initiationCost = initiationCost
            task.interestLevel = interestLevel
            task.estimatedMinutes = estimatedMinutes
            task.contextTag = contextTag
            task.updatedAt = updatedAt
        }
    }

    private struct InboxItemSnapshot {
        let title: String?
        let friction: Int?
        let energy: Int?
        let initiationCost: Int?
        let sensoryLoad: Int?
        let socialLoad: Int?
        let contextTag: String?
        let updatedAt: Date

        init(_ item: InboxItem) {
            title = item.aiSuggestedTitle
            friction = item.aiSuggestedFriction
            energy = item.aiSuggestedEnergy
            initiationCost = item.aiSuggestedInitiationCost
            sensoryLoad = item.aiSuggestedSensoryLoad
            socialLoad = item.aiSuggestedSocialLoad
            contextTag = item.aiSuggestedContextTag
            updatedAt = item.updatedAt
        }

        func restore(_ item: InboxItem) {
            item.aiSuggestedTitle = title
            item.aiSuggestedFriction = friction
            item.aiSuggestedEnergy = energy
            item.aiSuggestedInitiationCost = initiationCost
            item.aiSuggestedSensoryLoad = sensoryLoad
            item.aiSuggestedSocialLoad = socialLoad
            item.aiSuggestedContextTag = contextTag
            item.updatedAt = updatedAt
        }
    }

    /// Applies suggestions to an existing backlog task as one SwiftData
    /// transaction. Usage and personalization are attempted only after save.
    static func apply(
        _ enrichment: TaskEnrichment,
        to task: AgendaTask,
        allowInterestInference: Bool,
        in context: ModelContext,
        now: Date = .now,
        save: (ModelContext) throws -> Void = { try $0.save() },
        effects injectedEffects: AIEnrichmentPostCommitEffects? = nil
    ) throws -> AIEnrichmentPostCommitResult {
        let effects = injectedEffects ?? .live
        let snapshot = AgendaTaskSnapshot(task)
        do {
            if let title = enrichment.title, !title.isEmpty {
                task.title = title
            }
            if let description = enrichment.taskDescription,
               !description.isEmpty,
               task.notes.isEmpty {
                task.notes = description
            }
            if let value = enrichment.friction {
                task.frictionLevel = value
            }
            if let value = enrichment.energy {
                task.energyRequired = value
            }
            if let value = enrichment.sensoryLoad {
                task.sensoryLoad = value
            }
            if let value = enrichment.socialLoad {
                task.socialLoad = value
            }
            if let value = enrichment.initiationCost {
                task.initiationCost = value
            }
            if let value = enrichment.interest, allowInterestInference {
                task.interestLevel = value
            }
            if let value = enrichment.estimatedMinutes {
                task.estimatedMinutes = value
            }
            if let value = enrichment.contextTag, !value.isEmpty {
                task.contextTag = value
            }

            if let subTasks = enrichment.subTasks, !subTasks.isEmpty {
                let existingCount = task.steps?.count ?? 0
                for (index, title) in subTasks.enumerated() {
                    let step = TaskStep(
                        title: title,
                        sortOrder: existingCount + index
                    )
                    step.parentTask = task
                    context.insert(step)
                }
            }
            let providerName = enrichment.usage?.provider ?? "ai"
            let modelName = enrichment.usage?.model ?? "default"
            let provenanceNote = Note(
                title: "AI Enrichment",
                body: "Provider: \(providerName)\nModel: \(modelName)\nPrompt Revision: v\(AIConsentPolicy.currentDisclosureVersion)\nApplied: \(now.formatted(date: .abbreviated, time: .shortened))",
                relatedTaskID: task.clientID
            )
            provenanceNote.tags = "ai-provenance"
            context.insert(provenanceNote)

            task.updatedAt = now
            try save(context)
        } catch {
            context.rollback()
            // SwiftData does not consistently refresh already-observed
            // model instances after rollback. Restore the exact visible
            // snapshot as well as the durable context.
            snapshot.restore(task)
            throw error
        }

        return publish(
            enrichments: [enrichment],
            memoryTitle: task.title,
            memoryBand: task.difficultyBand,
            effects: effects
        )
    }

    /// Caches provider suggestions on an Inbox item. The returned draft is
    /// safe for the view to publish only after this method succeeds.
    static func cache(
        _ enrichment: TaskEnrichment,
        on item: InboxItem,
        draft: InboxEnrichmentDraft,
        in context: ModelContext,
        now: Date = .now,
        save: (ModelContext) throws -> Void = { try $0.save() },
        effects injectedEffects: AIEnrichmentPostCommitEffects? = nil
    ) throws -> (
        draft: InboxEnrichmentDraft,
        postCommit: AIEnrichmentPostCommitResult
    ) {
        let effects = injectedEffects ?? .live
        let snapshot = InboxItemSnapshot(item)
        do {
            item.aiSuggestedTitle = draft.title
            item.aiSuggestedFriction = draft.friction
            item.aiSuggestedEnergy = draft.energy
            item.aiSuggestedInitiationCost = draft.initiationCost
            item.aiSuggestedSensoryLoad = draft.sensoryLoad
            item.aiSuggestedSocialLoad = draft.socialLoad
            item.aiSuggestedContextTag = draft.contextTag.isEmpty
                ? nil
                : draft.contextTag
            item.updatedAt = now
            try save(context)
        } catch {
            context.rollback()
            snapshot.restore(item)
            throw error
        }

        return (
            draft,
            publish(
                enrichments: [enrichment],
                memoryTitle: nil,
                memoryBand: nil,
                effects: effects
            )
        )
    }

    /// Publishes deferred effects for an enriched create/edit draft after its
    /// owning model has committed successfully.
    static func publishDraftEffects(
        enrichments: [TaskEnrichment],
        finalTitle: String,
        finalBand: DifficultyBand,
        effects injectedEffects: AIEnrichmentPostCommitEffects? = nil
    ) -> AIEnrichmentPostCommitResult {
        let effects = injectedEffects ?? .live
        return publish(
            enrichments: enrichments,
            memoryTitle: enrichments.isEmpty ? nil : finalTitle,
            memoryBand: enrichments.isEmpty ? nil : finalBand,
            effects: effects
        )
    }

    private static func publish(
        enrichments: [TaskEnrichment],
        memoryTitle: String?,
        memoryBand: DifficultyBand?,
        effects: AIEnrichmentPostCommitEffects
    ) -> AIEnrichmentPostCommitResult {
        var failures: [AIEnrichmentPostCommitResult.FailedEffect] = []

        for enrichment in enrichments where !effects.recordUsage(enrichment) {
            if !failures.contains(.usageLedger) {
                failures.append(.usageLedger)
            }
        }

        if let memoryTitle,
           let memoryBand,
           !effects.recordMemory(memoryTitle, memoryBand) {
            failures.append(.personalizationMemory)
        }

        return AIEnrichmentPostCommitResult(failedEffects: failures)
    }
}
