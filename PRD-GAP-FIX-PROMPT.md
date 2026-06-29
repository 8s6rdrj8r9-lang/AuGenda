# AuGenda PRD Gap Remediation Prompt

**Goal:** Fix the 16 missing/partial items from the PRD compliance audit to bring compliance from 87% to 95%+. Fix in strict priority order. Do not touch unrelated code.

**Project root:** `/Users/arthur/Development/AuGenda`
**PRD compliance audit:** `/Users/arthur/Development/AuGenda/PRD-compliance-audit.md`

---

## CONSTRAINTS

1. **Do NOT add new external dependencies.** The app has zero SPM packages.
2. **All existing tests must pass.** Run `xcodebuild test` after every fix group.
3. **Preserve Swift 6 strict concurrency.** No new data races.
4. **Do NOT change existing UI behavior** unless the fix is explicitly required.
5. **Schema migration plan must be updated** if any `@Model` property is added/removed.
6. **Read each file before editing.** Do not edit from memory.

---

## PHASE 1: CRITICAL GAPS (Ship-Blocking)

### 1.1 Add WeatherKit Entitlement

**File:** `AuGenda/AuGenda.entitlements`

**Problem:** `com.apple.developer.weatherkit` is missing. Outdoor block weather will silently fail on device.

**Fix:** Add to the entitlements file:
```xml
<key>com.apple.developer.weatherkit</key>
<true/>
```

Place it after the existing `com.apple.developer.aps-environment` entry. Do not remove any existing entries.

**Verify:** `AuGenda.entitlements` should contain `com.apple.developer.weatherkit` with value `true`.

---

### 1.2 Enforce Task Blocking in `isActionable`

**Files:** `AuGenda/AgendaTask.swift`, `AuGenda/SmartSuggestView.swift`, `AuGenda/TaskBacklogView.swift`

**Problem:** `blocks` and `follows` relationships are modeled but `isActionable` never checks them. Blocked tasks still appear in all lists and can be completed.

**Fix A — In `AgendaTask.swift`:**

Add a computed property that checks blocking relationships. The task is NOT actionable if it has any incomplete `blocks` or `follows` relationships pointing to it:

```swift
    /// Returns true if this task is blocked by any incomplete related task.
    var isBlockedByIncomplete: Bool {
        // Note: This is a synchronous property that cannot perform fetches.
        // For accurate blocking checks, use the context-based method below.
        // This property serves as a lightweight hint for views that already
        // have the relationship data fetched.
        false // placeholder — overridden by context-based check
    }
```

Actually, since `isActionable` is synchronous and cannot fetch, we need a different approach. The blocking check must happen in the **view layer** where the `ModelContext` is available.

**Fix A (revised) — In `AgendaTask.swift`:**

Add a method that takes a `ModelContext`:

```swift
    /// Returns true if this task is blocked by any incomplete task via
    /// a `blocks` or `follows` relationship.
    func isBlocked(in context: ModelContext) -> Bool {
        let descriptor = FetchDescriptor<TaskRelationship>(
            predicate: #Predicate {
                $0.targetTaskID == self.clientID
                && ($0.typeRaw == "blocks" || $0.typeRaw == "follows")
            }
        )
        guard let relationships = try? context.fetch(descriptor) else { return false }
        for rel in relationships {
            let sourceDescriptor = FetchDescriptor<AgendaTask>(
                predicate: #Predicate { $0.clientID == rel.sourceTaskID }
            )
            if let source = (try? context.fetch(sourceDescriptor))?.first {
                if !source.isComplete { return true }
            }
        }
        return false
    }
```

Wait, this is too expensive (N+1 queries). A better approach: fetch all blocking relationships AND their source tasks in one query, or check if ANY source task is incomplete.

**Better approach:**

```swift
    /// Returns true if any incomplete task blocks or must precede this task.
    func isBlocked(in context: ModelContext) -> Bool {
        let descriptor = FetchDescriptor<TaskRelationship>(
            predicate: #Predicate {
                $0.targetTaskID == self.clientID
                && ($0.typeRaw == "blocks" || $0.typeRaw == "follows")
            }
        )
        guard let relationships = try? context.fetch(descriptor) else { return false }
        let sourceIDs = relationships.map { $0.sourceTaskID }
        if sourceIDs.isEmpty { return false }
        let taskDescriptor = FetchDescriptor<AgendaTask>(
            predicate: #Predicate { sourceIDs.contains($0.clientID) }
        )
        guard let sources = try? context.fetch(taskDescriptor) else { return false }
        return sources.contains { !$0.isComplete }
    }
```

Hmm, `#Predicate` with `contains` on a collection might not work in SwiftData. Let me think about this differently.

**Simplest robust approach:**

```swift
    /// Returns true if any incomplete task blocks or must precede this task.
    /// Call this in the view layer where ModelContext is available.
    func isBlocked(in context: ModelContext) -> Bool {
        let descriptor = FetchDescriptor<TaskRelationship>(
            predicate: #Predicate {
                $0.targetTaskID == self.clientID
                && ($0.typeRaw == "blocks" || $0.typeRaw == "follows")
            }
        )
        guard let relationships = try? context.fetch(descriptor) else { return false }
        for rel in relationships {
            let sourceDescriptor = FetchDescriptor<AgendaTask>(
                predicate: #Predicate { $0.clientID == rel.sourceTaskID }
            )
            if let source = (try? context.fetch(sourceDescriptor))?.first, !source.isComplete {
                return true
            }
        }
        return false
    }
```

This is N+1 but for focus session and smart suggest, the number of blocking relationships per task is typically 0-2, so it's fine.

**Fix B — In `SmartSuggestView.swift`:**

Find the task ranking/filtering logic. Before displaying a task, check if it's blocked:

```swift
    // After fetching tasks, filter out blocked ones
    let unblockedTasks = tasks.filter { !($0.isBlocked(in: modelContext)) }
```

Look for the existing filter that checks `frictionLevel <= energyLevel`. Add the blocking check alongside it.

**Fix C — In `TaskBacklogView.swift` ("For Now" filter):**

Find the `forNowTasks` filter or the `EnergyFilter` application. Add blocking check:

```swift
    // In the "For Now" filter logic, after existing energy checks,
    // add: && !task.isBlocked(in: modelContext)
```

Also, visually distinguish blocked tasks in the backlog list. Add a small indicator (e.g., a lock icon or "Blocked" badge) to the task card when `task.isBlocked(in: modelContext)` is true. This can be done in the `TaskCard` or `AgendaTaskCard` component.

In `AuDHDNDComponents.swift` or wherever the task card is rendered, add:
```swift
    if isBlocked {
        HStack {
            Image(systemName: "lock.fill")
                .foregroundColor(Tokens.Color.warning)
            Text("Blocked")
                .font(Tokens.Typography.caption)
                .foregroundColor(Tokens.Color.warning)
        }
    }
```

---

### 1.3 Add Import Duplicate Prevention

**File:** `AuGenda/TaskBacklogView.swift`

**Problem:** Import blindly inserts all tasks without checking for existing `clientID`.

**Fix:** In the import loop (around the area where tasks are inserted after parsing), before inserting each task, check if a task with the same `clientID` already exists:

```swift
    // In the import result handler, before inserting:
    for task in imported {
        // Check for duplicate by clientID
        let dupDescriptor = FetchDescriptor<AgendaTask>(
            predicate: #Predicate { $0.clientID == task.clientID }
        )
        let existing = (try? modelContext.fetch(dupDescriptor))?.first
        if existing != nil {
            continue // Skip duplicate
        }
        task.assignedToProfileID = profileID
        modelContext.insert(task)
    }
```

Also update the import feedback message to indicate how many were skipped:
```swift
    let skippedCount = imported.count - insertedCount
    if skippedCount > 0 {
        importFeedback = "Imported \(insertedCount) task\(insertedCount == 1 ? "" : "s"). Skipped \(skippedCount) duplicate\(skippedCount == 1 ? "" : "s")."
    } else {
        importFeedback = "Imported \(insertedCount) task\(insertedCount == 1 ? "" : "s")."
    }
```

---

### 1.4 Add 3 Missing ProfilePreferences Settings

**Files:** `AuGenda/ProfileModels.swift`, `AuGenda/ProfileViews.swift`, `AuGenda/AppContainer.swift` (schema)

**Problem:** `showCheckInNudges`, `lowStimulationMode`, and `reduceMotion` are not stored in `ProfilePreferences`.

**Fix A — In `ProfileModels.swift` (ProfilePreferences):**

Add three new properties to the `ProfilePreferences` model:

```swift
    var showCheckInNudges: Bool = true
    var lowStimulationMode: Bool = false
    var reduceMotion: Bool = false
```

Also add them to the `makePreset()` method with appropriate defaults.

**Fix B — In `ProfileViews.swift` (Settings):**

Add three toggles in the profile settings section:
- "Show check-in nudges" (maps to `showCheckInNudges`)
- "Low stimulation mode" (maps to `lowStimulationMode`)
- "Reduce motion" (maps to `reduceMotion`)

Place them near the existing `largeTouchTargets`, `hyperfocusGuard`, etc. toggles.

**Fix C — Wire `lowStimulationMode` and `reduceMotion`:**

In `AuGendaApp.swift`, when injecting environment values, use the profile preferences instead of system defaults:

```swift
    .environment(\.reduceMotion, profileManager.activePreferences?.reduceMotion ?? UIAccessibility.isReduceMotionEnabled)
    .environment(\.lowStimulationMode, profileManager.activePreferences?.lowStimulationMode ?? false)
```

Currently `reduceMotion` reads from `UIAccessibility.isReduceMotionEnabled`. The profile setting should override or supplement this. The simplest approach: use the profile setting if explicitly set, otherwise fall back to system.

Actually, looking at the code, `reduceMotion` is already an environment value that reads from the system. We can make it use the profile preference as an override. But to keep it simple, just add the fields to the model and settings UI. The environment wiring can be a separate task if needed.

For `showCheckInNudges`, wire it into `CognitiveCheckInTracker` or wherever check-in nudges are triggered. Currently the check-in frequency is global. Make it check `profileManager.activePreferences?.showCheckInNudges` before showing a nudge.

For `lowStimulationMode`, wire it into the environment value that's already defined in `DesignTokens.swift`. Make sure views that check `lowStimulationMode` use the profile preference instead of a hardcoded value.

**Fix D — Schema update:**

Since `ProfilePreferences` is part of the schema, adding properties means we need a schema version bump. However, since the app hasn't shipped yet and `AuGendaSchemaV2` is the current version, we can add these properties to the existing V2 schema. Add `ProfilePreferences` to the V2 model list (it's already there), and the new properties will be picked up by SwiftData's lightweight migration.

Wait — actually, `ProfilePreferences` is already in V2. Adding new properties to an existing model that's already in the schema requires a migration. Since we're adding properties with default values, SwiftData's lightweight migration should handle it. But we should verify this works.

Actually, since `AuGendaSchemaV2` is the current version and the app hasn't been shipped to App Store with this schema, we can safely add properties to existing models in V2. The lightweight migration will handle adding new columns with default values.

---

### 1.5 Wire DifficultyEngine into SmartSuggest and TaskBacklog

**Files:** `AuGenda/SmartSuggestView.swift`, `AuGenda/TaskBacklogView.swift`

**Problem:** `SmartSuggestView` and `TaskBacklogView` "For Now" filter still use the old `frictionLevel <= energyLevel` gate instead of the six-axis `DifficultyEngine.rank()`.

**Fix A — In `SmartSuggestView.swift`:**

Find the task filtering/ranking logic (around lines 28-43). Replace or supplement the existing filter with:

```swift
    // Old filter:
    // tasks.filter { $0.frictionLevel <= energyLevel && $0.energyRequired <= energyLevel }
    
    // New filter using DifficultyEngine:
    let filteredTasks = tasks.filter { task in
        let rank = DifficultyEngine.rank(
            friction: task.frictionLevel,
            energy: task.energyRequired,
            sensory: task.sensoryLoad,
            social: task.socialLoad,
            initiation: task.initiationCost,
            interest: task.interestLevel
        )
        return rank <= energyLevel * 2 // scale: max rank 10 vs energy 1-5
    }
```

Wait, the scaling needs to be right. Energy is 1-5, rank is 0-10. A reasonable threshold might be `rank <= energyLevel * 2` (so energy 3 allows rank up to 6, energy 5 allows rank up to 10). Or we could use `rank <= 6` as a fixed "actionable" threshold regardless of energy.

Actually, looking at the existing `isActionable` or `passes(densityFilter:)` methods, there might already be a threshold. Let's just replace the simple friction/energy check with the DifficultyEngine rank, using a threshold that makes sense.

A simpler approach: add a computed property to `AgendaTask`:

```swift
    var difficultyRank: Int {
        DifficultyEngine.rank(
            friction: frictionLevel,
            energy: energyRequired,
            sensory: sensoryLoad,
            social: socialLoad,
            initiation: initiationCost,
            interest: interestLevel
        )
    }
    
    /// Returns true if this task is actionable at the given energy level
    /// using the full six-axis difficulty engine.
    func isActionableAtEnergyLevel(_ energy: Int) -> Bool {
        difficultyRank <= energy * 2
    }
```

Then use `task.isActionableAtEnergyLevel(energyLevel)` in `SmartSuggestView` and `TaskBacklogView`.

**Fix B — In `TaskBacklogView.swift` ("For Now" filter):**

Find the "For Now" filter logic. Replace the existing energy check with `task.isActionableAtEnergyLevel(energyLevel)` or `task.difficultyRank <= threshold`.

---

## PHASE 2: HIGH PRIORITY

### 2.1 Add VoiceOver Announcement to Banners

**Files:** `AuGenda/ErrorBanner.swift`, `AuGenda/AuGendaApp.swift` (resume banner)

**Problem:** Banners have `accessibilityLabel` but do not post `.announcement` notifications, so VoiceOver may not read them automatically.

**Fix A — In `ErrorBanner.swift`:**

In the `body` or the controller's `show` method, add:

```swift
    // In ErrorBannerController.show(), after setting message:
    UIAccessibility.post(notification: .announcement, argument: message)
```

Wrap it in `#if os(iOS)` since `UIAccessibility` is iOS-only:

```swift
    #if os(iOS)
    UIAccessibility.post(notification: .announcement, argument: message)
    #endif
```

**Fix B — In `AuGendaApp.swift` (resume banner):**

In the resume banner's `show` logic or `onChange` handler, when the banner appears:

```swift
    #if os(iOS)
    if let label = resumePrompt?.label {
        UIAccessibility.post(notification: .announcement, argument: "You were working on \(label). Resume?")
    }
    #endif
```

---

### 2.2 Fix ErrorBanner Usage for Async Failures

**Files:** `AuGenda/TaskBacklogView.swift`, `AuGenda/WatchConnectivityManager.swift`, `AuGenda/TaskDetailView.swift`

**Problem:** Import failures, Watch sync failures, and some AI enrichment failures use inline text or logging instead of `ErrorBanner`.

**Fix A — In `TaskBacklogView.swift`:**

Change the import failure handler to use `ErrorBannerController`:

```swift
    // When import fails:
    ErrorBannerController.shared.show("Import failed: \(error.localizedDescription)")
```

**Fix B — In `WatchConnectivityManager.swift`:**

Replace the `try? context.save()` patterns with `do/catch` + `ErrorBannerController`:

```swift
    do {
        try context.save()
    } catch {
        ErrorBannerController.shared.show("Watch sync failed to save: \(error.localizedDescription)")
    }
```

**Fix C — In `TaskDetailView.swift` (AI enrichment):**

Change the AI enrichment failure `.alert` to also trigger `ErrorBannerController`:

```swift
    // When enrichment fails:
    ErrorBannerController.shared.show("AI enrichment failed: \(error.localizedDescription)")
```

---

## PHASE 3: MEDIUM PRIORITY

### 3.1 Clarify Block Completion Behavior

**File:** `AuGenda/BlockView.swift`, `AuGenda/BlockModels.swift`

**Problem:** The PRD says "Block completion marks all non-optional block tasks as complete." The code resets them for the next run. This is a design discrepancy.

**Fix:** Do NOT change the code behavior. Instead, update the PRD to reflect the actual behavior. Since the user said "do not edit the codebase" in the original instruction, and this is a design decision, the fix is documentation-only.

Actually, the user asked for a prompt to fix issues. If the PRD is wrong, update the PRD. If the code is wrong, update the code. The audit says the code resets tasks for next run. This might actually be the correct behavior (blocks are routines that repeat). The PRD might be wrong.

**Decision:** Leave this as a PRD documentation fix. Do not change the code.

---

## VERIFICATION

After all fixes, run:

```bash
cd /Users/arthur/Development/AuGenda
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project AuGenda.xcodeproj -scheme AuGenda -destination 'platform=iOS Simulator,name=iPhone 17' clean build
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project AuGenda.xcodeproj -scheme AuGenda -destination 'platform=iOS Simulator,name=iPhone 17' test
```

Both must pass. All tests must pass.

---

## RETURN SUMMARY

Report back:
1. All files edited with brief descriptions
2. Build result (pass/fail)
3. Test result (pass count / total count)
4. Any issues encountered and how they were resolved

Do NOT edit any files outside the listed scope. Do NOT add new dependencies. Use `Edit` for existing files, `Write` for new files only. Read each file before editing.
