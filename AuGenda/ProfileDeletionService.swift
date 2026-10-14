import Foundation
import SwiftData

enum ProfileDeletionError: LocalizedError {
    case mustKeepOneProfile
    case ownsRecords(Int)

    var errorDescription: String? {
        switch self {
        case .mustKeepOneProfile:
            return "AuGenda must keep at least one profile."
        case .ownsRecords(let count):
            return "This profile still owns \(count) record\(count == 1 ? "" : "s"). Reassign or clear them before deletion."
        }
    }
}

/// Enforces the profile-deletion contract independently of any one view.
/// Raw profile UUID references are validated before deletion so a swipe,
/// future command, or automation cannot create orphaned ownership records.
@MainActor
enum ProfileDeletionService {

    /// Deletes profiles only when doing so keeps one profile and no owned
    /// records. Historical assigner references are cleared transactionally.
    /// Returns the preferred remaining profile ID.
    static func delete(
        profileIDs: Set<UUID>,
        in context: ModelContext
    ) throws -> UUID? {
        guard !profileIDs.isEmpty else { return nil }

        let profiles = try context.fetch(
            FetchDescriptor<Profile>(sortBy: [SortDescriptor(\.sortOrder)])
        )
        let targets = profiles.filter { profileIDs.contains($0.clientID) }
        let remaining = profiles.filter { !profileIDs.contains($0.clientID) }
        guard targets.count == profileIDs.count, !remaining.isEmpty else {
            throw ProfileDeletionError.mustKeepOneProfile
        }

        let agendaItems = try context.fetch(FetchDescriptor<AgendaItem>())
        let tasks = try context.fetch(FetchDescriptor<AgendaTask>())
        let inboxItems = try context.fetch(FetchDescriptor<InboxItem>())
        let sessions = try context.fetch(FetchDescriptor<FocusSession>())

        let ownedAgenda = agendaItems.filter { $0.assignedToProfileID.map(profileIDs.contains) == true }.count
        let ownedTasks = tasks.filter { $0.assignedToProfileID.map(profileIDs.contains) == true }.count
        let ownedInbox = inboxItems.filter { $0.assignedToProfileID.map(profileIDs.contains) == true }.count
        let ownedSessions = sessions.filter { $0.profileID.map(profileIDs.contains) == true }.count
        let ownedCount = ownedAgenda + ownedTasks + ownedInbox + ownedSessions
        guard ownedCount == 0 else {
            throw ProfileDeletionError.ownsRecords(ownedCount)
        }

        for item in agendaItems where item.assignedByProfileID.map(profileIDs.contains) == true {
            item.assignedByProfileID = nil
            item.updatedAt = .now
        }
        for task in tasks where task.assignedByProfileID.map(profileIDs.contains) == true {
            task.assignedByProfileID = nil
            task.updatedAt = .now
        }
        for profile in targets {
            context.delete(profile)
        }

        do {
            try context.save()
            return remaining.first?.clientID
        } catch {
            context.rollback()
            throw error
        }
    }
}
