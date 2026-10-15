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
#if os(iOS)
import Speech
import AVFoundation
#endif
import UniformTypeIdentifiers

// MARK: - Filter & Sort Mode

enum TaskFilter: String, CaseIterable {
    case all     = "All"
    case suggest = "Matches energy"
    case waiting = "Waiting"
}

enum BacklogSortMode: String, CaseIterable {
    case sortOrder    = "Manual"
    case ndPriority   = "Suggested order"
    case dueDate      = "Due Date"
    case friction     = "Easiest First"
}

private struct PendingTaskListImport {
    let tasks: [AgendaTask]
    let format: TaskExportFormat
    let diagnostics: [TaskImportDiagnostic]

    var previewMessage: String {
        let sampleTitles = tasks.prefix(3).map(\.title)
            .joined(separator: ", ")
        let remaining = max(0, tasks.count - 3)
        let sampleSuffix = remaining > 0 ? " (+\(remaining) more)" : ""
        let warningText = diagnostics.map(\.localizedDescription)
            .joined(separator: "\n")
        return [
            "\(tasks.count) validated task\(tasks.count == 1 ? "" : "s") from \(format.displayName).",
            sampleTitles.isEmpty ? nil : "Preview: \(sampleTitles)\(sampleSuffix)",
            warningText.isEmpty ? nil : warningText
        ]
        .compactMap { $0 }
        .joined(separator: "\n\n")
    }
}


// MARK: - Task Backlog View

struct TaskBacklogView: View {

    private static let maximumFetchedTasks = 1_000
    private static let maximumFetchedRelationships = 20_000
    private static let taskPageSize = 100

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var profileManager: ActiveProfileManager
    @Query(
        filter: #Predicate<AgendaTask> { !$0.isComplete && !$0.isAbandoned },
        sort: \AgendaTask.sortOrder
    )
    private var tasks: [AgendaTask]

    @Query private var blockingRelationships: [TaskRelationship]

    @State private var filter: TaskFilter = .all
    @State private var sortMode: BacklogSortMode = .ndPriority
    @State private var energyLevel: Int = 3
    @State private var showAddTask = false
    @State private var showBrainDump = false
    @State private var selectedTask: AgendaTask? = nil
    @State private var visibleTaskLimit = Self.taskPageSize

    // Import / Export state
    @State private var showExporter = false
    @State private var showImporter = false
    @State private var showBackupImporter = false
    @State private var showTaskImportConfirmation = false
    @State private var showBackupRestoreConfirmation = false
    @State private var exportDocument = TaskTextFileDocument()
    @State private var exportFormat: TaskExportFormat = .markdown
    @State private var exportIsWholeBackup = false
    @State private var pendingTaskImport: PendingTaskListImport? = nil
    @State private var pendingBackupRestore: AuGendaBackupEnvelope? = nil
    @State private var importFeedback: String? = nil
    @State private var importExportPassword: String = ""

    init() {
        var descriptor = FetchDescriptor<AgendaTask>(
            predicate: #Predicate { !$0.isComplete && !$0.isAbandoned },
            sortBy: [SortDescriptor(\.sortOrder)]
        )
        descriptor.fetchLimit = Self.maximumFetchedTasks
        _tasks = Query(descriptor)

        var relationshipDescriptor = FetchDescriptor<TaskRelationship>(
            predicate: #Predicate {
                $0.typeRaw == "blocks" || $0.typeRaw == "follows"
            }
        )
        relationshipDescriptor.fetchLimit = Self.maximumFetchedRelationships
        _blockingRelationships = Query(relationshipDescriptor)
    }

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

    // MARK: - Import / Export

    /// Default filename presented in the system Save dialog. Includes today's
    /// date so the user can tell exports apart at a glance.
    private var defaultExportFilename: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        if exportIsWholeBackup {
            return "AuGenda-full-backup-\(formatter.string(from: .now)).augendabackup"
        }
        return "AuGenda-active-tasks-\(formatter.string(from: .now)).\(exportFormat.fileExtension)"
    }

    private var exportContentType: UTType {
        exportIsWholeBackup ? .data : exportFormat.contentType
    }

    /// Gather every active AgendaTask for the active profile, serialize
    /// in the chosen format, and trigger the system file-exporter. The actual
    /// "Save to…" dialog is presented by `.fileExporter`.
    private func beginExport(format: TaskExportFormat) {
        let allForProfile = profileTasks
            .sorted { $0.sortOrder < $1.sortOrder }

        do {
            var payload = try TaskExporter.export(allForProfile, as: format)
            if !importExportPassword.isEmpty {
                // Throwing encryption is intentionally fail-closed: the
                // exporter is never presented with plaintext after a request
                // for password protection.
                payload = try TaskExporter.encrypt(
                    payload,
                    password: importExportPassword
                )
            }

            exportFormat = format
            exportIsWholeBackup = false
            exportDocument = TaskTextFileDocument(text: payload)
            showExporter = true
        } catch {
            importFeedback = "Export failed: \(error.localizedDescription)"
            ErrorBannerController.shared.show("Export failed: \(error.localizedDescription)")
        }
    }

    /// Full-product backups are always password protected. The archive includes
    /// every SwiftData entity and safe product preference, but never Keychain
    /// API keys, OAuth tokens, or reusable consent receipts.
    private func beginWholeBackup() {
        do {
            let payload = try AuGendaBackupService.encryptedArchive(
                from: modelContext,
                password: importExportPassword
            )
            exportIsWholeBackup = true
            exportDocument = TaskTextFileDocument(text: payload)
            showExporter = true
        } catch {
            importFeedback = "Full backup failed: \(error.localizedDescription)"
            ErrorBannerController.shared.show(
                "Full backup failed: \(error.localizedDescription)"
            )
        }
    }

    private func handleBackupImportResult(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            importFeedback = "Backup restore failed: \(error.localizedDescription)"
        case .success(let urls):
            guard let url = urls.first else { return }
            let needsScope = url.startAccessingSecurityScopedResource()
            defer { if needsScope { url.stopAccessingSecurityScopedResource() } }
            do {
                let values = try url.resourceValues(forKeys: [.fileSizeKey])
                if let size = values.fileSize,
                   size > AuGendaBackupService.maximumBackupBytes {
                    throw AuGendaBackupError.backupTooLarge
                }
                let data = try Data(contentsOf: url, options: .mappedIfSafe)
                guard let archive = String(data: data, encoding: .utf8) else {
                    throw AuGendaBackupError.decryptionFailed
                }
                pendingBackupRestore = try AuGendaBackupService.decodeEncryptedArchive(
                    archive,
                    password: importExportPassword
                )
                showBackupRestoreConfirmation = true
            } catch {
                pendingBackupRestore = nil
                importFeedback = "Backup restore failed without changing your data: \(error.localizedDescription)"
                ErrorBannerController.shared.show(
                    "Backup restore failed: \(error.localizedDescription)"
                )
            }
        }
    }

    private func confirmBackupRestore() {
        guard let pendingBackupRestore else { return }
        do {
            let summary = try AuGendaBackupService.restore(
                pendingBackupRestore,
                in: modelContext,
                afterCommit: {
                    profileManager.loadActiveProfile()
                    NotificationManager.shared.removeAllNotifications()
                    NotificationManager.shared.reconcilePendingAgendaNotifications()
                    NotificationManager.shared.reconcileFocusSessionState()
                    #if canImport(WatchConnectivity)
                    WatchConnectivityManager.shared.sendSyncSnapshot()
                    #endif
                }
            )
            self.pendingBackupRestore = nil
            importFeedback = "Restored \(summary.restoredEntityCount) records and \(summary.restoredPreferenceCount) preferences. API keys and provider consent were not restored."
        } catch AuGendaBackupError.historyRollbackFailed {
            self.pendingBackupRestore = nil
            importFeedback = "Restore stopped, but local AI history could not be fully rolled back. Tasks and preferences were not committed. Keep this backup, restart AuGenda, and retry recovery before making further changes."
            ErrorBannerController.shared.show(
                "Backup restore needs recovery: AI history rollback failed."
            )
        } catch {
            self.pendingBackupRestore = nil
            importFeedback = "Backup restore failed and saved data was left unchanged: \(error.localizedDescription)"
            ErrorBannerController.shared.show(
                "Backup restore failed: \(error.localizedDescription)"
            )
        }
    }

    /// Read the picked file, detect format from its extension, parse, and
    /// atomically insert new tasks. Stable IDs make repeated imports
    /// idempotent; existing records are left unchanged.
    private func handleImportResult(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            importFeedback = "Import failed: \(error.localizedDescription)"
            ErrorBannerController.shared.show("Import failed: \(error.localizedDescription)")

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

            do {
                let values = try url.resourceValues(forKeys: [.fileSizeKey])
                if let size = values.fileSize, size > TaskImporter.maximumImportBytes {
                    throw TaskPortabilityError.importTooLarge
                }
                let data = try Data(contentsOf: url, options: .mappedIfSafe)
                guard let text = String(data: data, encoding: .utf8) else {
                    throw TaskPortabilityError.invalidFormat("file isn't UTF-8 text")
                }

                let preview = try TaskImporter.previewImport(
                    text,
                    as: format,
                    password: importExportPassword
                )
                guard !preview.tasks.isEmpty else {
                    importFeedback = "The task list is valid but contains no tasks."
                    return
                }
                pendingTaskImport = PendingTaskListImport(
                    tasks: preview.tasks,
                    format: format,
                    diagnostics: preview.diagnostics
                )
                showTaskImportConfirmation = true
            } catch TaskPortabilityError.validationFailed(let diagnostics) {
                let details = diagnostics.map(\.localizedDescription)
                    .joined(separator: "\n")
                importFeedback = "Import rejected without changing your saved tasks:\n\(details)"
                ErrorBannerController.shared.show(
                    "Import rejected with \(diagnostics.count) invalid field\(diagnostics.count == 1 ? "" : "s")."
                )
            } catch {
                importFeedback = "Import failed without changing your saved tasks: \(error.localizedDescription)"
                ErrorBannerController.shared.show("Import failed: \(error.localizedDescription)")
            }
        }
    }

    private func confirmTaskImport() {
        guard let pendingTaskImport else { return }
        do {
            let summary = try TaskImportService.apply(
                pendingTaskImport.tasks,
                assignedTo: profileManager.activeProfile?.clientID,
                using: modelContext.container
            )
            self.pendingTaskImport = nil
            if summary.skippedDuplicateCount > 0 {
                importFeedback = "Imported \(summary.insertedCount) task\(summary.insertedCount == 1 ? "" : "s"). Skipped \(summary.skippedDuplicateCount) existing task\(summary.skippedDuplicateCount == 1 ? "" : "s")."
            } else {
                importFeedback = "Imported \(summary.insertedCount) task\(summary.insertedCount == 1 ? "" : "s") from \(pendingTaskImport.format.displayName)."
            }
        } catch {
            self.pendingTaskImport = nil
            importFeedback = "Import failed without changing your saved tasks: \(error.localizedDescription)"
            ErrorBannerController.shared.show(
                "Import failed: \(error.localizedDescription)"
            )
        }
    }

    // MARK: Body

    var body: some View {
        let projection = BacklogProjection.make(
            tasks: tasks,
            relationships: blockingRelationships,
            activeProfileID: activeProfileID,
            filter: filter,
            sortMode: sortMode,
            energyLevel: energyLevel
        )
        let visibleTasks = Array(projection.tasks.prefix(visibleTaskLimit))
        let hiddenCount = max(0, projection.actionableCount - projection.tasks.count)

        NavigationStack {
            VStack(spacing: 0) {
                Text("Tasks you add or review from Inbox. Scheduled items are in Today.")
                    .font(Tokens.Typography.caption)
                    .foregroundStyle(Color.appTextSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Tokens.Spacing.base)
                filterBar

                // Control bar — energy (For Now) or sort (All/Waiting)
                if filter == .suggest {
                    EnergyFilterBanner(
                        energyLevel: $energyLevel,
                        filteredOutCount: hiddenCount
                    )
                } else {
                    sortBar(taskCount: projection.tasks.count)
                }

                Divider()

                if projection.tasks.isEmpty {
                    emptyState
                } else {
                    taskList(
                        visibleTasks: visibleTasks,
                        totalCount: projection.tasks.count
                    )
                }
            }
            .navigationTitle("Tasks")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            #endif
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    InboxAccessButton()
                        .labelStyle(.titleAndIcon)
                }
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
                        Section("Export active task list") {
                            ForEach(TaskExportFormat.allCases) { format in
                                Button(format.displayName) {
                                    beginExport(format: format)
                                }
                            }
                            Text("Task list only — not a full backup")
                            Text("JSON preserves steps. YAML and CSV omit steps; Markdown and plain text are intentionally lossy.")
                        }
                        Section("Import task list") {
                            Button {
                                showImporter = true
                            } label: {
                                Label("From file…", systemImage: "tray.and.arrow.down")
                            }
                        }
                        Section("Full encrypted backup") {
                            Button {
                                beginWholeBackup()
                            } label: {
                                Label("Create full backup…", systemImage: "lock.doc")
                            }
                            Button {
                                showBackupImporter = true
                            } label: {
                                Label("Restore full backup…", systemImage: "arrow.counterclockwise.circle")
                            }
                            Text("Password required. Includes all product records and safe preferences; excludes credentials.")
                        }
                        Section {
                            SecureField("Encryption password (optional)", text: $importExportPassword)
                                .textContentType(.password)
                        }
                    } label: {
                        Image(systemName: "tray.and.arrow.up")
                            .font(.title2)
                            .foregroundStyle(Tokens.Color.primary)
                    }
                    .accessibilityLabel("Import or export active task list")
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
                contentType: exportContentType,
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
                // .data lets .yaml/.yml through — the extension check in
                // handleImportResult filters to supported formats.
                allowedContentTypes: [.json, .commaSeparatedText, .plainText, .text, .data],
                allowsMultipleSelection: false
            ) { result in
                handleImportResult(result)
            }
            .fileImporter(
                isPresented: $showBackupImporter,
                allowedContentTypes: [.data, .text, .plainText],
                allowsMultipleSelection: false
            ) { result in
                handleBackupImportResult(result)
            }
            .confirmationDialog(
                "Import this validated task list?",
                isPresented: $showTaskImportConfirmation,
                titleVisibility: .visible
            ) {
                if let pendingTaskImport {
                    Button(
                        "Import \(pendingTaskImport.tasks.count) task\(pendingTaskImport.tasks.count == 1 ? "" : "s")"
                    ) {
                        confirmTaskImport()
                    }
                }
                Button("Cancel", role: .cancel) {
                    pendingTaskImport = nil
                }
            } message: {
                if let pendingTaskImport {
                    Text(pendingTaskImport.previewMessage)
                }
            }
            .confirmationDialog(
                "Replace all AuGenda product data?",
                isPresented: $showBackupRestoreConfirmation,
                titleVisibility: .visible
            ) {
                Button("Replace and restore", role: .destructive) {
                    confirmBackupRestore()
                }
                Button("Cancel", role: .cancel) {
                    pendingBackupRestore = nil
                }
            } message: {
                if let pendingBackupRestore {
                    Text(
                        "This validated backup contains \(pendingBackupRestore.totalEntityCount) records. Current tasks, profiles, blocks, notes, focus history, and preferences will be replaced. Credentials are not included."
                    )
                }
            }
            .alert(
                "Task List Import or Export",
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
        .onChange(of: filter) { _, _ in resetVisiblePage() }
        .onChange(of: sortMode) { _, _ in resetVisiblePage() }
        .onChange(of: energyLevel) { _, _ in resetVisiblePage() }
        .onChange(of: activeProfileID) { _, _ in resetVisiblePage() }
    }

    // MARK: - Sort Bar (All / Waiting modes)

    private func sortBar(taskCount: Int) -> some View {
        HStack(spacing: Tokens.Spacing.sm) {
            Text("Sort:")
                .font(Tokens.Typography.caption)
                .foregroundColor(Color.appTextSecondary)

            Picker("Task order", selection: $sortMode) {
                ForEach(BacklogSortMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()

            Spacer()

            Text("\(taskCount) task\(taskCount == 1 ? "" : "s")")
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
                .accessibilityAddTraits(filter == mode ? .isSelected : [])
            }
        }
        .background(Color.appBackgroundSecondary)
    }

    // MARK: - Task List

    @ViewBuilder
    private func taskList(
        visibleTasks: [AgendaTask],
        totalCount: Int
    ) -> some View {
        ScrollView {
            LazyVStack(spacing: Tokens.Spacing.xl) {
                ForEach(visibleTasks) { task in
                    AgendaTaskCard(task: task, showWaitingOn: filter == .waiting) {
                        selectedTask = task
                        InterruptionContext.recordActivity(
                            itemID: task.clientID,
                            contextLabel: "task detail"
                        )
                    }
                }

                if visibleTasks.count < totalCount {
                    Button {
                        visibleTaskLimit = min(
                            visibleTaskLimit + Self.taskPageSize,
                            totalCount
                        )
                    } label: {
                        Label(
                            "Show \(min(Self.taskPageSize, totalCount - visibleTasks.count)) more",
                            systemImage: "chevron.down.circle"
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Tokens.Spacing.sm)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityHint(
                        "\(totalCount - visibleTasks.count) additional matching tasks remain"
                    )
                }

                if visibleTasks.count == totalCount,
                   tasks.count == Self.maximumFetchedTasks {
                    Text("Showing the first \(Self.maximumFetchedTasks.formatted()) active tasks. Complete, archive, or export older work before adding more.")
                        .font(Tokens.Typography.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding()
                        .accessibilityLabel("Task list limit reached")
                }
            }
            .padding(.horizontal, Tokens.Spacing.base)
            .padding(.vertical, Tokens.Spacing.md)
        }
    }

    private func resetVisiblePage() {
        visibleTaskLimit = Self.taskPageSize
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
        case .all:     return "No tasks in this list"
        case .suggest: return "No tasks for right now"
        case .waiting: return "Nothing waiting"
        }
    }

    private var emptyMessage: String {
        switch filter {
        case .all:     return "Add a task or review a capture in Inbox. Scheduled items remain in Today."
        case .suggest: return "No tasks match this energy level. You can browse All or change the filter."
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
    @Environment(\.modelContext) private var modelContext

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
                                .font(.caption2)
                                .foregroundColor(Tokens.Color.info)
                        }

                        if task.hyperfocusRisk {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption2)
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

                    // ── Blocked indicator ──
                    if task.isBlocked(in: modelContext) {
                        HStack(spacing: Tokens.Spacing.xs) {
                            Image(systemName: "lock.fill")
                                .font(.caption2)
                                .foregroundColor(Tokens.Color.warning)
                            Text("Blocked")
                                .font(Tokens.Typography.caption)
                                .foregroundColor(Tokens.Color.warning)
                        }
                        .opacity(0.8)
                    }

                    // ── Waiting-on row (Waiting filter only) ──
                    if showWaitingOn && !task.waitingOn.isEmpty {
                        HStack(spacing: Tokens.Spacing.xs) {
                            Image(systemName: "clock.badge.questionmark")
                                .font(.caption2)
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
        .accessibilityLabel(taskAccessibilityLabel)
        .accessibilityHint("Opens task detail")
    }

    /// One cognitive-meaning VoiceOver sentence, reusing the shared summary so
    /// the backlog reads consistently with the Home cards. Adds waiting-on when
    /// the Waiting filter is showing it.
    private var taskAccessibilityLabel: String {
        var summary = TaskSurfaceData(from: task).accessibilitySummary
        if showWaitingOn && !task.waitingOn.isEmpty {
            summary += ", waiting on \(task.waitingOn)"
        }
        return summary
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

    @State private var showDetails = false
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
    @State private var excludeFromAI = false
    @State private var priority = 0
    @State private var dueDate: Date? = nil
    @State private var showDueDatePicker = false
    @State private var recurrenceRule: RecurrenceRule = .none
    @State private var assignedToProfileID: UUID? = nil

    private var activeProfile: Profile? { profileManager.activeProfile }
    private var canAssign: Bool { (activeProfile?.canAssignTasks == true) && profiles.count > 1 }
    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (recurrenceRule == .none || showDueDatePicker)
    }

    private var contextOptions: [String] {
        let standard = ["home", "computer", "phone", "outside", "focus", "errand"]
        guard profileManager.activePreferences?.sensoryContextTagsEnabled == true else {
            return standard
        }
        return standard + ["quiet", "low light", "headphones", "low scent"]
    }

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
                        .disabled(!canSave)
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

                Section {
                    Toggle("Add optional details", isOn: $showDetails)
                } footer: {
                    Text("A title is enough. Time and effort use starting estimates you can change later.")
                }

                if showDetails {
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
                                Text("4 Wall").tag(4)
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 190)
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
                                Text("1 Low").tag(1)
                                Text("2").tag(2)
                                Text("3").tag(3)
                                Text("4 High").tag(4)
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 190)
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
                    Toggle(isOn: $excludeFromAI) {
                        Label("Keep this task out of AI", systemImage: "hand.raised")
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

                Section("Repeat") {
                    Picker("Schedule", selection: $recurrenceRule) {
                        ForEach(RecurrenceRule.allCases) { rule in
                            Text(rule.displayName).tag(rule)
                        }
                    }
                    .pickerStyle(.menu)

                    if recurrenceRule != .none && !showDueDatePicker {
                        Label(
                            "Choose a due date to anchor the repeating schedule.",
                            systemImage: "calendar.badge.exclamationmark"
                        )
                        .font(.caption)
                        .foregroundStyle(.orange)
                    } else if recurrenceRule != .none {
                        Text("Completing this task creates one next future occurrence. Missed dates are not backfilled.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
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
                }   // optional details
                }   // closes Form
                .formStyle(.grouped)   // macOS-native label/control layout
            }   // closes outer VStack
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .onAppear {
                if let task = editingTask {
                    showDetails = true
                    title              = task.title
                    notes              = task.notes
                    frictionLevel      = min(
                        max(task.frictionLevel, TaskFieldDomain.friction.lowerBound),
                        TaskFieldDomain.friction.upperBound
                    )
                    interestLevel      = task.interestLevel
                    energyRequired     = min(
                        max(task.energyRequired, TaskFieldDomain.energy.lowerBound),
                        TaskFieldDomain.energy.upperBound
                    )
                    estimatedMinutes   = task.estimatedMinutes
                    contextTag         = task.contextTag
                    waitingOn          = task.waitingOn
                    hyperfocusRisk     = task.hyperfocusRisk
                    needsBodyDouble    = task.needsBodyDouble
                    excludeFromAI      = task.excludeFromAI
                    priority           = task.priority
                    recurrenceRule     = RecurrenceRule(rawValue: task.recurrenceRule) ?? .none
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
        do {
            try PersistentMutation.commit(in: modelContext) {
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
                    task.excludeFromAI    = excludeFromAI
                    task.waitingOn        = waitingOn
                    task.dueDate          = showDueDatePicker ? dueDate : nil
                    task.recurrenceRule    = recurrenceRule.rawValue
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
                    task.excludeFromAI = excludeFromAI
                    task.waitingOn = waitingOn
                    if showDueDatePicker { task.dueDate = dueDate }
                    task.recurrenceRule = recurrenceRule.rawValue
                    task.assignedToProfileID = assignedToProfileID
                    if assignedToProfileID != activeProfile?.clientID {
                        task.assignedByProfileID = activeProfile?.clientID
                    }
                    modelContext.insert(task)
                }
            }
            isPresented = false
        } catch {
            ErrorBannerController.shared.show("Couldn't save: \(error.localizedDescription)")
        }
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

    #if os(iOS)
    @State private var isRecording: Bool = false
    @State private var voiceUnavailable: Bool = false
    @State private var audioEngine = AVAudioEngine()
    @State private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    @State private var recognitionTask: SFSpeechRecognitionTask?
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale.autoupdatingCurrent)
    #endif

    /// Non-empty, trimmed lines — each becomes one InboxItem.
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
                HStack(spacing: Tokens.Spacing.base) {
                    Button("Cancel") {
                        #if os(iOS)
                        stopRecording()
                        #endif
                        isPresented = false
                    }
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

                    Button("Send to inbox") { sendToInbox() }
                        .buttonStyle(.borderedProminent)
                        .disabled(lines.isEmpty)
                        .keyboardShortcut(.defaultAction)
                }
                .padding(.horizontal, Tokens.Spacing.base)
                .padding(.vertical, Tokens.Spacing.sm)
                .background(Color.appBackgroundSecondary)

                // ── Reassurance copy ─────────────────────────────
                Text("One thought per line. Lands in the inbox for review — nothing goes to tasks until you confirm it.")
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

                // ── Voice dictation bar (iOS only) ────────────────
                #if os(iOS)
                if !voiceUnavailable {
                    Divider()
                    HStack {
                        Button {
                            if voiceUnavailable {
                                ErrorBannerController.shared.show("Voice input is not available on this device")
                                return
                            }
                            isRecording
                                ? stopRecording()
                                : requestSpeechPermissionAndStart()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: isRecording
                                      ? "stop.circle.fill" : "mic.circle.fill")
                                    .font(.title3)
                                    .foregroundStyle(isRecording ? .red : Color.appAccent)
                                Text(isRecording ? "Stop dictating" : "Dictate")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundStyle(isRecording ? .red : Color.appAccent)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                isRecording
                                    ? Color.red.opacity(0.08)
                                    : Color.appAccent.opacity(0.10),
                                in: Capsule()
                            )
                        }
                        .buttonStyle(.plain)
                        .animation(.easeInOut(duration: 0.2), value: isRecording)
                        Spacer()
                    }
                    .padding(.horizontal, Tokens.Spacing.base)
                    .padding(.vertical, Tokens.Spacing.sm)
                    .background(Color.appBackgroundSecondary)
                }
                #endif
            }
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .onAppear {
                editorFocused = true
                #if os(iOS)
                voiceUnavailable = !(SFSpeechRecognizer(locale: .autoupdatingCurrent)?.isAvailable ?? false)
                #endif
            }
            .onDisappear {
                #if os(iOS)
                stopRecording()
                #endif
            }
        }
    }

    // MARK: - Send to inbox

    private func sendToInbox() {
        let profileID = profileManager.activeProfile?.clientID
        let allLines = lines
        guard !allLines.isEmpty else { return }

        #if os(iOS)
        let source: InboxItemSource = isRecording ? .voiceCapture : .textCapture
        stopRecording()
        #else
        let source: InboxItemSource = .textCapture
        #endif

        do {
            try PersistentMutation.commit(in: modelContext) {
                for line in allLines {
                    let item = InboxItem(rawCapture: line, source: source)
                    item.assignedToProfileID = profileID
                    modelContext.insert(item)
                }
            }
            isPresented = false
        } catch {
            ErrorBannerController.shared.show("Couldn't save: \(error.localizedDescription)")
        }
    }

    // MARK: - Speech recognition (iOS only)

    #if os(iOS)
    private func requestSpeechPermissionAndStart() {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            startRecording()
        case .notDetermined:
            // Ask only after the user taps the microphone; opening a text-only
            // brain dump must not trigger a speech privacy prompt.
            SFSpeechRecognizer.requestAuthorization { status in
                DispatchQueue.main.async {
                    voiceUnavailable = (status != .authorized)
                    if status == .authorized {
                        startRecording()
                    }
                }
            }
        case .denied, .restricted:
            voiceUnavailable = true
            ErrorBannerController.shared.show(
                "Voice input is unavailable until Speech Recognition is allowed in Settings."
            )
        @unknown default:
            voiceUnavailable = true
        }
    }

    private func startRecording() {
        guard !isRecording else { return }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        recognitionRequest = request

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let node = audioEngine.inputNode
            let format = node.outputFormat(forBus: 0)
            node.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                request.append(buffer)
            }
            audioEngine.prepare()
            try audioEngine.start()

            let baseline = text
            recognitionTask = speechRecognizer?.recognitionTask(with: request) { result, error in
                if let result {
                    DispatchQueue.main.async {
                        let prefix = baseline.trimmingCharacters(in: .whitespacesAndNewlines)
                        let transcription = result.bestTranscription.formattedString
                        text = prefix.isEmpty ? transcription : prefix + "\n" + transcription
                    }
                }
                if error != nil || result?.isFinal == true {
                    DispatchQueue.main.async { stopRecording() }
                }
            }
            isRecording = true
        } catch {
            voiceUnavailable = true
            stopRecording()
        }
    }

    private func stopRecording() {
        guard isRecording else { return }
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false,
            options: .notifyOthersOnDeactivation)
    }
    #endif
}
