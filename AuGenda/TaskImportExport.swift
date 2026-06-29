// TaskImportExport.swift
// AuGenda
//
// Export AgendaTask records to Markdown / JSON / CSV / YAML / plain text,
// and import the same formats back. Designed for backup, sharing, and
// migrating tasks between AuGenda installs or other tools.
//
// Round-trip contract:
// - JSON, YAML, CSV → lossless within the AgendaTask field set we expose
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
import os.log

private let logger = Logger(subsystem: "com.augenda.AuGenda", category: "TaskImportExport")

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

struct TaskExportPayload: Codable {
    let version: Int
    let exportedAt: Date
    let tasks: [ExportedTask]
}

struct ExportedTask: Codable {
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

    init(from task: AgendaTask) {
        self.title           = task.title
        self.notes           = task.notes
        self.frictionLevel   = task.frictionLevel
        self.energyRequired  = task.energyRequired
        self.estimatedMinutes = task.totalEstimatedMinutes
        self.contextTag      = task.contextTag
        self.interestLevel   = task.interestLevel
        self.priority        = task.priority
        self.hyperfocusRisk  = task.hyperfocusRisk
        self.needsBodyDouble = task.needsBodyDouble
        self.waitingOn       = task.waitingOn
        self.dueDate         = task.dueDate
        self.scheduledDate   = task.scheduledDate
        self.isComplete      = task.isComplete
    }

    func toAgendaTask() -> AgendaTask {
        let task = AgendaTask(
            title: title,
            frictionLevel: frictionLevel.clamped(to: 1...5),
            energyRequired: energyRequired.clamped(to: 1...3),
            estimatedMinutes: max(1, estimatedMinutes),
            contextTag: contextTag,
            priority: priority.clamped(to: 0...2),
            interestLevel: interestLevel.clamped(to: 1...5)
        )
        task.notes           = notes
        task.hyperfocusRisk  = hyperfocusRisk
        task.needsBodyDouble = needsBodyDouble
        task.waitingOn       = waitingOn
        task.dueDate         = dueDate
        task.scheduledDate   = scheduledDate
        task.isComplete      = isComplete
        return task
    }
}

private extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int {
        // Qualify with `Swift.` — inside an Int extension, bare `min` / `max`
        // resolve to Int's static properties, not the global functions.
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

// MARK: - Exporter

enum TaskExporter {

    static func export(_ tasks: [AgendaTask], as format: TaskExportFormat) -> String {
        let exported = tasks.map(ExportedTask.init)
        let payload = TaskExportPayload(version: 1, exportedAt: .now, tasks: exported)
        switch format {
        case .json:      return jsonString(payload)
        case .yaml:      return yamlString(payload)
        case .csv:       return csvString(exported)
        case .markdown:  return markdownString(exported)
        case .plainText: return plainTextString(exported)
        }
    }

    // MARK: JSON

    private static func jsonString(_ payload: TaskExportPayload) -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data: Data
        do {
            data = try encoder.encode(payload)
        } catch {
            logger.error("Failed to encode JSON payload: \(error.localizedDescription, privacy: .public)")
            return "{}"
        }
        guard let str = String(data: data, encoding: .utf8) else { return "{}" }
        return str
    }

    // MARK: YAML
    //
    // Hand-rolled — Foundation has no YAML encoder. We control both write and
    // read, so the format only needs to round-trip with itself.

    private static func yamlString(_ payload: TaskExportPayload) -> String {
        let iso = ISO8601DateFormatter()
        var out = "version: \(payload.version)\n"
        out += "exportedAt: \(iso.string(from: payload.exportedAt))\n"
        out += "tasks:\n"
        for task in payload.tasks {
            out += "  - title: \(yamlQuote(task.title))\n"
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
            .replacingOccurrences(of: "\n", with: "\\n")
        return "\"\(escaped)\""
    }

    // MARK: CSV

    private static let csvHeaders = [
        "title", "notes", "frictionLevel", "energyRequired", "estimatedMinutes",
        "contextTag", "interestLevel", "priority", "hyperfocusRisk",
        "needsBodyDouble", "waitingOn", "dueDate", "scheduledDate", "isComplete"
    ]

    private static func csvString(_ tasks: [ExportedTask]) -> String {
        let iso = ISO8601DateFormatter()
        var out = csvHeaders.joined(separator: ",") + "\n"
        for t in tasks {
            let row = [
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
                "\(t.isComplete)"
            ]
            out += row.joined(separator: ",") + "\n"
        }
        return out
    }

    private static func csvEscape(_ s: String) -> String {
        if s.contains(",") || s.contains("\"") || s.contains("\n") {
            return "\"\(s.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return s
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
    // AES-256-GCM with a user-provided password. Salt is prepended to the
    // ciphertext so the same password can decrypt without external state.

    static func encrypt(_ payload: String, password: String) -> String? {
        guard let data = payload.data(using: .utf8) else { return nil }
        guard let passwordData = password.data(using: .utf8) else { return nil }

        // Generate random salt
        var salt = Data(count: 32)
        _ = salt.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 32, $0.baseAddress!) }

        // Derive key: password + salt → SHA-256 → SymmetricKey
        var combined = passwordData
        combined.append(salt)
        let hash = SHA256.hash(data: combined)
        let key = SymmetricKey(data: Data(hash))

        // Encrypt
        let nonce = AES.GCM.Nonce()
        let sealedBox: AES.GCM.SealedBox
        do {
            sealedBox = try AES.GCM.seal(data, using: key, nonce: nonce)
        } catch {
            logger.error("AES encryption failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }

        // Combine: salt + nonce + ciphertext + tag
        var result = salt
        result.append(contentsOf: nonce)
        result.append(sealedBox.ciphertext)
        result.append(sealedBox.tag)
        return result.base64EncodedString()
    }

    static func decrypt(_ base64String: String, password: String) -> String? {
        guard let combined = Data(base64Encoded: base64String) else { return nil }
        guard combined.count > 60 else { return nil }

        let salt = combined.prefix(32)
        let nonceData = combined[32..<44]
        let ciphertext = combined[44..<(combined.count - 16)]
        let tag = combined.suffix(16)

        let nonce: AES.GCM.Nonce
        do {
            nonce = try AES.GCM.Nonce(data: nonceData)
        } catch {
            logger.error("Invalid nonce data: \(error.localizedDescription, privacy: .public)")
            return nil
        }

        guard let passwordData = password.data(using: .utf8) else { return nil }
        var combinedData = passwordData
        combinedData.append(salt)
        let hash = SHA256.hash(data: combinedData)
        let key = SymmetricKey(data: Data(hash))

        let box: AES.GCM.SealedBox
        do {
            box = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ciphertext, tag: tag)
        } catch {
            logger.error("Invalid sealed box: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        let decrypted: Data
        do {
            decrypted = try AES.GCM.open(box, using: key)
        } catch {
            logger.error("AES decryption failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        return String(data: decrypted, encoding: .utf8)
    }
}

// MARK: - Importer

enum TaskImporter {

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
        switch format {
        case .json:      return parseJSON(text)
        case .yaml:      return parseYAML(text)
        case .csv:       return parseCSV(text)
        case .markdown:  return parseMarkdown(text)
        case .plainText: return parsePlainText(text)
        }
    }

    // MARK: JSON

    private static func parseJSON(_ text: String) -> [AgendaTask] {
        guard let data = text.data(using: .utf8) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            let payload = try decoder.decode(TaskExportPayload.self, from: data)
            return payload.tasks.map { $0.toAgendaTask() }
        } catch {
            logger.warning("Failed to decode TaskExportPayload, trying bare array: \(error.localizedDescription, privacy: .public)")
        }
        // Tolerate a bare task array too (no envelope)
        do {
            let tasks = try decoder.decode([ExportedTask].self, from: data)
            return tasks.map { $0.toAgendaTask() }
        } catch {
            logger.warning("Failed to decode bare task array: \(error.localizedDescription, privacy: .public)")
        }
        return []
    }

    // MARK: YAML

    private static func parseYAML(_ text: String) -> [AgendaTask] {
        var tasks: [[String: String]] = []
        var current: [String: String]? = nil

        for rawLine in text.components(separatedBy: "\n") {
            let line = String(rawLine)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            if trimmed.hasPrefix("- title:") {
                if let c = current { tasks.append(c) }
                current = [:]
                let value = trimmed.replacingOccurrences(of: "- title:", with: "").trimmingCharacters(in: .whitespaces)
                current?["title"] = stripYAMLQuotes(value)
            } else if trimmed.contains(":"), current != nil {
                let parts = trimmed.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
                guard parts.count == 2 else { continue }
                let key = String(parts[0]).trimmingCharacters(in: .whitespaces)
                let value = String(parts[1]).trimmingCharacters(in: .whitespaces)
                current?[key] = stripYAMLQuotes(value)
            }
        }
        if let c = current { tasks.append(c) }

        return tasks.compactMap { dict in
            guard let title = dict["title"], !title.isEmpty else { return nil }
            return buildTask(from: dict, title: title)
        }
    }

    private static func stripYAMLQuotes(_ s: String) -> String {
        var s = s
        if s.hasPrefix("\"") && s.hasSuffix("\"") && s.count >= 2 {
            s = String(s.dropFirst().dropLast())
            s = s
                .replacingOccurrences(of: "\\\"", with: "\"")
                .replacingOccurrences(of: "\\\\", with: "\\")
                .replacingOccurrences(of: "\\n", with: "\n")
        }
        return s
    }

    // MARK: CSV

    private static func parseCSV(_ text: String) -> [AgendaTask] {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        guard lines.count > 1 else { return [] }

        let headers = parseCSVLine(lines[0])
        var result: [AgendaTask] = []
        for line in lines.dropFirst() {
            let values = parseCSVLine(line)
            guard values.count == headers.count else { continue }
            var dict: [String: String] = [:]
            for (i, h) in headers.enumerated() { dict[h] = values[i] }
            guard let title = dict["title"], !title.isEmpty else { continue }
            result.append(buildTask(from: dict, title: title))
        }
        return result
    }

    private static func parseCSVLine(_ line: String) -> [String] {
        var result: [String] = []
        var current = ""
        var inQuotes = false
        var i = line.startIndex
        while i < line.endIndex {
            let ch = line[i]
            if ch == "\"" {
                let next = line.index(after: i)
                if inQuotes, next < line.endIndex, line[next] == "\"" {
                    current.append("\"")
                    i = next
                } else {
                    inQuotes.toggle()
                }
            } else if ch == "," && !inQuotes {
                result.append(current)
                current = ""
            } else {
                current.append(ch)
            }
            i = line.index(after: i)
        }
        result.append(current)
        return result
    }

    // MARK: Markdown

    private static func parseMarkdown(_ text: String) -> [AgendaTask] {
        var tasks: [AgendaTask] = []
        for rawLine in text.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("- [") else { continue }
            let isComplete = line.lowercased().hasPrefix("- [x]")
            guard let closeBracket = line.range(of: "]") else { continue }

            let after = line[line.index(after: closeBracket.upperBound)...]
                .trimmingCharacters(in: .whitespaces)

            var title = after
            var meta: [String: String] = [:]

            // Trailing italic-metadata block "— *…*" or "- *…*"
            if let dashRange = after.range(of: " — *") ?? after.range(of: " - *") {
                title = String(after[..<dashRange.lowerBound])
                let metaPart = String(after[dashRange.upperBound...])
                    .replacingOccurrences(of: "*", with: "")
                    .trimmingCharacters(in: .whitespaces)
                for piece in metaPart.components(separatedBy: " · ") {
                    let bit = piece.trimmingCharacters(in: .whitespaces)
                    if bit.hasPrefix("friction:") {
                        meta["frictionLevel"] = String(bit.dropFirst("friction:".count))
                    } else if bit.hasPrefix("energy:") {
                        meta["energyRequired"] = String(bit.dropFirst("energy:".count))
                    } else if bit.hasSuffix("m"), Int(bit.dropLast()) != nil {
                        meta["estimatedMinutes"] = String(bit.dropLast())
                    } else if bit.hasPrefix("@") {
                        meta["contextTag"] = String(bit.dropFirst())
                    } else if bit.hasPrefix("priority:") {
                        meta["priority"] = String(bit.dropFirst("priority:".count))
                    } else if bit == "hyperfocus" {
                        meta["hyperfocusRisk"] = "true"
                    } else if bit == "body-double" {
                        meta["needsBodyDouble"] = "true"
                    } else if bit.hasPrefix("interest:") {
                        meta["interestLevel"] = String(bit.dropFirst("interest:".count))
                    }
                }
            }

            meta["title"] = title
            meta["isComplete"] = "\(isComplete)"
            tasks.append(buildTask(from: meta, title: title))
        }
        return tasks
    }

    // MARK: Plain text

    private static func parsePlainText(_ text: String) -> [AgendaTask] {
        text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { line in
                AgendaTask(
                    title: line,
                    frictionLevel: 3,
                    energyRequired: 2,
                    estimatedMinutes: 15,
                    contextTag: "",
                    priority: 0,
                    interestLevel: 3
                )
            }
    }

    // MARK: Shared dict → AgendaTask

    private static func buildTask(from dict: [String: String], title: String) -> AgendaTask {
        // Clamp to the model's documented ranges so foreign / hand-edited
        // YAML, CSV, or Markdown can't store out-of-range values. Mirrors the
        // JSON path's `ExportedTask.toAgendaTask()` contract (single source of
        // truth for the valid ranges).
        let task = AgendaTask(
            title: title,
            frictionLevel: (Int(dict["frictionLevel"] ?? "") ?? 3).clamped(to: 1...5),
            energyRequired: (Int(dict["energyRequired"] ?? "") ?? 2).clamped(to: 1...3),
            estimatedMinutes: max(1, Int(dict["estimatedMinutes"] ?? "") ?? 15),
            contextTag: dict["contextTag"] ?? "",
            priority: (Int(dict["priority"] ?? "") ?? 0).clamped(to: 0...2),
            interestLevel: (Int(dict["interestLevel"] ?? "") ?? 3).clamped(to: 1...5)
        )
        task.notes           = dict["notes"] ?? ""
        task.hyperfocusRisk  = (dict["hyperfocusRisk"]  ?? "false").lowercased() == "true"
        task.needsBodyDouble = (dict["needsBodyDouble"] ?? "false").lowercased() == "true"
        task.waitingOn       = dict["waitingOn"] ?? ""
        task.isComplete      = (dict["isComplete"]     ?? "false").lowercased() == "true"

        if let due = dict["dueDate"], let date = ISO8601DateFormatter().date(from: due) {
            task.dueDate = date
        }
        if let sched = dict["scheduledDate"], let date = ISO8601DateFormatter().date(from: sched) {
            task.scheduledDate = date
        }
        return task
    }
}

// MARK: - FileDocument adapter
//
// Lightweight wrapper so the Tasks view can drive `.fileExporter` / `.fileImporter`
// with a single text payload regardless of format.

struct TaskTextFileDocument: FileDocument {
    static var readableContentTypes: [UTType] {
        [.json, .commaSeparatedText, .plainText, .text]
    }
    static var writableContentTypes: [UTType] {
        [.json, .commaSeparatedText, .plainText, .text]
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
        FileWrapper(regularFileWithContents: text.data(using: .utf8) ?? Data())
    }
}
