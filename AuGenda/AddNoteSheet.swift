// AddNoteSheet.swift
// AuGenda
//
// Minimal sheet for adding a note to a task or item.

import SwiftUI
import SwiftData

struct AddNoteSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let relatedTaskID: UUID?
    let relatedItemID: UUID?

    @State private var title = ""
    @State private var bodyText = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Title", text: $title)
                TextField("Body", text: $bodyText, axis: .vertical)
                    .lineLimit(3...6)
            }
            .navigationTitle("New Note")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let note = Note(
                            title: title,
                            body: bodyText,
                            relatedTaskID: relatedTaskID,
                            relatedItemID: relatedItemID
                        )
                        modelContext.insert(note)
                        do {
                            try modelContext.save()
                        } catch {
                            ErrorBannerController.shared.show("Couldn't save: \(error.localizedDescription)")
                        }
                        dismiss()
                    }
                    .disabled(title.isEmpty && bodyText.isEmpty)
                }
            }
        }
    }
}
