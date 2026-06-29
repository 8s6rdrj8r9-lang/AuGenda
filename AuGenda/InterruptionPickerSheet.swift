// InterruptionPickerSheet.swift
// AuGenda
//
// Quick picker for logging why a focus session was interrupted.

import SwiftUI

struct InterruptionPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onSelect: (String) -> Void

    let reasons = [
        "Notification",
        "Phone call",
        "Lost track",
        "Physical discomfort",
        "Other"
    ]

    var body: some View {
        NavigationStack {
            List {
                Section("What happened?") {
                    ForEach(reasons, id: \.self) { reason in
                        Button {
                            onSelect(reason)
                            dismiss()
                        } label: {
                            Text(reason)
                                .foregroundStyle(.primary)
                        }
                    }
                    Button {
                        onSelect("")
                        dismiss()
                    } label: {
                        Text("Skip reason")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Interruption")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
