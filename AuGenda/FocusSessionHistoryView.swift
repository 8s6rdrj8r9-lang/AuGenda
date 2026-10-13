// FocusSessionHistoryView.swift
// AuGenda
//
// Simple list view showing past FocusSession records.

import SwiftUI
import SwiftData

struct FocusSessionHistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query private var sessions: [FocusSession]

    @MainActor
    init(profileID: UUID? = nil) {
        let targetID = profileID ?? ActiveProfileManager.shared.activeProfile?.clientID
        let descriptor: FetchDescriptor<FocusSession>
        if let targetID {
            descriptor = FetchDescriptor<FocusSession>(
                predicate: #Predicate<FocusSession> {
                    $0.profileID == nil || $0.profileID == targetID
                },
                sortBy: [SortDescriptor(\.startTime, order: .reverse)]
            )
        } else {
            descriptor = FetchDescriptor<FocusSession>(
                sortBy: [SortDescriptor(\.startTime, order: .reverse)]
            )
        }
        _sessions = Query(descriptor)
    }

    var body: some View {
        NavigationStack {
            List {
                if sessions.isEmpty {
                    Section {
                        Text("No focus sessions yet.")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(sessions) { session in
                        SessionRow(session: session)
                    }
                }
            }
            .navigationTitle("Focus History")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct SessionRow: View {
    let session: FocusSession

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(session.taskTitle.isEmpty ? "Untitled session" : session.taskTitle)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                StatusBadge(session: session)
            }

            HStack(spacing: 12) {
                Text("\(session.plannedDurationMinutes) min planned")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if session.endTime != nil {
                    Text("\(session.actualDurationMinutes) min actual")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if session.interruptionCount > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Text("\(session.interruptionCount) interruption\(session.interruptionCount == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    if !session.interruptionReasons.isEmpty {
                        Text("— \(session.interruptionReasons.joined(separator: ", "))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            if session.state == .abandoned, !session.abandonReason.isEmpty {
                Text("Reason: \(session.abandonReason)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(session.startTime, style: .date)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}

private struct StatusBadge: View {
    let session: FocusSession

    private var presentation: (icon: String, label: String, color: Color) {
        switch session.state {
        case .idle:
            return ("circle.dashed", "Idle", .secondary)
        case .active:
            return ("timer", "Active", .blue)
        case .paused:
            return ("pause.circle.fill", "Paused", .orange)
        case .completed:
            return ("checkmark.circle.fill", "Done", .green)
        case .abandoned:
            return ("archivebox.fill", "Abandoned", .secondary)
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: presentation.icon)
                .font(.caption)
            Text(presentation.label)
                .font(.caption)
        }
        .foregroundStyle(presentation.color)
    }
}

#Preview {
    FocusSessionHistoryView()
}
