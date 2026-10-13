// TaskRelationship.swift
// AuGenda
//
// Dependency and relationship links between AgendaTasks.

import Foundation
import SwiftData

enum TaskRelationshipType: String, Codable, CaseIterable, Identifiable {
    case blocks
    case follows
    case bundles
    case related
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .blocks:  return "Blocks"
        case .follows: return "Follows"
        case .bundles: return "Bundled with"
        case .related: return "Related to"
        }
    }
    
    var inverseDisplayName: String {
        switch self {
        case .blocks:  return "Blocked by"
        case .follows: return "Must do first"
        case .bundles: return "Bundled with"
        case .related: return "Related to"
        }
    }
}

@Model
final class TaskRelationship {
    
    var clientID: UUID = UUID()
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    
    var sourceTaskID: UUID = UUID()
    var targetTaskID: UUID = UUID()
    
    var typeRaw: String = TaskRelationshipType.blocks.rawValue
    
    var type: TaskRelationshipType {
        get { TaskRelationshipType(rawValue: typeRaw) ?? .blocks }
        set { typeRaw = newValue.rawValue; updatedAt = .now }
    }
    
    var isBlocking: Bool {
        type == .blocks || type == .follows
    }
    
    init(
        sourceTaskID: UUID,
        targetTaskID: UUID,
        type: TaskRelationshipType = .blocks
    ) {
        self.clientID = UUID()
        self.createdAt = .now
        self.updatedAt = .now
        self.sourceTaskID = sourceTaskID
        self.targetTaskID = targetTaskID
        self.typeRaw = type.rawValue
    }
}

extension AgendaTask {
    /// Authoritative actionability check for any surface that has a model
    /// context. The context-free property covers lifecycle state; this method
    /// additionally enforces persisted blocking relationships.
    func isActionable(in context: ModelContext) -> Bool {
        isActionable && !isBlocked(in: context)
    }

    func blockingTaskIDs(in context: ModelContext) -> [UUID] {
        let taskID = self.clientID
        let blocksRaw = "blocks"
        let followsRaw = "follows"
        let descriptor = FetchDescriptor<TaskRelationship>(
            predicate: #Predicate { $0.sourceTaskID == taskID && ($0.typeRaw == blocksRaw || $0.typeRaw == followsRaw) }
        )
        return (try? context.fetch(descriptor))?.map { $0.targetTaskID } ?? []
    }
    
    func blockedByTaskIDs(in context: ModelContext) -> [UUID] {
        let taskID = self.clientID
        let blocksRaw = "blocks"
        let followsRaw = "follows"
        let descriptor = FetchDescriptor<TaskRelationship>(
            predicate: #Predicate { $0.targetTaskID == taskID && ($0.typeRaw == blocksRaw || $0.typeRaw == followsRaw) }
        )
        return (try? context.fetch(descriptor))?.map { $0.sourceTaskID } ?? []
    }
}

enum TaskRelationshipError: LocalizedError {
    case missingTask
    case selfReference
    case duplicate
    case cycle

    var errorDescription: String? {
        switch self {
        case .missingTask: return "Both tasks must exist before they can be linked."
        case .selfReference: return "A task cannot depend on itself."
        case .duplicate: return "That task relationship already exists."
        case .cycle: return "That dependency would create a cycle."
        }
    }
}

/// The only supported write boundary for task relationships. Reads remain
/// available on `AgendaTask`, while creation enforces referential integrity,
/// uniqueness, direction, and acyclic blocking dependencies.
@MainActor
enum TaskRelationshipService {

    @discardableResult
    static func create(
        sourceTaskID: UUID,
        targetTaskID: UUID,
        type: TaskRelationshipType,
        in context: ModelContext
    ) throws -> TaskRelationship {
        guard sourceTaskID != targetTaskID else {
            throw TaskRelationshipError.selfReference
        }

        let tasks = try context.fetch(FetchDescriptor<AgendaTask>())
        let taskIDs = Set(tasks.map(\.clientID))
        guard taskIDs.contains(sourceTaskID), taskIDs.contains(targetTaskID) else {
            throw TaskRelationshipError.missingTask
        }

        let relationships = try context.fetch(FetchDescriptor<TaskRelationship>())
        guard !relationships.contains(where: {
            $0.sourceTaskID == sourceTaskID
                && $0.targetTaskID == targetTaskID
                && $0.type == type
        }) else {
            throw TaskRelationshipError.duplicate
        }

        if type == .blocks || type == .follows,
           createsBlockingCycle(
               sourceTaskID: sourceTaskID,
               targetTaskID: targetTaskID,
               existing: relationships
           ) {
            throw TaskRelationshipError.cycle
        }

        let relationship = TaskRelationship(
            sourceTaskID: sourceTaskID,
            targetTaskID: targetTaskID,
            type: type
        )
        context.insert(relationship)
        do {
            try context.save()
            return relationship
        } catch {
            context.rollback()
            throw error
        }
    }

    static func deleteReferences(
        to taskID: UUID,
        in context: ModelContext
    ) throws {
        let relationships = try context.fetch(FetchDescriptor<TaskRelationship>())
        for relationship in relationships
        where relationship.sourceTaskID == taskID || relationship.targetTaskID == taskID {
            context.delete(relationship)
        }
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    private static func createsBlockingCycle(
        sourceTaskID: UUID,
        targetTaskID: UUID,
        existing: [TaskRelationship]
    ) -> Bool {
        var adjacency: [UUID: [UUID]] = [:]
        for relationship in existing where relationship.isBlocking {
            adjacency[relationship.sourceTaskID, default: []].append(relationship.targetTaskID)
        }
        adjacency[sourceTaskID, default: []].append(targetTaskID)

        var stack = [targetTaskID]
        var visited = Set<UUID>()
        while let current = stack.popLast() {
            if current == sourceTaskID { return true }
            guard visited.insert(current).inserted else { continue }
            stack.append(contentsOf: adjacency[current] ?? [])
        }
        return false
    }
}
