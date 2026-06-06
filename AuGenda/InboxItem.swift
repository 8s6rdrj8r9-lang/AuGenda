// InboxItem.swift
// AuGenda
//
// Brain-dump landing zone. Every raw capture lands here as .unprocessed
// before the user (with optional AI assist) confirms structure and moves
// it to AgendaTask. Nothing auto-files — the user always confirms.
//
// CloudKit-compatible: all properties have defaults or are optional.

import Foundation
import SwiftData

// MARK: - Supporting types

enum InboxItemSource: String, Codable {
    case textCapture  = "textCapture"
    case voiceCapture = "voiceCapture"
}

enum InboxItemState: String, Codable {
    case unprocessed = "unprocessed"  // raw capture, awaiting review
    case organized   = "organized"    // user confirmed → became an AgendaTask
    case archived    = "archived"     // user discarded
}

// MARK: - InboxItem

@Model
final class InboxItem {

    // MARK: Identity
    var clientID: UUID = UUID()
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    // MARK: Capture
    var rawCapture: String = ""
    var sourceRaw: String = InboxItemSource.textCapture.rawValue
    var stateRaw: String = InboxItemState.unprocessed.rawValue

    // MARK: AI suggestions (nil = AI hasn't run or AI is off)
    // Stored individually so each field can be nil-checked without JSON parsing.
    var aiSuggestedTitle: String? = nil
    var aiSuggestedFriction: Int? = nil
    var aiSuggestedEnergy: Int? = nil
    var aiSuggestedInitiationCost: Int? = nil
    var aiSuggestedSensoryLoad: Int? = nil
    var aiSuggestedSocialLoad: Int? = nil
    var aiSuggestedContextTag: String? = nil

    // MARK: Resolution
    /// UUID of the AgendaTask created when this item was confirmed as organized.
    var resolvedTaskID: UUID? = nil
    var assignedToProfileID: UUID? = nil

    // MARK: Computed

    var source: InboxItemSource {
        get { InboxItemSource(rawValue: sourceRaw) ?? .textCapture }
        set { sourceRaw = newValue.rawValue }
    }

    var state: InboxItemState {
        get { InboxItemState(rawValue: stateRaw) ?? .unprocessed }
        set { stateRaw = newValue.rawValue; updatedAt = .now }
    }

    var hasAISuggestions: Bool {
        aiSuggestedTitle != nil || aiSuggestedFriction != nil
    }

    // MARK: Init

    init(rawCapture: String = "", source: InboxItemSource = .textCapture) {
        self.clientID = UUID()
        self.createdAt = .now
        self.updatedAt = .now
        self.rawCapture = rawCapture
        self.sourceRaw = source.rawValue
    }
}
