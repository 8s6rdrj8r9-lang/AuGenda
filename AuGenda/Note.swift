// Note.swift
// AuGenda
//
// First-class Note model for the Artifact Ontology concept.

import Foundation
import SwiftData

@Model
final class Note {
    var clientID: UUID = UUID()
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    var title: String = ""
    var body: String = ""
    var tags: String = ""  // comma-separated

    var relatedTaskID: UUID? = nil
    var relatedItemID: UUID? = nil

    init(title: String = "", body: String = "", relatedTaskID: UUID? = nil, relatedItemID: UUID? = nil) {
        self.clientID = UUID()
        self.createdAt = .now
        self.updatedAt = .now
        self.title = title
        self.body = body
        self.relatedTaskID = relatedTaskID
        self.relatedItemID = relatedItemID
    }
}
