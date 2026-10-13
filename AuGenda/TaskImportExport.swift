// TaskImportExport.swift
// AuGenda
//
// Export AgendaTask records to Markdown / JSON / CSV / YAML / plain text,
// and import the same formats back. This is a task-list portability feature,
// not a full AuGenda backup: profiles, blocks, focus history, notes, settings,
// and other model types are intentionally outside this file's contract.
//
// Round-trip contract:
// - JSON → round-trips the exposed AgendaTask fields and task steps
// - YAML / CSV → round-trip the exposed scalar AgendaTask fields
// - Markdown → lossy on dates/flags-without-inline-marker; preserves
//   title, completion state, friction/energy/time/context when written by us
// - Plain text → titles only; everything else gets sensible defaults
//
// All exporters/importers are pure functions on Strings — no SwiftData
// dependency in the formatter layer. The bridge to AgendaTask lives in
// `ExportedTask.toAgendaTask()` so future schema changes only touch one
// translation seam.

import Foundation
import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import CryptoKit
import Security
import CommonCrypto
import os.log

private let logger = Logger(subsystem: "com.augenda.AuGenda", category: "TaskImportExport")

enum TaskPortabilityError: LocalizedError {
    case encodingFailed
    case encryptionFailed
    case passwordRequired
    case decryptionFailed
    case unsupportedVersion(Int)
    case wrongPayloadKind
    case invalidFormat(String)
    case importTooLarge
    case tooManyTasks
    case duplicateIdentity
    case validationFailed([TaskImportDiagnostic])

    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "The task list couldn't be encoded."
        case .encryptionFailed:
            return "Encryption failed. No export file was created."
        case .passwordRequired:
            return "This task list is encrypted. Enter its password and try again."
        case .decryptionFailed:
            return "The password is incorrect or the encrypted task list is damaged."
        case .unsupportedVersion(let version):
            return "Task-list version \(version) isn't supported by this version of AuGenda."
        case .wrongPayloadKind:
            return "This file isn't an AuGenda active-task-list export."
        case .invalidFormat(let detail):
            return "The task-list file is invalid: \(detail)"
        case .importTooLarge:
            return "The task-list file is larger than the 10 MB import limit."
        case .tooManyTasks:
            return "The task-list file contains more than 10,000 tasks."
        case .duplicateIdentity:
            return "The task-list file contains the same task identity more than once."
        case .validationFailed(let diagnostics):
            guard let first = diagnostics.first else {
                return "The task-list file contains invalid values."
            }
            let remainder = diagnostics.count - 1
            let suffix = remainder > 0 ? " (+\(remainder) more)" : ""
            return "\(first.localizedDescription)\(suffix)"
        }
    }
}

/// A stable, typed import diagnostic that can be rendered by any future
/// preview UI without parsing an error string.
struct TaskImportDiagnostic: Codable, Equatable, Sendable {
    enum Severity: String, Codable, Sendable {
        case error
        case warning
    }

    let severity: Severity
    let row: Int
    let field: String
    let message: String

    var localizedDescription: String {
        "Row \(row), \(field): \(message)"
    }
}

struct TaskImportPreview {
    let tasks: [AgendaTask]
    let diagnostics: [TaskImportDiagnostic]
}

// MARK: - Format

enum TaskExportFormat: String, CaseIterable, Identifiable {
    case markdown
    case json
    case csv
    case yaml
    case plainText

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .markdown:  return "Markdown"
        case .json:      return "JSON"
        case .csv:       return "CSV"
        case .yaml:      return "YAML"
        case .plainText: return "Plain text"
        }
    }

    var fileExtension: String {
        switch self {
        case .markdown:  return "md"
        case .json:      return "json"
        case .csv:       return "csv"
        case .yaml:      return "yaml"
        case .plainText: return "txt"
        }
    }

    /// UTType for `.fileExporter` and `.fileImporter`. macOS/iOS don't ship
    /// dedicated UTTypes for Markdown/YAML, so those fall back to `.plainText`.
    var contentType: UTType {
        switch self {
        case .json:      return .json
        case .csv:       return .commaSeparatedText
        case .markdown:  return .plainText
        case .yaml:      return .plainText
        case .plainText: return .plainText
        }
    }
}

// MARK: - Canonical payload (used by JSON, mirrored by YAML)

enum TaskExportKind: String, Codable {
    case activeTaskList
}

struct TaskExportPayload: Codable {
    let version: Int
    let kind: TaskExportKind?
    let exportedAt: Date
    let tasks: [ExportedTask]

    init(
        version: Int,
        kind: TaskExportKind? = .activeTaskList,
        exportedAt: Date,
        tasks: [ExportedTask]
    ) {
        self.version = version
        self.kind = kind
        self.exportedAt = exportedAt
        self.tasks = tasks
    }
}

struct ExportedTaskStep: Codable {
    var clientID: UUID
    var createdAt: Date
    var title: String
    var isComplete: Bool
    var sortOrder: Int
    var estimatedMinutes: Int

    init(from step: TaskStep) {
        clientID = step.clientID
        createdAt = step.createdAt
        title = step.title
        isComplete = step.isComplete
        sortOrder = step.sortOrder
        estimatedMinutes = step.estimatedMinutes
    }

    func toTaskStep(parent: AgendaTask) -> TaskStep {
        let step = TaskStep(
            title: title,
            estimatedMinutes: estimatedMinutes,
            sortOrder: sortOrder
        )
        step.clientID = clientID
        step.createdAt = createdAt
        step.isComplete = isComplete
        step.parentTask = parent
        return step
    }
}

struct ExportedTask: Codable {
    var clientID: UUID?
    var createdAt: Date?
    var updatedAt: Date?
    var title: String
    var notes: String
    var frictionLevel: Int
    var energyRequired: Int
    var estimatedMinutes: Int
    var contextTag: String
    var interestLevel: Int
    var priority: Int
    var hyperfocusRisk: Bool
    var needsBodyDouble: Bool
    var waitingOn: String
    var dueDate: Date?
    var scheduledDate: Date?
    var isComplete: Bool
    var completedAt: Date?
    var isDeferredUntil: Date?
    var isAbandoned: Bool?
    var abandonedAt: Date?
    var abandonReason: String?
    var sensoryLoad: Int?
    var socialLoad: Int?
    var initiationCost: Int?
    var specialInterest: Bool?
    var excludeFromAI: Bool?
    var sortOrder: Int?
    var recurrenceRule: String?
    var recurrenceParentID: UUID?
    var assignedToProfileID: UUID?
    var assignedByProfileID: UUID?
    var agendaItemID: UUID?
    var steps: [ExportedTaskStep]?

    init(from task: AgendaTask) {
        self.clientID        = task.clientID
        self.createdAt       = task.createdAt
        self.updatedAt       = task.updatedAt
        self.title           = task.title
        self.notes           = task.notes
        self.frictionLevel   = task.frictionLevel
        self.energyRequired  = task.energyRequired
        // Preserve the stored base estimate. `totalEstimatedMinutes` is a
        // derived display value that switches to the step sum when steps exist.
        self.estimatedMinutes = task.estimatedMinutes
        self.contextTag      = task.contextTag
        self.interestLevel   = task.interestLevel
        self.priority        = task.priority
        self.hyperfocusRisk  = task.hyperfocusRisk
        self.needsBodyDouble = task.needsBodyDouble
        self.waitingOn       = task.waitingOn
        self.dueDate         = task.dueDate
        self.scheduledDate   = task.scheduledDate
        self.isComplete      = task.isComplete
        self.completedAt     = task.completedAt
        self.isDeferredUntil = task.isDeferredUntil
        self.isAbandoned     = task.isAbandoned
        self.abandonedAt     = task.abandonedAt
        self.abandonReason   = task.abandonReason
        self.sensoryLoad     = task.sensoryLoad
        self.socialLoad      = task.socialLoad
        self.initiationCost  = task.initiationCost
        self.specialInterest = task.specialInterest
        self.excludeFromAI   = task.excludeFromAI
        self.sortOrder       = task.sortOrder
        self.recurrenceRule  = task.recurrenceRule
        // A task-list share has no profile, agenda-item, or recurrence-parent
        // records that could make these foreign keys valid at the destination.
        // Whole-product backup carries the complete graph instead.
        self.recurrenceParentID = nil
        self.assignedToProfileID = nil
        self.assignedByProfileID = nil
        self.agendaItemID = nil
        if let taskSteps = task.steps {
            let sortedSteps = taskSteps.sorted { $0.sortOrder < $1.sortOrder }
            var exportedSteps: [ExportedTaskStep] = []
            exportedSteps.reserveCapacity(sortedSteps.count)
            for step in sortedSteps {
                exportedSteps.append(ExportedTaskStep(from: step))
            }
            self.steps = exportedSteps
        } else {
            self.steps = nil
        }
    }

    func toAgendaTask() -> AgendaTask {
        let task = AgendaTask(
            title: title,
            frictionLevel: frictionLevel,
            energyRequired: energyRequired,
            estimatedMinutes: estimatedMinutes,
            contextTag: contextTag,
            priority: priority,
            interestLevel: interestLevel
        )
        task.clientID        = clientID ?? deterministicLegacyID
        task.createdAt       = createdAt ?? .now
        task.updatedAt       = updatedAt ?? task.createdAt
        task.notes           = notes
        task.hyperfocusRisk  = hyperfocusRisk
        task.needsBodyDouble = needsBodyDouble
        task.waitingOn       = waitingOn
        task.dueDate         = dueDate
        task.scheduledDate   = scheduledDate
        task.isComplete      = isComplete
        task.completedAt     = completedAt
        task.isDeferredUntil = isDeferredUntil
        task.isAbandoned     = isAbandoned ?? false
        task.abandonedAt     = abandonedAt
        task.abandonReason   = abandonReason ?? ""
        task.sensoryLoad     = sensoryLoad ?? 0
        task.socialLoad      = socialLoad ?? 0
        task.initiationCost  = initiationCost ?? 0
        task.specialInterest = specialInterest ?? false
        task.excludeFromAI   = excludeFromAI ?? false
        task.sortOrder       = sortOrder ?? 0
        task.recurrenceRule  = recurrenceRule ?? "none"
        task.recurrenceParentID = recurrenceParentID
        task.assignedToProfileID = assignedToProfileID
        task.assignedByProfileID = assignedByProfileID
        task.agendaItemID    = agendaItemID
        if let steps, !steps.isEmpty {
            task.steps = steps.map { $0.toTaskStep(parent: task) }
        }
        return task
    }

    private var deterministicLegacyID: UUID {
        TaskImportIdentity.uuid(
            seed: [
                title, notes, "\(frictionLevel)", "\(energyRequired)",
                "\(estimatedMinutes)", contextTag, "\(interestLevel)",
                "\(priority)", "\(hyperfocusRisk)", "\(needsBodyDouble)",
                waitingOn, dueDate?.ISO8601Format() ?? "",
                scheduledDate?.ISO8601Format() ?? "", "\(isComplete)"
            ].joined(separator: "\u{1F}")
        )
    }
}

private enum TaskImportIdentity {
    static func uuid(seed: String) -> UUID {
        var bytes = Array(SHA256.hash(data: Data(seed.utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80

        let hex = bytes.map { String(format: "%02x", $0) }
        let string = [
            hex[0...3].joined(),
            hex[4...5].joined(),
            hex[6...7].joined(),
            hex[8...9].joined(),
            hex[10...15].joined()
        ].joined(separator: "-")
        return UUID(uuidString: string)!
    }
}

// MARK: - Exporter

enum TaskExporter {

    static let encryptedExportV2Prefix = "AuGendaExportV2:"
    private static let encryptedExportSaltBytes = 32
    private static let encryptedExportNonceBytes = 12
    private static let encryptedExportTagBytes = 16
    private static let pbkdf2Iterations: UInt32 = 210_000

    /// Legacy encrypted exports had no textual magic prefix. Their only
    /// detectable shape is a single Base64 value large enough to contain the
    /// fixed salt, nonce, authentication tag, and at least one ciphertext
    /// byte. Treating that shape as encrypted before format parsing prevents a
    /// wrong password from becoming a bogus one-line plain-text task.
    static func looksLikeLegacyEncryptedEnvelope(_ value: String) -> Bool {
        guard !value.hasPrefix(encryptedExportV2Prefix) else { return false }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.unicodeScalars.allSatisfy({
                  CharacterSet(
                      charactersIn:
                          "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/="
                  ).contains($0)
              }),
              let combined = Data(base64Encoded: trimmed) else {
            return false
        }
        return combined.count
            > encryptedExportSaltBytes
                + encryptedExportNonceBytes
                + encryptedExportTagBytes
    }

    @MainActor
    static func export(_ tasks: [AgendaTask], as format: TaskExportFormat) throws -> String {
        let exported = tasks.map(ExportedTask.init)
        let payload = TaskExportPayload(version: 2, exportedAt: .now, tasks: exported)
        switch format {
        case .json:      return try jsonString(payload)
        case .yaml:      return yamlString(payload)
        case .csv:       return csvString(exported)
        case .markdown:  return markdownString(exported)
        case .plainText: return plainTextString(exported)
        }
    }

    // MARK: JSON

    private static func jsonString(_ payload: TaskExportPayload) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data: Data
        do {
            data = try encoder.encode(payload)
        } catch {
            logger.error("Failed to encode JSON payload")
            throw TaskPortabilityError.encodingFailed
        }
        guard let str = String(data: data, encoding: .utf8) else {
            throw TaskPortabilityError.encodingFailed
        }
        return str
    }

    // MARK: YAML
    //
    // Hand-rolled — Foundation has no YAML encoder. We control both write and
    // read, so the format only needs to round-trip with itself.

    private static func yamlString(_ payload: TaskExportPayload) -> String {
        let iso = ISO8601DateFormatter()
        var out = "version: \(payload.version)\n"
        out += "kind: \(TaskExportKind.activeTaskList.rawValue)\n"
        out += "exportedAt: \(iso.string(from: payload.exportedAt))\n"
        out += "tasks:\n"
        for task in payload.tasks {
            out += "  - title: \(yamlQuote(task.title))\n"
            if let clientID = task.clientID {
                out += "    clientID: \(clientID.uuidString)\n"
            }
            if let createdAt = task.createdAt {
                out += "    createdAt: \(iso.string(from: createdAt))\n"
            }
            if let updatedAt = task.updatedAt {
                out += "    updatedAt: \(iso.string(from: updatedAt))\n"
            }
            out += "    notes: \(yamlQuote(task.notes))\n"
            out += "    frictionLevel: \(task.frictionLevel)\n"
            out += "    energyRequired: \(task.energyRequired)\n"
            out += "    estimatedMinutes: \(task.estimatedMinutes)\n"
            out += "    contextTag: \(yamlQuote(task.contextTag))\n"
            out += "    interestLevel: \(task.interestLevel)\n"
            out += "    priority: \(task.priority)\n"
            out += "    hyperfocusRisk: \(task.hyperfocusRisk)\n"
            out += "    needsBodyDouble: \(task.needsBodyDouble)\n"
            out += "    waitingOn: \(yamlQuote(task.waitingOn))\n"
            out += "    isComplete: \(task.isComplete)\n"
            out += "    completedAt: \(task.completedAt.map(iso.string(from:)) ?? "")\n"
            out += "    isDeferredUntil: \(task.isDeferredUntil.map(iso.string(from:)) ?? "")\n"
            out += "    isAbandoned: \(task.isAbandoned ?? false)\n"
            out += "    abandonedAt: \(task.abandonedAt.map(iso.string(from:)) ?? "")\n"
            out += "    abandonReason: \(yamlQuote(task.abandonReason ?? ""))\n"
            out += "    sensoryLoad: \(task.sensoryLoad ?? 0)\n"
            out += "    socialLoad: \(task.socialLoad ?? 0)\n"
            out += "    initiationCost: \(task.initiationCost ?? 0)\n"
            out += "    specialInterest: \(task.specialInterest ?? false)\n"
            out += "    excludeFromAI: \(task.excludeFromAI ?? false)\n"
            out += "    sortOrder: \(task.sortOrder ?? 0)\n"
            out += "    recurrenceRule: \(yamlQuote(task.recurrenceRule ?? "none"))\n"
            out += "    recurrenceParentID: \(task.recurrenceParentID?.uuidString ?? "")\n"
            out += "    assignedToProfileID: \(task.assignedToProfileID?.uuidString ?? "")\n"
            out += "    assignedByProfileID: \(task.assignedByProfileID?.uuidString ?? "")\n"
            out += "    agendaItemID: \(task.agendaItemID?.uuidString ?? "")\n"
            if let due = task.dueDate {
                out += "    dueDate: \(iso.string(from: due))\n"
            }
            if let sched = task.scheduledDate {
                out += "    scheduledDate: \(iso.string(from: sched))\n"
            }
        }
        return out
    }

    private static func yamlQuote(_ s: String) -> String {
        // Always quote strings — robust against colons, ampersands, etc.
        let escaped = s
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\n", with: "\\n")
        return "\"\(escaped)\""
    }

    // MARK: CSV

    private static let csvHeaders = [
        "auGendaCSVVersion", "clientID", "createdAt", "updatedAt", "title", "notes",
        "frictionLevel", "energyRequired", "estimatedMinutes",
        "contextTag", "interestLevel", "priority", "hyperfocusRisk",
        "needsBodyDouble", "waitingOn", "dueDate", "scheduledDate", "isComplete",
        "completedAt", "isDeferredUntil", "isAbandoned", "abandonedAt",
        "abandonReason", "sensoryLoad", "socialLoad", "initiationCost",
        "specialInterest", "excludeFromAI", "sortOrder", "recurrenceRule",
        "recurrenceParentID", "assignedToProfileID", "assignedByProfileID",
        "agendaItemID"
    ]

    private static func csvString(_ tasks: [ExportedTask]) -> String {
        let iso = ISO8601DateFormatter()
        var out = csvHeaders.joined(separator: ",") + "\n"
        for t in tasks {
            var row: [String] = [
                "2",
                t.clientID?.uuidString ?? "",
                t.createdAt.map { iso.string(from: $0) } ?? "",
                t.updatedAt.map { iso.string(from: $0) } ?? "",
                csvEscape(t.title),
                csvEscape(t.notes),
                "\(t.frictionLevel)",
                "\(t.energyRequired)",
                "\(t.estimatedMinutes)",
                csvEscape(t.contextTag),
                "\(t.interestLevel)",
                "\(t.priority)",
                "\(t.hyperfocusRisk)",
                "\(t.needsBodyDouble)",
                csvEscape(t.waitingOn),
                t.dueDate.map { iso.string(from: $0) } ?? "",
                t.scheduledDate.map { iso.string(from: $0) } ?? "",
                "\(t.isComplete)",
                t.completedAt.map { iso.string(from: $0) } ?? "",
                t.isDeferredUntil.map { iso.string(from: $0) } ?? ""
            ]
            row.append(contentsOf: [
                String(t.isAbandoned ?? false),
                t.abandonedAt.map { iso.string(from: $0) } ?? "",
                csvEscape(t.abandonReason ?? ""),
                String(t.sensoryLoad ?? 0),
                String(t.socialLoad ?? 0),
                String(t.initiationCost ?? 0),
                String(t.specialInterest ?? false),
                String(t.excludeFromAI ?? false),
                String(t.sortOrder ?? 0),
                csvEscape(t.recurrenceRule ?? "none"),
            ])
            row.append(contentsOf: [
                t.recurrenceParentID?.uuidString ?? "",
                t.assignedToProfileID?.uuidString ?? "",
                t.assignedByProfileID?.uuidString ?? "",
                t.agendaItemID?.uuidString ?? ""
            ])
            out += row.joined(separator: ",") + "\n"
        }
        return out
    }

    private static func csvEscape(_ s: String) -> String {
        let safe = neutralizeCSVFormula(s)
        if safe.contains(",") || safe.contains("\"") || safe.contains("\n") || safe.contains("\r") {
            return "\"\(safe.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return safe
    }

    private static func neutralizeCSVFormula(_ value: String) -> String {
        let apostropheCount = value.prefix { $0 == "'" }.count
        if apostropheCount > 0 {
            let remainder = String(value.dropFirst(apostropheCount))
            if isCSVFormulaCandidate(remainder) {
                // Add one escape layer so a literal leading apostrophe remains
                // distinguishable from the neutralization marker on import.
                return "'" + value
            }
        }
        guard isCSVFormulaCandidate(value) else {
            return value
        }
        // Spreadsheet applications interpret these prefixes as formulas even
        // inside a quoted CSV field. A leading apostrophe forces literal text.
        return "'" + value
    }

    static func isCSVFormulaCandidate(_ value: String) -> Bool {
        let trimmed = value.drop {
            $0 == " " || $0 == "\t" || $0 == "\r"
        }
        guard let first = value.first else { return false }
        return first == "\t" || first == "\r"
            || trimmed.first.map { ["=", "+", "-", "@"].contains($0) } == true
    }

    // MARK: Markdown
    //
    // GFM checklist format with an italic metadata trailer. Round-trips
    // title + completion + friction/energy/minutes/context when we wrote it;
    // tolerant of foreign markdown that lacks the trailer.

    private static func markdownString(_ tasks: [ExportedTask]) -> String {
        let df = DateFormatter()
        df.dateStyle = .medium
        var out = "# AuGenda Tasks\n_Exported \(df.string(from: .now))_\n\n"

        let backlog = tasks.filter { !$0.isComplete }
        let done = tasks.filter { $0.isComplete }

        if !backlog.isEmpty {
            out += "## Backlog\n\n"
            for t in backlog { out += markdownLine(t) }
            out += "\n"
        }
        if !done.isEmpty {
            out += "## Done\n\n"
            for t in done { out += markdownLine(t) }
        }
        return out
    }

    private static func markdownLine(_ t: ExportedTask) -> String {
        let check = t.isComplete ? "x" : " "
        var meta: [String] = []
        meta.append("friction:\(t.frictionLevel)")
        meta.append("energy:\(t.energyRequired)")
        meta.append("\(t.estimatedMinutes)m")
        if !t.contextTag.isEmpty   { meta.append("@\(t.contextTag)") }
        if t.priority > 0          { meta.append("priority:\(t.priority)") }
        if t.hyperfocusRisk        { meta.append("hyperfocus") }
        if t.needsBodyDouble       { meta.append("body-double") }
        if t.interestLevel != 3    { meta.append("interest:\(t.interestLevel)") }
        if let clientID = t.clientID { meta.append("id:\(clientID.uuidString)") }

        var line = "- [\(check)] \(t.title) — *\(meta.joined(separator: " · "))*\n"
        if !t.notes.isEmpty {
            let quoted = t.notes.replacingOccurrences(of: "\n", with: "\n  > ")
            line += "  > \(quoted)\n"
        }
        return line
    }

    // MARK: Plain text

    private static func plainTextString(_ tasks: [ExportedTask]) -> String {
        tasks.map { $0.title }.joined(separator: "\n") + "\n"
    }

    // MARK: - Encryption
    //
    // AES-256-GCM with a user-provided password. New exports use a versioned
    // PBKDF2-HMAC-SHA256 envelope. The legacy SHA-256 envelope remains readable.

    static func encrypt(_ payload: String, password: String) throws -> String {
        guard !password.isEmpty else { throw TaskPortabilityError.passwordRequired }
        guard let data = payload.data(using: .utf8) else {
            throw TaskPortabilityError.encodingFailed
        }

        guard let salt = randomData(count: encryptedExportSaltBytes),
              let key = pbkdf2Key(password: password, salt: salt) else {
            throw TaskPortabilityError.encryptionFailed
        }

        // Encrypt
        let nonce = AES.GCM.Nonce()
        let sealedBox: AES.GCM.SealedBox
        do {
            sealedBox = try AES.GCM.seal(data, using: key, nonce: nonce)
        } catch {
            logger.error("AES encryption failed")
            throw TaskPortabilityError.encryptionFailed
        }

        // Combine: salt + nonce + ciphertext + tag
        var result = salt
        result.append(contentsOf: nonce)
        result.append(sealedBox.ciphertext)
        result.append(sealedBox.tag)
        return encryptedExportV2Prefix + result.base64EncodedString()
    }

    static func decrypt(_ base64String: String, password: String) throws -> String {
        guard !password.isEmpty else { throw TaskPortabilityError.passwordRequired }
        let decrypted: String?
        if base64String.hasPrefix(encryptedExportV2Prefix) {
            let payload = String(base64String.dropFirst(encryptedExportV2Prefix.count))
            decrypted = decryptV2(payload, password: password)
        } else {
            decrypted = decryptLegacyV1(base64String, password: password)
        }
        guard let decrypted else { throw TaskPortabilityError.decryptionFailed }
        return decrypted
    }

    private static func decryptV2(_ base64String: String, password: String) -> String? {
        guard let combined = Data(base64Encoded: base64String) else { return nil }
        guard combined.count > encryptedExportSaltBytes + encryptedExportNonceBytes + encryptedExportTagBytes else {
            return nil
        }

        let salt = combined.prefix(encryptedExportSaltBytes)
        let nonceStart = encryptedExportSaltBytes
        let nonceEnd = nonceStart + encryptedExportNonceBytes
        let nonceData = combined[nonceStart..<nonceEnd]
        let ciphertext = combined[nonceEnd..<(combined.count - encryptedExportTagBytes)]
        let tag = combined.suffix(encryptedExportTagBytes)

        let nonce: AES.GCM.Nonce
        do {
            nonce = try AES.GCM.Nonce(data: nonceData)
        } catch {
            logger.error("Invalid nonce data")
            return nil
        }

        guard let key = pbkdf2Key(password: password, salt: Data(salt)) else { return nil }
        return open(ciphertext: ciphertext, tag: tag, nonce: nonce, key: key)
    }

    private static func decryptLegacyV1(_ base64String: String, password: String) -> String? {
        guard let combined = Data(base64Encoded: base64String) else { return nil }
        guard combined.count > encryptedExportSaltBytes + encryptedExportNonceBytes + encryptedExportTagBytes else {
            return nil
        }

        let salt = combined.prefix(encryptedExportSaltBytes)
        let nonceStart = encryptedExportSaltBytes
        let nonceEnd = nonceStart + encryptedExportNonceBytes
        let nonceData = combined[nonceStart..<nonceEnd]
        let ciphertext = combined[nonceEnd..<(combined.count - encryptedExportTagBytes)]
        let tag = combined.suffix(encryptedExportTagBytes)

        let nonce: AES.GCM.Nonce
        do {
            nonce = try AES.GCM.Nonce(data: nonceData)
        } catch {
            logger.error("Invalid nonce data")
            return nil
        }

        guard let passwordData = password.data(using: .utf8) else { return nil }
        var combinedData = passwordData
        combinedData.append(salt)
        let hash = SHA256.hash(data: combinedData)
        let key = SymmetricKey(data: Data(hash))

        return open(ciphertext: ciphertext, tag: tag, nonce: nonce, key: key)
    }

    private static func open<DataSlice: DataProtocol>(
        ciphertext: DataSlice,
        tag: DataSlice,
        nonce: AES.GCM.Nonce,
        key: SymmetricKey
    ) -> String? {
        let box: AES.GCM.SealedBox
        do {
            box = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ciphertext, tag: tag)
        } catch {
            logger.error("Invalid sealed box")
            return nil
        }
        let decrypted: Data
        do {
            decrypted = try AES.GCM.open(box, using: key)
        } catch {
            logger.error("AES decryption failed")
            return nil
        }
        return String(data: decrypted, encoding: .utf8)
    }

    private static func randomData(count: Int) -> Data? {
        var data = Data(count: count)
        let status = data.withUnsafeMutableBytes { buffer in
            guard let baseAddress = buffer.baseAddress else { return errSecParam }
            return SecRandomCopyBytes(kSecRandomDefault, count, baseAddress)
        }
        guard status == errSecSuccess else {
            logger.error("Random generation failed: \(status)")
            return nil
        }
        return data
    }

    private static func pbkdf2Key(password: String, salt: Data) -> SymmetricKey? {
        guard !password.isEmpty, let passwordData = password.data(using: .utf8) else { return nil }
        var derived = Data(count: 32)
        let derivedCount = derived.count
        let status = derived.withUnsafeMutableBytes { derivedBuffer in
            salt.withUnsafeBytes { saltBuffer in
                passwordData.withUnsafeBytes { passwordBuffer in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBuffer.bindMemory(to: Int8.self).baseAddress!,
                        passwordData.count,
                        saltBuffer.bindMemory(to: UInt8.self).baseAddress!,
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        pbkdf2Iterations,
                        derivedBuffer.bindMemory(to: UInt8.self).baseAddress!,
                        derivedCount
                    )
                }
            }
        }
        guard status == kCCSuccess else {
            logger.error("PBKDF2 key derivation failed: \(status)")
            return nil
        }
        return SymmetricKey(data: derived)
    }
}

// MARK: - Importer

enum TaskImporter {

    static let maximumImportBytes = 10 * 1024 * 1024
    static let maximumTaskCount = 10_000
    private static let structuredTaskFields: Set<String> = [
        "clientID", "createdAt", "updatedAt", "title", "notes",
        "frictionLevel", "energyRequired", "estimatedMinutes",
        "contextTag", "interestLevel", "priority", "hyperfocusRisk",
        "needsBodyDouble", "waitingOn", "dueDate", "scheduledDate",
        "isComplete", "completedAt", "isDeferredUntil", "isAbandoned",
        "abandonedAt", "abandonReason", "sensoryLoad", "socialLoad",
        "initiationCost", "specialInterest", "excludeFromAI", "sortOrder",
        "recurrenceRule", "recurrenceParentID", "assignedToProfileID",
        "assignedByProfileID", "agendaItemID"
    ]
    private static let jsonEnvelopeFields: Set<String> = [
        "version", "kind", "exportedAt", "tasks"
    ]
    private static let jsonStepFields: Set<String> = [
        "clientID", "createdAt", "title", "isComplete", "sortOrder",
        "estimatedMinutes"
    ]

    /// Detect format from a filename's extension. Returns nil if no match.
    static func detectFormat(filename: String) -> TaskExportFormat? {
        let ext = (filename as NSString).pathExtension.lowercased()
        switch ext {
        case "json":             return .json
        case "yaml", "yml":      return .yaml
        case "csv":              return .csv
        case "md", "markdown":   return .markdown
        case "txt":              return .plainText
        default:                 return nil
        }
    }

    static func parse(_ text: String, as format: TaskExportFormat) -> [AgendaTask] {
        (try? validateBatch(validateAndParse(text, as: format))) ?? []
    }

    /// Strict path used by the file-import UI. It validates the envelope and
    /// format before any model context is mutated.
    static func validatedImport(
        _ text: String,
        as format: TaskExportFormat,
        password: String
    ) throws -> [AgendaTask] {
        try previewImport(text, as: format, password: password).tasks
    }

    /// Produces a typed preview before persistence. Malformed rows are rejected
    /// with `TaskPortabilityError.validationFailed`; warnings describe only
    /// intentional lossiness in formats that do not carry structured fields.
    static func previewImport(
        _ text: String,
        as format: TaskExportFormat,
        password: String
    ) throws -> TaskImportPreview {
        guard text.utf8.count <= maximumImportBytes else {
            throw TaskPortabilityError.importTooLarge
        }

        let cleartext: String
        if text.hasPrefix(TaskExporter.encryptedExportV2Prefix) {
            cleartext = try TaskExporter.decrypt(text, password: password)
        } else if TaskExporter.looksLikeLegacyEncryptedEnvelope(text) {
            cleartext = try TaskExporter.decrypt(
                text.trimmingCharacters(in: .whitespacesAndNewlines),
                password: password
            )
        } else {
            let tasks = try validateBatch(validateAndParse(text, as: format))
            return TaskImportPreview(
                tasks: tasks,
                diagnostics: lossinessWarnings(for: format)
            )
        }

        let tasks = try validateBatch(validateAndParse(cleartext, as: format))
        return TaskImportPreview(
            tasks: tasks,
            diagnostics: lossinessWarnings(for: format)
        )
    }

    private static func lossinessWarnings(
        for format: TaskExportFormat
    ) -> [TaskImportDiagnostic] {
        let detachedGraphWarning = TaskImportDiagnostic(
            severity: .warning,
            row: 1,
            field: "format",
            message: "Task-list sharing omits profile assignments, agenda links, and recurrence lineage; use a full backup to preserve the product graph."
        )
        switch format {
        case .markdown:
            return [
                detachedGraphWarning,
                TaskImportDiagnostic(
                    severity: .warning,
                    row: 1,
                    field: "format",
                    message: "Markdown carries task checklist fields only; unavailable fields use documented defaults."
                )
            ]
        case .plainText:
            return [
                detachedGraphWarning,
                TaskImportDiagnostic(
                    severity: .warning,
                    row: 1,
                    field: "format",
                    message: "Plain text carries titles only; all structured fields use documented defaults."
                )
            ]
        case .yaml, .csv:
            return [
                detachedGraphWarning,
                TaskImportDiagnostic(
                    severity: .warning,
                    row: 1,
                    field: "steps",
                    message: "\(format.displayName) task lists do not carry task steps; use JSON sharing or a full backup to preserve steps."
                )
            ]
        case .json:
            return [detachedGraphWarning]
        }
    }

    private static func validateAndParse(
        _ text: String,
        as format: TaskExportFormat
    ) throws -> [AgendaTask] {
        switch format {
        case .json:
            guard let data = text.data(using: .utf8) else {
                throw TaskPortabilityError.invalidFormat("JSON isn't UTF-8")
            }
            try rejectDuplicateJSONKeys(data)
            try validateJSONSchema(data)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let payload: TaskExportPayload
            do {
                payload = try decoder.decode(TaskExportPayload.self, from: data)
            } catch {
                throw TaskPortabilityError.invalidFormat("JSON envelope couldn't be decoded")
            }
            guard (1...2).contains(payload.version) else {
                throw TaskPortabilityError.unsupportedVersion(payload.version)
            }
            guard payload.version < 2 || payload.kind != nil else {
                throw TaskPortabilityError.invalidFormat(
                    "JSON kind is required for version 2"
                )
            }
            guard payload.kind == nil || payload.kind == .activeTaskList else {
                throw TaskPortabilityError.wrongPayloadKind
            }
            var diagnostics: [TaskImportDiagnostic] = []
            for (index, task) in payload.tasks.enumerated() {
                diagnostics.append(contentsOf: validate(task, row: index + 1))
            }
            try rejectErrors(diagnostics)
            return payload.tasks.map { $0.toAgendaTask() }

        case .yaml:
            let lines = text.components(separatedBy: .newlines)
            let yamlEnvelope = try validateYAMLEnvelope(lines)
            let version = yamlEnvelope.version
            guard (1...2).contains(version) else {
                throw TaskPortabilityError.unsupportedVersion(version)
            }
            if let kind = yamlEnvelope.kind {
                guard kind == TaskExportKind.activeTaskList.rawValue else {
                    throw TaskPortabilityError.wrongPayloadKind
                }
            } else if version >= 2 {
                throw TaskPortabilityError.invalidFormat(
                    "YAML kind is required for version 2"
                )
            }
            let records = try strictYAMLRecords(text)
            return try buildValidatedTasks(records)

        case .csv:
            let parsed = parseCSVRows(text)
            if let syntaxError = parsed.syntaxError {
                throw TaskPortabilityError.invalidFormat(syntaxError)
            }
            let rows = parsed.rows.filter {
                !($0.count == 1 && $0[0].isEmpty)
            }
            guard let headers = rows.first else {
                throw TaskPortabilityError.invalidFormat("CSV header is missing")
            }
            let normalizedHeaders = headers.enumerated().map { index, header in
                index == 0 ? header.replacingOccurrences(of: "\u{FEFF}", with: "") : header
            }
            guard Set(normalizedHeaders).count == normalizedHeaders.count else {
                throw TaskPortabilityError.invalidFormat("CSV has duplicate columns")
            }
            let unknownHeaders = Set(normalizedHeaders)
                .subtracting(structuredTaskFields.union(["auGendaCSVVersion"]))
                .sorted()
            guard unknownHeaders.isEmpty else {
                throw TaskPortabilityError.invalidFormat(
                    "CSV has unsupported column\(unknownHeaders.count == 1 ? "" : "s"): "
                        + unknownHeaders.joined(separator: ", ")
                )
            }
            let required = Set(["title", "frictionLevel", "energyRequired", "estimatedMinutes"])
            guard required.isSubset(of: Set(normalizedHeaders)) else {
                throw TaskPortabilityError.invalidFormat("CSV is missing required task columns")
            }
            guard rows.dropFirst().allSatisfy({ $0.count == normalizedHeaders.count }) else {
                throw TaskPortabilityError.invalidFormat("CSV row width doesn't match its header")
            }
            var records: [(row: Int, fields: [String: String])] = []
            for (offset, values) in rows.dropFirst().enumerated() {
                var fields: [String: String] = [:]
                let formatVersion: String? = normalizedHeaders
                    .firstIndex(of: "auGendaCSVVersion")
                    .map { values[$0] }
                if let formatVersion, formatVersion != "2" {
                    throw TaskPortabilityError.invalidFormat(
                        "CSV escaping version \(formatVersion) isn't supported"
                    )
                }
                for (index, header) in normalizedHeaders.enumerated() {
                    guard header != "auGendaCSVVersion" else { continue }
                    fields[header] = formatVersion == "2"
                        ? restoreCSVLiteral(values[index])
                        : values[index]
                }
                records.append((row: offset + 2, fields: fields))
            }
            return try buildValidatedTasks(records)

        case .markdown:
            guard text.components(separatedBy: .newlines).contains(where: {
                $0.trimmingCharacters(in: .whitespaces).hasPrefix("- [")
            }) else {
                throw TaskPortabilityError.invalidFormat("Markdown contains no task checklist")
            }
            return try parseMarkdownStrict(text)

        case .plainText:
            let tasks = parsePlainText(text)
            guard !tasks.isEmpty else {
                throw TaskPortabilityError.invalidFormat("plain text contains no task titles")
            }
            let diagnostics = tasks.enumerated().compactMap { index, task in
                task.title.count > 10_000
                    ? TaskImportDiagnostic(
                        severity: .error,
                        row: index + 1,
                        field: "title",
                        message: "must not exceed 10,000 characters"
                    )
                    : nil
            }
            try rejectErrors(diagnostics)
            return tasks
        }
    }

    private static func rejectDuplicateJSONKeys(_ data: Data) throws {
        var scanner = StrictJSONDuplicateScanner(data: data)
        try scanner.scan()
    }

    private static func validateJSONSchema(_ data: Data) throws {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw TaskPortabilityError.invalidFormat(
                "JSON envelope couldn't be decoded"
            )
        }
        guard let envelope = object as? [String: Any] else {
            throw TaskPortabilityError.invalidFormat(
                "JSON envelope must be an object"
            )
        }
        let unknownEnvelopeKeys = Set(envelope.keys)
            .subtracting(jsonEnvelopeFields)
            .sorted()
        guard unknownEnvelopeKeys.isEmpty else {
            throw TaskPortabilityError.invalidFormat(
                "JSON envelope has unsupported key\(unknownEnvelopeKeys.count == 1 ? "" : "s"): "
                    + unknownEnvelopeKeys.joined(separator: ", ")
            )
        }
        guard let taskValues = envelope["tasks"] as? [Any] else {
            throw TaskPortabilityError.invalidFormat(
                "JSON tasks must be an array"
            )
        }

        var diagnostics: [TaskImportDiagnostic] = []
        for (taskIndex, value) in taskValues.enumerated() {
            guard let task = value as? [String: Any] else {
                diagnostics.append(
                    .init(
                        severity: .error,
                        row: taskIndex + 1,
                        field: "task",
                        message: "must be an object"
                    )
                )
                continue
            }
            let unknownTaskKeys = Set(task.keys).subtracting(
                structuredTaskFields.union(["steps"])
            )
            for key in unknownTaskKeys.sorted() {
                diagnostics.append(
                    .init(
                        severity: .error,
                        row: taskIndex + 1,
                        field: key,
                        message: "field is not supported"
                    )
                )
            }
            guard let rawSteps = task["steps"], !(rawSteps is NSNull) else {
                continue
            }
            guard let steps = rawSteps as? [Any] else {
                diagnostics.append(
                    .init(
                        severity: .error,
                        row: taskIndex + 1,
                        field: "steps",
                        message: "must be an array"
                    )
                )
                continue
            }
            for (stepIndex, rawStep) in steps.enumerated() {
                guard let step = rawStep as? [String: Any] else {
                    diagnostics.append(
                        .init(
                            severity: .error,
                            row: taskIndex + 1,
                            field: "steps[\(stepIndex)]",
                            message: "must be an object"
                        )
                    )
                    continue
                }
                for key in Set(step.keys).subtracting(jsonStepFields).sorted() {
                    diagnostics.append(
                        .init(
                            severity: .error,
                            row: taskIndex + 1,
                            field: "steps[\(stepIndex)].\(key)",
                            message: "field is not supported"
                        )
                    )
                }
            }
        }
        try rejectErrors(diagnostics)
    }

    private struct ValidatedYAMLEnvelope {
        let version: Int
        let kind: String?
    }

    private static func validateYAMLEnvelope(
        _ lines: [String]
    ) throws -> ValidatedYAMLEnvelope {
        let allowedKeys: Set<String> = [
            "version", "kind", "exportedAt", "tasks"
        ]
        var values: [String: String] = [:]
        var foundTasks = false

        for (offset, originalLine) in lines.enumerated() {
            var rawLine = originalLine
            if offset == 0 {
                rawLine = rawLine.replacingOccurrences(
                    of: "\u{FEFF}",
                    with: ""
                )
            }
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
            if foundTasks { break }
            guard rawLine == trimmed else {
                throw TaskPortabilityError.invalidFormat(
                    "YAML envelope field on row \(offset + 1) must not be indented"
                )
            }
            guard let colon = trimmed.firstIndex(of: ":") else {
                throw TaskPortabilityError.invalidFormat(
                    "YAML envelope row \(offset + 1) must be key: value"
                )
            }
            let key = String(trimmed[..<colon])
            let value = String(trimmed[trimmed.index(after: colon)...])
                .trimmingCharacters(in: .whitespaces)
            guard allowedKeys.contains(key) else {
                throw TaskPortabilityError.invalidFormat(
                    "YAML envelope field \(key) is not supported"
                )
            }
            guard values[key] == nil else {
                throw TaskPortabilityError.invalidFormat(
                    "YAML envelope field \(key) is repeated"
                )
            }
            values[key] = value
            if key == "tasks" {
                guard value.isEmpty else {
                    throw TaskPortabilityError.invalidFormat(
                        "YAML tasks must start on following rows"
                    )
                }
                foundTasks = true
            }
        }

        guard foundTasks else {
            throw TaskPortabilityError.invalidFormat(
                "YAML tasks section is missing"
            )
        }
        guard let rawVersion = values["version"],
              let version = Int(rawVersion) else {
            throw TaskPortabilityError.invalidFormat(
                "YAML version is missing or invalid"
            )
        }
        if let exportedAt = values["exportedAt"],
           ISO8601DateFormatter().date(from: exportedAt) == nil {
            throw TaskPortabilityError.invalidFormat(
                "YAML exportedAt must be an ISO-8601 date"
            )
        }
        return ValidatedYAMLEnvelope(
            version: version,
            kind: values["kind"]
        )
    }

    private struct StrictJSONDuplicateScanner {
        private let bytes: [UInt8]
        private var index = 0

        init(data: Data) {
            bytes = Array(data)
        }

        mutating func scan() throws {
            skipWhitespace()
            try parseValue()
            skipWhitespace()
            guard index == bytes.count else {
                throw syntaxError
            }
        }

        private var syntaxError: TaskPortabilityError {
            .invalidFormat("JSON syntax is invalid")
        }

        private mutating func parseValue() throws {
            skipWhitespace()
            guard index < bytes.count else { throw syntaxError }
            switch bytes[index] {
            case 0x7B:
                try parseObject()
            case 0x5B:
                try parseArray()
            case 0x22:
                _ = try parseString()
            default:
                try parsePrimitive()
            }
        }

        private mutating func parseObject() throws {
            index += 1
            skipWhitespace()
            if consume(0x7D) { return }
            var keys: Set<String> = []
            while true {
                skipWhitespace()
                guard index < bytes.count, bytes[index] == 0x22 else {
                    throw syntaxError
                }
                let key = try parseString()
                guard keys.insert(key).inserted else {
                    throw TaskPortabilityError.invalidFormat(
                        "JSON object repeats key \(key)"
                    )
                }
                skipWhitespace()
                guard consume(0x3A) else { throw syntaxError }
                try parseValue()
                skipWhitespace()
                if consume(0x7D) { return }
                guard consume(0x2C) else { throw syntaxError }
            }
        }

        private mutating func parseArray() throws {
            index += 1
            skipWhitespace()
            if consume(0x5D) { return }
            while true {
                try parseValue()
                skipWhitespace()
                if consume(0x5D) { return }
                guard consume(0x2C) else { throw syntaxError }
            }
        }

        private mutating func parseString() throws -> String {
            let start = index
            index += 1
            var escaping = false
            while index < bytes.count {
                let byte = bytes[index]
                index += 1
                if escaping {
                    escaping = false
                    continue
                }
                if byte == 0x5C {
                    escaping = true
                } else if byte == 0x22 {
                    let encoded = Data(bytes[start..<index])
                    do {
                        return try JSONDecoder().decode(
                            String.self,
                            from: encoded
                        )
                    } catch {
                        throw syntaxError
                    }
                }
            }
            throw syntaxError
        }

        private mutating func parsePrimitive() throws {
            let start = index
            while index < bytes.count {
                let byte = bytes[index]
                if byte == 0x2C || byte == 0x5D || byte == 0x7D
                    || isWhitespace(byte) {
                    break
                }
                index += 1
            }
            guard index > start else { throw syntaxError }
        }

        private mutating func skipWhitespace() {
            while index < bytes.count, isWhitespace(bytes[index]) {
                index += 1
            }
        }

        private func isWhitespace(_ byte: UInt8) -> Bool {
            byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D
        }

        private mutating func consume(_ byte: UInt8) -> Bool {
            guard index < bytes.count, bytes[index] == byte else {
                return false
            }
            index += 1
            return true
        }
    }

    private static func strictYAMLRecords(
        _ text: String
    ) throws -> [(row: Int, fields: [String: String])] {
        var records: [(row: Int, fields: [String: String])] = []
        var currentFields: [String: String]?
        var currentRow = 0
        var inTasks = false
        var diagnostics: [TaskImportDiagnostic] = []

        func finishCurrent() {
            if let currentFields {
                records.append((row: currentRow, fields: currentFields))
            }
        }

        for (offset, rawLine) in text.components(separatedBy: .newlines).enumerated() {
            let row = offset + 1
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            if !inTasks {
                if trimmed == "tasks:" { inTasks = true }
                continue
            }

            if trimmed.hasPrefix("- ") {
                finishCurrent()
                currentFields = [:]
                currentRow = row
                let entry = String(trimmed.dropFirst(2))
                guard let colon = entry.firstIndex(of: ":") else {
                    diagnostics.append(
                        .init(
                            severity: .error,
                            row: row,
                            field: "row",
                            message: "YAML task entries must start with “- title:”"
                        )
                    )
                    continue
                }
                let key = String(entry[..<colon]).trimmingCharacters(in: .whitespaces)
                let value = String(entry[entry.index(after: colon)...])
                    .trimmingCharacters(in: .whitespaces)
                guard key == "title" else {
                    diagnostics.append(
                        .init(
                            severity: .error,
                            row: row,
                            field: key,
                            message: "YAML task entries must start with the title field"
                        )
                    )
                    continue
                }
                currentFields?[key] = decodeYAMLScalar(
                    value,
                    row: row,
                    field: key,
                    diagnostics: &diagnostics
                )
                continue
            }

            guard currentFields != nil else {
                diagnostics.append(
                    .init(
                        severity: .error,
                        row: row,
                        field: "row",
                        message: "unexpected content in the tasks section"
                    )
                )
                continue
            }
            guard let colon = trimmed.firstIndex(of: ":") else {
                diagnostics.append(
                    .init(
                        severity: .error,
                        row: row,
                        field: "row",
                        message: "expected a key: value pair"
                    )
                )
                continue
            }
            let key = String(trimmed[..<colon]).trimmingCharacters(in: .whitespaces)
            let value = String(trimmed[trimmed.index(after: colon)...])
                .trimmingCharacters(in: .whitespaces)
            if currentFields?[key] != nil {
                diagnostics.append(
                    .init(
                        severity: .error,
                        row: row,
                        field: key,
                        message: "field is repeated"
                    )
                )
            } else {
                currentFields?[key] = decodeYAMLScalar(
                    value,
                    row: row,
                    field: key,
                    diagnostics: &diagnostics
                )
            }
        }
        finishCurrent()
        try rejectErrors(diagnostics)
        return records
    }

    private static func buildValidatedTasks(
        _ records: [(row: Int, fields: [String: String])]
    ) throws -> [AgendaTask] {
        var diagnostics: [TaskImportDiagnostic] = []
        for record in records {
            diagnostics.append(
                contentsOf: validateTaskFields(record.fields, row: record.row)
            )
        }
        try rejectErrors(diagnostics)

        return records.map { record in
            buildValidatedTask(
                from: record.fields,
                identitySeed: "structured:\(record.row):\(canonicalSeed(record.fields))"
            )
        }
    }

    private static func validateTaskFields(
        _ fields: [String: String],
        row: Int
    ) -> [TaskImportDiagnostic] {
        var diagnostics: [TaskImportDiagnostic] = []

        func error(_ field: String, _ message: String) {
            diagnostics.append(
                .init(severity: .error, row: row, field: field, message: message)
            )
        }

        for field in Set(fields.keys).subtracting(structuredTaskFields).sorted() {
            error(field, "field is not supported")
        }

        guard let title = fields["title"], !title.isEmpty else {
            error("title", "a non-empty title is required")
            return diagnostics
        }
        if title.count > 10_000 {
            error("title", "must not exceed 10,000 characters")
        }
        if let notes = fields["notes"], notes.count > 1_000_000 {
            error("notes", "must not exceed 1,000,000 characters")
        }

        validateInteger(
            fields["frictionLevel"],
            field: "frictionLevel",
            row: row,
            required: true,
            range: TaskFieldDomain.friction,
            diagnostics: &diagnostics
        )
        validateInteger(
            fields["energyRequired"],
            field: "energyRequired",
            row: row,
            required: true,
            range: TaskFieldDomain.energy,
            diagnostics: &diagnostics
        )
        validateInteger(
            fields["estimatedMinutes"],
            field: "estimatedMinutes",
            row: row,
            required: true,
            range: 1...525_600,
            diagnostics: &diagnostics
        )
        validateInteger(
            fields["interestLevel"],
            field: "interestLevel",
            row: row,
            required: false,
            range: TaskFieldDomain.interest,
            diagnostics: &diagnostics
        )
        validateInteger(
            fields["priority"],
            field: "priority",
            row: row,
            required: false,
            range: TaskFieldDomain.priority,
            diagnostics: &diagnostics
        )
        for field in ["sensoryLoad", "socialLoad", "initiationCost"] {
            validateInteger(
                fields[field],
                field: field,
                row: row,
                required: false,
                range: TaskFieldDomain.load,
                diagnostics: &diagnostics
            )
        }
        validateInteger(
            fields["sortOrder"],
            field: "sortOrder",
            row: row,
            required: false,
            range: -1_000_000...1_000_000,
            diagnostics: &diagnostics
        )

        for field in [
            "hyperfocusRisk", "needsBodyDouble", "isComplete",
            "isAbandoned", "specialInterest", "excludeFromAI"
        ] {
            validateBoolean(
                fields[field],
                field: field,
                row: row,
                diagnostics: &diagnostics
            )
        }
        for field in [
            "createdAt", "updatedAt", "dueDate", "scheduledDate",
            "completedAt", "isDeferredUntil", "abandonedAt"
        ] {
            validateDate(
                fields[field],
                field: field,
                row: row,
                diagnostics: &diagnostics
            )
        }
        for field in [
            "clientID", "recurrenceParentID", "assignedToProfileID",
            "assignedByProfileID", "agendaItemID"
        ] {
            validateUUID(
                fields[field],
                field: field,
                row: row,
                diagnostics: &diagnostics
            )
        }
        for field in [
            "recurrenceParentID", "assignedToProfileID",
            "assignedByProfileID", "agendaItemID"
        ] where !(fields[field] ?? "").isEmpty {
            error(
                field,
                "external relationship IDs are not valid in a detached task list; use a full backup"
            )
        }
        return diagnostics
    }

    private static func validateInteger(
        _ value: String?,
        field: String,
        row: Int,
        required: Bool,
        range: ClosedRange<Int>,
        diagnostics: inout [TaskImportDiagnostic]
    ) {
        guard let value else {
            if required {
                diagnostics.append(
                    .init(
                        severity: .error,
                        row: row,
                        field: field,
                        message: "field is required"
                    )
                )
            }
            return
        }
        guard !value.isEmpty, let parsed = Int(value) else {
            diagnostics.append(
                .init(
                    severity: .error,
                    row: row,
                    field: field,
                    message: "expected a whole number"
                )
            )
            return
        }
        guard range.contains(parsed) else {
            diagnostics.append(
                .init(
                    severity: .error,
                    row: row,
                    field: field,
                    message: "must be in \(range.lowerBound)...\(range.upperBound)"
                )
            )
            return
        }
    }

    private static func validateBoolean(
        _ value: String?,
        field: String,
        row: Int,
        diagnostics: inout [TaskImportDiagnostic]
    ) {
        guard let value else { return }
        let normalized = value.lowercased()
        guard normalized == "true" || normalized == "false" else {
            diagnostics.append(
                .init(
                    severity: .error,
                    row: row,
                    field: field,
                    message: "expected true or false"
                )
            )
            return
        }
    }

    private static func validateDate(
        _ value: String?,
        field: String,
        row: Int,
        diagnostics: inout [TaskImportDiagnostic]
    ) {
        guard let value, !value.isEmpty else { return }
        guard ISO8601DateFormatter().date(from: value) != nil else {
            diagnostics.append(
                .init(
                    severity: .error,
                    row: row,
                    field: field,
                    message: "expected an ISO-8601 date"
                )
            )
            return
        }
    }

    private static func validateUUID(
        _ value: String?,
        field: String,
        row: Int,
        diagnostics: inout [TaskImportDiagnostic]
    ) {
        guard let value, !value.isEmpty else { return }
        guard UUID(uuidString: value) != nil else {
            diagnostics.append(
                .init(
                    severity: .error,
                    row: row,
                    field: field,
                    message: "expected a UUID"
                )
            )
            return
        }
    }

    private static func validate(
        _ task: ExportedTask,
        row: Int
    ) -> [TaskImportDiagnostic] {
        var fields: [String: String] = [
            "title": task.title,
            "notes": task.notes,
            "frictionLevel": String(task.frictionLevel),
            "energyRequired": String(task.energyRequired),
            "estimatedMinutes": String(task.estimatedMinutes),
            "interestLevel": String(task.interestLevel),
            "priority": String(task.priority),
            "hyperfocusRisk": String(task.hyperfocusRisk),
            "needsBodyDouble": String(task.needsBodyDouble),
            "isComplete": String(task.isComplete)
        ]
        if let sensoryLoad = task.sensoryLoad {
            fields["sensoryLoad"] = String(sensoryLoad)
        }
        if let socialLoad = task.socialLoad {
            fields["socialLoad"] = String(socialLoad)
        }
        if let initiationCost = task.initiationCost {
            fields["initiationCost"] = String(initiationCost)
        }
        if let sortOrder = task.sortOrder {
            fields["sortOrder"] = String(sortOrder)
        }

        var diagnostics = validateTaskFields(fields, row: row)
        if let steps = task.steps {
            let stepIDs = steps.map(\.clientID)
            if Set(stepIDs).count != stepIDs.count {
                diagnostics.append(
                    .init(
                        severity: .error,
                        row: row,
                        field: "steps.clientID",
                        message: "step identities must be unique within a task"
                    )
                )
            }
            for (index, step) in steps.enumerated() {
                if step.title.isEmpty {
                    diagnostics.append(
                        .init(
                            severity: .error,
                            row: row,
                            field: "steps[\(index)].title",
                            message: "a non-empty title is required"
                        )
                    )
                }
                if step.title.count > 10_000 {
                    diagnostics.append(
                        .init(
                            severity: .error,
                            row: row,
                            field: "steps[\(index)].title",
                            message: "must not exceed 10,000 characters"
                        )
                    )
                }
                if !(1...525_600).contains(step.estimatedMinutes) {
                    diagnostics.append(
                        .init(
                            severity: .error,
                            row: row,
                            field: "steps[\(index)].estimatedMinutes",
                            message: "must be in 1...525600"
                        )
                    )
                }
                if !(-1_000_000...1_000_000).contains(step.sortOrder) {
                    diagnostics.append(
                        .init(
                            severity: .error,
                            row: row,
                            field: "steps[\(index)].sortOrder",
                            message: "must be in -1000000...1000000"
                        )
                    )
                }
            }
        }
        for (field, identifier) in [
            ("recurrenceParentID", task.recurrenceParentID),
            ("assignedToProfileID", task.assignedToProfileID),
            ("assignedByProfileID", task.assignedByProfileID),
            ("agendaItemID", task.agendaItemID)
        ] where identifier != nil {
            diagnostics.append(
                .init(
                    severity: .error,
                    row: row,
                    field: field,
                    message: "external relationship IDs are not valid in a detached task list; use a full backup"
                )
            )
        }
        return diagnostics
    }

    private static func rejectErrors(
        _ diagnostics: [TaskImportDiagnostic]
    ) throws {
        let errors = diagnostics.filter { $0.severity == .error }
        if !errors.isEmpty {
            throw TaskPortabilityError.validationFailed(errors)
        }
    }

    private static func validateBatch(_ tasks: [AgendaTask]) throws -> [AgendaTask] {
        guard tasks.count <= maximumTaskCount else {
            throw TaskPortabilityError.tooManyTasks
        }
        let identities = tasks.map(\.clientID)
        guard Set(identities).count == identities.count else {
            throw TaskPortabilityError.duplicateIdentity
        }
        let stepIdentities = tasks.flatMap { ($0.steps ?? []).map(\.clientID) }
        guard Set(stepIdentities).count == stepIdentities.count else {
            throw TaskPortabilityError.validationFailed([
                .init(
                    severity: .error,
                    row: 1,
                    field: "steps.clientID",
                    message: "step identities must be unique across the import"
                )
            ])
        }
        return tasks
    }

    private static func decodeYAMLScalar(
        _ value: String,
        row: Int,
        field: String,
        diagnostics: inout [TaskImportDiagnostic]
    ) -> String {
        let startsQuoted = value.hasPrefix("\"")
        let endsQuoted = value.hasSuffix("\"")
        guard startsQuoted == endsQuoted else {
            diagnostics.append(
                .init(
                    severity: .error,
                    row: row,
                    field: field,
                    message: "quoted value is not closed"
                )
            )
            return value
        }
        guard startsQuoted, value.count >= 2 else { return value }

        // Decode in one pass so a literal "\\n" remains backslash+n.
        var result = ""
        var escaping = false
        for character in value.dropFirst().dropLast() {
            if escaping {
                switch character {
                case "n": result.append("\n")
                case "r": result.append("\r")
                case "\"": result.append("\"")
                case "\\": result.append("\\")
                default:
                    diagnostics.append(
                        .init(
                            severity: .error,
                            row: row,
                            field: field,
                            message: "contains unsupported escape \\\(character)"
                        )
                    )
                }
                escaping = false
            } else if character == "\\" {
                escaping = true
            } else {
                result.append(character)
            }
        }
        if escaping {
            diagnostics.append(
                .init(
                    severity: .error,
                    row: row,
                    field: field,
                    message: "ends with an incomplete escape"
                )
            )
        }
        return result
    }

    // MARK: CSV

    private static func parseCSVRows(
        _ text: String
    ) -> (rows: [[String]], syntaxError: String?) {
        var rows: [[String]] = []
        var row: [String] = []
        var current = ""
        var inQuotes = false
        var justClosedQuote = false
        var i = text.startIndex
        while i < text.endIndex {
            let ch = text[i]
            if inQuotes, ch == "\"" {
                let next = text.index(after: i)
                if next < text.endIndex, text[next] == "\"" {
                    current.append("\"")
                    i = next
                } else {
                    inQuotes = false
                    justClosedQuote = true
                }
            } else if inQuotes {
                current.append(ch)
            } else if justClosedQuote {
                if ch == "," {
                    row.append(current)
                    current = ""
                    justClosedQuote = false
                } else if ch == "\n" || ch == "\r" {
                    row.append(current)
                    rows.append(row)
                    row = []
                    current = ""
                    justClosedQuote = false
                    if ch == "\r" {
                        let next = text.index(after: i)
                        if next < text.endIndex, text[next] == "\n" {
                            i = next
                        }
                    }
                } else {
                    return (
                        rows,
                        "CSV has content after a closing quote before the field delimiter"
                    )
                }
            } else if ch == "\"" {
                guard current.isEmpty else {
                    return (rows, "CSV has a quote inside an unquoted field")
                }
                inQuotes = true
            } else if ch == "," && !inQuotes {
                row.append(current)
                current = ""
            } else if (ch == "\n" || ch == "\r") && !inQuotes {
                row.append(current)
                rows.append(row)
                row = []
                current = ""
                if ch == "\r" {
                    let next = text.index(after: i)
                    if next < text.endIndex, text[next] == "\n" {
                        i = next
                    }
                }
            } else {
                current.append(ch)
            }
            i = text.index(after: i)
        }
        guard !inQuotes else {
            return (rows, "CSV has an unclosed quoted field")
        }
        if !current.isEmpty || !row.isEmpty {
            row.append(current)
            rows.append(row)
        }
        return (rows, nil)
    }

    private static func restoreCSVLiteral(_ value: String) -> String {
        guard value.hasPrefix("'") else { return value }
        let candidate = String(value.dropFirst())
        let apostropheCount = candidate.prefix { $0 == "'" }.count
        if apostropheCount > 0 {
            let remainder = String(candidate.dropFirst(apostropheCount))
            if TaskExporter.isCSVFormulaCandidate(remainder) {
                return candidate
            }
        }
        return TaskExporter.isCSVFormulaCandidate(candidate)
            ? candidate
            : value
    }

    // MARK: Markdown

    private static func parseMarkdown(_ text: String) -> [AgendaTask] {
        (try? parseMarkdownStrict(text)) ?? []
    }

    private static func parseMarkdownStrict(_ text: String) throws -> [AgendaTask] {
        var records: [(row: Int, fields: [String: String])] = []
        var diagnostics: [TaskImportDiagnostic] = []

        for (offset, rawLine) in text.components(separatedBy: .newlines).enumerated() {
            let row = offset + 1
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("- [") else { continue }

            let lower = line.lowercased()
            guard line.hasPrefix("- [ ]") || lower.hasPrefix("- [x]") else {
                diagnostics.append(
                    .init(
                        severity: .error,
                        row: row,
                        field: "completion",
                        message: "checklist marker must be [ ] or [x]"
                    )
                )
                continue
            }
            guard let closeBracket = line.firstIndex(of: "]") else {
                diagnostics.append(
                    .init(
                        severity: .error,
                        row: row,
                        field: "row",
                        message: "checklist marker is not closed"
                    )
                )
                continue
            }

            let after = String(line[line.index(after: closeBracket)...])
                .trimmingCharacters(in: .whitespaces)
            var title = after
            var fields: [String: String] = [
                "frictionLevel": "3",
                "energyRequired": "2",
                "estimatedMinutes": "15",
                "isComplete": String(lower.hasPrefix("- [x]"))
            ]

            if let dashRange = after.range(of: " — *", options: .backwards)
                ?? after.range(of: " - *", options: .backwards) {
                title = String(after[..<dashRange.lowerBound])
                let metadataWithTerminator = String(after[dashRange.upperBound...])
                guard metadataWithTerminator.hasSuffix("*") else {
                    diagnostics.append(
                        .init(
                            severity: .error,
                            row: row,
                            field: "metadata",
                            message: "metadata emphasis marker is not closed"
                        )
                    )
                    fields["title"] = title
                    records.append((row: row, fields: fields))
                    continue
                }
                let metadata = String(metadataWithTerminator.dropLast())
                    .trimmingCharacters(in: .whitespaces)
                var seenMetadataFields: Set<String> = []
                for piece in metadata.components(separatedBy: " · ") {
                    let bit = piece.trimmingCharacters(in: .whitespaces)
                    let metadataField: String
                    if bit.hasPrefix("friction:") {
                        metadataField = "frictionLevel"
                        fields["frictionLevel"] = String(bit.dropFirst("friction:".count))
                    } else if bit.hasPrefix("energy:") {
                        metadataField = "energyRequired"
                        fields["energyRequired"] = String(bit.dropFirst("energy:".count))
                    } else if bit.hasSuffix("m") {
                        metadataField = "estimatedMinutes"
                        fields["estimatedMinutes"] = String(bit.dropLast())
                    } else if bit.hasPrefix("@") {
                        metadataField = "contextTag"
                        fields["contextTag"] = String(bit.dropFirst())
                    } else if bit.hasPrefix("priority:") {
                        metadataField = "priority"
                        fields["priority"] = String(bit.dropFirst("priority:".count))
                    } else if bit == "hyperfocus" {
                        metadataField = "hyperfocusRisk"
                        fields["hyperfocusRisk"] = "true"
                    } else if bit == "body-double" {
                        metadataField = "needsBodyDouble"
                        fields["needsBodyDouble"] = "true"
                    } else if bit.hasPrefix("interest:") {
                        metadataField = "interestLevel"
                        fields["interestLevel"] = String(bit.dropFirst("interest:".count))
                    } else if bit.hasPrefix("id:") {
                        metadataField = "clientID"
                        fields["clientID"] = String(bit.dropFirst("id:".count))
                    } else {
                        diagnostics.append(
                            .init(
                                severity: .error,
                                row: row,
                                field: "metadata",
                                message: "unsupported metadata component “\(bit)”"
                            )
                        )
                        continue
                    }
                    guard seenMetadataFields.insert(metadataField).inserted else {
                        diagnostics.append(
                            .init(
                                severity: .error,
                                row: row,
                                field: metadataField,
                                message: "metadata field is repeated"
                            )
                        )
                        continue
                    }
                }
            }
            fields["title"] = title
            records.append((row: row, fields: fields))
        }

        try rejectErrors(diagnostics)
        return try buildValidatedTasks(records)
    }

    // MARK: Plain text

    private static func parsePlainText(_ text: String) -> [AgendaTask] {
        text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .enumerated()
            .map { index, line in
                let task = AgendaTask(
                    title: line,
                    frictionLevel: 3,
                    energyRequired: 2,
                    estimatedMinutes: 15,
                    contextTag: "",
                    priority: 0,
                    interestLevel: 3
                )
                task.clientID = TaskImportIdentity.uuid(seed: "plain:\(index):\(line)")
                return task
            }
    }

    // MARK: Shared dict → AgendaTask

    private static func buildValidatedTask(
        from dict: [String: String],
        identitySeed: String
    ) -> AgendaTask {
        let title = dict["title"] ?? ""
        let task = AgendaTask(
            title: title,
            frictionLevel: Int(dict["frictionLevel"] ?? "") ?? 3,
            energyRequired: Int(dict["energyRequired"] ?? "") ?? 2,
            estimatedMinutes: Int(dict["estimatedMinutes"] ?? "") ?? 15,
            contextTag: dict["contextTag"] ?? "",
            priority: Int(dict["priority"] ?? "") ?? 0,
            interestLevel: Int(dict["interestLevel"] ?? "") ?? 3
        )
        task.clientID = dict["clientID"].flatMap(UUID.init(uuidString:))
            ?? TaskImportIdentity.uuid(seed: identitySeed)
        task.createdAt = parseDate(dict["createdAt"]) ?? .now
        task.updatedAt = parseDate(dict["updatedAt"]) ?? task.createdAt
        task.notes = dict["notes"] ?? ""
        task.hyperfocusRisk = parseValidatedBool(dict["hyperfocusRisk"]) ?? false
        task.needsBodyDouble = parseValidatedBool(dict["needsBodyDouble"]) ?? false
        task.waitingOn = dict["waitingOn"] ?? ""
        task.isComplete = parseValidatedBool(dict["isComplete"]) ?? false
        task.completedAt = parseDate(dict["completedAt"])
        task.isDeferredUntil = parseDate(dict["isDeferredUntil"])
        task.isAbandoned = parseValidatedBool(dict["isAbandoned"]) ?? false
        task.abandonedAt = parseDate(dict["abandonedAt"])
        task.abandonReason = dict["abandonReason"] ?? ""
        task.sensoryLoad = Int(dict["sensoryLoad"] ?? "") ?? 0
        task.socialLoad = Int(dict["socialLoad"] ?? "") ?? 0
        task.initiationCost = Int(dict["initiationCost"] ?? "") ?? 0
        task.specialInterest = parseValidatedBool(dict["specialInterest"]) ?? false
        task.excludeFromAI = parseValidatedBool(dict["excludeFromAI"]) ?? false
        task.sortOrder = Int(dict["sortOrder"] ?? "") ?? 0
        task.recurrenceRule = dict["recurrenceRule"] ?? "none"
        task.recurrenceParentID = dict["recurrenceParentID"].flatMap(UUID.init(uuidString:))
        task.assignedToProfileID = dict["assignedToProfileID"].flatMap(UUID.init(uuidString:))
        task.assignedByProfileID = dict["assignedByProfileID"].flatMap(UUID.init(uuidString:))
        task.agendaItemID = dict["agendaItemID"].flatMap(UUID.init(uuidString:))
        task.dueDate = parseDate(dict["dueDate"])
        task.scheduledDate = parseDate(dict["scheduledDate"])
        return task
    }

    private static func parseValidatedBool(_ value: String?) -> Bool? {
        guard let value else { return nil }
        switch value.lowercased() {
        case "true": return true
        case "false": return false
        default: return nil
        }
    }

    private static func parseDate(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        return ISO8601DateFormatter().date(from: value)
    }

    private static func canonicalSeed(_ dict: [String: String]) -> String {
        dict.keys.sorted().map { "\($0)=\(dict[$0] ?? "")" }.joined(separator: "\u{1E}")
    }
}

// MARK: - Whole-product backup

enum AuGendaBackupError: LocalizedError {
    case passwordRequired
    case encodingFailed
    case decryptionFailed
    case unsupportedVersion(Int)
    case unsupportedDataModelVersion(String)
    case wrongPayloadKind
    case integrityMismatch
    case incompleteManifest(String)
    case duplicateIdentity(String)
    case invalidRelationship(String)
    case backupTooLarge
    case historyRestoreFailed
    case historyRollbackFailed

    var errorDescription: String? {
        switch self {
        case .passwordRequired:
            return "A password is required for a full backup."
        case .encodingFailed:
            return "The full backup couldn't be encoded."
        case .decryptionFailed:
            return "The password is incorrect or the full backup is damaged."
        case .unsupportedVersion(let version):
            return "Backup version \(version) isn't supported by this version of AuGenda."
        case .unsupportedDataModelVersion(let version):
            return "Backup data-model version \(version) isn't supported by this version of AuGenda."
        case .wrongPayloadKind:
            return "This file isn't an AuGenda full backup."
        case .integrityMismatch:
            return "The backup failed its integrity check and was not restored."
        case .incompleteManifest(let detail):
            return "The backup completeness manifest is invalid: \(detail)"
        case .duplicateIdentity(let entity):
            return "The backup contains duplicate \(entity) identities."
        case .invalidRelationship(let detail):
            return "The backup contains an invalid relationship: \(detail)"
        case .backupTooLarge:
            return "The backup is larger than the 100 MB restore limit."
        case .historyRestoreFailed:
            return "The backup's local AI history could not be restored. Product data was not changed."
        case .historyRollbackFailed:
            return "The restore was cancelled, but local AI history could not be fully rolled back."
        }
    }
}

private enum AuGendaBackupKind: String, Codable {
    case wholeProduct
}

struct AuGendaBackupIntegrity: Codable, Equatable {
    let algorithm: String
    let payloadSHA256: String
}

struct AuGendaBackupCompleteness: Codable, Equatable {
    let expectedEntityTypes: [String]
    let entityCounts: [String: Int]
    let historyCounts: [String: Int]
    let preferenceKeys: [String]
    let excludedSecurityClasses: [String]
}

struct AuGendaBackupPreference: Codable, Equatable {
    let key: String
    /// Binary property-list encoding preserves the exact supported
    /// UserDefaults type (Date, number, string, or array) without type guessing.
    let propertyListData: Data
}

struct BackupAgendaItem: Codable {
    let clientID: UUID
    let createdAt: Date
    let updatedAt: Date
    let title: String
    let notes: String
    let scheduledDate: Date
    let dueDate: Date?
    let isAllDay: Bool
    let snoozedUntil: Date?
    let frictionLevel: Int
    let energyRequired: Int
    let contextTag: String
    let needsBodyDouble: Bool
    let interestLevel: Int
    let sensoryLoad: Int
    let socialLoad: Int
    let initiationCost: Int
    let specialInterest: Bool
    let excludeFromAI: Bool
    let isComplete: Bool
    let completedAt: Date?
    let priority: Int
    let sortOrder: Int
    let recurrenceRule: String
    let recurrenceParentID: UUID?
    let assignedToProfileID: UUID?
    let assignedByProfileID: UUID?
}

struct BackupSubTask: Codable {
    let clientID: UUID
    let createdAt: Date
    let title: String
    let isComplete: Bool
    let sortOrder: Int
    let parentItemID: UUID?
}

struct BackupAgendaTask: Codable {
    let clientID: UUID
    let createdAt: Date
    let updatedAt: Date
    let title: String
    let notes: String
    let scheduledDate: Date?
    let dueDate: Date?
    let frictionLevel: Int
    let energyRequired: Int
    let estimatedMinutes: Int
    let contextTag: String
    let hyperfocusRisk: Bool
    let needsBodyDouble: Bool
    let waitingOn: String
    let interestLevel: Int
    let sensoryLoad: Int
    let socialLoad: Int
    let initiationCost: Int
    let specialInterest: Bool
    let excludeFromAI: Bool
    let priority: Int
    let sortOrder: Int
    let isComplete: Bool
    let completedAt: Date?
    let isDeferredUntil: Date?
    let isAbandoned: Bool
    let abandonedAt: Date?
    let abandonReason: String
    let recurrenceRule: String
    let recurrenceParentID: UUID?
    let assignedToProfileID: UUID?
    let assignedByProfileID: UUID?
    let agendaItemID: UUID?
}

struct BackupTaskStep: Codable {
    let clientID: UUID
    let createdAt: Date
    let title: String
    let isComplete: Bool
    let sortOrder: Int
    let estimatedMinutes: Int
    let parentTaskID: UUID?
}

struct BackupInboxItem: Codable {
    let clientID: UUID
    let createdAt: Date
    let updatedAt: Date
    let rawCapture: String
    let sourceRaw: String
    let stateRaw: String
    let aiSuggestedTitle: String?
    let aiSuggestedFriction: Int?
    let aiSuggestedEnergy: Int?
    let aiSuggestedInitiationCost: Int?
    let aiSuggestedSensoryLoad: Int?
    let aiSuggestedSocialLoad: Int?
    let aiSuggestedContextTag: String?
    let resolvedTaskID: UUID?
    let assignedToProfileID: UUID?
}

struct BackupUserPreferences: Codable {
    let clientID: UUID
    let updatedAt: Date
    let currentEnergyLevel: Int
    let lowEFMaxFriction: Int
    let focusSessionMinutes: Int
    let breakMinutes: Int
    let notificationStyle: String
    let watchComplicationMode: String
    let theme: String
    let minimalMode: Bool
}

struct BackupBlock: Codable {
    let clientID: UUID
    let createdAt: Date
    let updatedAt: Date
    let typeRaw: String
    let customName: String
    let sortOrder: Int
    let isActive: Bool
    let startedAt: Date?
    let completedAt: Date?
    let lastCompletedDate: Date?
    let currentStreak: Int
    let longestStreak: Int
    let lastStreakDate: Date?
    let weatherCheckEnabled: Bool
}

struct BackupBlockTask: Codable {
    let clientID: UUID
    let createdAt: Date
    let title: String
    let notes: String
    let isComplete: Bool
    let completedAt: Date?
    let sortOrder: Int
    let isOptional: Bool
    let blockID: UUID?
}

struct BackupBundleTemplate: Codable {
    let clientID: UUID
    let createdAt: Date
    let updatedAt: Date
    let typeRaw: String
    let customName: String
    let sortOrder: Int
    let autoPromptBlockTypesRaw: String
}

struct BackupBundleTemplateItem: Codable {
    let clientID: UUID
    let title: String
    let sortOrder: Int
    let templateID: UUID?
}

struct BackupAttachedBundle: Codable {
    let clientID: UUID
    let createdAt: Date
    let name: String
    let icon: String
    let isComplete: Bool
    let blockID: UUID?
}

struct BackupAttachedBundleItem: Codable {
    let clientID: UUID
    let title: String
    let isComplete: Bool
    let sortOrder: Int
    let bundleID: UUID?
}

struct BackupProfile: Codable {
    let clientID: UUID
    let createdAt: Date
    let updatedAt: Date
    let name: String
    let roleRaw: String
    let neurotypesRaw: String
    let avatarImageData: Data?
    let avatarColorHex: String
    let sortOrder: Int
}

struct BackupProfilePreferences: Codable {
    let clientID: UUID
    let updatedAt: Date
    let profileID: UUID?
    let currentEnergyLevel: Int
    let energyTrackingEnabled: Bool
    let lowEFMaxFriction: Int
    let densityPinnedRaw: String
    let focusSessionMinutes: Int
    let breakMinutes: Int
    let hyperfocusGuard: Bool
    let taskLanguageStyleRaw: String
    let frictionLabelRaw: String
    let transitionPrepMinutes: Int
    let routineProtectionEnabled: Bool
    let timeBlindnessWarningsEnabled: Bool
    let deadlinePressureVisible: Bool
    let notificationStyleRaw: String
    let maxNotificationsPerHour: Int
    let notificationPrivacyStrict: Bool
    let appFontRaw: String
    let minimalMode: Bool
    let largeTouchTargets: Bool
    let sensoryContextTagsEnabled: Bool
    let highContrastMode: Bool
    let showCheckInNudges: Bool
    let lowStimulationMode: Bool
    let reduceMotion: Bool
    let uiScale: Double
    let watchComplicationMode: String
    let appliedPresetRaw: String
}

struct BackupFocusSession: Codable {
    let clientID: UUID
    let createdAt: Date
    let updatedAt: Date
    let startTime: Date
    let endTime: Date?
    let plannedDurationMinutes: Int
    let taskID: UUID?
    let taskTitle: String
    let stateRaw: String
    let interruptionCount: Int
    let interruptionTimestamps: [Date]
    let interruptionReasons: [String]
    let wasCompleted: Bool
    let wasAbandoned: Bool
    let abandonReason: String
    let profileID: UUID?
}

struct BackupTaskRelationship: Codable {
    let clientID: UUID
    let createdAt: Date
    let updatedAt: Date
    let sourceTaskID: UUID
    let targetTaskID: UUID
    let typeRaw: String
}

struct BackupNote: Codable {
    let clientID: UUID
    let createdAt: Date
    let updatedAt: Date
    let title: String
    let body: String
    let tags: String
    let relatedTaskID: UUID?
    let relatedItemID: UUID?
}

struct AuGendaBackupPayload: Codable {
    let agendaItems: [BackupAgendaItem]
    let subTasks: [BackupSubTask]
    let agendaTasks: [BackupAgendaTask]
    let taskSteps: [BackupTaskStep]
    let inboxItems: [BackupInboxItem]
    let userPreferences: [BackupUserPreferences]
    let blocks: [BackupBlock]
    let blockTasks: [BackupBlockTask]
    let bundleTemplates: [BackupBundleTemplate]
    let bundleTemplateItems: [BackupBundleTemplateItem]
    let attachedBundles: [BackupAttachedBundle]
    let attachedBundleItems: [BackupAttachedBundleItem]
    let profiles: [BackupProfile]
    let profilePreferences: [BackupProfilePreferences]
    let focusSessions: [BackupFocusSession]
    let taskRelationships: [BackupTaskRelationship]
    let notes: [BackupNote]
    let aiUsageHistory: [AIUsageEntry]
    let personalizationMemory: [PersonalizationContext.MemoryEntry]
    let preferences: [AuGendaBackupPreference]
}

struct AuGendaBackupEnvelope: Codable {
    let formatVersion: Int
    fileprivate let kind: AuGendaBackupKind
    let backupID: UUID
    let createdAt: Date
    let dataModelVersion: String
    let completeness: AuGendaBackupCompleteness
    let integrity: AuGendaBackupIntegrity
    let payload: AuGendaBackupPayload

    var totalEntityCount: Int {
        completeness.entityCounts.values.reduce(0, +)
    }
}

private extension BackupAgendaItem {
    init(_ source: AgendaItem) {
        clientID = source.clientID
        createdAt = source.createdAt
        updatedAt = source.updatedAt
        title = source.title
        notes = source.notes
        scheduledDate = source.scheduledDate
        dueDate = source.dueDate
        isAllDay = source.isAllDay
        snoozedUntil = source.snoozedUntil
        frictionLevel = source.frictionLevel
        energyRequired = source.energyRequired
        contextTag = source.contextTag
        needsBodyDouble = source.needsBodyDouble
        interestLevel = source.interestLevel
        sensoryLoad = source.sensoryLoad
        socialLoad = source.socialLoad
        initiationCost = source.initiationCost
        specialInterest = source.specialInterest
        excludeFromAI = source.excludeFromAI
        isComplete = source.isComplete
        completedAt = source.completedAt
        priority = source.priority
        sortOrder = source.sortOrder
        recurrenceRule = source.recurrenceRule
        recurrenceParentID = source.recurrenceParentID
        assignedToProfileID = source.assignedToProfileID
        assignedByProfileID = source.assignedByProfileID
    }
}

private extension BackupSubTask {
    init(_ source: SubTask) {
        clientID = source.clientID
        createdAt = source.createdAt
        title = source.title
        isComplete = source.isComplete
        sortOrder = source.sortOrder
        parentItemID = source.parentItem?.clientID
    }
}

private extension BackupAgendaTask {
    init(_ source: AgendaTask) {
        clientID = source.clientID
        createdAt = source.createdAt
        updatedAt = source.updatedAt
        title = source.title
        notes = source.notes
        scheduledDate = source.scheduledDate
        dueDate = source.dueDate
        frictionLevel = source.frictionLevel
        energyRequired = source.energyRequired
        estimatedMinutes = source.estimatedMinutes
        contextTag = source.contextTag
        hyperfocusRisk = source.hyperfocusRisk
        needsBodyDouble = source.needsBodyDouble
        waitingOn = source.waitingOn
        interestLevel = source.interestLevel
        sensoryLoad = source.sensoryLoad
        socialLoad = source.socialLoad
        initiationCost = source.initiationCost
        specialInterest = source.specialInterest
        excludeFromAI = source.excludeFromAI
        priority = source.priority
        sortOrder = source.sortOrder
        isComplete = source.isComplete
        completedAt = source.completedAt
        isDeferredUntil = source.isDeferredUntil
        isAbandoned = source.isAbandoned
        abandonedAt = source.abandonedAt
        abandonReason = source.abandonReason
        recurrenceRule = source.recurrenceRule
        recurrenceParentID = source.recurrenceParentID
        assignedToProfileID = source.assignedToProfileID
        assignedByProfileID = source.assignedByProfileID
        agendaItemID = source.agendaItemID
    }
}

private extension BackupTaskStep {
    init(_ source: TaskStep) {
        clientID = source.clientID
        createdAt = source.createdAt
        title = source.title
        isComplete = source.isComplete
        sortOrder = source.sortOrder
        estimatedMinutes = source.estimatedMinutes
        parentTaskID = source.parentTask?.clientID
    }
}

private extension BackupInboxItem {
    init(_ source: InboxItem) {
        clientID = source.clientID
        createdAt = source.createdAt
        updatedAt = source.updatedAt
        rawCapture = source.rawCapture
        sourceRaw = source.sourceRaw
        stateRaw = source.stateRaw
        aiSuggestedTitle = source.aiSuggestedTitle
        aiSuggestedFriction = source.aiSuggestedFriction
        aiSuggestedEnergy = source.aiSuggestedEnergy
        aiSuggestedInitiationCost = source.aiSuggestedInitiationCost
        aiSuggestedSensoryLoad = source.aiSuggestedSensoryLoad
        aiSuggestedSocialLoad = source.aiSuggestedSocialLoad
        aiSuggestedContextTag = source.aiSuggestedContextTag
        resolvedTaskID = source.resolvedTaskID
        assignedToProfileID = source.assignedToProfileID
    }
}

private extension BackupUserPreferences {
    init(_ source: UserPreferences) {
        clientID = source.clientID
        updatedAt = source.updatedAt
        currentEnergyLevel = source.currentEnergyLevel
        lowEFMaxFriction = source.lowEFMaxFriction
        focusSessionMinutes = source.focusSessionMinutes
        breakMinutes = source.breakMinutes
        notificationStyle = source.notificationStyle
        watchComplicationMode = source.watchComplicationMode
        theme = source.theme
        minimalMode = source.minimalMode
    }
}

private extension BackupBlock {
    init(_ source: Block) {
        clientID = source.clientID
        createdAt = source.createdAt
        updatedAt = source.updatedAt
        typeRaw = source.typeRaw
        customName = source.customName
        sortOrder = source.sortOrder
        isActive = source.isActive
        startedAt = source.startedAt
        completedAt = source.completedAt
        lastCompletedDate = source.lastCompletedDate
        currentStreak = source.currentStreak
        longestStreak = source.longestStreak
        lastStreakDate = source.lastStreakDate
        weatherCheckEnabled = source.weatherCheckEnabled
    }
}

private extension BackupBlockTask {
    init(_ source: BlockTask) {
        clientID = source.clientID
        createdAt = source.createdAt
        title = source.title
        notes = source.notes
        isComplete = source.isComplete
        completedAt = source.completedAt
        sortOrder = source.sortOrder
        isOptional = source.isOptional
        blockID = source.block?.clientID
    }
}

private extension BackupBundleTemplate {
    init(_ source: BundleTemplate) {
        clientID = source.clientID
        createdAt = source.createdAt
        updatedAt = source.updatedAt
        typeRaw = source.typeRaw
        customName = source.customName
        sortOrder = source.sortOrder
        autoPromptBlockTypesRaw = source.autoPromptBlockTypesRaw
    }
}

private extension BackupBundleTemplateItem {
    init(_ source: BundleTemplateItem) {
        clientID = source.clientID
        title = source.title
        sortOrder = source.sortOrder
        templateID = source.template?.clientID
    }
}

private extension BackupAttachedBundle {
    init(_ source: AttachedBundle) {
        clientID = source.clientID
        createdAt = source.createdAt
        name = source.name
        icon = source.icon
        isComplete = source.isComplete
        blockID = source.block?.clientID
    }
}

private extension BackupAttachedBundleItem {
    init(_ source: AttachedBundleItem) {
        clientID = source.clientID
        title = source.title
        isComplete = source.isComplete
        sortOrder = source.sortOrder
        bundleID = source.bundle?.clientID
    }
}

private extension BackupProfile {
    init(_ source: Profile) {
        clientID = source.clientID
        createdAt = source.createdAt
        updatedAt = source.updatedAt
        name = source.name
        roleRaw = source.roleRaw
        neurotypesRaw = source.neurotypesRaw
        avatarImageData = source.avatarImageData
        avatarColorHex = source.avatarColorHex
        sortOrder = source.sortOrder
    }
}

private extension BackupProfilePreferences {
    init(_ source: ProfilePreferences) {
        clientID = source.clientID
        updatedAt = source.updatedAt
        profileID = source.profile?.clientID
        currentEnergyLevel = source.currentEnergyLevel
        energyTrackingEnabled = source.energyTrackingEnabled
        lowEFMaxFriction = source.lowEFMaxFriction
        densityPinnedRaw = source.densityPinnedRaw
        focusSessionMinutes = source.focusSessionMinutes
        breakMinutes = source.breakMinutes
        hyperfocusGuard = source.hyperfocusGuard
        taskLanguageStyleRaw = source.taskLanguageStyleRaw
        frictionLabelRaw = source.frictionLabelRaw
        transitionPrepMinutes = source.transitionPrepMinutes
        routineProtectionEnabled = source.routineProtectionEnabled
        timeBlindnessWarningsEnabled = source.timeBlindnessWarningsEnabled
        deadlinePressureVisible = source.deadlinePressureVisible
        notificationStyleRaw = source.notificationStyleRaw
        maxNotificationsPerHour = source.maxNotificationsPerHour
        notificationPrivacyStrict = source.notificationPrivacyStrict
        appFontRaw = source.appFontRaw
        minimalMode = source.minimalMode
        largeTouchTargets = source.largeTouchTargets
        sensoryContextTagsEnabled = source.sensoryContextTagsEnabled
        highContrastMode = source.highContrastMode
        showCheckInNudges = source.showCheckInNudges
        lowStimulationMode = source.lowStimulationMode
        reduceMotion = source.reduceMotion
        uiScale = source.uiScale
        watchComplicationMode = source.watchComplicationMode
        appliedPresetRaw = source.appliedPresetRaw
    }
}

private extension BackupFocusSession {
    init(_ source: FocusSession) {
        clientID = source.clientID
        createdAt = source.createdAt
        updatedAt = source.updatedAt
        startTime = source.startTime
        endTime = source.endTime
        plannedDurationMinutes = source.plannedDurationMinutes
        taskID = source.taskID
        taskTitle = source.taskTitle
        stateRaw = source.stateRaw
        interruptionCount = source.interruptionCount
        interruptionTimestamps = source.interruptionTimestamps
        interruptionReasons = source.interruptionReasons
        wasCompleted = source.wasCompleted
        wasAbandoned = source.wasAbandoned
        abandonReason = source.abandonReason
        profileID = source.profileID
    }
}

private extension BackupTaskRelationship {
    init(_ source: TaskRelationship) {
        clientID = source.clientID
        createdAt = source.createdAt
        updatedAt = source.updatedAt
        sourceTaskID = source.sourceTaskID
        targetTaskID = source.targetTaskID
        typeRaw = source.typeRaw
    }
}

private extension BackupNote {
    init(_ source: Note) {
        clientID = source.clientID
        createdAt = source.createdAt
        updatedAt = source.updatedAt
        title = source.title
        body = source.body
        tags = source.tags
        relatedTaskID = source.relatedTaskID
        relatedItemID = source.relatedItemID
    }
}

private extension BackupAgendaItem {
    func makeModel() -> AgendaItem {
        let model = AgendaItem(
            title: title,
            scheduledDate: scheduledDate,
            priority: priority,
            frictionLevel: frictionLevel,
            energyRequired: energyRequired,
            contextTag: contextTag,
            recurrenceRule: recurrenceRule
        )
        model.clientID = clientID
        model.createdAt = createdAt
        model.updatedAt = updatedAt
        model.notes = notes
        model.dueDate = dueDate
        model.isAllDay = isAllDay
        model.snoozedUntil = snoozedUntil
        model.needsBodyDouble = needsBodyDouble
        model.interestLevel = interestLevel
        model.sensoryLoad = sensoryLoad
        model.socialLoad = socialLoad
        model.initiationCost = initiationCost
        model.specialInterest = specialInterest
        model.excludeFromAI = excludeFromAI
        model.isComplete = isComplete
        model.completedAt = completedAt
        model.sortOrder = sortOrder
        model.recurrenceParentID = recurrenceParentID
        model.assignedToProfileID = assignedToProfileID
        model.assignedByProfileID = assignedByProfileID
        return model
    }
}

private extension BackupSubTask {
    func makeModel() -> SubTask {
        let model = SubTask(title: title, sortOrder: sortOrder)
        model.clientID = clientID
        model.createdAt = createdAt
        model.isComplete = isComplete
        return model
    }
}

private extension BackupAgendaTask {
    func makeModel() -> AgendaTask {
        let model = AgendaTask(
            title: title,
            frictionLevel: frictionLevel,
            energyRequired: energyRequired,
            estimatedMinutes: estimatedMinutes,
            contextTag: contextTag,
            priority: priority,
            interestLevel: interestLevel
        )
        model.clientID = clientID
        model.createdAt = createdAt
        model.updatedAt = updatedAt
        model.notes = notes
        model.scheduledDate = scheduledDate
        model.dueDate = dueDate
        model.hyperfocusRisk = hyperfocusRisk
        model.needsBodyDouble = needsBodyDouble
        model.waitingOn = waitingOn
        model.sensoryLoad = sensoryLoad
        model.socialLoad = socialLoad
        model.initiationCost = initiationCost
        model.specialInterest = specialInterest
        model.excludeFromAI = excludeFromAI
        model.sortOrder = sortOrder
        model.isComplete = isComplete
        model.completedAt = completedAt
        model.isDeferredUntil = isDeferredUntil
        model.isAbandoned = isAbandoned
        model.abandonedAt = abandonedAt
        model.abandonReason = abandonReason
        model.recurrenceRule = recurrenceRule
        model.recurrenceParentID = recurrenceParentID
        model.assignedToProfileID = assignedToProfileID
        model.assignedByProfileID = assignedByProfileID
        model.agendaItemID = agendaItemID
        return model
    }
}

private extension BackupTaskStep {
    func makeModel() -> TaskStep {
        let model = TaskStep(
            title: title,
            estimatedMinutes: estimatedMinutes,
            sortOrder: sortOrder
        )
        model.clientID = clientID
        model.createdAt = createdAt
        model.isComplete = isComplete
        return model
    }
}

private extension BackupInboxItem {
    func makeModel() -> InboxItem {
        let source = InboxItemSource(rawValue: sourceRaw) ?? .textCapture
        let model = InboxItem(rawCapture: rawCapture, source: source)
        model.clientID = clientID
        model.createdAt = createdAt
        model.updatedAt = updatedAt
        model.sourceRaw = sourceRaw
        model.stateRaw = stateRaw
        model.aiSuggestedTitle = aiSuggestedTitle
        model.aiSuggestedFriction = aiSuggestedFriction
        model.aiSuggestedEnergy = aiSuggestedEnergy
        model.aiSuggestedInitiationCost = aiSuggestedInitiationCost
        model.aiSuggestedSensoryLoad = aiSuggestedSensoryLoad
        model.aiSuggestedSocialLoad = aiSuggestedSocialLoad
        model.aiSuggestedContextTag = aiSuggestedContextTag
        model.resolvedTaskID = resolvedTaskID
        model.assignedToProfileID = assignedToProfileID
        return model
    }
}

private extension BackupUserPreferences {
    func makeModel() -> UserPreferences {
        let model = UserPreferences()
        model.clientID = clientID
        model.updatedAt = updatedAt
        model.currentEnergyLevel = currentEnergyLevel
        model.lowEFMaxFriction = lowEFMaxFriction
        model.focusSessionMinutes = focusSessionMinutes
        model.breakMinutes = breakMinutes
        model.notificationStyle = notificationStyle
        model.watchComplicationMode = watchComplicationMode
        model.theme = theme
        model.minimalMode = minimalMode
        return model
    }
}

private extension BackupBlock {
    func makeModel() -> Block {
        let type = BlockType(rawValue: typeRaw) ?? .custom
        let model = Block(type: type, customName: customName, sortOrder: sortOrder)
        model.clientID = clientID
        model.createdAt = createdAt
        model.updatedAt = updatedAt
        model.typeRaw = typeRaw
        model.isActive = isActive
        model.startedAt = startedAt
        model.completedAt = completedAt
        model.lastCompletedDate = lastCompletedDate
        model.currentStreak = currentStreak
        model.longestStreak = longestStreak
        model.lastStreakDate = lastStreakDate
        model.weatherCheckEnabled = weatherCheckEnabled
        return model
    }
}

private extension BackupBlockTask {
    func makeModel() -> BlockTask {
        let model = BlockTask(
            title: title,
            sortOrder: sortOrder,
            isOptional: isOptional
        )
        model.clientID = clientID
        model.createdAt = createdAt
        model.notes = notes
        model.isComplete = isComplete
        model.completedAt = completedAt
        return model
    }
}

private extension BackupBundleTemplate {
    func makeModel() -> BundleTemplate {
        let type = BundleType(rawValue: typeRaw) ?? .custom
        let model = BundleTemplate(type: type, customName: customName)
        model.clientID = clientID
        model.createdAt = createdAt
        model.updatedAt = updatedAt
        model.typeRaw = typeRaw
        model.sortOrder = sortOrder
        model.autoPromptBlockTypesRaw = autoPromptBlockTypesRaw
        return model
    }
}

private extension BackupBundleTemplateItem {
    func makeModel() -> BundleTemplateItem {
        let model = BundleTemplateItem(title: title, sortOrder: sortOrder)
        model.clientID = clientID
        return model
    }
}

private extension BackupAttachedBundle {
    func makeModel() -> AttachedBundle {
        let model = AttachedBundle(name: name, icon: icon)
        model.clientID = clientID
        model.createdAt = createdAt
        model.isComplete = isComplete
        return model
    }
}

private extension BackupAttachedBundleItem {
    func makeModel() -> AttachedBundleItem {
        let model = AttachedBundleItem(title: title, sortOrder: sortOrder)
        model.clientID = clientID
        model.isComplete = isComplete
        return model
    }
}

private extension BackupProfile {
    func makeModel() -> Profile {
        let role = ProfileRole(rawValue: roleRaw) ?? .adult
        let model = Profile(name: name, role: role, sortOrder: sortOrder)
        model.clientID = clientID
        model.createdAt = createdAt
        model.updatedAt = updatedAt
        model.roleRaw = roleRaw
        model.neurotypesRaw = neurotypesRaw
        model.avatarImageData = avatarImageData
        model.avatarColorHex = avatarColorHex
        return model
    }
}

private extension BackupProfilePreferences {
    func makeModel() -> ProfilePreferences {
        let model = ProfilePreferences()
        model.clientID = clientID
        model.updatedAt = updatedAt
        model.currentEnergyLevel = currentEnergyLevel
        model.energyTrackingEnabled = energyTrackingEnabled
        model.lowEFMaxFriction = lowEFMaxFriction
        model.densityPinnedRaw = densityPinnedRaw
        model.focusSessionMinutes = focusSessionMinutes
        model.breakMinutes = breakMinutes
        model.hyperfocusGuard = hyperfocusGuard
        model.taskLanguageStyleRaw = taskLanguageStyleRaw
        model.frictionLabelRaw = frictionLabelRaw
        model.transitionPrepMinutes = transitionPrepMinutes
        model.routineProtectionEnabled = routineProtectionEnabled
        model.timeBlindnessWarningsEnabled = timeBlindnessWarningsEnabled
        model.deadlinePressureVisible = deadlinePressureVisible
        model.notificationStyleRaw = notificationStyleRaw
        model.maxNotificationsPerHour = maxNotificationsPerHour
        model.notificationPrivacyStrict = notificationPrivacyStrict
        model.appFontRaw = appFontRaw
        model.minimalMode = minimalMode
        model.largeTouchTargets = largeTouchTargets
        model.sensoryContextTagsEnabled = sensoryContextTagsEnabled
        model.highContrastMode = highContrastMode
        model.showCheckInNudges = showCheckInNudges
        model.lowStimulationMode = lowStimulationMode
        model.reduceMotion = reduceMotion
        model.uiScale = uiScale
        model.watchComplicationMode = watchComplicationMode
        model.appliedPresetRaw = appliedPresetRaw
        return model
    }
}

private extension BackupFocusSession {
    func makeModel() -> FocusSession {
        let model = FocusSession(
            plannedDurationMinutes: plannedDurationMinutes,
            taskID: taskID,
            taskTitle: taskTitle,
            profileID: profileID
        )
        model.clientID = clientID
        model.createdAt = createdAt
        model.updatedAt = updatedAt
        model.startTime = startTime
        model.endTime = endTime
        model.stateRaw = stateRaw
        model.interruptionCount = interruptionCount
        model.interruptionTimestamps = interruptionTimestamps
        model.interruptionReasons = interruptionReasons
        model.wasCompleted = wasCompleted
        model.wasAbandoned = wasAbandoned
        model.abandonReason = abandonReason
        return model
    }
}

private extension BackupTaskRelationship {
    func makeModel() -> TaskRelationship {
        let type = TaskRelationshipType(rawValue: typeRaw) ?? .related
        let model = TaskRelationship(
            sourceTaskID: sourceTaskID,
            targetTaskID: targetTaskID,
            type: type
        )
        model.clientID = clientID
        model.createdAt = createdAt
        model.updatedAt = updatedAt
        model.typeRaw = typeRaw
        return model
    }
}

private extension BackupNote {
    func makeModel() -> Note {
        let model = Note(
            title: title,
            body: body,
            relatedTaskID: relatedTaskID,
            relatedItemID: relatedItemID
        )
        model.clientID = clientID
        model.createdAt = createdAt
        model.updatedAt = updatedAt
        model.tags = tags
        return model
    }
}

@MainActor
enum AuGendaBackupService {
    static let encryptedPrefix = "AuGendaBackupV1:"
    static let maximumBackupBytes = 100 * 1024 * 1024
    static let formatVersion = 1
    static let dataModelVersion = "2.0.0"

    static let expectedEntityTypes = [
        "AgendaItem", "AgendaTask", "AttachedBundle", "AttachedBundleItem",
        "Block", "BlockTask", "BundleTemplate", "BundleTemplateItem",
        "FocusSession", "InboxItem", "Note", "Profile",
        "ProfilePreferences", "SubTask", "TaskRelationship", "TaskStep",
        "UserPreferences"
    ]

    /// Consent receipts are purpose- and destination-specific and must be
    /// re-confirmed after restore. Watch acknowledgement IDs are transport
    /// bookkeeping rather than user data. Keychain material is never in
    /// UserDefaults and is explicitly outside this archive.
    private static var backupPreferenceKeys: [String] {
        AppDefaultsKeys.resettable
            .filter { !$0.hasPrefix("ai.consent.") }
            .filter { $0 != "watch.sync.processedMutationIDs.v1" }
            .sorted()
    }

    static func makeEnvelope(
        from context: ModelContext,
        defaults: UserDefaults = .standard,
        now: Date = .now,
        backupID: UUID = UUID(),
        aiUsageHistory: [AIUsageEntry]? = nil,
        personalizationMemory: [PersonalizationContext.MemoryEntry]? = nil
    ) throws -> AuGendaBackupEnvelope {
        let payload = try makePayload(
            from: context,
            defaults: defaults,
            aiUsageHistory: aiUsageHistory ?? AIUsageLedger.shared.entries,
            personalizationMemory: personalizationMemory
                ?? PersonalizationStore.shared.memory
        )
        let counts = entityCounts(for: payload)
        let completeness = AuGendaBackupCompleteness(
            expectedEntityTypes: expectedEntityTypes,
            entityCounts: counts,
            historyCounts: historyCounts(for: payload),
            preferenceKeys: payload.preferences.map(\.key).sorted(),
            excludedSecurityClasses: [
                "Keychain API keys",
                "OAuth access and refresh tokens",
                "provider consent receipts",
                "Watch mutation acknowledgement ledger"
            ]
        )
        let digest = try payloadDigest(payload)
        let envelope = AuGendaBackupEnvelope(
            formatVersion: formatVersion,
            kind: .wholeProduct,
            backupID: backupID,
            createdAt: now,
            dataModelVersion: dataModelVersion,
            completeness: completeness,
            integrity: .init(algorithm: "SHA-256", payloadSHA256: digest),
            payload: payload
        )
        try validate(envelope)
        return envelope
    }

    static func encryptedArchive(
        from context: ModelContext,
        defaults: UserDefaults = .standard,
        password: String,
        aiUsageHistory: [AIUsageEntry]? = nil,
        personalizationMemory: [PersonalizationContext.MemoryEntry]? = nil
    ) throws -> String {
        guard !password.isEmpty else { throw AuGendaBackupError.passwordRequired }
        let envelope = try makeEnvelope(
            from: context,
            defaults: defaults,
            aiUsageHistory: aiUsageHistory,
            personalizationMemory: personalizationMemory
        )
        let cleartext = try encodeEnvelope(envelope)
        let encrypted: String
        do {
            encrypted = try TaskExporter.encrypt(cleartext, password: password)
        } catch {
            throw AuGendaBackupError.encodingFailed
        }
        guard encrypted.hasPrefix(TaskExporter.encryptedExportV2Prefix) else {
            throw AuGendaBackupError.encodingFailed
        }
        return encryptedPrefix
            + encrypted.dropFirst(TaskExporter.encryptedExportV2Prefix.count)
    }

    static func decodeEncryptedArchive(
        _ archive: String,
        password: String
    ) throws -> AuGendaBackupEnvelope {
        guard archive.utf8.count <= maximumBackupBytes else {
            throw AuGendaBackupError.backupTooLarge
        }
        guard !password.isEmpty else { throw AuGendaBackupError.passwordRequired }
        guard archive.hasPrefix(encryptedPrefix) else {
            throw AuGendaBackupError.wrongPayloadKind
        }
        let taskEnvelope = TaskExporter.encryptedExportV2Prefix
            + archive.dropFirst(encryptedPrefix.count)
        let cleartext: String
        do {
            cleartext = try TaskExporter.decrypt(taskEnvelope, password: password)
        } catch {
            throw AuGendaBackupError.decryptionFailed
        }
        guard let data = cleartext.data(using: .utf8) else {
            throw AuGendaBackupError.decryptionFailed
        }
        let decoder = JSONDecoder()
        // Whole-product recovery must preserve subsecond event ordering. The
        // task-sharing formats retain their legacy ISO-8601 contract, while
        // backups use a symmetric Double timestamp representation.
        decoder.dateDecodingStrategy = .secondsSince1970
        let envelope: AuGendaBackupEnvelope
        do {
            envelope = try decoder.decode(AuGendaBackupEnvelope.self, from: data)
        } catch {
            throw AuGendaBackupError.decryptionFailed
        }
        try validate(envelope)
        return envelope
    }

    static func encodeEnvelope(_ envelope: AuGendaBackupEnvelope) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let string = String(
            data: try encoder.encode(envelope),
            encoding: .utf8
        ) else {
            throw AuGendaBackupError.encodingFailed
        }
        return string
    }

    static func validate(_ envelope: AuGendaBackupEnvelope) throws {
        guard envelope.formatVersion == formatVersion else {
            throw AuGendaBackupError.unsupportedVersion(envelope.formatVersion)
        }
        guard envelope.kind == .wholeProduct else {
            throw AuGendaBackupError.wrongPayloadKind
        }
        guard envelope.dataModelVersion == dataModelVersion else {
            throw AuGendaBackupError.unsupportedDataModelVersion(
                envelope.dataModelVersion
            )
        }
        guard envelope.integrity.algorithm == "SHA-256",
              envelope.integrity.payloadSHA256 == (try payloadDigest(envelope.payload)) else {
            throw AuGendaBackupError.integrityMismatch
        }

        let actualCounts = entityCounts(for: envelope.payload)
        guard envelope.completeness.expectedEntityTypes == expectedEntityTypes else {
            throw AuGendaBackupError.incompleteManifest("entity schema does not match")
        }
        guard envelope.completeness.entityCounts == actualCounts else {
            throw AuGendaBackupError.incompleteManifest("entity counts do not match the payload")
        }
        guard envelope.completeness.historyCounts
                == historyCounts(for: envelope.payload) else {
            throw AuGendaBackupError.incompleteManifest(
                "history counts do not match the payload"
            )
        }
        let preferenceKeys = envelope.payload.preferences.map(\.key).sorted()
        guard Set(preferenceKeys).count == preferenceKeys.count else {
            throw AuGendaBackupError.duplicateIdentity("preference key")
        }
        guard envelope.completeness.preferenceKeys == preferenceKeys else {
            throw AuGendaBackupError.incompleteManifest("preference keys do not match the payload")
        }
        guard Set(preferenceKeys).isSubset(of: Set(backupPreferenceKeys)) else {
            throw AuGendaBackupError.incompleteManifest("archive contains a disallowed preference key")
        }

        try validateIdentities(envelope.payload)
        try validateRelationships(envelope.payload)
        do {
            _ = try AIUsageLedger.encodePersistedEntries(
                envelope.payload.aiUsageHistory
            )
            _ = try PersonalizationStore.encodePersistedMemory(
                envelope.payload.personalizationMemory
            )
        } catch {
            throw AuGendaBackupError.incompleteManifest(
                "AI history failed validation"
            )
        }
        _ = try decodedPreferences(envelope.payload.preferences)
    }

    struct RestoreSummary: Equatable {
        let restoredEntityCount: Int
        let restoredPreferenceCount: Int
    }

    /// Destructive whole-product restore. All archive validation and preference
    /// decoding happens before mutation. SwiftData changes share one save and
    /// roll back together on failure; preferences are applied only after that
    /// save succeeds, using already-decoded property-list values.
    static func restore(
        _ envelope: AuGendaBackupEnvelope,
        in context: ModelContext,
        defaults: UserDefaults = .standard,
        afterCommit: () -> Void = {}
    ) throws -> RestoreSummary {
        try restore(
            envelope,
            in: context,
            defaults: defaults,
            save: { try $0.save() },
            currentAIUsageHistory: { AIUsageLedger.shared.entries },
            currentPersonalizationMemory: {
                PersonalizationStore.shared.memory
            },
            replaceAIUsageHistory: {
                try AIUsageLedger.shared.restoreForBackup($0)
            },
            replacePersonalizationMemory: {
                try PersonalizationStore.shared.restoreMemoryForBackup($0)
            },
            reloadPersonalizationPreferences: {
                PersonalizationStore.shared.reloadFromDefaultsForBackup(
                    defaults: defaults
                )
            },
            afterCommit: afterCommit
        )
    }

    static func restore(
        _ envelope: AuGendaBackupEnvelope,
        in context: ModelContext,
        defaults: UserDefaults = .standard,
        save: (ModelContext) throws -> Void,
        currentAIUsageHistory: () -> [AIUsageEntry],
        currentPersonalizationMemory: () -> [PersonalizationContext.MemoryEntry],
        replaceAIUsageHistory: ([AIUsageEntry]) throws -> Void,
        replacePersonalizationMemory: ([PersonalizationContext.MemoryEntry]) throws -> Void,
        reloadPersonalizationPreferences: () -> Void,
        afterCommit: () -> Void = {}
    ) throws -> RestoreSummary {
        try validate(envelope)
        let decodedPreferenceValues = try decodedPreferences(
            envelope.payload.preferences
        )
        let payload = envelope.payload
        let previousAIUsageHistory = currentAIUsageHistory()
        let previousPersonalizationMemory = currentPersonalizationMemory()

        let agendaItems = payload.agendaItems.map { $0.makeModel() }
        let subTasks = payload.subTasks.map { $0.makeModel() }
        let agendaTasks = payload.agendaTasks.map { $0.makeModel() }
        let taskSteps = payload.taskSteps.map { $0.makeModel() }
        let inboxItems = payload.inboxItems.map { $0.makeModel() }
        let userPreferences = payload.userPreferences.map { $0.makeModel() }
        let blocks = payload.blocks.map { $0.makeModel() }
        let blockTasks = payload.blockTasks.map { $0.makeModel() }
        let bundleTemplates = payload.bundleTemplates.map { $0.makeModel() }
        let bundleTemplateItems = payload.bundleTemplateItems.map { $0.makeModel() }
        let attachedBundles = payload.attachedBundles.map { $0.makeModel() }
        let attachedBundleItems = payload.attachedBundleItems.map { $0.makeModel() }
        let profiles = payload.profiles.map { $0.makeModel() }
        let profilePreferences = payload.profilePreferences.map { $0.makeModel() }
        let focusSessions = payload.focusSessions.map { $0.makeModel() }
        let taskRelationships = payload.taskRelationships.map { $0.makeModel() }
        let notes = payload.notes.map { $0.makeModel() }

        let agendaItemByID = Dictionary(
            uniqueKeysWithValues: agendaItems.map { ($0.clientID, $0) }
        )
        let agendaTaskByID = Dictionary(
            uniqueKeysWithValues: agendaTasks.map { ($0.clientID, $0) }
        )
        let blockByID = Dictionary(
            uniqueKeysWithValues: blocks.map { ($0.clientID, $0) }
        )
        let templateByID = Dictionary(
            uniqueKeysWithValues: bundleTemplates.map { ($0.clientID, $0) }
        )
        let attachedBundleByID = Dictionary(
            uniqueKeysWithValues: attachedBundles.map { ($0.clientID, $0) }
        )
        let profileByID = Dictionary(
            uniqueKeysWithValues: profiles.map { ($0.clientID, $0) }
        )

        for (record, model) in zip(payload.subTasks, subTasks) {
            model.parentItem = record.parentItemID.flatMap { agendaItemByID[$0] }
        }
        for (record, model) in zip(payload.taskSteps, taskSteps) {
            model.parentTask = record.parentTaskID.flatMap { agendaTaskByID[$0] }
        }
        for (record, model) in zip(payload.blockTasks, blockTasks) {
            model.block = record.blockID.flatMap { blockByID[$0] }
        }
        for (record, model) in zip(payload.bundleTemplateItems, bundleTemplateItems) {
            model.template = record.templateID.flatMap { templateByID[$0] }
        }
        for (record, model) in zip(payload.attachedBundles, attachedBundles) {
            model.block = record.blockID.flatMap { blockByID[$0] }
        }
        for (record, model) in zip(payload.attachedBundleItems, attachedBundleItems) {
            model.bundle = record.bundleID.flatMap { attachedBundleByID[$0] }
        }
        for (record, model) in zip(payload.profilePreferences, profilePreferences) {
            if let profileID = record.profileID,
               let profile = profileByID[profileID] {
                model.profile = profile
                profile.preferences = model
            }
        }

        do {
            try replaceAIUsageHistory(payload.aiUsageHistory)
            try replacePersonalizationMemory(payload.personalizationMemory)
        } catch {
            try rollbackHistories(
                usage: previousAIUsageHistory,
                memory: previousPersonalizationMemory,
                replaceUsage: replaceAIUsageHistory,
                replaceMemory: replacePersonalizationMemory
            )
            throw AuGendaBackupError.historyRestoreFailed
        }

        let previousAutosaveSetting = context.autosaveEnabled
        context.autosaveEnabled = false
        defer { context.autosaveEnabled = previousAutosaveSetting }
        do {
            try deleteExistingProductData(in: context)

            agendaItems.forEach(context.insert)
            subTasks.forEach(context.insert)
            agendaTasks.forEach(context.insert)
            taskSteps.forEach(context.insert)
            inboxItems.forEach(context.insert)
            userPreferences.forEach(context.insert)
            blocks.forEach(context.insert)
            blockTasks.forEach(context.insert)
            bundleTemplates.forEach(context.insert)
            bundleTemplateItems.forEach(context.insert)
            attachedBundles.forEach(context.insert)
            attachedBundleItems.forEach(context.insert)
            profiles.forEach(context.insert)
            profilePreferences.forEach(context.insert)
            focusSessions.forEach(context.insert)
            taskRelationships.forEach(context.insert)
            notes.forEach(context.insert)

            try save(context)
        } catch {
            context.rollback()
            try rollbackHistories(
                usage: previousAIUsageHistory,
                memory: previousPersonalizationMemory,
                replaceUsage: replaceAIUsageHistory,
                replaceMemory: replacePersonalizationMemory
            )
            throw error
        }

        for key in backupPreferenceKeys {
            defaults.removeObject(forKey: key)
        }
        for provider in AIProvider.allCases {
            defaults.removeObject(forKey: AIConsentPolicy.consentKey(for: provider))
        }
        defaults.removeObject(forKey: AIConsentPolicy.ollamaDestinationKey)
        defaults.removeObject(forKey: "watch.sync.processedMutationIDs.v1")
        for (key, value) in decodedPreferenceValues {
            defaults.set(value, forKey: key)
        }
        reloadPersonalizationPreferences()
        afterCommit()

        return RestoreSummary(
            restoredEntityCount: envelope.totalEntityCount,
            restoredPreferenceCount: decodedPreferenceValues.count
        )
    }

    private static func deleteExistingProductData(
        in context: ModelContext
    ) throws {
        // Children first prevents cascade traversal from retaining transient
        // relationship objects in a replacement restore.
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

    private static func rollbackHistories(
        usage: [AIUsageEntry],
        memory: [PersonalizationContext.MemoryEntry],
        replaceUsage: ([AIUsageEntry]) throws -> Void,
        replaceMemory: ([PersonalizationContext.MemoryEntry]) throws -> Void
    ) throws {
        var rollbackFailed = false
        do {
            try replaceUsage(usage)
        } catch {
            rollbackFailed = true
        }
        do {
            try replaceMemory(memory)
        } catch {
            rollbackFailed = true
        }
        if rollbackFailed {
            throw AuGendaBackupError.historyRollbackFailed
        }
    }

    private static func deleteAll<T: PersistentModel>(
        _ type: T.Type,
        in context: ModelContext
    ) throws {
        for model in try context.fetch(FetchDescriptor<T>()) {
            context.delete(model)
        }
    }

    private static func makePayload(
        from context: ModelContext,
        defaults: UserDefaults,
        aiUsageHistory: [AIUsageEntry],
        personalizationMemory: [PersonalizationContext.MemoryEntry]
    ) throws -> AuGendaBackupPayload {
        let agendaItems = try context.fetch(FetchDescriptor<AgendaItem>())
            .map(BackupAgendaItem.init).sortedByID()
        let subTasks = try context.fetch(FetchDescriptor<SubTask>())
            .map(BackupSubTask.init).sortedByID()
        let agendaTasks = try context.fetch(FetchDescriptor<AgendaTask>())
            .map(BackupAgendaTask.init).sortedByID()
        let taskSteps = try context.fetch(FetchDescriptor<TaskStep>())
            .map(BackupTaskStep.init).sortedByID()
        let inboxItems = try context.fetch(FetchDescriptor<InboxItem>())
            .map(BackupInboxItem.init).sortedByID()
        let userPreferences = try context.fetch(
            FetchDescriptor<UserPreferences>()
        ).map(BackupUserPreferences.init).sortedByID()
        let blocks = try context.fetch(FetchDescriptor<Block>())
            .map(BackupBlock.init).sortedByID()
        let blockTasks = try context.fetch(FetchDescriptor<BlockTask>())
            .map(BackupBlockTask.init).sortedByID()
        let bundleTemplates = try context.fetch(
            FetchDescriptor<BundleTemplate>()
        ).map(BackupBundleTemplate.init).sortedByID()
        let bundleTemplateItems = try context.fetch(
            FetchDescriptor<BundleTemplateItem>()
        ).map(BackupBundleTemplateItem.init).sortedByID()
        let attachedBundles = try context.fetch(
            FetchDescriptor<AttachedBundle>()
        ).map(BackupAttachedBundle.init).sortedByID()
        let attachedBundleItems = try context.fetch(
            FetchDescriptor<AttachedBundleItem>()
        ).map(BackupAttachedBundleItem.init).sortedByID()
        let profiles = try context.fetch(FetchDescriptor<Profile>())
            .map(BackupProfile.init).sortedByID()
        let profilePreferences = try context.fetch(
            FetchDescriptor<ProfilePreferences>()
        ).map(BackupProfilePreferences.init).sortedByID()
        let focusSessions = try context.fetch(FetchDescriptor<FocusSession>())
            .map(BackupFocusSession.init).sortedByID()
        let taskRelationships = try context.fetch(
            FetchDescriptor<TaskRelationship>()
        ).map(BackupTaskRelationship.init).sortedByID()
        let notes = try context.fetch(FetchDescriptor<Note>())
            .map(BackupNote.init).sortedByID()
        let preferences = try snapshotPreferences(defaults)

        return AuGendaBackupPayload(
            agendaItems: agendaItems,
            subTasks: subTasks,
            agendaTasks: agendaTasks,
            taskSteps: taskSteps,
            inboxItems: inboxItems,
            userPreferences: userPreferences,
            blocks: blocks,
            blockTasks: blockTasks,
            bundleTemplates: bundleTemplates,
            bundleTemplateItems: bundleTemplateItems,
            attachedBundles: attachedBundles,
            attachedBundleItems: attachedBundleItems,
            profiles: profiles,
            profilePreferences: profilePreferences,
            focusSessions: focusSessions,
            taskRelationships: taskRelationships,
            notes: notes,
            // File-backed histories are ordered ledgers. Preserve their exact
            // sequence; timestamp sorting would change intentionally
            // out-of-order or equal-timestamp entries.
            aiUsageHistory: aiUsageHistory,
            personalizationMemory: personalizationMemory,
            preferences: preferences
        )
    }

    private static func snapshotPreferences(
        _ defaults: UserDefaults
    ) throws -> [AuGendaBackupPreference] {
        try backupPreferenceKeys.compactMap { key in
            guard let value = defaults.object(forKey: key) else { return nil }
            let data: Data
            do {
                data = try PropertyListSerialization.data(
                    fromPropertyList: value,
                    format: .binary,
                    options: 0
                )
            } catch {
                throw AuGendaBackupError.encodingFailed
            }
            return AuGendaBackupPreference(key: key, propertyListData: data)
        }
    }

    private static func decodedPreferences(
        _ preferences: [AuGendaBackupPreference]
    ) throws -> [String: Any] {
        var decoded: [String: Any] = [:]
        for preference in preferences {
            let value: Any
            do {
                value = try PropertyListSerialization.propertyList(
                    from: preference.propertyListData,
                    options: [],
                    format: nil
                )
            } catch {
                throw AuGendaBackupError.incompleteManifest(
                    "preference \(preference.key) is not a valid property list"
                )
            }
            decoded[preference.key] = value
        }
        return decoded
    }

    private static func payloadDigest(
        _ payload: AuGendaBackupPayload
    ) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        let data: Data
        do {
            data = try encoder.encode(payload)
        } catch {
            throw AuGendaBackupError.encodingFailed
        }
        return SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private static func entityCounts(
        for payload: AuGendaBackupPayload
    ) -> [String: Int] {
        [
            "AgendaItem": payload.agendaItems.count,
            "SubTask": payload.subTasks.count,
            "AgendaTask": payload.agendaTasks.count,
            "TaskStep": payload.taskSteps.count,
            "InboxItem": payload.inboxItems.count,
            "UserPreferences": payload.userPreferences.count,
            "Block": payload.blocks.count,
            "BlockTask": payload.blockTasks.count,
            "BundleTemplate": payload.bundleTemplates.count,
            "BundleTemplateItem": payload.bundleTemplateItems.count,
            "AttachedBundle": payload.attachedBundles.count,
            "AttachedBundleItem": payload.attachedBundleItems.count,
            "Profile": payload.profiles.count,
            "ProfilePreferences": payload.profilePreferences.count,
            "FocusSession": payload.focusSessions.count,
            "TaskRelationship": payload.taskRelationships.count,
            "Note": payload.notes.count
        ]
    }

    private static func historyCounts(
        for payload: AuGendaBackupPayload
    ) -> [String: Int] {
        [
            "AIUsageEntry": payload.aiUsageHistory.count,
            "PersonalizationMemoryEntry": payload.personalizationMemory.count
        ]
    }

    private static func validateIdentities(
        _ payload: AuGendaBackupPayload
    ) throws {
        try requireUnique(payload.agendaItems.map(\.clientID), "AgendaItem")
        try requireUnique(payload.subTasks.map(\.clientID), "SubTask")
        try requireUnique(payload.agendaTasks.map(\.clientID), "AgendaTask")
        try requireUnique(payload.taskSteps.map(\.clientID), "TaskStep")
        try requireUnique(payload.inboxItems.map(\.clientID), "InboxItem")
        try requireUnique(payload.userPreferences.map(\.clientID), "UserPreferences")
        try requireUnique(payload.blocks.map(\.clientID), "Block")
        try requireUnique(payload.blockTasks.map(\.clientID), "BlockTask")
        try requireUnique(payload.bundleTemplates.map(\.clientID), "BundleTemplate")
        try requireUnique(payload.bundleTemplateItems.map(\.clientID), "BundleTemplateItem")
        try requireUnique(payload.attachedBundles.map(\.clientID), "AttachedBundle")
        try requireUnique(payload.attachedBundleItems.map(\.clientID), "AttachedBundleItem")
        try requireUnique(payload.profiles.map(\.clientID), "Profile")
        try requireUnique(payload.profilePreferences.map(\.clientID), "ProfilePreferences")
        try requireUnique(payload.focusSessions.map(\.clientID), "FocusSession")
        try requireUnique(payload.taskRelationships.map(\.clientID), "TaskRelationship")
        try requireUnique(payload.notes.map(\.clientID), "Note")
    }

    private static func requireUnique(
        _ ids: [UUID],
        _ entity: String
    ) throws {
        guard Set(ids).count == ids.count else {
            throw AuGendaBackupError.duplicateIdentity(entity)
        }
    }

    private static func validateRelationships(
        _ payload: AuGendaBackupPayload
    ) throws {
        let agendaItemIDs = Set(payload.agendaItems.map(\.clientID))
        let agendaTaskIDs = Set(payload.agendaTasks.map(\.clientID))
        let profileIDs = Set(payload.profiles.map(\.clientID))

        try requireParents(
            payload.subTasks.compactMap(\.parentItemID),
            in: agendaItemIDs,
            relationship: "SubTask.parentItem"
        )
        try requireParents(
            payload.taskSteps.compactMap(\.parentTaskID),
            in: agendaTaskIDs,
            relationship: "TaskStep.parentTask"
        )
        try requireParents(
            payload.blockTasks.compactMap(\.blockID),
            in: Set(payload.blocks.map(\.clientID)),
            relationship: "BlockTask.block"
        )
        try requireParents(
            payload.bundleTemplateItems.compactMap(\.templateID),
            in: Set(payload.bundleTemplates.map(\.clientID)),
            relationship: "BundleTemplateItem.template"
        )
        try requireParents(
            payload.attachedBundles.compactMap(\.blockID),
            in: Set(payload.blocks.map(\.clientID)),
            relationship: "AttachedBundle.block"
        )
        try requireParents(
            payload.attachedBundleItems.compactMap(\.bundleID),
            in: Set(payload.attachedBundles.map(\.clientID)),
            relationship: "AttachedBundleItem.bundle"
        )
        try requireParents(
            payload.profilePreferences.compactMap(\.profileID),
            in: profileIDs,
            relationship: "ProfilePreferences.profile"
        )
        let profileLinks = payload.profilePreferences.compactMap(\.profileID)
        guard Set(profileLinks).count == profileLinks.count else {
            throw AuGendaBackupError.invalidRelationship(
                "more than one ProfilePreferences record targets the same Profile"
            )
        }

        try requireParents(
            payload.agendaItems.compactMap(\.assignedToProfileID)
                + payload.agendaItems.compactMap(\.assignedByProfileID),
            in: profileIDs,
            relationship: "AgendaItem profile assignment"
        )
        try requireParents(
            payload.agendaTasks.compactMap(\.assignedToProfileID)
                + payload.agendaTasks.compactMap(\.assignedByProfileID),
            in: profileIDs,
            relationship: "AgendaTask profile assignment"
        )
        try requireParents(
            payload.agendaItems.compactMap(\.recurrenceParentID),
            in: agendaItemIDs,
            relationship: "AgendaItem.recurrenceParentID"
        )
        try requireParents(
            payload.agendaTasks.compactMap(\.recurrenceParentID),
            in: agendaTaskIDs,
            relationship: "AgendaTask.recurrenceParentID"
        )
        guard payload.agendaItems.allSatisfy({
            $0.recurrenceParentID == nil || $0.recurrenceParentID != $0.clientID
        }) else {
            throw AuGendaBackupError.invalidRelationship(
                "AgendaItem recurrence cannot reference itself"
            )
        }
        guard payload.agendaTasks.allSatisfy({
            $0.recurrenceParentID == nil || $0.recurrenceParentID != $0.clientID
        }) else {
            throw AuGendaBackupError.invalidRelationship(
                "AgendaTask recurrence cannot reference itself"
            )
        }
        try requireParents(
            payload.agendaTasks.compactMap(\.agendaItemID),
            in: agendaItemIDs,
            relationship: "AgendaTask.agendaItemID"
        )
        try requireParents(
            payload.inboxItems.compactMap(\.resolvedTaskID),
            in: agendaTaskIDs,
            relationship: "InboxItem.resolvedTaskID"
        )
        try requireParents(
            payload.inboxItems.compactMap(\.assignedToProfileID),
            in: profileIDs,
            relationship: "InboxItem.assignedToProfileID"
        )
        try requireParents(
            payload.focusSessions.compactMap(\.taskID),
            in: agendaTaskIDs,
            relationship: "FocusSession.taskID"
        )
        try requireParents(
            payload.focusSessions.compactMap(\.profileID),
            in: profileIDs,
            relationship: "FocusSession.profileID"
        )
        try requireParents(
            payload.notes.compactMap(\.relatedTaskID),
            in: agendaTaskIDs,
            relationship: "Note.relatedTaskID"
        )
        try requireParents(
            payload.notes.compactMap(\.relatedItemID),
            in: agendaItemIDs,
            relationship: "Note.relatedItemID"
        )

        let relationshipEndpoints = payload.taskRelationships.flatMap {
            [$0.sourceTaskID, $0.targetTaskID]
        }
        try requireParents(
            relationshipEndpoints,
            in: agendaTaskIDs,
            relationship: "TaskRelationship endpoint"
        )
        guard payload.taskRelationships.allSatisfy({
            $0.sourceTaskID != $0.targetTaskID
        }) else {
            throw AuGendaBackupError.invalidRelationship(
                "TaskRelationship cannot reference the same task twice"
            )
        }
        let relationshipKeys = payload.taskRelationships.map {
            "\($0.sourceTaskID.uuidString)|\($0.targetTaskID.uuidString)|\($0.typeRaw)"
        }
        guard Set(relationshipKeys).count == relationshipKeys.count else {
            throw AuGendaBackupError.invalidRelationship(
                "duplicate TaskRelationship edge"
            )
        }
        guard payload.taskRelationships.allSatisfy({
            TaskRelationshipType(rawValue: $0.typeRaw) != nil
        }) else {
            throw AuGendaBackupError.invalidRelationship(
                "TaskRelationship contains an unsupported type"
            )
        }
        try validateRecurrenceCycles(
            payload.agendaItems.map { ($0.clientID, $0.recurrenceParentID) },
            relationship: "AgendaItem recurrence"
        )
        try validateRecurrenceCycles(
            payload.agendaTasks.map { ($0.clientID, $0.recurrenceParentID) },
            relationship: "AgendaTask recurrence"
        )
        try validateBlockingRelationshipCycles(payload.taskRelationships)
    }

    private static func validateRecurrenceCycles(
        _ links: [(id: UUID, parentID: UUID?)],
        relationship: String
    ) throws {
        let parentByID = Dictionary(
            uniqueKeysWithValues: links.compactMap { link in
                link.parentID.map { (link.id, $0) }
            }
        )
        enum VisitState {
            case visiting
            case visited
        }
        var states: [UUID: VisitState] = [:]

        func visit(_ id: UUID) -> Bool {
            if states[id] == .visiting { return true }
            if states[id] == .visited { return false }
            states[id] = .visiting
            if let parentID = parentByID[id], visit(parentID) {
                return true
            }
            states[id] = .visited
            return false
        }

        for id in parentByID.keys where visit(id) {
            throw AuGendaBackupError.invalidRelationship(
                "\(relationship) contains a cycle"
            )
        }
    }

    private static func validateBlockingRelationshipCycles(
        _ relationships: [BackupTaskRelationship]
    ) throws {
        let blocking = relationships.filter {
            $0.typeRaw == TaskRelationshipType.blocks.rawValue
                || $0.typeRaw == TaskRelationshipType.follows.rawValue
        }
        var adjacency: [UUID: [UUID]] = [:]
        for relationship in blocking {
            adjacency[relationship.sourceTaskID, default: []]
                .append(relationship.targetTaskID)
        }

        enum VisitState {
            case visiting
            case visited
        }
        var states: [UUID: VisitState] = [:]

        func visit(_ id: UUID) -> Bool {
            if states[id] == .visiting { return true }
            if states[id] == .visited { return false }
            states[id] = .visiting
            for target in adjacency[id] ?? [] where visit(target) {
                return true
            }
            states[id] = .visited
            return false
        }

        for id in adjacency.keys where visit(id) {
            throw AuGendaBackupError.invalidRelationship(
                "blocking task relationships contain a cycle"
            )
        }
    }

    private static func requireParents(
        _ parentIDs: [UUID],
        in validIDs: Set<UUID>,
        relationship: String
    ) throws {
        guard parentIDs.allSatisfy(validIDs.contains) else {
            throw AuGendaBackupError.invalidRelationship(
                "\(relationship) points to a missing parent"
            )
        }
    }
}

private protocol BackupIdentified {
    var clientID: UUID { get }
}

extension BackupAgendaItem: BackupIdentified {}
extension BackupSubTask: BackupIdentified {}
extension BackupAgendaTask: BackupIdentified {}
extension BackupTaskStep: BackupIdentified {}
extension BackupInboxItem: BackupIdentified {}
extension BackupUserPreferences: BackupIdentified {}
extension BackupBlock: BackupIdentified {}
extension BackupBlockTask: BackupIdentified {}
extension BackupBundleTemplate: BackupIdentified {}
extension BackupBundleTemplateItem: BackupIdentified {}
extension BackupAttachedBundle: BackupIdentified {}
extension BackupAttachedBundleItem: BackupIdentified {}
extension BackupProfile: BackupIdentified {}
extension BackupProfilePreferences: BackupIdentified {}
extension BackupFocusSession: BackupIdentified {}
extension BackupTaskRelationship: BackupIdentified {}
extension BackupNote: BackupIdentified {}

private extension Array where Element: BackupIdentified {
    func sortedByID() -> [Element] {
        sorted { $0.clientID.uuidString < $1.clientID.uuidString }
    }
}

// MARK: - Atomic persistence boundaries

struct TaskImportSummary: Equatable {
    let insertedCount: Int
    let skippedDuplicateCount: Int
}

@MainActor
enum TaskImportService {
    /// Imports through a dedicated context. A failed fetch or save discards
    /// the entire staging context, leaving the view context and durable store
    /// unchanged.
    static func apply(
        _ tasks: [AgendaTask],
        assignedTo profileID: UUID?,
        using container: ModelContainer
    ) throws -> TaskImportSummary {
        try apply(
            tasks,
            assignedTo: profileID,
            using: container,
            save: { try $0.save() }
        )
    }

    /// Save injection is internal so tests can prove the failure path without
    /// corrupting a real store.
    static func apply(
        _ tasks: [AgendaTask],
        assignedTo profileID: UUID?,
        using container: ModelContainer,
        save: (ModelContext) throws -> Void
    ) throws -> TaskImportSummary {
        let incomingIDs = tasks.map(\.clientID)
        guard Set(incomingIDs).count == incomingIDs.count else {
            throw TaskPortabilityError.duplicateIdentity
        }
        let incomingStepIDs = tasks.flatMap {
            ($0.steps ?? []).map(\.clientID)
        }
        guard Set(incomingStepIDs).count == incomingStepIDs.count else {
            throw TaskPortabilityError.validationFailed([
                .init(
                    severity: .error,
                    row: 1,
                    field: "steps.clientID",
                    message: "step identities must be unique across the import"
                )
            ])
        }

        var graphDiagnostics: [TaskImportDiagnostic] = []
        for (index, task) in tasks.enumerated() {
            for (field, identifier) in [
                ("recurrenceParentID", task.recurrenceParentID),
                ("assignedToProfileID", task.assignedToProfileID),
                ("assignedByProfileID", task.assignedByProfileID),
                ("agendaItemID", task.agendaItemID)
            ] where identifier != nil {
                graphDiagnostics.append(
                    .init(
                        severity: .error,
                        row: index + 1,
                        field: field,
                        message: "detached task-list imports cannot carry external relationship IDs"
                    )
                )
            }
        }
        if !graphDiagnostics.isEmpty {
            throw TaskPortabilityError.validationFailed(graphDiagnostics)
        }

        let stagingContext = ModelContext(container)
        stagingContext.autosaveEnabled = false

        do {
            let existing = try stagingContext.fetch(FetchDescriptor<AgendaTask>())
            let existingIDs = Set(existing.map(\.clientID))
            if let profileID {
                let profileIDs = Set(
                    try stagingContext.fetch(FetchDescriptor<Profile>())
                        .map(\.clientID)
                )
                guard profileIDs.contains(profileID) else {
                    throw TaskPortabilityError.validationFailed([
                        .init(
                            severity: .error,
                            row: 1,
                            field: "assignedToProfileID",
                            message: "the selected destination profile no longer exists"
                        )
                    ])
                }
            }
            let newTasks = tasks.filter {
                !existingIDs.contains($0.clientID)
            }
            let existingStepIDs = Set(
                try stagingContext.fetch(FetchDescriptor<TaskStep>())
                    .map(\.clientID)
            )
            let collidingStepIDs = newTasks.flatMap {
                ($0.steps ?? []).map(\.clientID)
            }.filter(existingStepIDs.contains)
            guard collidingStepIDs.isEmpty else {
                throw TaskPortabilityError.validationFailed([
                    .init(
                        severity: .error,
                        row: 1,
                        field: "steps.clientID",
                        message: "a step identity already exists in saved data"
                    )
                ])
            }
            var insertedCount = 0

            for task in newTasks {
                task.assignedToProfileID = profileID
                stagingContext.insert(task)
                insertedCount += 1
            }

            try save(stagingContext)
            return TaskImportSummary(
                insertedCount: insertedCount,
                skippedDuplicateCount: tasks.count - insertedCount
            )
        } catch {
            stagingContext.rollback()
            throw error
        }
    }
}

@MainActor
enum PersistentMutation {
    static func commit(
        in context: ModelContext,
        changes: () throws -> Void
    ) throws {
        try commit(in: context, changes: changes, save: { try $0.save() })
    }

    /// Ensures callers do not dismiss UI or publish side effects until save
    /// succeeds. Rollback restores the last durable state on any failure.
    static func commit(
        in context: ModelContext,
        changes: () throws -> Void,
        save: (ModelContext) throws -> Void
    ) throws {
        do {
            try changes()
            try save(context)
        } catch {
            context.rollback()
            throw error
        }
    }
}

// MARK: - FileDocument adapter
//
// Lightweight wrapper so the Tasks view can drive `.fileExporter` / `.fileImporter`
// with a single text payload regardless of format.

struct TaskTextFileDocument: FileDocument {
    static var readableContentTypes: [UTType] {
        [.json, .commaSeparatedText, .plainText, .text, .data]
    }
    static var writableContentTypes: [UTType] {
        [.json, .commaSeparatedText, .plainText, .text, .data]
    }

    var text: String

    init(text: String = "") {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        let data = configuration.file.regularFileContents ?? Data()
        self.text = String(data: data, encoding: .utf8) ?? ""
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        guard let data = text.data(using: .utf8) else {
            throw TaskPortabilityError.encodingFailed
        }
        return FileWrapper(regularFileWithContents: data)
    }
}
