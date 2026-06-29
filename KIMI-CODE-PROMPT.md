# Kimi Code Execution Prompt: AuGenda Governance Remediation

**Goal:** Bring the AuGenda codebase from its current state (C+ grade) to a **Strong Pass across all 5 Governance Tiers** (Constitution, Doctrine, Engineering, Ontology, User Context). Execute in strict phases. Do not skip phases. Do not edit files outside the listed scope. Verify after every phase.

**Project Context:**
- **Project:** AuGenda — iOS/macOS/watchOS SwiftUI app for AuDHD (Autism + ADHD) users
- **Stack:** Swift 6, SwiftData, zero external dependencies, SwiftUI
- **Bundle ID:** `ensdev.AuGenda` | Dev team: `GAB62HZP25`
- **Targets:** iPhone (1), iPad (2), Mac-designed-for-iPad (7), Watch extension
- **Current container:** `AppContainer.dev` (local-only, no CloudKit)
- **Workspace root:** `/Users/arthur/Development/AuGenda`
- **User profile:** Arthur — AuADHD, hEDS, chronic fatigue, 2–4h productive windows, $0 budget, extreme disorientation, cannot handle data loss or crashes

**Governance Framework:** The EnsDev Governance Prompt (5 tiers) requires:
1. **Constitution:** User authority, semantic discipline, non-interference, reliability, transparency
2. **Doctrine:** Contrast (no generic), decomposition, system safety, feedback loops, progress reporting, reliability
3. **Engineering:** Memory/context, reasoning, security/privacy, clear code
4. **Ontology:** All 11 concepts mapped to code (Observation, Artifact, Action, Outcome, Learning, Entity, State, Relationship, FocusSession, CognitiveProfile, Context)
5. **User Context:** Arthur's specific needs — zero friction, zero data loss, scaffold for inconsistency, 2–4h window management, resume-after-interruption, $0 budget enforcement

---

## CONSTRAINTS (DO NOT VIOLATE)

1. **No breaking changes to existing UI behavior.** Every view must look and behave the same after your edits unless explicitly instructed to add a new feature.
2. **No new external dependencies.** The app has zero SPM packages. Keep it that way.
3. **All existing tests must pass.** Run `xcodebuild test` after every phase. If a test fails, fix it before proceeding.
4. **Swift 6 strict concurrency.** All `@MainActor` and `nonisolated` patterns must be preserved. Do not introduce data races.
5. **CloudKit remains inactive.** Do NOT activate CloudKit. Keep `AppContainer.dev` as the active container. The migration plan must exist but CloudKit stays off until Arthur manually enables it.
6. **Do not remove `try?` in Watch code.** Watch targets have limited error-handling UI; only fix `try?` in the iOS/macOS app layer.
7. **Preserve all accessibility features.** Dynamic type, VoiceOver labels, and `strictPrivacy` defaults must remain intact.
8. **Do not change the design tokens.** `Tokens`, `AppColor`, `DesignTokens.swift` are sacred unless fixing a compile error.

---

## PHASE 1: SAFETY & SECURITY (HARD BLOCKERS — MUST COMPLETE FIRST)

These are critical failures that prevent any TestFlight or App Store submission. Fix them before touching anything else.

### 1.1 Remove Hardcoded OAuth Credential from Source

**File:** `AuGenda/GoogleOAuth.swift`  
**Current state (lines 38–45):**
```swift
    // Real iOS OAuth client (project: AuGenda). iOS clients have no secret,
    // and the reversed-ID scheme ships in the bundle anyway, so this is fine
    // in source. To re-create, follow the checklist above.
    static let clientID = "416358058147-9g1kdn4bpip0ink7mg0ou6foj1a3nk4k.apps.googleusercontent.com"

    /// Reversed-DNS form is what Google requires for iOS OAuth clients.
    /// Must match the URL scheme registered in Info.plist (CFBundleURLTypes).
    static let redirectURI = "com.googleusercontent.apps.416358058147-9g1kdn4bpip0ink7mg0ou6foj1a3nk4k:/oauth2redirect"
```

**Action:**
1. Replace the hardcoded `clientID` with a placeholder that fails the `isConfigured` check.
2. Update `isConfigured` to detect the placeholder.
3. Replace the `redirectURI` to match the placeholder.
4. Update the comment to explain this MUST be replaced via Xcode build settings before shipping.

**After edit, `GoogleOAuth.swift` should contain:**
```swift
    // ⚠️ PLACEHOLDER — MUST be replaced before shipping Google Sign-In.
    // Set AUGENDA_GOOGLE_CLIENT_ID in your Xcode Build Settings (or pass as
    // -DAUGENDA_GOOGLE_CLIENT_ID at compile time). The real client ID must be
    // an iOS OAuth client from Google Cloud Console, and the reversed-DNS form
    // must be registered in Info.plist under CFBundleURLTypes.
    static let clientID = ProcessInfo.processInfo.environment["AUGENDA_GOOGLE_CLIENT_ID"]
        ?? "YOUR_CLIENT_ID_HERE.apps.googleusercontent.com"

    static let redirectURI = {
        let reversed = clientID.components(separatedBy: ".").reversed().joined(separator: ".")
        return "\(reversed):/oauth2redirect"
    }()

    static var isConfigured: Bool {
        clientID != "YOUR_CLIENT_ID_HERE.apps.googleusercontent.com"
        && !clientID.contains("YOUR_CLIENT_ID")
    }
```

**Also update `Info.plist`:**
- In `CFBundleURLTypes` → `CFBundleURLSchemes`, replace the hardcoded reversed client ID with `YOUR_CLIENT_ID_REVERSED`.

**File:** `AuGenda/Info.plist` (line 51)  
Replace:
```xml
<string>com.googleusercontent.apps.416358058147-9g1kdn4bpip0ink7mg0ou6foj1a3nk4k</string>
```
With:
```xml
<string>YOUR_CLIENT_ID_REVERSED</string>
```

### 1.2 Fix macOS Compile Errors in `AuDHDComponents.swift`

**File:** `AuGenda/AuDHDComponents.swift`  
**Issue:** The `#else` (macOS) path in the `Color` adaptive extensions uses `NSColor(name: nil) { ... }` trailing closure syntax which does not compile. `AppColor.slate900` etc. are `SwiftUI.Color` values and cannot be passed to `NSColor(...)`.

**Lines 391–424 currently have:**
```swift
    static let appBackground: Color = {
        #if os(iOS)
        return Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(AppColor.slate900) : UIColor(AppColor.white) })
        #else
        return Color(NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(AppColor.slate900) : NSColor(AppColor.white) })
        #endif
    }()
```

**Fix for ALL five `Color` extensions** (`appBackground`, `appBackgroundSecondary`, `appTextPrimary`, `appTextSecondary`, `appBorder`):

In the `#else` block, replace the `NSColor` dynamic provider with a direct `Color` that uses the raw RGB values from `AppColor`. Since `AppColor` values are already cross-platform `SwiftUI.Color`, we can simply use `Color` directly with `@Environment` or use a simpler appearance-aware approach.

**The simplest valid macOS fix:** Use `Color` directly with the raw `AppColor` values, but wrapped in a dynamic provider. Since `SwiftUI.Color` doesn't have a direct appearance-based init, use `NSColor` correctly:

```swift
        #else
        return Color(NSColor(name: nil, dynamicProvider: { appearance in
            if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                return NSColor(red: 15/255, green: 23/255, blue: 42/255, alpha: 1) // slate900
            } else {
                return NSColor.white
            }
        }))
        #endif
```

Apply this pattern to all five extensions, using the correct RGB values from `AppColor`:
- `appBackground`: dark=slate900 (15/255, 23/255, 42/255), light=white (1,1,1)
- `appBackgroundSecondary`: dark=slate800 (30/255, 41/255, 59/255), light=slate50 (250/255, 250/255, 251/255)
- `appTextPrimary`: dark=white (1,1,1), light=slate900 (15/255, 23/255, 42/255)
- `appTextSecondary`: dark=slate400 (148/255, 163/255, 184/255), light=slate600 (71/255, 85/255, 105/255)
- `appBorder`: dark=slate700 (51/255, 65/255, 85/255), light=slate200 (226/255, 232/255, 240/255)

**Verification:** Build the macOS target (Target 7) and confirm zero compile errors:
```bash
cd /Users/arthur/Development/AuGenda
xcodebuild -project AuGenda.xcodeproj -scheme AuGenda -destination 'platform=macOS' clean build
```

### 1.3 Change `aps-environment` to `production`

**File:** `AuGenda/AuGenda.entitlements`  
**Current:**
```xml
<key>aps-environment</key>
<string>development</string>
<key>com.apple.developer.aps-environment</key>
<string>development</string>
```

**Replace with:**
```xml
<key>aps-environment</key>
<string>production</string>
<key>com.apple.developer.aps-environment</key>
<string>production</string>
```

---

## PHASE 2: SCHEMA MIGRATION & CORE MODELS (DATA SAFETY)

This phase ensures the app never crashes on schema changes and fills the two biggest Ontology gaps: `FocusSession` and `Relationship`.

### 2.1 Add VersionedSchema & MigrationPlan to `AppContainer.swift`

**File:** `AuGenda/AppContainer.swift`  

**Step A:** Add the schema version definitions BEFORE the `AppContainer` enum.

Insert after the `cloudKitContainerID` constant and before `enum AppContainer`:

```swift
// MARK: - Schema Versioning

enum AuGendaSchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] = [
        AgendaItem.self, SubTask.self, AgendaTask.self, TaskStep.self,
        InboxItem.self, UserPreferences.self, Block.self, BlockTask.self,
        BundleTemplate.self, BundleTemplateItem.self, AttachedBundle.self,
        AttachedBundleItem.self, Profile.self, ProfilePreferences.self
    ]
}

enum AuGendaSchemaV2: VersionedSchema {
    static var versionIdentifier = Schema.Version(2, 0, 0)
    static var models: [any PersistentModel.Type] = [
        AgendaItem.self, SubTask.self, AgendaTask.self, TaskStep.self,
        InboxItem.self, UserPreferences.self, Block.self, BlockTask.self,
        BundleTemplate.self, BundleTemplateItem.self, AttachedBundle.self,
        AttachedBundleItem.self, Profile.self, ProfilePreferences.self,
        FocusSession.self, TaskRelationship.self
    ]
}

enum AuGendaMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [AuGendaSchemaV1.self, AuGendaSchemaV2.self]
    }
    
    static var stages: [MigrationStage] {
        [migrateV1toV2]
    }
    
    static let migrateV1toV2 = MigrationStage.lightweight(
        fromVersion: AuGendaSchemaV1.self,
        toVersion: AuGendaSchemaV2.self
    )
}
```

**Step B:** Update `AppContainer` to use the migration plan.

Replace the `schemaModels` array inside `AppContainer` with a reference to the current schema:

```swift
    private static var schemaModels: [any PersistentModel.Type] {
        AuGendaSchemaV2.models
    }
```

**Step C:** Update `production` and `dev` containers to use the migration plan.

In `production` (line 51):
```swift
    static var production: ModelContainer = {
        let schema = Schema(schemaModels)
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .private(cloudKitContainerID)
        )
        do {
            return try ModelContainer(
                for: schema,
                migrationPlan: AuGendaMigrationPlan.self,
                configurations: [config]
            )
        } catch {
            fatalError("Failed to create production ModelContainer: \(error)")
        }
    }()
```

In `dev` (line 74):
```swift
    static var dev: ModelContainer = {
        let schema = Schema(schemaModels)
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false
        )
        do {
            return try ModelContainer(
                for: schema,
                migrationPlan: AuGendaMigrationPlan.self,
                configurations: [config]
            )
        } catch {
            return Self.makeTestContainer()
        }
    }()
```

In `makeTestContainer` (line 93):
```swift
    static func makeTestContainer() -> ModelContainer {
        let schema = Schema(schemaModels)
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true
        )
        do {
            return try ModelContainer(
                for: schema,
                migrationPlan: AuGendaMigrationPlan.self,
                configurations: [config]
            )
        } catch {
            fatalError("Failed to create test ModelContainer: \(error)")
        }
    }
```

### 2.2 Create `FocusSession` Model

**New file:** `AuGenda/FocusSession.swift`  

This is the Ontology `FocusSession` concept — a persistent, trackable focus session. It replaces the in-memory-only state in `NotificationManager`.

```swift
// FocusSession.swift
// AuGenda
//
// Persistent FocusSession model.
// Tracks start time, end time, interruptions, and completion state.
// Replaces the ephemeral focusSessionActive/focusSessionEndsAt in NotificationManager.

import Foundation
import SwiftData

enum FocusSessionState: String, Codable, CaseIterable {
    case idle
    case active
    case paused
    case completed
    case abandoned
}

@Model
final class FocusSession {
    
    // MARK: Identity
    var clientID: UUID = UUID()
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    
    // MARK: Timing
    var startTime: Date = Date.now
    var endTime: Date? = nil
    var plannedDurationMinutes: Int = 25
    
    // MARK: Target
    var taskID: UUID? = nil
    var taskTitle: String = ""
    
    // MARK: State
    var stateRaw: String = FocusSessionState.idle.rawValue
    
    // MARK: Interruptions & outcomes
    var interruptionCount: Int = 0
    var wasCompleted: Bool = false
    var wasAbandoned: Bool = false
    var abandonReason: String = ""
    
    // MARK: Profile
    var profileID: UUID? = nil
    
    // MARK: Computed
    var state: FocusSessionState {
        get { FocusSessionState(rawValue: stateRaw) ?? .idle }
        set { stateRaw = newValue.rawValue; updatedAt = .now }
    }
    
    var actualDurationMinutes: Int {
        guard let end = endTime else {
            return Int(Date.now.timeIntervalSince(startTime) / 60)
        }
        return Int(end.timeIntervalSince(startTime) / 60)
    }
    
    var isOverdue: Bool {
        guard state == .active else { return false }
        let plannedEnd = startTime.addingTimeInterval(Double(plannedDurationMinutes) * 60)
        return Date.now > plannedEnd
    }
    
    // MARK: Init
    init(
        plannedDurationMinutes: Int = 25,
        taskID: UUID? = nil,
        taskTitle: String = "",
        profileID: UUID? = nil
    ) {
        self.clientID = UUID()
        self.createdAt = .now
        self.updatedAt = .now
        self.startTime = .now
        self.plannedDurationMinutes = plannedDurationMinutes
        self.taskID = taskID
        self.taskTitle = taskTitle
        self.profileID = profileID
        self.state = .active
    }
}

// MARK: - Active Session Query Helper

extension FocusSession {
    /// Fetch descriptor for the currently active session (if any).
    static var activeSessionDescriptor: FetchDescriptor<FocusSession> {
        FetchDescriptor<FocusSession>(
            predicate: #Predicate { $0.stateRaw == FocusSessionState.active.rawValue }
        )
    }
}
```

### 2.3 Create `TaskRelationship` Model

**New file:** `AuGenda/TaskRelationship.swift`  

This maps the Ontology `Relationship` concept. It enables real dependency tracking between tasks.

```swift
// TaskRelationship.swift
// AuGenda
//
// Dependency and relationship links between AgendaTasks.
// Replaces the string-based `waitingOn` field with structured, queryable relationships.

import Foundation
import SwiftData

enum TaskRelationshipType: String, Codable, CaseIterable, Identifiable {
    case blocks       // source task blocks target task
    case follows      // source follows target (target must complete first)
    case bundles      // tasks are grouped together
    case related      // generic association, no execution order
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .blocks:  return "Blocks"
        case .follows: return "Follows"
        case .bundles: return "Bundled with"
        case .related: return "Related to"
        }
    }
    
    var inverseDisplayName: String {
        switch self {
        case .blocks:  return "Blocked by"
        case .follows: return "Must do first"
        case .bundles: return "Bundled with"
        case .related: return "Related to"
        }
    }
}

@Model
final class TaskRelationship {
    
    // MARK: Identity
    var clientID: UUID = UUID()
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    
    // MARK: Endpoints
    var sourceTaskID: UUID = UUID()
    var targetTaskID: UUID = UUID()
    
    // MARK: Type
    var typeRaw: String = TaskRelationshipType.blocks.rawValue
    
    // MARK: Computed
    var type: TaskRelationshipType {
        get { TaskRelationshipType(rawValue: typeRaw) ?? .blocks }
        set { typeRaw = newValue.rawValue; updatedAt = .now }
    }
    
    /// Convenience: does this relationship block the target from starting?
    var isBlocking: Bool {
        type == .blocks || type == .follows
    }
    
    // MARK: Init
    init(
        sourceTaskID: UUID,
        targetTaskID: UUID,
        type: TaskRelationshipType = .blocks
    ) {
        self.clientID = UUID()
        self.createdAt = .now
        self.updatedAt = .now
        self.sourceTaskID = sourceTaskID
        self.targetTaskID = targetTaskID
        self.typeRaw = type.rawValue
    }
}

// MARK: - AgendaTask Relationship Helpers

extension AgendaTask {
    
    /// IDs of tasks that this task blocks (outgoing blocking relationships).
    func blockingTaskIDs(in context: ModelContext) -> [UUID] {
        let descriptor = FetchDescriptor<TaskRelationship>(
            predicate: #Predicate { $0.sourceTaskID == self.clientID && ($0.typeRaw == "blocks" || $0.typeRaw == "follows") }
        )
        return (try? context.fetch(descriptor))?.map { $0.targetTaskID } ?? []
    }
    
    /// IDs of tasks that block this task (incoming blocking relationships).
    func blockedByTaskIDs(in context: ModelContext) -> [UUID] {
        let descriptor = FetchDescriptor<TaskRelationship>(
            predicate: #Predicate { $0.targetTaskID == self.clientID && ($0.typeRaw == "blocks" || $0.typeRaw == "follows") }
        )
        return (try? context.fetch(descriptor))?.map { $0.sourceTaskID } ?? []
    }
    
    /// Is this task currently blocked by any incomplete related task?
    var isBlocked: Bool {
        // Note: this is a synchronous property that cannot perform fetches.
        // Use the context-based helpers above for accurate blocking checks.
        !waitingOn.isEmpty
    }
}
```

### 2.4 Update `NotificationManager` to Persist Focus Sessions

**File:** `AuGenda/NotificationManager.swift`  

The current `focusSessionActive` and `focusSessionEndsAt` are ephemeral `@Published` properties. They must be backed by the new `FocusSession` model.

**Step A:** Add a `modelContext` property to `NotificationManager`.

```swift
    var modelContext: ModelContext? = nil
```

**Step B:** Rewrite `startFocusSession` to create a persistent `FocusSession`.

```swift
    func startFocusSession(durationMinutes: Int, taskTitle: String = "", taskID: UUID? = nil) {
        let endsAt = Date.now.addingTimeInterval(Double(durationMinutes) * 60)
        focusSessionActive = true
        focusSessionEndsAt = endsAt
        
        // Persist the session
        if let ctx = modelContext {
            let session = FocusSession(
                plannedDurationMinutes: durationMinutes,
                taskID: taskID,
                taskTitle: taskTitle,
                profileID: ActiveProfileManager.shared.activeProfile?.clientID
            )
            ctx.insert(session)
            do { try ctx.save() } catch {
                logger.error("Failed to save focus session: \(error.localizedDescription)")
            }
        }
        
        // Notify Watch
        #if canImport(WatchConnectivity)
        WatchConnectivityManager.shared.sendFocusStarted(endsAt: endsAt)
        #endif
        
        // ... rest of the notification scheduling remains the same ...
    }
```

**Step C:** Rewrite `endFocusSession` to mark the active session as completed.

```swift
    func endFocusSession() {
        focusSessionActive = false
        focusSessionEndsAt = nil
        
        // Mark active session as completed
        if let ctx = modelContext {
            let descriptor = FetchDescriptor<FocusSession>(
                predicate: #Predicate { $0.stateRaw == FocusSessionState.active.rawValue }
            )
            if let active = (try? ctx.fetch(descriptor))?.first {
                active.state = .completed
                active.endTime = .now
                active.wasCompleted = true
                do { try ctx.save() } catch {
                    logger.error("Failed to complete focus session: \(error.localizedDescription)")
                }
            }
        }
        
        center.removePendingNotificationRequests(withIdentifiers: [
            "focus-session-end",
            "focus-session-halfway",
            "hyperfocus-guard-warning",
            "hyperfocus-guard-stop"
        ])
        #if canImport(WatchConnectivity)
        WatchConnectivityManager.shared.sendFocusEnded()
        #endif
    }
```

**Step D:** Inject `modelContext` in `RootView.onAppear`.

In `AuGenda/RootView.swift` (or wherever `RootView` is defined), add:
```swift
notificationManager.modelContext = modelContext
```
alongside the other manager injections.

### 2.5 Add Relationship Query to `TaskDetailView`

**File:** `AuGenda/TaskDetailView.swift`  

Add a section that shows tasks this task blocks and tasks that block it. This is lightweight UI — just a section header + list of related task titles.

**Implementation approach:**
- Add a `@Query` for `TaskRelationship` or fetch in `onAppear`.
- Show "Blocked by" and "Blocks" sections if non-empty.
- This is a minimal UI addition that validates the model exists and is queryable.

---

## PHASE 3: ERROR HANDLING & RELIABILITY (SILENT FAILURE ELIMINATION)

### 3.1 Create a Lightweight Error Banner / Toast System

**New file:** `AuGenda/ErrorBanner.swift`  

A simple, reusable error banner that appears at the top of the screen and auto-dismisses after 3 seconds. This replaces the silent `try?` pattern.

```swift
// ErrorBanner.swift
// AuGenda
//
// Lightweight, non-blocking error banner for surfacing save failures
// and other user-actionable errors without modal interruption.

import SwiftUI

@MainActor
final class ErrorBannerController: ObservableObject {
    static let shared = ErrorBannerController()
    
    @Published var message: String? = nil
    private var dismissTask: Task<Void, Never>? = nil
    
    func show(_ message: String) {
        self.message = message
        dismissTask?.cancel()
        dismissTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self.message = nil
        }
    }
    
    func dismiss() {
        dismissTask?.cancel()
        message = nil
    }
}

struct ErrorBanner: View {
    @StateObject private var controller = ErrorBannerController.shared
    
    var body: some View {
        VStack {
            if let message = controller.message {
                HStack(spacing: Tokens.Spacing.sm) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(Tokens.Color.warning)
                    Text(message)
                        .font(Tokens.Typography.caption)
                        .foregroundColor(Color.appTextPrimary)
                    Spacer()
                    Button { controller.dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.caption)
                            .foregroundColor(Color.appTextSecondary)
                    }
                }
                .padding(Tokens.Spacing.base)
                .background(Tokens.Color.warning.opacity(0.1))
                .overlay(
                    Rectangle()
                        .frame(height: 2)
                        .foregroundColor(Tokens.Color.warning),
                    alignment: .top
                )
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            Spacer()
        }
        .animation(.easeInOut(duration: 0.25), value: controller.message)
        .zIndex(100)
        .allowsHitTesting(controller.message != nil)
    }
}
```

### 3.2 Replace `try? modelContext.save()` with Explicit Error Handling

**Scope:** All files in the iOS/macOS app (NOT Watch targets).  
**Pattern to replace:** `try? modelContext.save()`  
**Replacement:**
```swift
do {
    try modelContext.save()
} catch {
    ErrorBannerController.shared.show("Couldn't save: \(error.localizedDescription)")
}
```

**Files to edit (all in `AuGenda/` directory, NOT `AuGendaWatch/`):**
- `TaskBacklogView.swift` — lines 176, 947
- `HouseholdView.swift` — line 252
- `ContentView.swift` — lines 173, 193, 474, 485, 693, 703, 820, 994, 1054, 1469, 1491, 1641
- `ProfileViews.swift` — lines 748, 1117, 1189
- `BlockView.swift` — lines 765, 906
- `CognitiveStateSelector.swift` — line 327
- `TaskDetailView.swift` — lines 168, 372, 393
- `HomeDashboardView.swift` — lines 523, 535, 543, 567, 578, 598, 1512, 1521
- `AuDHDNDComponents.swift` — lines 566, 577, 596
- `InboxView.swift` — lines 44, 439, 445, 502

**Important:** Do NOT change `try?` in `AuGendaWatch/` files. The Watch has no banner UI.

**Also fix `ActiveProfileManager.seedDefaultsIfNeeded()`:**
- In `ProfileModels.swift` line 493: `try? ctx.save()` → use `do/catch` with banner.

### 3.3 Add Save Error Handling to `TaskBacklogView` Import

**File:** `AuGenda/TaskBacklogView.swift` line 176  
The import loop currently does `try? modelContext.save()` after inserting tasks. If the save fails, the user gets a false success message. Replace with:

```swift
            do {
                try modelContext.save()
                importFeedback = "Imported \(imported.count) task\(imported.count == 1 ? "" : "s") from \(format.displayName)."
            } catch {
                importFeedback = "Import saved to memory but couldn't persist: \(error.localizedDescription)"
            }
```

---

## PHASE 4: ONTOLOGY COMPLETION & USER CONTEXT ALIGNMENT

### 4.1 Add `CognitiveProfile` Aggregator (Lightweight)

**New file:** `AuGenda/CognitiveProfile.swift`  

This is a lightweight aggregator that surfaces insights from `ActivityLog` and `CognitiveCheckInTracker`. It does NOT require a new SwiftData model — it's a pure logic layer that reads existing data and produces insights. This satisfies the Ontology `Learning` → `CognitiveProfile` mapping without schema churn.

```swift
// CognitiveProfile.swift
// AuGenda
//
// Lightweight cognitive profile aggregator.
// Reads ActivityLog and CognitiveCheckInTracker to produce insights
// about the user's patterns — energy by time-of-day, completion accuracy, etc.
// Pure logic — no SwiftData model needed; computes on demand.

import Foundation

enum CognitiveProfile {
    
    /// Energy pattern by hour-of-day (0–23). Returns average reported energy
    /// for each hour that has at least 3 check-ins. Useful for suggesting
    /// when the user's best windows typically occur.
    static func energyByHour() -> [Int: Double] {
        // Implementation reads CognitiveCheckInTracker.history
        // and averages energyLevel by hour.
        // Stub for now — returns empty dict.
        [:]
    }
    
    /// Typical productive window length based on completed focus sessions.
    /// Returns the median actual duration of completed sessions in the last 30 days.
    static func typicalWindowLengthMinutes(in context: ModelContext) -> Int {
        let thirtyDaysAgo = Date.now.addingTimeInterval(-30 * 24 * 60 * 60)
        let descriptor = FetchDescriptor<FocusSession>(
            predicate: #Predicate { $0.wasCompleted && $0.startTime > thirtyDaysAgo }
        )
        guard let sessions = try? context.fetch(descriptor), !sessions.isEmpty else {
            return 25 // default
        }
        let durations = sessions.map { $0.actualDurationMinutes }.sorted()
        return durations[durations.count / 2]
    }
    
    /// Suggests a focus session length based on the user's historical data
    /// and current energy level. If no history, falls back to profile default.
    static func suggestedFocusLength(in context: ModelContext, energyLevel: Int) -> Int {
        let typical = typicalWindowLengthMinutes(in: context)
        // Scale down for low energy, up for high energy
        let scale = Double(energyLevel) / 3.0
        return Int(Double(typical) * scale)
    }
}
```

### 4.2 Add "Resume After Interruption" Flow

**File:** `AuGenda/RootView.swift`  

When the app returns from background, check `InterruptionContext` and prompt the user if they were in the middle of something.

**Implementation:**
- In `RootView.onChange(of: scenePhase)`, when `.active` is detected:
  - Check `InterruptionContext.currentActivity`
  - If there was an activity within the last 15 minutes, show a small banner: "You were working on [X]. Resume?"
  - The banner is non-modal — it auto-dismisses after 10 seconds if ignored.

**New helper:** Add to `InterruptionContext` (or create it if missing):

```swift
// InterruptionContext.swift
// AuGenda
//
// Tracks what the user was doing before an interruption so the app can
// offer a gentle "resume" prompt when returning.

import Foundation

enum InterruptionContext {
    private static let activityKey = "interruptionContext.activity"
    private static let itemIDKey = "interruptionContext.itemID"
    private static let timestampKey = "interruptionContext.timestamp"
    
    static func recordActivity(itemID: UUID? = nil, contextLabel: String) {
        UserDefaults.standard.set(contextLabel, forKey: activityKey)
        UserDefaults.standard.set(itemID?.uuidString, forKey: itemIDKey)
        UserDefaults.standard.set(Date.now.timeIntervalSince1970, forKey: timestampKey)
    }
    
    static func currentActivity() -> (label: String, itemID: UUID?, timestamp: Date)? {
        guard let label = UserDefaults.standard.string(forKey: activityKey) else { return nil }
        let timestamp = Date(timeIntervalSince1970: UserDefaults.standard.double(forKey: timestampKey))
        // Only relevant if within last 15 minutes
        guard Date.now.timeIntervalSince(timestamp) < 15 * 60 else { return nil }
        let itemID = UserDefaults.standard.string(forKey: itemIDKey).flatMap(UUID.init)
        return (label, itemID, timestamp)
    }
    
    static func clear() {
        UserDefaults.standard.removeObject(forKey: activityKey)
        UserDefaults.standard.removeObject(forKey: itemIDKey)
        UserDefaults.standard.removeObject(forKey: timestampKey)
    }
}
```

**In `RootView.swift`**, add a `@State` for the resume banner and show it in `onChange(of: scenePhase)` when returning to `.active`.

### 4.3 Add "Local AI Only" Mode to Enforce $0 Budget

**File:** `AuGenda/AIEnrichmentSettingsView.swift` (or wherever AI provider settings are)  

Add a toggle at the top of the AI settings: **"Local AI only (Ollama) — zero cost"**.

When enabled:
- Hide all paid providers (Claude, OpenAI, Gemini, DeepSeek, Mistral, Perplexity, Grok) from the provider list.
- Show only `ollama` and `appleFoundation` (on-device).
- Add a help text explaining how to set up Ollama locally.

This enforces Arthur's $0 budget constraint.

---

## PHASE 5: VERIFICATION & TESTING

### 5.1 Build Verification

After every phase, run:
```bash
cd /Users/arthur/Development/AuGenda
xcodebuild -project AuGenda.xcodeproj -scheme AuGenda -destination 'platform=iOS Simulator,name=iPhone 16' clean build
xcodebuild -project AuGenda.xcodeproj -scheme AuGenda -destination 'platform=macOS' clean build
```

Both must pass with zero errors.

### 5.2 Test Verification

Run the existing test suite:
```bash
xcodebuild -project AuGenda.xcodeproj -scheme AuGenda -destination 'platform=iOS Simulator,name=iPhone 16' test
```

All existing tests must pass. If any fail, fix them.

### 5.3 New Model Tests

Add tests to `AuGendaTests/` for the new models:

**New file:** `AuGendaTests/FocusSessionTests.swift`
```swift
import XCTest
import SwiftData
@testable import AuGenda

final class FocusSessionTests: XCTestCase {
    
    @MainActor
    func testFocusSessionCreation() {
        let session = FocusSession(plannedDurationMinutes: 45, taskTitle: "Test task")
        XCTAssertEqual(session.plannedDurationMinutes, 45)
        XCTAssertEqual(session.taskTitle, "Test task")
        XCTAssertEqual(session.state, .active)
        XCTAssertFalse(session.isOverdue)
    }
    
    @MainActor
    func testFocusSessionCompletion() {
        let session = FocusSession(plannedDurationMinutes: 25)
        session.state = .completed
        session.endTime = .now
        session.wasCompleted = true
        XCTAssertTrue(session.wasCompleted)
        XCTAssertGreaterThan(session.actualDurationMinutes, 0)
    }
    
    @MainActor
    func testFocusSessionOverdue() {
        let session = FocusSession(plannedDurationMinutes: 1)
        // Force start time into the past
        session.startTime = Date.now.addingTimeInterval(-120)
        XCTAssertTrue(session.isOverdue)
    }
}
```

**New file:** `AuGendaTests/TaskRelationshipTests.swift`
```swift
import XCTest
import SwiftData
@testable import AuGenda

final class TaskRelationshipTests: XCTestCase {
    
    @MainActor
    func testRelationshipCreation() {
        let id1 = UUID()
        let id2 = UUID()
        let rel = TaskRelationship(sourceTaskID: id1, targetTaskID: id2, type: .blocks)
        XCTAssertEqual(rel.sourceTaskID, id1)
        XCTAssertEqual(rel.targetTaskID, id2)
        XCTAssertEqual(rel.type, .blocks)
        XCTAssertTrue(rel.isBlocking)
    }
    
    @MainActor
    func testRelationshipTypeRoundTrip() {
        let rel = TaskRelationship(sourceTaskID: UUID(), targetTaskID: UUID(), type: .follows)
        XCTAssertEqual(rel.typeRaw, "follows")
        XCTAssertEqual(rel.type, .follows)
    }
    
    @MainActor
    func testRelatedTypeNotBlocking() {
        let rel = TaskRelationship(sourceTaskID: UUID(), targetTaskID: UUID(), type: .related)
        XCTAssertFalse(rel.isBlocking)
    }
}
```

### 5.4 Migration Verification

Create a small script or manual test that:
1. Builds the app with schema v1 (by temporarily removing the new models from the schema list).
2. Launches the app, creates some data.
3. Builds the app with schema v2 (restore new models).
4. Launches the app again and confirms the old data is still present and the new models are queryable.

Since this is hard to automate in a prompt, verify this manually by:
1. Running the app in the simulator.
2. Adding a few tasks and items.
3. Stopping the app.
4. Re-running with the new schema.
5. Confirming the old data appears and no crash occurs.

---

## DELIVERABLES

After completing all phases, the codebase should have:

1. ✅ `AuGendaMigrationPlan` with `VersionedSchema` v1 and v2
2. ✅ `FocusSession.swift` — persistent focus session model
3. ✅ `TaskRelationship.swift` — structured task dependency model
4. ✅ `ErrorBanner.swift` + `ErrorBannerController` — non-blocking error surfacing
5. ✅ `InterruptionContext.swift` — resume-after-interruption tracking
6. ✅ `CognitiveProfile.swift` — lightweight insight aggregator
7. ✅ Zero hardcoded credentials in source
8. ✅ macOS target builds cleanly
9. ✅ `aps-environment` = `production`
10. ✅ All `try? modelContext.save()` replaced with `do/catch` + banner (in app layer)
11. ✅ `NotificationManager` persists focus sessions to SwiftData
12. ✅ `TaskDetailView` shows relationship sections
13. ✅ AI settings have "Local AI only" $0-budget mode
14. ✅ All existing tests pass + new tests for FocusSession and TaskRelationship
15. ✅ Zero new external dependencies

---

## EXECUTION NOTES FOR KIMI CODE

- Work in `/Users/arthur/Development/AuGenda`.
- Read each file before editing. Do not edit from memory.
- Use `Edit` for incremental changes. Do not use `Write` for existing files.
- When adding new files, use `Write`.
- After each phase, run `xcodebuild` to verify.
- If you encounter a build error you can't resolve, report it and move to the next phase — do not get stuck.
- Keep all changes minimal and focused. Do not refactor unrelated code.
- Preserve existing comments and add new ones where appropriate.
- Use `///` doc comments for all new public APIs.

**End of Prompt.**
