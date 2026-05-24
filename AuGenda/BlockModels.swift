// BlockModels.swift
// AUDHD Agenda App
//
// Block = named group of tasks run as a unit (Startup, Shopping, etc.)
// Bundle = add-on checklist that attaches to a block (Dog Bag, Snacks, etc.)
// BundleItem = individual item within a bundle
// BlockTask = a task belonging to a block
//
// CloudKit-compatible: all properties have defaults or are optional

import Foundation
import SwiftData

// MARK: - Block Type

enum BlockType: String, Codable, CaseIterable {
    case startup = "startup"
    case shutdown = "shutdown"
    case shop = "shop"
    case tech = "tech"
    case cleaning = "cleaning"
    case cooking = "cooking"
    case maintenance = "maintenance"
    case family = "family"
    case shopping = "shopping"
    case adventures = "adventures"
    case travel = "travel"
    case custom = "custom"

    var displayName: String {
        switch self {
        case .startup: return "Startup"
        case .shutdown: return "Shutdown"
        case .shop: return "Shop"
        case .tech: return "Tech"
        case .cleaning: return "Cleaning"
        case .cooking: return "Cooking"
        case .maintenance: return "Maintenance"
        case .family: return "Family"
        case .shopping: return "Shopping"
        case .adventures: return "Adventures"
        case .travel: return "Travel"
        case .custom: return "Custom"
        }
    }

    var icon: String {
        switch self {
        case .startup: return "sunrise.fill"
        case .shutdown: return "sunset.fill"
        case .shop: return "bag.fill"
        case .tech: return "desktopcomputer"
        case .cleaning: return "sparkles"
        case .cooking: return "fork.knife"
        case .maintenance: return "wrench.and.screwdriver.fill"
        case .family: return "figure.2.and.child.holdinghands"
        case .shopping: return "cart.fill"
        case .adventures: return "figure.hiking"
        case .travel: return "airplane"
        case .custom: return "square.grid.2x2.fill"
        }
    }

    /// Blocks that are outdoor-relevant — trigger weather check
    var isOutdoor: Bool {
        switch self {
        case .adventures, .travel, .shopping, .shop: return true
        default: return false
        }
    }

    /// Bundles that auto-prompt for this block type
    var defaultBundleTypes: [BundleType] {
        switch self {
        case .adventures: return [.dogBag, .snacks, .extraWater]
        case .shopping: return [.snacks, .extraWater]
        case .travel: return [.dogBag, .snacks, .extraWater]
        case .shop: return []
        default: return []
        }
    }
}

// MARK: - Bundle Type

enum BundleType: String, Codable, CaseIterable {
    case dogBag = "dogBag"
    case snacks = "snacks"
    case extraWater = "extraWater"
    case custom = "custom"

    var displayName: String {
        switch self {
        case .dogBag: return "Dog Bag"
        case .snacks: return "Snacks"
        case .extraWater: return "Extra Water"
        case .custom: return "Custom"
        }
    }

    var icon: String {
        switch self {
        case .dogBag: return "pawprint.fill"
        case .snacks: return "takeoutbag.and.cup.and.straw.fill"
        case .extraWater: return "drop.fill"
        case .custom: return "plus.circle.fill"
        }
    }

    /// Default items for this bundle type
    var defaultItems: [String] {
        switch self {
        case .dogBag:
            return [
                "Poop bags",
                "Collapsible water bowl",
                "Dog treats",
                "Leash",
                "Dog towel"
            ]
        case .snacks:
            return [
                "Snacks packed",
                "Check dietary needs"
            ]
        case .extraWater:
            return [
                "Water bottles filled",
                "Check bottle count"
            ]
        case .custom:
            return []
        }
    }
}

// MARK: - Block Model

@Model
final class Block {

    var clientID: UUID = UUID()
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    // Type stored as raw string for CloudKit compatibility
    var typeRaw: String = BlockType.custom.rawValue
    var customName: String = ""

    var sortOrder: Int = 0
    var isActive: Bool = false
    var startedAt: Date? = nil
    var completedAt: Date? = nil

    // Tracks last completion date — used for startup auto-surface logic
    var lastCompletedDate: Date? = nil

    // Streak tracking — incremented each day the block is completed
    var currentStreak: Int = 0
    var longestStreak: Int = 0
    var lastStreakDate: Date? = nil

    // Whether to check weather when this block starts
    var weatherCheckEnabled: Bool = false

    @Relationship(deleteRule: .cascade, inverse: \BlockTask.block)
    var tasks: [BlockTask]? = nil

    @Relationship(deleteRule: .cascade, inverse: \AttachedBundle.block)
    var attachedBundles: [AttachedBundle]? = nil

    var type: BlockType {
        get { BlockType(rawValue: typeRaw) ?? .custom }
        set { typeRaw = newValue.rawValue }
    }

    var displayName: String {
        type == .custom ? customName : type.displayName
    }

    var icon: String { type.icon }

    var isComplete: Bool {
        guard let tasks = tasks, !tasks.isEmpty else { return false }
        return tasks.allSatisfy { $0.isComplete }
    }

    var completedTaskCount: Int {
        tasks?.filter { $0.isComplete }.count ?? 0
    }

    var totalTaskCount: Int {
        tasks?.count ?? 0
    }

    // True if startup block and not yet complete today
    var shouldAutoSurface: Bool {
        guard type == .startup else { return false }
        guard !isComplete else { return false }
        guard let last = lastCompletedDate else { return true }
        return !Calendar.current.isDateInToday(last)
    }

    init(type: BlockType = .custom, customName: String = "", sortOrder: Int = 0) {
        self.clientID = UUID()
        self.createdAt = .now
        self.updatedAt = .now
        self.typeRaw = type.rawValue
        self.customName = customName
        self.sortOrder = sortOrder
        self.weatherCheckEnabled = type.isOutdoor
    }
}

// MARK: - BlockTask Model

@Model
final class BlockTask {

    var clientID: UUID = UUID()
    var createdAt: Date = Date.now

    var title: String = ""
    var notes: String = ""
    var isComplete: Bool = false
    var completedAt: Date? = nil
    var sortOrder: Int = 0
    var isOptional: Bool = false

    var block: Block? = nil

    init(title: String = "", sortOrder: Int = 0, isOptional: Bool = false) {
        self.clientID = UUID()
        self.createdAt = .now
        self.title = title
        self.sortOrder = sortOrder
        self.isOptional = isOptional
    }
}

// MARK: - Bundle Template Model
// The reusable bundle definition — separate from an instance attached to a block

@Model
final class BundleTemplate {

    var clientID: UUID = UUID()
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    var typeRaw: String = BundleType.custom.rawValue
    var customName: String = ""
    var sortOrder: Int = 0

    // Which block types this bundle auto-prompts on (stored as comma-separated raw values)
    var autoPromptBlockTypesRaw: String = ""

    @Relationship(deleteRule: .cascade, inverse: \BundleTemplateItem.template)
    var items: [BundleTemplateItem]? = nil

    var type: BundleType {
        get { BundleType(rawValue: typeRaw) ?? .custom }
        set { typeRaw = newValue.rawValue }
    }

    var displayName: String {
        type == .custom ? customName : type.displayName
    }

    var icon: String { type.icon }

    var autoPromptBlockTypes: [BlockType] {
        get {
            autoPromptBlockTypesRaw
                .split(separator: ",")
                .compactMap { BlockType(rawValue: String($0)) }
        }
        set {
            autoPromptBlockTypesRaw = newValue.map { $0.rawValue }.joined(separator: ",")
        }
    }

    init(type: BundleType = .custom, customName: String = "") {
        self.clientID = UUID()
        self.createdAt = .now
        self.updatedAt = .now
        self.typeRaw = type.rawValue
        self.customName = customName

        // Set default auto-prompt block types
        switch type {
        case .dogBag:
            self.autoPromptBlockTypesRaw = [BlockType.adventures, .shopping, .travel]
                .map { $0.rawValue }.joined(separator: ",")
        case .snacks:
            self.autoPromptBlockTypesRaw = [BlockType.adventures, .shopping, .travel]
                .map { $0.rawValue }.joined(separator: ",")
        case .extraWater:
            self.autoPromptBlockTypesRaw = [BlockType.adventures, .shopping, .travel]
                .map { $0.rawValue }.joined(separator: ",")
        default:
            self.autoPromptBlockTypesRaw = ""
        }
    }
}

// MARK: - BundleTemplateItem

@Model
final class BundleTemplateItem {

    var clientID: UUID = UUID()
    var title: String = ""
    var sortOrder: Int = 0

    var template: BundleTemplate? = nil

    init(title: String = "", sortOrder: Int = 0) {
        self.clientID = UUID()
        self.title = title
        self.sortOrder = sortOrder
    }
}

// MARK: - AttachedBundle
// An instance of a bundle attached to a specific block run

@Model
final class AttachedBundle {

    var clientID: UUID = UUID()
    var createdAt: Date = Date.now

    var name: String = ""
    var icon: String = ""
    var isComplete: Bool = false

    var block: Block? = nil

    @Relationship(deleteRule: .cascade, inverse: \AttachedBundleItem.bundle)
    var items: [AttachedBundleItem]? = nil

    var completedItemCount: Int {
        items?.filter { $0.isComplete }.count ?? 0
    }

    var totalItemCount: Int {
        items?.count ?? 0
    }

    init(name: String = "", icon: String = "") {
        self.clientID = UUID()
        self.createdAt = .now
        self.name = name
        self.icon = icon
    }

    /// Create from a BundleTemplate
    static func from(template: BundleTemplate) -> AttachedBundle {
        let bundle = AttachedBundle(name: template.displayName, icon: template.icon)
        let items = (template.items ?? [])
            .sorted { $0.sortOrder < $1.sortOrder }
            .enumerated()
            .map { index, templateItem in
                AttachedBundleItem(title: templateItem.title, sortOrder: index)
            }
        bundle.items = items
        return bundle
    }
}

// MARK: - AttachedBundleItem

@Model
final class AttachedBundleItem {

    var clientID: UUID = UUID()
    var title: String = ""
    var isComplete: Bool = false
    var sortOrder: Int = 0

    var bundle: AttachedBundle? = nil

    init(title: String = "", sortOrder: Int = 0) {
        self.clientID = UUID()
        self.title = title
        self.sortOrder = sortOrder
    }
}

// MARK: - Weather Suggestion

struct WeatherSuggestion {
    var item: String
    var reason: String
    var icon: String
}
