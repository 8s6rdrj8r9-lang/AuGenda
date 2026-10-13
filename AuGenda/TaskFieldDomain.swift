// TaskFieldDomain.swift
// Single source of truth for persisted/imported/AI-generated task dimensions.

import Foundation

enum TaskFieldDomain {
    static let friction = 1...4
    static let energy = 1...4
    static let interest = 1...5
    static let load = 0...3
    static let priority = 0...2
}
