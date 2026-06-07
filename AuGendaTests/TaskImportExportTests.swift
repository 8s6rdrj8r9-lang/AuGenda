// TaskImportExportTests.swift
// AuGendaTests
//
// Locks the spec's explicit beta success criterion: "YAML export round-trips
// (export → human-readable → re-importable)." Also covers JSON and the
// import clamping contract. These were entirely untested before.

import Testing
@testable import AuGenda

@MainActor
struct TaskImportExportTests {

    /// Build a task that exercises the tricky serialization cases: quotes,
    /// a colon, an ampersand, and an embedded newline in `notes`.
    private func sampleTask() -> AgendaTask {
        let t = AgendaTask(
            title: "Call insurance: claim #42",
            frictionLevel: 4,
            energyRequired: 3,
            estimatedMinutes: 25,
            contextTag: "phone",
            priority: 2,
            interestLevel: 2
        )
        t.notes = "Ask about \"deductible\" & timeline\nsecond line"
        t.waitingOn = "callback from rep"
        t.hyperfocusRisk = true
        t.needsBodyDouble = true
        return t
    }

    // MARK: - YAML round-trip (the spec criterion)

    @Test func yamlRoundTripPreservesFields() {
        let original = sampleTask()
        let yaml = TaskExporter.export([original], as: .yaml)
        let parsed = TaskImporter.parse(yaml, as: .yaml)

        #expect(parsed.count == 1)
        guard let r = parsed.first else { return }

        #expect(r.title == original.title)                 // colon + '#' survive
        #expect(r.notes == original.notes)                 // quotes, &, newline survive
        #expect(r.frictionLevel == original.frictionLevel)
        #expect(r.energyRequired == original.energyRequired)
        #expect(r.estimatedMinutes == original.estimatedMinutes)
        #expect(r.contextTag == original.contextTag)
        #expect(r.interestLevel == original.interestLevel)
        #expect(r.priority == original.priority)
        #expect(r.hyperfocusRisk == original.hyperfocusRisk)
        #expect(r.needsBodyDouble == original.needsBodyDouble)
        #expect(r.waitingOn == original.waitingOn)
        #expect(r.isComplete == original.isComplete)
    }

    @Test func yamlIsHumanReadable() {
        let yaml = TaskExporter.export([sampleTask()], as: .yaml)
        // Sanity: the format is the documented key: value shape, not JSON.
        #expect(yaml.contains("version: 1"))
        #expect(yaml.contains("tasks:"))
        #expect(yaml.contains("- title:"))
        #expect(yaml.contains("frictionLevel: 4"))
    }

    @Test func multipleTasksRoundTrip() {
        let a = AgendaTask(title: "First", frictionLevel: 1, interestLevel: 5)
        let b = AgendaTask(title: "Second", frictionLevel: 5, interestLevel: 1)
        let yaml = TaskExporter.export([a, b], as: .yaml)
        let parsed = TaskImporter.parse(yaml, as: .yaml)
        #expect(parsed.count == 2)
        #expect(parsed.map(\.title).sorted() == ["First", "Second"])
    }

    // MARK: - JSON round-trip

    @Test func jsonRoundTripPreservesCoreFields() {
        let original = sampleTask()
        let json = TaskExporter.export([original], as: .json)
        let parsed = TaskImporter.parse(json, as: .json)
        #expect(parsed.count == 1)
        guard let r = parsed.first else { return }
        #expect(r.title == original.title)
        #expect(r.notes == original.notes)
        #expect(r.frictionLevel == original.frictionLevel)
        #expect(r.priority == original.priority)
    }

    // MARK: - Import clamping contract

    @Test func importClampsOutOfRangeValues() {
        // A hostile/foreign YAML with out-of-range numbers must clamp, not crash.
        let yaml = """
        version: 1
        exportedAt: 2026-01-01T00:00:00Z
        tasks:
          - title: "Drifted"
            notes: ""
            frictionLevel: 99
            energyRequired: -3
            estimatedMinutes: 0
            contextTag: ""
            interestLevel: 50
            priority: 9
            hyperfocusRisk: false
            needsBodyDouble: false
            waitingOn: ""
            isComplete: false
        """
        let parsed = TaskImporter.parse(yaml, as: .yaml)
        #expect(parsed.count == 1)
        guard let r = parsed.first else { return }
        #expect((1...5).contains(r.frictionLevel))
        #expect((1...3).contains(r.energyRequired))
        #expect(r.estimatedMinutes >= 1)
        #expect((1...5).contains(r.interestLevel))
        #expect((0...2).contains(r.priority))
    }

    // MARK: - Empty / malformed input is safe

    @Test func emptyInputYieldsNoTasks() {
        #expect(TaskImporter.parse("", as: .yaml).isEmpty)
        #expect(TaskImporter.parse("not yaml at all", as: .yaml).isEmpty)
    }
}
