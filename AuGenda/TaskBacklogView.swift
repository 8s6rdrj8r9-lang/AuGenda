// TaskBacklogView.swift
// AUDHD Agenda App
//
// Full task backlog with:
// - Three filter modes: All / For Now (energy-matched, ndPriorityScore ranked) / Waiting On
// - Control bar: EnergyFilterBanner (For Now) + sort picker (All)
// - Add task sheet with all ND-relevant fields
// - Tap row to open TaskDetailView sheet
// - Design-system styled rows: AgendaTaskCard (inline component, AgendaTask-typed)

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// MARK: - Filter & Sort Mode

enum TaskFilter: String, CaseIterable {
    case all     = "All"
    case suggest = "For Now"
    case waiting = "Waiting"
}

enum BacklogSortMode: String, CaseIterable {
    case sortOrder    = "Manual"
    case ndPriority   = "ND Priority"
    case dueDate      = "Due Date"
    case friction     = "Easiest First"
}


// MARK: - Task Backlog View

struct TaskBacklogView: View {

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var profileManager: ActiveProfileManager
    @Query(
        filter: #Predicate<AgendaTask> { !$0.isComplete && !$0.isAbandoned },
        sort: \AgendaTask.sortOrder
    )
    private var tasks: [AgendaTask]

    @State private var filter: TaskFilter = .all
    @State private var sortMode: BacklogSortMode = .ndPriority
    @State private var energyLevel: Int = 3
    @State private var showAddTask = false
    @State private var showBrainDump = false
    @State private var selectedTask: AgendaTask? = nil

    // Import / Export state
    @State private var showExporter = false
    @State private var showImporter = false
    @State private var exportDocument = TaskTextFileDocument()
    @State private var exportFormat: TaskExportFormat = .markdown
    @State private var importFeedback: String? = nil

    private var activeProfileID: UUID? { profileManager.activeProfile?.clientID }
    private var activePrefs: ProfilePreferences? { profileManager.activePreferences }

    // MARK: Derived data

    private var profileTasks: [AgendaTask] {
        let profileID = activeProfileID
        return tasks.filter { task in
            if let assignedID = task.assignedToProfileID {
                return assignedID == profileID
            }
            return true  // unassigned legacy tasks visible to all
        }
    }

    private var filteredTasks: [AgendaTask] {
        switch filter {
        case .all:
            return sorted(profileTasks.filter { $0.isActionable })
        case .suggest:
            return profileTasks
                .filter {
                    $0.isActionable &&
                    $0.frictionLevel <= max(energyLevel, 2) &&
                    $0.energyRequired <= energyLevel
                }
                .sorted { $0.ndPriorityScore > $1.ndPriorityScore }
        case .waiting:
            return profileTasks.filter { !$0.waitingOn.isEmpty }
        }
    }

    private var hiddenCount: Int {
        profileTasks.filter { $0.isActionable }.count - filteredTasks.count
    }

    private func sorted(_ items: [AgendaTask]) -> [AgendaTask] {
        switch sortMode {
        case .sortOrder:
            return items  // already sorted by @Query
        case .ndPriority:
            return items.sorted { $0.ndPriorityScore > $1.ndPriorityScore }
        case .dueDate:
            return items.sorted {
                switch ($0.dueDate, $1.dueDate) {
                case let (a?, b?): return a < b
                case (_?, nil):   return true   // has date sorts before nil
                default:          return false
                }
            }
        case .friction:
            return items.sorted { $0.frictionLevel < $1.frictionLevel }
        }
    }

    // MARK: - Import / Export

    /// Default filename presented in the system Save dialog. Includes today's
    /// date so the user can tell exports apart at a glance.
    private var defaultExportFilename: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return "AuGenda-tasks-\(formatter.string(from: .now)).\(exportFormat.fileExtension)"
    }

    /// Gather every actionable AgendaTask for the active profile, serialize
    /// in the chosen format, and trigger the system file-exporter. The actual
    /// "Save to…" dialog is presented by `.fileExporter`.
    private func beginExport(format: TaskExportFormat) {
        let allForProfile = profileTasks
            .sorted { $0.sortOrder < $1.sortOrder }
        let payload = TaskExporter.export(allForProfile, as: format)

        exportFormat = format
        exportDocument = TaskTextFileDocument(text: payload)
        showExporter = true
    }

    /// Read the picked file, detect format from its extension, parse, and
    /// append-insert the resulting AgendaTasks into the model context. The
    /// importer never deletes existing data — duplicates are accepted.
    private func handleImportResult(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            importFeedback = "Import failed: \(error.localizedDescription)"

        case .success(let urls):
            guard let url = urls.first else { return }

            // Security-scoped access — required when the file is outside the
            // app's sandbox (which it almost always is for user-picked files).
            let needsScope = url.startAccessingSecurityScopedResource()
            defer { if needsScope { url.stopAccessingSecurityScopedResource() } }

            guard let format = TaskImporter.detectFormat(filename: url.lastPathComponent) else {
                importFeedback = "Couldn't detect the file format from the extension. Supported: .json .yaml .yml .csv .md .markdown .txt"
                return
            }
            guard let data = try? Data(contentsOf: url),
                  let text = String(data: data, encoding: .utf8) else {
                importFeedback = "Couldn't read the file."
                return
            }

            let imported = TaskImporter.parse(text, as: format)
            guard !imported.isEmpty else {
                importFeedback = "No tasks found in the file."
                return
            }

            let profileID = profileManager.activeProfile?.clientID
            for task in imported {
                task.assignedToProfileID = profileID
                modelContext.insert(task)
            }
            try? modelContext.save()
            importFeedback = "Imported \(imported.count) task\(imported.count == 1 ? "" : "s") from \(format.displayName)."
        }
    }

    // MARK: Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                filterBar

                // Control bar — energy (For Now) or sort (All/Waiting)
                if filter == .suggest {
                    EnergyFilterBanner(
                        energyLevel: $energyLevel,
                        filteredOutCount: hiddenCount
                    )
                } else {
                    sortBar
                }

                Divider()

                if filteredTasks.isEmpty {
                    emptyState
                } else {
                    taskList
                }
            }
            .navigationTitle("Tasks")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            #endif
            .toolbar {
                // Brain dump — fast batch add for the racing-thoughts moment.
                // Sits LEFT of the detailed-add button so it reads first; this
                // is the lower-friction path and should be the easier reach.
                ToolbarItem(placement: {
                    #if os(iOS)
                    return .navigationBarTrailing
                    #else
                    return .primaryAction
                    #endif
                }()) {
                    Button {
                        showBrainDump = true
                    } label: {
                        Image(systemName: "brain.head.profile")
                            .font(.title2)
                            .foregroundStyle(Tokens.Color.primary)
                    }
                    .accessibilityLabel("Brain dump — add many tasks at once")
                }

                // Detailed single-task add.
                ToolbarItem(placement: {
                    #if os(iOS)
                    return .navigationBarTrailing
                    #else
                    return .primaryAction
                    #endif
                }()) {
                    Button {
                        showAddTask = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .foregroundStyle(Tokens.Color.primary)
                    }
                    .accessibilityLabel("Add a single task with full detail")
                }

                // Import / Export menu — lower frequency than the two adds,
                // so a single Menu (popover) instead of a third button.
                ToolbarItem(placement: {
                    #if os(iOS)
                    return .navigationBarTrailing
                    #else
                    return .primaryAction
                    #endif
                }()) {
                    Menu {
                        Section("Export") {
                            ForEach(TaskExportFormat.allCases) { format in
                                Button(format.displayName) {
                                    beginExport(format: format)
                                }
                            }
                        }
                        Section("Import") {
                            Button {
                                showImporter = true
                            } label: {
                                Label("From file…", systemImage: "tray.and.arrow.down")
                            }
                        }
                    } label: {
                        Image(systemName: "tray.and.arrow.up")
                            .font(.title2)
                            .foregroundStyle(Tokens.Color.primary)
                    }
                    .accessibilityLabel("Import or export tasks")
                }
            }
            .sheet(isPresented: $showAddTask) {
                AddTaskView(isPresented: $showAddTask)
                #if os(iOS)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                #endif
            }
            .sheet(isPresented: $showBrainDump) {
                BrainDumpView(isPresented: $showBrainDump)
                #if os(iOS)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                #endif
            }
            .fileExporter(
                isPresented: $showExporter,
                document: exportDocument,
                contentType: exportFormat.contentType,
                defaultFilename: defaultExportFilename
            ) { result in
                // Silent on success; surface error via the same banner the
                // importer uses. Future v2: small confirmation toast.
                if case .failure(let error) = result {
                    importFeedback = "Export failed: \(error.localizedDescription)"
                }
            }
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [.json, .commaSeparatedText, .plainText, .text],
                allowsMultipleSelection: false
            ) { result in
                handleImportResult(result)
            }
            .alert(
                "Import",
                isPresented: Binding(
                    get: { importFeedback != nil },
                    set: { if !$0 { importFeedback = nil } }
                ),
                presenting: importFeedback
            ) { _ in
                Button("OK", role: .cancel) { importFeedback = nil }
            } message: { msg in
                Text(msg)
            }
            .sheet(item: $selectedTask) { task in
                TaskDetailView(task: task)
                #if os(iOS)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                #endif
            }
        }
        .onAppear {
            energyLevel = activePrefs?.currentEnergyLevel ?? 3
            InterruptionContext.recordActivity(contextLabel: "browsing tasks")
        }
    }

    // MARK: - Sort Bar (All / Waiting modes)

    private var sortBar: some View {
        HStack(spacing: Tokens.Spacing.sm) {
            Text("Sort:")
                .font(Tokens.Typography.caption)
                .foregroundColor(Color.appTextSecondary)

            ForEach(BacklogSortMode.allCases, id: \.self) { mode in
                Button {
                    withAnimation(Tokens.Animation.standardEase()) {
                        sortMode = mode
                    }
                } label: {
                    Text(mode.rawValue)
                        .font(Tokens.Typography.caption)
                        .fontWeight(sortMode == mode ? .semibold : .regular)
                        .padding(.horizontal, Tokens.Spacing.sm)
                        .padding(.vertical, Tokens.Spacing.xs)
                        .background(
                            sortMode == mode
                                ? Tokens.Color.primary.opacity(0.12)
                                : Color.clear
                        )
                        .foregroundColor(
                            sortMode == mode
                                ? Tokens.Color.primary
                                : Color.appTextSecondary
                        )
                        .cornerRadius(Tokens.Border.radiusSmall)
                }
                .buttonStyle(.plain)
            }

            Spacer()

            Text("\(filteredTasks.count) task\(filteredTasks.count == 1 ? "" : "s")")
                .font(Tokens.Typography.caption)
                .foregroundColor(Color.appTextSecondary)
        }
        .padding(.horizontal, Tokens.Spacing.base)
        .padding(.vertical, Tokens.Spacing.sm)
        .background(Color.appBackgroundSecondary)
    }

    // MARK: - Filter Bar

    /// Custom tab row replacing the system segmented picker.
    /// Uses typography + background-shift for state, not borders.
    /// Each tab is at least 44pt tall for accessible tap targets.
    private var filterBar: some View {
        HStack(spacing: 0) {
            ForEach(TaskFilter.allCases, id: \.self) { mode in
                Button {
                    withAnimation(Tokens.Animation.standardEase()) {
                        filter = mode
                    }
                } label: {
                    Text(mode.rawValue)
                        .font(Tokens.Typography.label)
                        .fontWeight(filter == mode ? .semibold : .regular)
                        .foregroundColor(
                            filter == mode
                                ? Color.appAccent
                                : Color.appTextSecondary
                        )
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: Tokens.Spacing.touchMinimum)
                        .background(
                            filter == mode
                                ? Color.appAccent.opacity(0.08)
                                : Color.clear
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .background(Color.appBackgroundSecondary)
    }

    // MARK: - Task List

    @ViewBuilder
    private var taskList: some View {
        ScrollView {
            LazyVStack(spacing: Tokens.Spacing.xl) {
                ForEach(filteredTasks) { task in
                    AgendaTaskCard(task: task, showWaitingOn: filter == .waiting) {
                        selectedTask = task
                        InterruptionContext.recordActivity(
                            itemID: task.clientID,
                            contextLabel: "task detail"
                        )
                    }
                }
            }
            .padding(.horizontal, Tokens.Spacing.base)
            .padding(.vertical, Tokens.Spacing.md)
        }
    }

    // MARK: - Empty State

    @ViewBuilder
    private var emptyState: some View {
        EmptyState(
            icon: filter == .waiting ? "clock.badge.questionmark" : "tray",
            title: emptyTitle,
            message: emptyMessage,
            action: filter == .all ? { showAddTask = true } : nil,
            actionLabel: filter == .all ? "Add Task" : nil
        )
    }

    private var emptyTitle: String {
        switch filter {
        case .all:     return "Backlog is clear"
        case .suggest: return "No tasks for right now"
        case .waiting: return "Nothing waiting"
        }
    }

    private var emptyMessage: String {
        switch filter {
        case .all:     return "Add your first task to get started."
        case .suggest: return "Try raising your energy level, or add an easy task."
        case .waiting: return "No tasks are blocked by anything."
        }
    }
}


// MARK: - Agenda Task Card (AgendaTask-typed design system card)
//
// Distinct from TaskCard (which takes AgendaItem) — this binds to AgendaTask
// to expose ndPriorityScore, waitingOn, and the full task field set.

struct AgendaTaskCard: View {
    let task: AgendaTask
    var showWaitingOn: Bool = false
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 0) {
                // Priority accent bar — full height, flush to left edge, clipped by clipShape
                if task.priority > 0 {
                    Rectangle()
                        .fill(priorityColor)
                        .frame(width: 3)
                }

                VStack(alignment: .leading, spacing: Tokens.Spacing.sm) {

                    // ── Title row ──
                    // h3 (16pt semibold) + bold override = clear typographic anchor;
                    // time estimate trails at caption weight so it doesn't compete.
                    HStack(alignment: .firstTextBaseline, spacing: Tokens.Spacing.sm) {
                        Text(task.title)
                            .font(Tokens.Typography.h3)
                            .fontWeight(.bold)
                            .foregroundColor(Color.appTextPrimary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)

                        Spacer(minLength: 0)

                        Text("~\(task.totalEstimatedMinutes)m")
                            .font(Tokens.Typography.caption)
                            .foregroundColor(Color.appTextSecondary)
                    }

                    // ── Status row ──
                    // Whole row at 0.8 opacity so it recedes behind the title.
                    // Layout: context tag + flags (left) → spacer → dots + date (right).
                    // This pushes the dot indicators to the trailing edge as quiet status.
                    HStack(alignment: .center, spacing: Tokens.Spacing.sm) {

                        if !task.contextTag.isEmpty {
                            Text(task.contextTag)
                                .font(Tokens.Typography.caption)
                                .foregroundColor(Color.appTextSecondary)
                        }

                        if task.needsBodyDouble {
                            Image(systemName: "person.wave.2.fill")
                                .font(.system(size: 10, weight: .regular))
                                .foregroundColor(Tokens.Color.info)
                        }

                        if task.hyperfocusRisk {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 10, weight: .regular))
                                .foregroundColor(Tokens.Color.warning)
                        }

                        Spacer(minLength: 0)

                        // Dots trail right — readable at a glance, not visually competing
                        FrictionDots(level: task.frictionLevel)
                        EnergyDots(level: task.energyRequired)
                        InterestPips(level: task.interestLevel)

                        if let dueDate = task.dueDate {
                            Text(dueDate.formatted(.dateTime.month(.abbreviated).day()))
                                .font(Tokens.Typography.caption)
                                .foregroundColor(dueDateColor(dueDate))
                        }
                    }
                    .opacity(0.8)

                    // ── Waiting-on row (Waiting filter only) ──
                    if showWaitingOn && !task.waitingOn.isEmpty {
                        HStack(spacing: Tokens.Spacing.xs) {
                            Image(systemName: "clock.badge.questionmark")
                                .font(.system(size: 10))
                                .foregroundColor(Tokens.Color.warning)
                            Text(task.waitingOn)
                                .font(Tokens.Typography.caption)
                                .foregroundColor(Color.appTextSecondary)
                                .lineLimit(1)
                        }
                        .opacity(0.8)
                    }
                }
                // Uniform lg padding (24pt) — generous whitespace is the primary organizer
                .padding(Tokens.Spacing.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            // Subtle surface: secondary background distinguishes panel from page; no border needed
            .background(Color.appBackgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: Tokens.Border.radiusMedium))
        }
        .buttonStyle(.plain)
    }

    private var priorityColor: Color {
        switch task.priority {
        case 2: return Tokens.Color.warning
        case 1: return Tokens.Color.info
        default: return Color.clear
        }
    }

    private func dueDateColor(_ date: Date) -> Color {
        let days = Calendar.current.dateComponents([.day], from: .now, to: date).day ?? 0
        if days < 0  { return Tokens.Color.warning }
        if days <= 1 { return Tokens.Color.warning }
        return Color.appTextSecondary
    }
}


// MARK: - Interest Pips (motivation level indicator)

struct InterestPips: View {
    let level: Int // 1–5

    var body: some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { pip in
                RoundedRectangle(cornerRadius: 1)
                    .fill(pip <= level ? interestColor : Color.appBorder.opacity(0.5))
                    .frame(width: 4, height: 8)
            }
        }
        .accessibilityLabel("Interest level: \(level) of 5")
    }

    private var interestColor: Color {
        switch level {
        case 1, 2: return Color.appTextSecondary
        case 3:    return Tokens.Color.warning
        case 4:    return Tokens.Color.success
        default:   return Tokens.Color.info
        }
    }
}


// MARK: - Add Task View

struct AddTaskView: View {

    @Binding var isPresented: Bool
    var editingTask: AgendaTask? = nil

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

    private let contextOptions = ["home", "computer", "phone", "outside", "focus", "errand"]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {

                // ── Sticky top action bar ─────────────────────────
                // Guarantees Cancel + Add are reachable even when the form
                // is taller than the window (the macOS .toolbar bottom-strip
                // can scroll off and trap the user).
                HStack(spacing: Tokens.Spacing.base) {
                    Button("Cancel") { isPresented = false }
                        .buttonStyle(.bordered)
                        .keyboardShortcut(.cancelAction)

                    Spacer()

                    Text(editingTask != nil ? "Edit Task" : "New Task")
                        .font(Tokens.Typography.h3)
                        .foregroundColor(Color.appTextPrimary)

                    Spacer()

                    Button(editingTask != nil ? "Save" : "Add") { save() }
                        .buttonStyle(.borderedProminent)
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                        .keyboardShortcut(.defaultAction)
                }
                .padding(.horizontal, Tokens.Spacing.base)
                .padding(.vertical, Tokens.Spacing.sm)
                .background(Color.appBackgroundSecondary)

                Form {

                // ── Title ──
                Section {
                    TextField("What needs doing?", text: $title, axis: .vertical)
                        .font(Tokens.Typography.body)
                        .lineLimit(1...4)
                }

                // ── Time estimate ──
                Section("Roughly how long?") {
                    HStack(spacing: Tokens.Spacing.sm) {
                        ForEach([5, 15, 30, 60], id: \.self) { min in
                            Button {
                                estimatedMinutes = min
                            } label: {
                                Text("\(min)m")
                                    .font(Tokens.Typography.label)
                                    .fontWeight(estimatedMinutes == min ? .semibold : .regular)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, Tokens.Spacing.sm)
                                    .background(
                                        estimatedMinutes == min
                                            ? Tokens.Color.primary.opacity(0.15)
                                            : Color.appBackgroundSecondary,
                                        in: RoundedRectangle(cornerRadius: Tokens.Border.radiusSmall)
                                    )
                                    .foregroundColor(
                                        estimatedMinutes == min
                                            ? Tokens.Color.primary
                                            : Color.appTextSecondary
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Stepper("Custom: \(estimatedMinutes) min", value: $estimatedMinutes, in: 1...480, step: 5)
                        .font(Tokens.Typography.caption)
                        .foregroundColor(Color.appTextSecondary)
                }

                // ── How does it feel? ──
                Section("How does it feel?") {
                    VStack(alignment: .leading, spacing: Tokens.Spacing.md) {
                        LabeledContent("Friction (hard to start)") {
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
                        HStack(spacing: Tokens.Spacing.sm) {
                            ForEach(contextOptions, id: \.self) { tag in
                                Button {
                                    contextTag = contextTag == tag ? "" : tag
                                } label: {
                                    Text(tag)
                                        .font(Tokens.Typography.caption)
                                        .padding(.horizontal, Tokens.Spacing.sm)
                                        .padding(.vertical, Tokens.Spacing.xs)
                                        .background(
                                            contextTag == tag
                                                ? Tokens.Color.primary.opacity(0.15)
                                                : Color.appBackgroundSecondary,
                                            in: Capsule()
                                        )
                                        .foregroundColor(
                                            contextTag == tag
                                                ? Tokens.Color.primary
                                                : Color.appTextSecondary
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    TextField("Or type your own", text: $contextTag)
                        .font(Tokens.Typography.caption)
                        .foregroundColor(Color.appTextSecondary)
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

                // ── Due date ──
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
                                HStack(spacing: Tokens.Spacing.md) {
                                    ProfileAvatarView(profile: profile, size: 28)
                                    Text(profile.name).foregroundColor(Color.appTextPrimary)
                                    Spacer()
                                    if assignedToProfileID == profile.clientID {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(Tokens.Color.primary)
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
                }   // closes Form
                .formStyle(.grouped)   // macOS-native label/control layout
            }   // closes outer VStack
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .onAppear {
                if let task = editingTask {
                    title              = task.title
                    notes              = task.notes
                    frictionLevel      = task.frictionLevel
                    interestLevel      = task.interestLevel
                    energyRequired     = task.energyRequired
                    estimatedMinutes   = task.estimatedMinutes
                    contextTag         = task.contextTag
                    waitingOn          = task.waitingOn
                    hyperfocusRisk     = task.hyperfocusRisk
                    needsBodyDouble    = task.needsBodyDouble
                    priority           = task.priority
                    assignedToProfileID = task.assignedToProfileID
                    if let due = task.dueDate {
                        dueDate = due
                        showDueDatePicker = true
                    }
                } else {
                    assignedToProfileID = activeProfile?.clientID
                }
            }
        }
    }

    private func save() {
        if let task = editingTask {
            task.title            = title.trimmingCharacters(in: .whitespaces)
            task.notes            = notes
            task.frictionLevel    = frictionLevel
            task.energyRequired   = energyRequired
            task.estimatedMinutes = estimatedMinutes
            task.contextTag       = contextTag
            task.priority         = priority
            task.interestLevel    = interestLevel
            task.hyperfocusRisk   = hyperfocusRisk
            task.needsBodyDouble  = needsBodyDouble
            task.waitingOn        = waitingOn
            task.dueDate          = showDueDatePicker ? dueDate : nil
            task.assignedToProfileID = assignedToProfileID
            if assignedToProfileID != activeProfile?.clientID {
                task.assignedByProfileID = activeProfile?.clientID
            }
            task.updatedAt = .now
        } else {
            let task = AgendaTask(
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
        }
        try? modelContext.save()
        isPresented = false
    }
}


// MARK: - Brain Dump View
//
// Batch task entry for the racing-thoughts moment. One thought per line,
// no friction/energy/context prompts — every line becomes an AgendaTask
// with sensible defaults. The user can refine each task later via the
// existing edit flow. Designed for ND users in a low-EF state: zero
// required decisions, large text surface, reassuring microcopy.

struct BrainDumpView: View {

    @Binding var isPresented: Bool
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var profileManager: ActiveProfileManager

    @State private var text: String = ""
    @FocusState private var editorFocused: Bool

    /// Non-empty, trimmed lines — each becomes one task.
    private var lines: [String] {
        text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private var countLabel: String {
        switch lines.count {
        case 0:  return "No thoughts yet"
        case 1:  return "1 thought"
        default: return "\(lines.count) thoughts"
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {

                // ── Sticky top action bar ────────────────────────
                // Same pattern as AddTaskView's sticky bar so Cancel + Add
                // are always reachable even when the keyboard takes the
                // bottom of the screen.
                HStack(spacing: Tokens.Spacing.base) {
                    Button("Cancel") { isPresented = false }
                        .buttonStyle(.bordered)
                        .keyboardShortcut(.cancelAction)

                    Spacer()

                    VStack(spacing: 0) {
                        Text("Brain dump")
                            .font(Tokens.Typography.h3)
                            .foregroundColor(Color.appTextPrimary)
                        Text(countLabel)
                            .font(Tokens.Typography.caption)
                            .foregroundColor(Color.appTextSecondary)
                    }

                    Spacer()

                    Button("Add all") { saveAll() }
                        .buttonStyle(.borderedProminent)
                        .disabled(lines.isEmpty)
                        .keyboardShortcut(.defaultAction)
                }
                .padding(.horizontal, Tokens.Spacing.base)
                .padding(.vertical, Tokens.Spacing.sm)
                .background(Color.appBackgroundSecondary)

                // ── Reassurance copy ─────────────────────────────
                // ND-friendly framing: explicit permission to skip the
                // detail. Keeps the executive load to "type, save."
                Text("One thought per line. Skip the detail — friction, energy, time, context all get sensible defaults. Refine later, or never.")
                    .font(Tokens.Typography.caption)
                    .foregroundColor(Color.appTextSecondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Tokens.Spacing.base)
                    .padding(.top, Tokens.Spacing.sm)
                    .padding(.bottom, Tokens.Spacing.xs)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // ── Editor ───────────────────────────────────────
                TextEditor(text: $text)
                    .focused($editorFocused)
                    .font(Tokens.Typography.body)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, Tokens.Spacing.sm)
                    .background(Color.appBackground)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .onAppear {
                // Focus the editor immediately — capture before the thought
                // evaporates is the whole point of the surface.
                editorFocused = true
            }
        }
    }

    private func saveAll() {
        let profileID = profileManager.activeProfile?.clientID
        let allLines = lines
        guard !allLines.isEmpty else { return }

        // Insert in reverse sortOrder so the first-typed line ends up at
        // the top of the backlog when sorted ascending — matches what the
        // user expects ("the thing I typed first is the thing I dumped first").
        for (offset, title) in allLines.enumerated() {
            let task = AgendaTask(
                title: title,
                frictionLevel: 3,
                energyRequired: 2,
                estimatedMinutes: 15,
                interestLevel: 3
            )
            task.assignedToProfileID = profileID
            task.sortOrder = offset
            modelContext.insert(task)
        }
        try? modelContext.save()
        isPresented = false
    }
}
