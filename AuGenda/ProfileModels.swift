// ProfileModels.swift
// AUDHD Agenda App
//
// Multi-profile foundation for household use.
// Each profile has its own neurotype-aware preferences, avatar, and role.
//
// CloudKit-compatible:
// - All properties have defaults or are optional
// - Enums stored as raw strings
// - Neurotype array stored as comma-separated string

import Combine
import Foundation
import SwiftData
import SwiftUI

// MARK: - Neurotype

enum Neurotype: String, Codable, CaseIterable, Identifiable {
    case adhd
    case autism
    case pda          // Pathological Demand Avoidance profile of autism
    case dyslexia
    case dyspraxia
    case neurotypical

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .adhd:         return "ADHD"
        case .autism:       return "Autistic"
        case .pda:          return "PDA"
        case .dyslexia:     return "Dyslexia"
        case .dyspraxia:    return "Dyspraxia"
        case .neurotypical: return "Neurotypical"
        }
    }

    var tagline: String {
        switch self {
        case .adhd:         return "Time blindness support, hyperfocus guard, dopamine-aware scheduling"
        case .autism:       return "Routine protection, sensory context, predictable notifications"
        case .pda:          return "Choice-framed language, minimal demands, autonomy-first layout"
        case .dyslexia:     return "ND-friendly font, simplified language, generous spacing"
        case .dyspraxia:    return "Larger touch targets, simplified navigation"
        case .neurotypical: return "Standard settings"
        }
    }

    var icon: String {
        switch self {
        case .adhd:         return "bolt.fill"
        case .autism:       return "infinity"
        case .pda:          return "person.fill.checkmark"
        case .dyslexia:     return "text.word.spacing"
        case .dyspraxia:    return "hand.point.up.left.fill"
        case .neurotypical: return "brain"
        }
    }

    /// Apply this neurotype's default preferences to a ProfilePreferences instance.
    /// Called once per neurotype when generating a preset; later neurotypes can override earlier ones.
    func apply(to prefs: ProfilePreferences) {
        switch self {
        case .adhd:
            prefs.hyperfocusGuard                  = true
            prefs.timeBlindnessWarningsEnabled      = true
            prefs.notificationStyleRaw              = NotificationStyle.standard.rawValue
            prefs.energyTrackingEnabled             = true
            prefs.frictionLabelRaw                  = FrictionLabel.friction.rawValue

        case .autism:
            prefs.routineProtectionEnabled          = true
            prefs.transitionPrepMinutes             = 10
            prefs.notificationStyleRaw              = NotificationStyle.predictable.rawValue
            prefs.sensoryContextTagsEnabled         = true
            prefs.energyTrackingEnabled             = true

        case .pda:
            prefs.taskLanguageStyleRaw              = TaskLanguageStyle.choiceOnly.rawValue
            prefs.deadlinePressureVisible           = false
            prefs.notificationStyleRaw              = NotificationStyle.minimal.rawValue
            prefs.routineProtectionEnabled          = true
            prefs.frictionLabelRaw                  = FrictionLabel.effort.rawValue

        case .dyslexia:
            prefs.appFontRaw                        = AppFont.openDyslexic.rawValue
            prefs.largeTouchTargets                 = true
            prefs.taskLanguageStyleRaw              = TaskLanguageStyle.simple.rawValue

        case .dyspraxia:
            prefs.largeTouchTargets                 = true

        case .neurotypical:
            break
        }
    }
}

// MARK: - AppFont

enum AppFont: String, Codable, CaseIterable, Identifiable {
    case system       = "system"
    case atkinson     = "atkinson"
    case openDyslexic = "openDyslexic"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system:       return "System (SF Pro)"
        case .atkinson:     return "Atkinson Hyperlegible"
        case .openDyslexic: return "OpenDyslexic"
        }
    }

    var description: String {
        switch self {
        case .system:       return "Apple's default — optimised for all-round legibility"
        case .atkinson:     return "Designed for low-vision readers; clear character distinction"
        case .openDyslexic: return "Weighted bottoms reduce letter confusion"
        }
    }

    /// Resolve a SwiftUI Font for the given text style, honouring dynamic type.
    /// Requires the font files to be bundled in the app target and listed under
    /// UIAppFonts in Info.plist:
    ///   - AtkinsonHyperlegible-Regular.ttf
    ///   - AtkinsonHyperlegible-Bold.ttf
    ///   - OpenDyslexic-Regular.otf
    func font(for style: Font.TextStyle) -> Font {
        switch self {
        case .system:
            return Font.system(style)
        case .atkinson:
            // ⚠️ Font files must be added to the app target in Xcode
            // (Build Phases → Copy Bundle Resources) and listed in Info.plist
            // under UIAppFonts for Font.custom to resolve correctly.
            return Font.custom("AtkinsonHyperlegible-Regular", size: 16, relativeTo: style)
        case .openDyslexic:
            // ⚠️ Font files must be added to the app target in Xcode
            // (Build Phases → Copy Bundle Resources) and listed in Info.plist
            // under UIAppFonts for Font.custom to resolve correctly.
            return Font.custom("OpenDyslexic", size: 16, relativeTo: style)
        }
    }
}

// MARK: - AppFont environment key

struct AppFontKey: EnvironmentKey {
    static let defaultValue: AppFont = .system
}

extension EnvironmentValues {
    var appFont: AppFont {
        get { self[AppFontKey.self] }
        set { self[AppFontKey.self] = newValue }
    }
}

// MARK: - Font resolution helper

extension Font {
    /// Resolve a text style using the active profile's AppFont.
    /// Use instead of bare .headline / .body etc. in views that should honour per-profile fonts.
    static func app(_ style: Font.TextStyle, scheme: AppFont) -> Font {
        scheme.font(for: style)
    }
}

// MARK: - Supporting enums (raw strings for CloudKit compatibility)

enum ProfileRole: String, Codable, CaseIterable {
    case coordinator  // household admin — can see all profiles, assign to anyone
    case adult        // can assign tasks to any profile including children
    case child        // sees own tasks only; cannot assign
}

enum TaskLanguageStyle: String, Codable, CaseIterable {
    case standard    = "standard"    // direct and clear
    case choiceOnly  = "choiceOnly"  // "you could…" framing (PDA)
    case simple      = "simple"      // short words, no jargon
}

enum NotificationStyle: String, Codable, CaseIterable {
    case standard    = "standard"    // normal frequency and variety
    case predictable = "predictable" // consistent timing patterns, no surprises (autism)
    case minimal     = "minimal"     // as few as possible (PDA)
}

enum FrictionLabel: String, Codable, CaseIterable {
    case friction = "friction"  // "Friction level" — default
    case effort   = "effort"    // "Effort level" — PDA-friendlier
    case energy   = "energy"    // "Energy cost" — alternative framing
}

// MARK: - Profile

@Model
final class Profile {

    // MARK: Identity
    var clientID: UUID = UUID()
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    var name: String = ""
    var roleRaw: String = ProfileRole.adult.rawValue

    /// Comma-separated Neurotype raw values (CloudKit-safe alternative to array)
    var neurotypesRaw: String = ""

    // MARK: Avatar
    /// PNG/JPEG data from Contacts picker (Memoji or contact photo)
    /// To populate: present CNContactPickerViewController filtered to imageDataAvailable == YES,
    /// then store CNContact.imageData here.
    var avatarImageData: Data? = nil

    /// Fallback colour when no avatar image is set (hex string, e.g. "#5AC8FA")
    var avatarColorHex: String = "#5AC8FA"

    // MARK: Ordering & state
    var sortOrder: Int = 0

    // MARK: Relationships
    @Relationship(deleteRule: .cascade, inverse: \ProfilePreferences.profile)
    var preferences: ProfilePreferences? = nil

    // MARK: Computed

    var role: ProfileRole {
        get { ProfileRole(rawValue: roleRaw) ?? .adult }
        set { roleRaw = newValue.rawValue }
    }

    var neurotypes: [Neurotype] {
        get {
            neurotypesRaw
                .split(separator: ",")
                .compactMap { Neurotype(rawValue: String($0)) }
        }
        set {
            neurotypesRaw = newValue.map { $0.rawValue }.joined(separator: ",")
        }
    }

    var canAssignTasks: Bool {
        role == .coordinator || role == .adult
    }

    var initials: String {
        name
            .split(separator: " ")
            .prefix(2)
            .compactMap { $0.first.map { String($0) } }
            .joined()
            .uppercased()
    }

    // MARK: Init

    init(
        name: String = "",
        role: ProfileRole = .adult,
        neurotypes: [Neurotype] = [],
        sortOrder: Int = 0
    ) {
        self.clientID = UUID()
        self.createdAt = .now
        self.updatedAt = .now
        self.name = name
        self.roleRaw = role.rawValue
        self.neurotypesRaw = neurotypes.map { $0.rawValue }.joined(separator: ",")
        self.sortOrder = sortOrder
    }
}

// MARK: - ProfilePreferences

@Model
final class ProfilePreferences {

    // MARK: Identity
    var clientID: UUID = UUID()
    var updatedAt: Date = Date.now

    var profile: Profile? = nil

    // MARK: Energy & EF
    var currentEnergyLevel: Int = 3
    var energyTrackingEnabled: Bool = true
    var lowEFMaxFriction: Int = 2

    /// Home dashboard density mode pinned by the user. Empty = auto-derive
    /// from `currentEnergyLevel` via DensityMode.autoFrom. Stored as raw
    /// String so SwiftData + CloudKit migrations stay additive.
    var densityPinnedRaw: String = ""

    // MARK: Focus sessions
    var focusSessionMinutes: Int = 25
    var breakMinutes: Int = 10
    /// ADHD: hard ceiling on session length to prevent hyperfocus spirals
    var hyperfocusGuard: Bool = false

    // MARK: Language & framing
    var taskLanguageStyleRaw: String = TaskLanguageStyle.standard.rawValue
    var frictionLabelRaw: String = FrictionLabel.friction.rawValue

    // MARK: Transitions & routine
    var transitionPrepMinutes: Int = 5
    var routineProtectionEnabled: Bool = false

    // MARK: Time & deadlines
    var timeBlindnessWarningsEnabled: Bool = false
    var deadlinePressureVisible: Bool = true

    // MARK: Notifications
    var notificationStyleRaw: String = NotificationStyle.standard.rawValue
    var maxNotificationsPerHour: Int = 3

    /// When true, notification titles and bodies redact task content
    /// ("Task" / "Tap to open") so sensitive task details never appear on
    /// the lock screen or in the Notification Center preview. Default ON
    /// because the typical AuGenda task title may contain medication
    /// regimens, therapy logistics, or other private context.
    var notificationPrivacyStrict: Bool = true

    // MARK: Display
    var appFontRaw: String = AppFont.system.rawValue
    var minimalMode: Bool = false
    var largeTouchTargets: Bool = false
    var sensoryContextTagsEnabled: Bool = false
    var highContrastMode: Bool = false
    var showCheckInNudges: Bool = true
    var lowStimulationMode: Bool = false
    var reduceMotion: Bool = false
    var uiScale: Double = 1.0  // 1.0 = normal, 1.25 = large, 1.5 = extra large

    // MARK: Watch
    var watchComplicationMode: String = "next-task"

    /// Comma-separated Neurotype raw values used to build this preset.
    /// Used by resetToPreset() to restore neurotype defaults.
    var appliedPresetRaw: String = ""

    // MARK: Computed accessors

    var taskLanguageStyle: TaskLanguageStyle {
        get { TaskLanguageStyle(rawValue: taskLanguageStyleRaw) ?? .standard }
        set { taskLanguageStyleRaw = newValue.rawValue }
    }

    var frictionLabel: FrictionLabel {
        get { FrictionLabel(rawValue: frictionLabelRaw) ?? .friction }
        set { frictionLabelRaw = newValue.rawValue }
    }

    var notificationStyle: NotificationStyle {
        get { NotificationStyle(rawValue: notificationStyleRaw) ?? .standard }
        set { notificationStyleRaw = newValue.rawValue }
    }

    var appFont: AppFont {
        get { AppFont(rawValue: appFontRaw) ?? .system }
        set { appFontRaw = newValue.rawValue }
    }

    /// Pinned density mode for the Home dashboard. nil → auto-derive from
    /// `currentEnergyLevel`. Setting to nil clears the pin.
    var densityPinned: DensityMode? {
        get {
            guard !densityPinnedRaw.isEmpty else { return nil }
            return DensityMode(rawValue: densityPinnedRaw)
        }
        set {
            densityPinnedRaw = newValue?.rawValue ?? ""
            updatedAt = .now
        }
    }

    /// THE single density resolution rule: an explicit pin wins; otherwise
    /// derive from live energy. Every surface (Home, watch, selector hydrate,
    /// onboarding routing) reads this instead of re-deriving
    /// `pinned ?? autoFrom(energy)` by hand. Computed only — no stored
    /// attribute, so the CloudKit-additive schema contract is preserved.
    var effectiveDensity: DensityMode {
        densityPinned ?? .autoFrom(energyLevel: currentEnergyLevel)
    }

    // MARK: Preset factory

    /// Build a new ProfilePreferences pre-filled with defaults for the given neurotypes.
    /// Neurotypes are applied in order; later entries can override earlier ones.
    static func makePreset(for neurotypes: [Neurotype]) -> ProfilePreferences {
        let prefs = ProfilePreferences()
        prefs.appliedPresetRaw = neurotypes.map { $0.rawValue }.joined(separator: ",")
        for neurotype in neurotypes {
            neurotype.apply(to: prefs)
        }
        prefs.showCheckInNudges = true
        prefs.lowStimulationMode = false
        prefs.reduceMotion = false
        return prefs
    }

    /// Reset all settings back to the neurotype defaults this preset was built from.
    func resetToPreset() {
        let neurotypes = appliedPresetRaw
            .split(separator: ",")
            .compactMap { Neurotype(rawValue: String($0)) }
        guard !neurotypes.isEmpty else { return }
        for neurotype in neurotypes {
            neurotype.apply(to: self)
        }
        updatedAt = .now
    }

    init() {
        self.clientID = UUID()
        self.updatedAt = .now
    }
}

// MARK: - ActiveProfileManager

/// Manages which profile is currently active on this device.
/// Active profile ID is stored in UserDefaults (device-local — prevents CloudKit sync
/// from switching profiles on other devices when you switch here).
@MainActor
final class ActiveProfileManager: ObservableObject {

    nonisolated let objectWillChange = ObservableObjectPublisher()

    static let shared = ActiveProfileManager()

    @Published var activeProfile: Profile? = nil

    var modelContext: ModelContext? {
        didSet { loadActiveProfile() }
    }

    private let activeProfileIDKey = "activeProfileID"

    private init() {}

    // MARK: Load

    func loadActiveProfile() {
        guard let ctx = modelContext else { return }

        // Try to restore the last-used profile by ID
        if let storedIDString = UserDefaults.standard.string(forKey: activeProfileIDKey),
           let storedID = UUID(uuidString: storedIDString) {
            let descriptor = FetchDescriptor<Profile>(
                predicate: #Predicate { $0.clientID == storedID }
            )
            if let profile = (try? ctx.fetch(descriptor))?.first {
                activeProfile = profile
                return
            }
        }

        // Fall back to first available profile
        let descriptor = FetchDescriptor<Profile>(
            sortBy: [SortDescriptor(\.sortOrder)]
        )
        activeProfile = (try? ctx.fetch(descriptor))?.first
        persistActiveProfileID()
    }

    // MARK: Switch

    func switchTo(_ profile: Profile) {
        activeProfile = profile
        persistActiveProfileID()
    }

    // MARK: Seed

    /// Creates a default coordinator profile if no profiles exist yet.
    /// Migrates energy level from legacy UserPreferences if present.
    func seedDefaultsIfNeeded(legacyPreferences: UserPreferences? = nil) {
        guard let ctx = modelContext else { return }

        let descriptor = FetchDescriptor<Profile>()
        let existingCount = (try? ctx.fetch(descriptor))?.count ?? 0
        guard existingCount == 0 else { return }

        let profile = Profile(name: "Me", role: .coordinator, sortOrder: 0)
        let prefs = ProfilePreferences.makePreset(for: Neurotype.audhd)

        // Carry over energy level from legacy prefs if available
        if let legacy = legacyPreferences {
            prefs.currentEnergyLevel = legacy.currentEnergyLevel
            prefs.focusSessionMinutes = legacy.focusSessionMinutes
            prefs.breakMinutes = legacy.breakMinutes
            prefs.minimalMode = legacy.minimalMode
            prefs.watchComplicationMode = legacy.watchComplicationMode
        }

        profile.preferences = prefs
        ctx.insert(profile)
        ctx.insert(prefs)
        do {
            try ctx.save()
        } catch {
            // Banner not available during seeding; log to console only
        }

        activeProfile = profile
        persistActiveProfileID()
    }

    // MARK: Convenience

    var activePreferences: ProfilePreferences? {
        activeProfile?.preferences
    }

    var activeFont: AppFont {
        activePreferences?.appFont ?? .system
    }

    var activeEnergyLevel: Int {
        get { activePreferences?.currentEnergyLevel ?? 3 }
        set {
            activePreferences?.currentEnergyLevel = newValue
            activePreferences?.updatedAt = .now
        }
    }

    // MARK: Private

    private func persistActiveProfileID() {
        UserDefaults.standard.set(
            activeProfile?.clientID.uuidString,
            forKey: activeProfileIDKey
        )
    }
}

// MARK: - Neurotype.audhd convenience

extension Neurotype {
    /// AUDHD is not a separate case — it's ADHD + autism applied together.
    /// This static helper applies both presets in the correct order.
    static var audhd: [Neurotype] { [.adhd, .autism] }
}

extension ProfilePreferences {
    static func makeAUDHDPreset() -> ProfilePreferences {
        makePreset(for: Neurotype.audhd)
    }
}
