// TaskBacklogView.swift
// AUDHD Agenda App
//
// Full task backlog with:
// - Three filter modes: All / For Now (smart suggest by energy) / Waiting On
// - Sort: All = sortOrder, For Now = ndPriorityScore descending
// - Add task sheet with all ND-relevant fields
// - Tap row to open TaskDetailView
// - Swipe to abandon or defer

import SwiftUI
import SwiftData

// MARK: - Filter Mode

enum TaskFilter: String, CaseIterable {
    case all = "All"
    case suggest = "For Now"
    case waiting = "Waiting"
}


// MARK: - Task Backlog View

struct TaskBacklogView: View {

    @EnvironmentObject private var profileManager: ActiveProfileManager
    @Query(
        filter: #Predicate<Task> { !$0.isComplete && !$0.isAbandoned },
        sort: \Task.sortOrder
    )
    private var tasks: [Task]

    @State private var filter: TaskFilter = .all
    @State private var showAddTask = false
    @State private var selectedTask: Task? = nil

    private var activeProfileID: UUID? { profileManager.activeProfile?.clientID }
    private var activePrefs: ProfilePreferences? { profileManager.activePreferences }

    private var filteredTasks: [Task] {
        let energyLevel = activePrefs?.currentEnergyLevel ?? 3
        let profileID = activeProfileID

        // Assignment filter: show tasks for active profile or unassigned legacy tasks
        let profileTasks = tasks.filter { task in
            if let assignedID = task.assignedToProfileID {
                return assignedID == profileID
            }
            return true  // unassigned legacy tasks visible to all
        }

        switch filter {
        case .all:
            return profileTasks.filter { $0.isActionable }
        case .suggest:
            return profileTasks
                .filter {
                    $0.isActionable &&
                    $0.frictionLevel <= energyLevel &&
                    $0.energyRequired <= energyLevel
                }
                .sorted { $0.ndPriorityScore > $1.ndPriorityScore }
        case .waiting:
            return profileTasks.filter { !$0.waitingOn.isEmpty }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Filter picker
                Picker("Filter", selection: $filter.animation()) {
                    ForEach(TaskFilter.allCases, id: \.self) { f in
                        Text(f.rawValue).tag(f)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 10)

                if filter == .suggest {
                    // Hand off to SmartSuggestView for the rich single-task UI
                    SmartSuggestView()
                } else {
                    taskList
                }
            }
            .navigationTitle("Tasks")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showAddTask = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .foregroundStyle(Color.appAccent)
                    }
                }
            }
            .sheet(isPresented: $showAddTask) {
                AddTaskView(isPresented: $showAddTask)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
            .sheet(item: $selectedTask) { task in
                TaskDetailView(task: task)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
        }
    }

    // MARK: - Task List

    @ViewBuilder
    private var taskList: some View {
        if filteredTasks.isEmpty {
            emptyState
        } else {
            List {
                ForEach(filteredTasks) { task in
                    Button {
                        selectedTask = task
                    } label: {
                        TaskBacklogRow(task: task, showWaitingOn: filter == .waiting)
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain)
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: filter == .waiting ? "clock.badge.questionmark" : "tray")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text(emptyMessage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var emptyMessage: String {
        switch filter {
        case .all: return "No tasks in the backlog"
        case .suggest: return "No tasks match your energy right now"
        case .waiting: return "Nothing is waiting on anything"
        }
    }
}


// MARK: - Task Backlog Row

struct TaskBacklogRow: View {
    let task: Task
    var showWaitingOn: Bool = false

    @Environment(\.appFont) private var appFont

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                // Priority indicator
                if task.priority >= 2 {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 7, height: 7)
                } else if task.priority == 1 {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 7, height: 7)
                }

                Text(task.title)
                    .font(.app(.body, scheme: appFont))
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)

                Spacer()

                Text("~\(task.totalEstimatedMinutes)m")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            HStack(spacing: 8) {
                FrictionDots(level: task.frictionLevel)

                InterestPips(level: task.interestLevel)

                if !task.contextTag.isEmpty {
                    Text(task.contextTag)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.ultraThinMaterial, in: Capsule())
                        .foregroundStyle(.secondary)
                }

                if task.needsBodyDouble {
                    Image(systemName: "person.2")
                        .font(.caption2)
                        .foregroundStyle(.blue)
                }

                if task.hyperfocusRisk {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }

                if let dueDate = task.dueDate {
                    Text("due \(dueDate.formatted(.dateTime.month(.abbreviated).day()))")
                        .font(.caption2)
                        .foregroundStyle(.red.opacity(0.8))
                }
            }

            if showWaitingOn && !task.waitingOn.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "clock.badge.questionmark")
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                    Text(task.waitingOn)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}


// MARK: - Interest Pips (complement to FrictionDots — shows motivation level)

struct InterestPips: View {
    let level: Int // 1–5

    var body: some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { pip in
                RoundedRectangle(cornerRadius: 1)
                    .fill(pip <= level ? interestColor : Color.secondary.opacity(0.15))
                    .frame(width: 4, height: 8)
            }
        }
    }

    private var interestColor: Color {
        switch level {
        case 1, 2: return .gray
        case 3: return .yellow
        case 4: return .green
        default: return .cyan
        }
    }
}


// MARK: - Add Task View

struct AddTaskView: View {

    @Binding var isPresented: Bool
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var profileManager: ActiveProfileManager
    @Query(sort: \Profile.sortOrder) private var profiles: [Profile]

    @State private var title = ""
    @State private var notes = ""
    @State private var frictionLevel = 3
    @State private var interestLevel = 3
    @State private var energyRequired = 2
    @State private var estimatedMinutes = 15
    @State private var contextTag = ""
    @State private var waitingOn = ""
    @State private var hyperfocusRisk = false
    @State private var needsBodyDouble = false
    @State private var priority = 0
    @State private var dueDate: Date? = nil
    @State private var showDueDatePicker = false
    @State private var assignedToProfileID: UUID? = nil

    private var activeProfile: Profile? { profileManager.activeProfile }
    private var canAssign: Bool { (activeProfile?.canAssignTasks == true) && profiles.count > 1 }

    // Common context tags for quick selection
    private let contextOptions = ["home", "computer", "phone", "outside", "focus", "errand"]

    var body: some View {
        NavigationStack {
            Form {

                // ── Title ──
                Section {
                    TextField("What needs doing?", text: $title, axis: .vertical)
                        .font(.body)
                        .lineLimit(1...4)
                }

                // ── Time estimate ──
                Section("Roughly how long?") {
                    HStack(spacing: 8) {
                        ForEach([5, 15, 30, 60], id: \.self) { min in
                            Button {
                                estimatedMinutes = min
                            } label: {
                                Text("\(min)m")
                                    .font(.subheadline)
                                    .fontWeight(estimatedMinutes == min ? .semibold : .regular)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(
                                        estimatedMinutes == min
                                            ? Color.appAccent.opacity(0.2)
                                            : Color.secondary.opacity(0.08),
                                        in: RoundedRectangle(cornerRadius: 8)
                                    )
                                    .foregroundStyle(estimatedMinutes == min ? Color.appAccent : .secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Stepper("Custom: \(estimatedMinutes) min", value: $estimatedMinutes, in: 1...480, step: 5)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // ── How does it feel? ──
                Section("How does it feel?") {
                    VStack(alignment: .leading, spacing: 12) {
                        LabeledContent("Friction (how hard to start)") {
                            Picker("Friction", selection: $frictionLevel) {
                                Text("1 Easy").tag(1)
                                Text("2").tag(2)
                                Text("3 Med").tag(3)
                                Text("4").tag(4)
                                Text("5 Wall").tag(5)
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 220)
                        }

                        LabeledContent("Interest level") {
                            Picker("Interest", selection: $interestLevel) {
                                Text("1 Ugh").tag(1)
                                Text("2").tag(2)
                                Text("3 OK").tag(3)
                                Text("4").tag(4)
                                Text("5 Fun").tag(5)
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 220)
                        }

                        LabeledContent("Energy needed") {
                            Picker("Energy", selection: $energyRequired) {
                                Text("Low").tag(1)
                                Text("Med").tag(2)
                                Text("High").tag(3)
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 160)
                        }
                    }
                }

                // ── Priority ──
                Section("Priority") {
                    Picker("Priority", selection: $priority) {
                        Text("Normal").tag(0)
                        Text("High").tag(1)
                        Text("Urgent").tag(2)
                    }
                    .pickerStyle(.segmented)
                }

                // ── Context ──
                Section("Context") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(contextOptions, id: \.self) { tag in
                                Button {
                                    contextTag = contextTag == tag ? "" : tag
                                } label: {
                                    Text(tag)
                                        .font(.caption)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(
                                            contextTag == tag
                                                ? Color.appAccent.opacity(0.2)
                                                : Color.secondary.opacity(0.1),
                                            in: Capsule()
                                        )
                                        .foregroundStyle(contextTag == tag ? Color.appAccent : .secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    TextField("Or type your own", text: $contextTag)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // ── Flags ──
                Section("Flags") {
                    Toggle(isOn: $hyperfocusRisk) {
                        Label("Hyperfocus risk", systemImage: "exclamationmark.triangle")
                    }
                    Toggle(isOn: $needsBodyDouble) {
                        Label("Body double helps", systemImage: "person.2")
                    }
                }

                // ── Waiting on ──
                Section("Blocked by") {
                    TextField("Waiting on… (person, event, info)", text: $waitingOn)
                }

                // ── Due date (optional) ──
                Section("Due date (optional)") {
                    Toggle("Has a deadline", isOn: $showDueDatePicker.animation())
                    if showDueDatePicker {
                        DatePicker(
                            "Due",
                            selection: Binding(
                                get: { dueDate ?? .now },
                                set: { dueDate = $0 }
                            ),
                            displayedComponents: [.date]
                        )
                    }
                }

                // ── Assign to ──
                if canAssign {
                    Section("Assign to") {
                        ForEach(profiles) { profile in
                            Button {
                                assignedToProfileID = profile.clientID
                            } label: {
                                HStack(spacing: 12) {
                                    ProfileAvatarView(profile: profile, size: 28)
                                    Text(profile.name).foregroundStyle(.primary)
                                    Spacer()
                                    if assignedToProfileID == profile.clientID {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(Color.appAccent)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                // ── Notes ──
                Section("Notes") {
                    TextField("Any extra context…", text: $notes, axis: .vertical)
                        .lineLimit(3...8)
                }
            }
            .navigationTitle("New Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { save() }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                        .fontWeight(.semibold)
                }
            }
            .onAppear { onAppear() }
        }
    }

    private func save() {
        let task = Task(
            title: title.trimmingCharacters(in: .whitespaces),
            frictionLevel: frictionLevel,
            energyRequired: energyRequired,
            estimatedMinutes: estimatedMinutes,
            contextTag: contextTag,
            priority: priority,
            interestLevel: interestLevel
        )
        task.notes = notes
        task.hyperfocusRisk = hyperfocusRisk
        task.needsBodyDouble = needsBodyDouble
        task.waitingOn = waitingOn
        if showDueDatePicker { task.dueDate = dueDate }
        task.assignedToProfileID = assignedToProfileID
        if assignedToProfileID != activeProfile?.clientID {
            task.assignedByProfileID = activeProfile?.clientID
        }
        modelContext.insert(task)
        try? modelContext.save()
        isPresented = false
    }

    // MARK: Lifecycle

    func onAppear() {
        assignedToProfileID = activeProfile?.clientID
    }
}
