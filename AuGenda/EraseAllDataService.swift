// EraseAllDataService.swift
// AuGenda
//
// Testable command boundaries for destructive local erasure. The SwiftData
// transaction must commit before notifications, credentials, files, defaults,
// or profile reseeding are touched.

import Foundation
import SwiftData

@MainActor
struct ProtectedDataEraseDependencies {
    var removeAPIKey: (AIProvider) throws -> Void
    var removeOAuthTokens: (AIProvider) -> Bool
    var resetPersonalization: () -> Bool
    var clearUsageLedger: () -> Bool

    static var live: Self {
        Self(
            removeAPIKey: { try KeychainStore.remove(for: $0) },
            removeOAuthTokens: { OAuthCoordinator.shared.signOut(provider: $0) },
            resetPersonalization: { PersonalizationStore.shared.resetAll() },
            clearUsageLedger: { AIUsageLedger.shared.clear() }
        )
    }
}

@MainActor
enum ProtectedDataEraseService {
    /// Every cleanup is attempted so a single inaccessible Keychain item
    /// cannot prevent deletion of the remaining local secrets. Failures are
    /// named for an explicit, idempotent retry.
    static func erase(
        providers: [AIProvider] = AIProvider.allCases,
        using injectedDependencies: ProtectedDataEraseDependencies? = nil
    ) -> [String] {
        let dependencies = injectedDependencies ?? .live
        var failures: [String] = []
        for provider in providers {
            do {
                try dependencies.removeAPIKey(provider)
            } catch {
                failures.append("\(provider.displayName) API key")
            }
            if !dependencies.removeOAuthTokens(provider) {
                failures.append("\(provider.displayName) OAuth tokens")
            }
        }
        if !dependencies.resetPersonalization() {
            failures.append("AI personalization files")
        }
        if !dependencies.clearUsageLedger() {
            failures.append("AI usage files")
        }
        return failures
    }
}

@MainActor
enum EraseAllDataService {
    /// Deletes the durable SwiftData graph as one rollback-capable mutation,
    /// then invokes external cleanup. Injected save/effect seams allow tests
    /// to prove no secret, notification, defaults, or sync effect occurs on a
    /// failed database commit.
    static func erase(
        in context: ModelContext,
        save: (ModelContext) throws -> Void = { try $0.save() },
        afterCommit: () -> [String]
    ) throws -> [String] {
        try PersistentMutation.commit(
            in: context,
            changes: {
                try deletePersistentGraph(in: context)
            },
            save: save
        )
        return afterCommit()
    }

    private static func deletePersistentGraph(in context: ModelContext) throws {
        // SwiftData's bulk `delete(model:)` executes outside the pending
        // context transaction and cannot be recovered by `rollback()`.
        // Fetching and deleting instances keeps erasure staged until save.
        try deleteAll(TaskStep.self, in: context)
        try deleteAll(SubTask.self, in: context)
        try deleteAll(BlockTask.self, in: context)
        try deleteAll(BundleTemplateItem.self, in: context)
        try deleteAll(AttachedBundleItem.self, in: context)
        try deleteAll(AttachedBundle.self, in: context)
        try deleteAll(ProfilePreferences.self, in: context)
        try deleteAll(TaskRelationship.self, in: context)
        try deleteAll(FocusSession.self, in: context)
        try deleteAll(Note.self, in: context)
        try deleteAll(InboxItem.self, in: context)
        try deleteAll(AgendaTask.self, in: context)
        try deleteAll(AgendaItem.self, in: context)
        try deleteAll(Block.self, in: context)
        try deleteAll(BundleTemplate.self, in: context)
        try deleteAll(Profile.self, in: context)
        try deleteAll(UserPreferences.self, in: context)
    }

    private static func deleteAll<Model: PersistentModel>(
        _ type: Model.Type,
        in context: ModelContext
    ) throws {
        for model in try context.fetch(FetchDescriptor<Model>()) {
            context.delete(model)
        }
    }
}
