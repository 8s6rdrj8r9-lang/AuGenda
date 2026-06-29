// FocusSessionHistoryView.swift
// AuGenda
//
// Simple list view showing past FocusSession records.

import SwiftUI
import SwiftData

struct FocusSessionHistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(
        sort: \FocusSession.startTime,
        order: .reverse
    )
    private var sessions: [FocusSession]

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

            Text(session.startTime, style: .date)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}

private struct StatusBadge: View {
    let session: FocusSession

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: session.wasCompleted ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.caption)
            Text(session.wasCompleted ? "Done" : "Ended")
                .font(.caption)
        }
        .foregroundStyle(session.wasCompleted ? .green : .secondary)
    }
}

#Preview {
    FocusSessionHistoryView()
}
