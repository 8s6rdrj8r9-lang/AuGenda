// Task.swift
// AUDHD Agenda App
//
// Task was renamed to AgendaTask to avoid collision with Swift's built-in Task concurrency type.
// This typealias keeps TaskBacklogView, SmartSuggestView, and TaskDetailView compiling
// without requiring a bulk rename across all backlog views.
//
// New code should use AgendaTask directly.

import Foundation

typealias Task = AgendaTask
