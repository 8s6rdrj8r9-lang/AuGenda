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
