# AuGenda — Developer Documentation

**Last updated:** 2026-05-26  
**Swift:** 5.0 (project setting) running Swift 6 strict concurrency  
**Project type:** SwiftUI + SwiftData, iOS/macOS dual-target, no external dependencies

---

## 1. BUILD & SETUP

### 1.1 Deployment targets

| Setting | Value |
|---|---|
| `IPHONEOS_DEPLOYMENT_TARGET` | 26.5 |
| `MACOSX_DEPLOYMENT_TARGET` | 26.3 |
| `SWIFT_VERSION` | 5.0 |
| `TARGETED_DEVICE_FAMILY` | `"1,2,7"` — iPhone (1), iPad (2), Mac-designed-for-iPad (7) |
| `SDKROOT` | `auto` — Xcode picks the right SDK per destination |
| `CODE_SIGN_STYLE` | Automatic |
| `DEVELOPMENT_TEAM` | `GAB62HZP25` |

The project builds for **native macOS** (not Catalyst). `TARGETED_DEVICE_FAMILY = 7` plus `MACOSX_DEPLOYMENT_TARGET` together enable "Designed for iPad" on Mac. The codebase also contains fully-native macOS-specific SwiftUI branches (`#if os(iOS)`) throughout, so it's being actively developed as a dual-target app.

### 1.2 Bundle identifiers and targets

| Target | Bundle ID | Type |
|---|---|---|
| AuGenda | `ensdev.AuGenda` | Application |
| AuGendaTests | `ensdev.AuGendaTests` | Unit test bundle |
| AuGendaUITests | `ensdev.AuGendaUITests` | UI test bundle |

No watchOS target exists yet. `WatchConnectivity` is conditionally imported (`#if canImport(WatchConnectivity)`) throughout so a Watch extension can be added later without changing the existing source.

### 1.3 External dependencies

**Zero SPM packages.** All frameworks are Apple system frameworks:

| Framework | Where used |
|---|---|
| `SwiftUI` | All views |
| `SwiftData` | All model files |
| `Combine` | `NotificationManager`, `WatchConnectivityManager`, `BlockManager`, `ActiveProfileManager` — `ObservableObjectPublisher` |
| `UserNotifications` | `NotificationManager.swift` |
| `WatchConnectivity` | `WatchConnectivityManager.swift` (conditional) |
| `WeatherKit` | `BlockView.swift` → `BlockManager` |
| `CoreLocation` | `BlockView.swift` → `BlockManager` |
| `Contacts` + `ContactsUI` | `ProfileViews.swift` — avatar picker |
| `UIKit` | `ProfileViews.swift`, `TaskDetailView.swift` — iOS-specific UI |
| `CloudKit` | Declared in entitlements; routed through SwiftData's `ModelConfiguration` |

**Font files** — referenced in code but need to be added to the bundle and `UIAppFonts` in Info.plist if you activate non-system fonts:

- `AtkinsonHyperlegible-Regular.ttf`
- `AtkinsonHyperlegible-Bold.ttf`
- `OpenDyslexic-Regular.otf`

These are referenced in `ProfileModels.swift` `AppFont.font(for:)`. If the files are missing, `Font.custom(...)` silently falls back to system font — no crash, but the user's dyslexia/legibility font choice is silently ignored.

### 1.4 Capabilities and entitlements

**File:** `AuGenda/AuGenda.entitlements`

```xml
aps-environment: development
com.apple.developer.aps-environment: development
com.apple.developer.icloud-container-identifiers: [] ← EMPTY — must be filled in
com.apple.developer.icloud-services: [CloudKit]
```

**Missing entitlements that need to be added before production:**
- `com.apple.developer.weatherkit: true` — required for `WeatherKit` API calls in `BlockManager`
- `com.apple.developer.icloud-container-identifiers` must contain the actual container ID

**`Info.plist` background modes:**
```xml
UIBackgroundModes: [remote-notification]
```

**Missing privacy strings** — `BlockManager` requests location at `kCLLocationAccuracyKilometer` and calls WeatherKit. These usage description strings must be added to Info.plist (or as `INFOPLIST_KEY_*` build settings) or the app will crash on first location request:
- `NSLocationWhenInUseUsageDescription`
- `NSWeatherKitClientIdentifier` (if using server-side WeatherKit; not needed for `WeatherService.shared` on-device)

### 1.5 Terminal build commands

```bash
# List available simulators
xcrun simctl list devices available

# Build for iOS Simulator (clean)
xcodebuild clean build \
  -project AuGenda.xcodeproj \
  -scheme AuGenda \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  | xcbeautify

# Run on simulator
xcodebuild test \
  -project AuGenda.xcodeproj \
  -scheme AuGendaTests \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro'

# Build for macOS
xcodebuild clean build \
  -project AuGenda.xcodeproj \
  -scheme AuGenda \
  -destination 'platform=macOS'
```

### 1.6 CloudKit — production not yet active

`AuGendaApp.swift` line 26:
```swift
.modelContainer(AppContainer.preview)   // ← in-memory; wipes on every launch
// .modelContainer(AppContainer.production)  ← uncomment when CloudKit is ready
```

`AppContainer.swift` line 7:
```swift
private let cloudKitContainerID = "iCloud.com.yourname.audhd-agenda"  // ← PLACEHOLDER
```

**Both must be changed before shipping.** The container ID needs to match what's provisioned in App Store Connect → CloudKit Console → Containers.

---

## 2. ARCHITECTURE & PATTERNS

### 2.1 SwiftData schema — all 13 models

All models are CloudKit-compatible by design: every property has a default value or is optional, enums are stored as raw `String`, and arrays are stored as comma-separated strings instead of relationships where CloudKit has relational limits.

**Scheduling domain:**

| Model | File | Key fields |
|---|---|---|
| `AgendaItem` | `AgendaItem.swift` | `title`, `scheduledDate`, `frictionLevel` (1–5), `energyRequired` (1–4), `contextTag`, `snoozedUntil`, `recurrenceRule` ("none"/"daily"/"weekly"/"weekdays"), `priority` (0/1/2), `assignedToProfileID`, `assignedByProfileID` |
| `SubTask` | `AgendaItem.swift` | `title`, `isComplete`, `sortOrder`; `@Relationship(deleteRule: .cascade, inverse: \SubTask.parentItem)` from `AgendaItem` |
| `AgendaTask` | `AgendaTask.swift` | Like `AgendaItem` but no `scheduledDate` — lives in backlog. Adds `interestLevel`, `estimatedMinutes`, `waitingOn`, `isAbandoned`, `hyperfocusRisk`. Has `ndPriorityScore` computed property. |
| `TaskStep` | `AgendaTask.swift` | Subtask of `AgendaTask`; adds `estimatedMinutes` |

**Block domain:**

| Model | File | Key fields |
|---|---|---|
| `Block` | `BlockModels.swift` | `typeRaw` → `BlockType` enum, `currentStreak`, `lastCompletedDate`, `weatherCheckEnabled` |
| `BlockTask` | `BlockModels.swift` | `title`, `isComplete`, `isOptional` |
| `BundleTemplate` | `BlockModels.swift` | Reusable bundle definition; `autoPromptBlockTypesRaw` comma-sep |
| `BundleTemplateItem` | `BlockModels.swift` | Item within a `BundleTemplate` |
| `AttachedBundle` | `BlockModels.swift` | Instance of a bundle attached to one `Block` run |
| `AttachedBundleItem` | `BlockModels.swift` | Item within an `AttachedBundle` |

**Profile domain:**

| Model | File | Key fields |
|---|---|---|
| `Profile` | `ProfileModels.swift` | `name`, `roleRaw` → `ProfileRole`, `neurotypesRaw` (comma-sep `Neurotype`), `avatarImageData` (PNG/JPEG), `avatarColorHex` |
| `ProfilePreferences` | `ProfileModels.swift` | 20+ per-profile settings: `currentEnergyLevel`, `hyperfocusGuard`, `taskLanguageStyleRaw`, `notificationStyleRaw`, `appFontRaw`, etc. |

**Legacy:**

| Model | File | Notes |
|---|---|---|
| `UserPreferences` | `AppContainer.swift` | Single-user precursor to `ProfilePreferences`. Retained for migration. New code should not use it. |

**`typealias Task = AgendaTask`** is declared in `Task.swift`. It exists because `AgendaTask.swift` was renamed from `Task.swift` to avoid colliding with Swift's built-in `Task` concurrency type. Existing views (`TaskBacklogView`, `SmartSuggestView`, `TaskDetailView`) still compile through the alias. **New code should use `AgendaTask` directly.**

### 2.2 Key computed properties

**`AgendaTask.ndPriorityScore: Double`** (`AgendaTask.swift` line 135):
```swift
// priority * 3.0 + interestLevel * 1.5 - frictionLevel * 1.0 - energyRequired * 0.5
```
Used by `SmartSuggestView`, `TaskBacklogView` ("For Now" sort), `FocusSessionView` to surface the most actionable task. Higher = more worth doing right now.

**`AgendaTask.isActionable: Bool`** — false if complete, abandoned, or deferred past now.

**`AgendaTask.totalEstimatedMinutes: Int`** — sums `TaskStep.estimatedMinutes` if steps exist, else returns `estimatedMinutes`.

**`Block.shouldAutoSurface: Bool`** — true if `type == .startup`, not complete, and `lastCompletedDate` is not today. Used in `ContentView` to auto-prompt the startup block.

### 2.3 State management — no MVVM

The app uses **flat SwiftUI patterns only** — no separate ViewModel types.

**@Query** — views fetch their own data directly:
```swift
@Query(sort: \AgendaItem.scheduledDate) private var items: [AgendaItem]
```

**@EnvironmentObject** — four singleton managers injected at root:
```swift
// AuGendaApp.swift — injected onto WindowGroup
.environmentObject(notificationManager)   // NotificationManager.shared
.environmentObject(blockManager)          // BlockManager.shared
.environmentObject(profileManager)        // ActiveProfileManager.shared
.environmentObject(watchManager)          // WatchConnectivityManager.shared (iOS only)
```

**@Environment(\.modelContext)** — used in views that write data:
```swift
@Environment(\.modelContext) private var modelContext
// ... 
try? modelContext.save()
```

**Why no MVVM:** SwiftData's `@Query` macro gives reactive data fetching at the view layer for free. Adding ViewModels between the view and SwiftData would be extra indirection with no gain for this codebase size.

**ModelContext injection into managers** — managers receive `modelContext` after they're initialized, via a `var modelContext: ModelContext?` property set in `RootView.onAppear`:
```swift
// RootView.swift
blockManager.modelContext = modelContext
profileManager.modelContext = modelContext
watchManager.modelContext = modelContext
```
This is because singletons are created before the SwiftData container is ready. Always check `guard let context = modelContext` before fetching/saving in managers.

### 2.4 The four singleton managers

| Class | File | Responsibility |
|---|---|---|
| `NotificationManager` | `NotificationManager.swift` | Schedule/cancel `UNUserNotificationCenter` alerts; manage focus session state (`focusSessionActive`, `focusSessionEndsAt`); handle notification action taps |
| `BlockManager` | `BlockView.swift` | Activate/complete blocks; fetch `WeatherService.shared` suggestions for outdoor blocks; prompt auto-bundles; `CLLocationManager` delegate |
| `ActiveProfileManager` | `ProfileModels.swift` | Track which `Profile` is active; persist selection across launches in `UserDefaults` key `"activeProfileID"`; expose `activePreferences: ProfilePreferences?` |
| `WatchConnectivityManager` | `WatchConnectivityManager.swift` | Bidirectional iPhone ↔ Watch sync; encode `WatchSyncPayload`; route Watch actions (complete, snooze, energy update) back to SwiftData |

All four managers use the **Swift 6 `@MainActor` + `ObservableObject`** pattern:
```swift
@MainActor
final class SomeManager: NSObject, ObservableObject {
    nonisolated let objectWillChange = ObservableObjectPublisher()
    // ...
}
```
The `nonisolated let objectWillChange` declaration is required because `ObservableObject`'s synthesized `objectWillChange` is `@MainActor`-isolated, but delegate callbacks (e.g. `WCSessionDelegate`, `CLLocationManagerDelegate`) arrive on non-main threads and need to call `objectWillChange.send()` from non-isolated contexts.

### 2.5 View hierarchy

```
AuGendaApp (@main)
└── WindowGroup
    └── RootView                         ← injects modelContext into managers
        └── ContentView                  ← tab/sidebar navigation shell
            ├── TodayView                ← AgendaItem list + focus bar
            │   ├── AgendaItemRowView    ← existing row (uses FrictionDots)
            │   └── TaskCard            ← design-system replacement (new)
            ├── TaskBacklogView         ← AgendaTask list + "For Now" filter
            │   └── TaskDetailView      ← edit task
            ├── BlockView               ← block runner + weather + bundles
            ├── HouseholdView           ← multi-profile task assignment
            │   └── ProfileViews        ← profile setup, avatar picker
            ├── SmartSuggestView        ← ndPriorityScore ranked task picker
            └── FocusSessionView        ← Pomodoro timer + task selection
```

Navigation is **tab-based on iOS** (bottom `TabBar`) and **sidebar on macOS** (left `Sidebar`), both controlled by `AppTab` enum and `NavigationLayout` from `AuDHDLayout.swift`.

### 2.6 WatchConnectivity data flow

```
iPhone app (source of truth)
  │
  ├── sendSyncSnapshot()               triggered on: scene active/background, task complete, snooze, energy change
  │    ├── if watch reachable → WCSession.sendMessage(_:replyHandler:)
  │    └── if not reachable   → WCSession.updateApplicationContext(_:)
  │
  └── WatchSyncPayload (Codable):
       nextAgendaItemTitle, nextAgendaItemTime, nextAgendaItemClientID,
       currentEnergyLevel, focusSessionActive, focusSessionEndsAt,
       pendingTaskCount, lowFrictionTaskCount

Watch app (display only)
  │
  └── sends back:
       WCMessageType.taskCompleted    → marks AgendaItem.isComplete = true
       WCMessageType.taskSnoozed      → sets AgendaItem.snoozedUntil
       WCMessageType.energyUpdate     → writes ProfilePreferences.currentEnergyLevel
       WCMessageType.requestSync      → triggers sendSyncSnapshot()
```

**Key constants** (duplicate these exactly in the Watch Extension target):
```swift
// WatchConnectivityManager.swift
enum WCMessageKey { /* nextTask, energyLevel, focusState, ... */ }
enum WCMessageType: String { /* syncSnapshot, taskCompleted, ... */ }
```

### 2.7 Notification system

Four `UNNotificationCategory` identifiers (registered in `NotificationManager.registerCategories()`):

| Category | ID | Actions |
|---|---|---|
| Agenda item | `AGENDA_ITEM` | ✓ Done, ⏱ 5 min, ⏱ 15 min, ⏱ 30 min |
| Focus session | `FOCUS_SESSION` | End Session |
| Hyperfocus warning | `HYPERFOCUS_WARNING` | I'm aware, End Session |
| Low-EF nudge | `LOW_EF_NUDGE` | Start focus session, Dismiss |

**Notification ID scheme** for `AgendaItem` (cancel by prefix):
```
{clientID.uuidString}-advance   ← 10 min before
{clientID.uuidString}-attime    ← at scheduled time
{clientID.uuidString}-overdue   ← 15 min after (standard style only)
{clientID.uuidString}-snooze    ← after snooze
```

**Per-profile notification styles** (`ProfilePreferences.notificationStyle`):
- `.standard` — all three alerts
- `.predictable` — advance + at-time only (autism preset; no overdue surprise)
- `.minimal` — at-time only (PDA preset)

Notification taps post `Notification.Name` events handled in `ContentView`:
```swift
Notification.Name.agendaItemCompleted   ← userInfo["clientID"]
Notification.Name.agendaItemSnoozed     ← userInfo["clientID", "minutes"]
```

### 2.8 RecurrenceEngine

`RecurrenceEngine.generateForToday(context:)` is called on app launch. It:
1. Fetches `AgendaItem` where `recurrenceRule != "none"` and `recurrenceParentID == nil` (templates)
2. For each template that should fire today, checks whether a generated instance already exists for today (idempotent)
3. Creates a new `AgendaItem` copy with `recurrenceParentID = template.clientID`

**Supported rules:** `"daily"`, `"weekly"` (same weekday as template), `"weekdays"` (Mon–Fri).  
**Not yet implemented:** `"monthly"`, `"biweekly"`, `"custom"`. The engine returns `false` for unknown rules — they silently don't fire.

### 2.9 Design system files (new in May 2026)

| File | Contents |
|---|---|
| `DesignTokens.swift` | `Tokens.Color`, `Tokens.Spacing`, `Tokens.Typography`, `Tokens.Border`, `Tokens.Shadow`, `Tokens.Animation`, `Tokens.Layout`, `AppColor` palette, environment keys for `reduceMotion`, `textSizeMultiplier`, `lowStimulationMode` |
| `AuDHDComponents.swift` | `AuDHDCard`, `AuDHDButton`, `AuDHDInput`, `OptionCard`, `StatusAlert`, adaptive `Color.app*` extensions |
| `AuDHDProgressComponents.swift` | `ProgressIndicator`, `ProgressSummary`, `ProgressRing`, `EnergyCheckInCard`, `SkeletonLoader` |
| `AuDHDLayout.swift` | `ScreenContainer`, `SectionHeader`, `CollapsibleSection`, `NavigationLayout`, `TabBar`, `Sidebar`, `EmptyState`, `AppTab` |
| `AuDHDNDComponents.swift` | `InterruptionContext`, `InterruptionRecoveryPrompt`, `TaskCard`, `SubtaskRow`, `EnergyDots`, `EnergyFilterBanner`, `EnergyFilter`, `HyperfocusWarning` |

---

## 3. KNOWN QUIRKS & GOTCHAS

### 3.1 `Task` name collision with Swift concurrency

**The problem:** Swift's standard library defines `Task` as the structured concurrency type. The original `Task.swift` model caused "ambiguous use of type 'Task'" errors everywhere.

**The fix:** Model renamed to `AgendaTask` in `AgendaTask.swift`. `Task.swift` now contains only:
```swift
typealias Task = AgendaTask
```
Existing backlog views (`TaskBacklogView`, `SmartSuggestView`, `TaskDetailView`, `FocusSessionView`) still reference `Task` through the alias and compile fine. **New code: use `AgendaTask` directly.**

### 3.2 Swift 6 strict concurrency — `@MainActor` + `ObservableObject`

All four managers must declare `objectWillChange` as `nonisolated`:
```swift
@MainActor
final class SomeManager: NSObject, ObservableObject {
    nonisolated let objectWillChange = ObservableObjectPublisher()
```

Without `nonisolated`, delegate callbacks arriving off the main thread cannot call `objectWillChange.send()`, producing Swift 6 errors like:
> "Main actor-isolated property 'objectWillChange' can not be referenced from a nonisolated context"

**Pattern for delegate callbacks:**
```swift
nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
    Task { @MainActor in
        isWatchReachable = session.isReachable  // safe — now on main actor
    }
}
```

### 3.3 Non-Sendable types in closures

`[AnyHashable: Any]` (e.g. `UNNotification.request.content.userInfo`) is not `Sendable` and cannot be captured in `@Sendable` closures (Swift 6 strict). Extract primitive values before crossing the isolation boundary:

```swift
// ❌ Swift 6 error:
let userInfo = response.notification.request.content.userInfo
DispatchQueue.main.async { self?.handleAction(userInfo: userInfo) }

// ✅ Correct:
let clientID = response.notification.request.content.userInfo["clientID"] as? String ?? ""
DispatchQueue.main.async { self?.handleAction(clientID: clientID) }
```

This pattern is used in `NotificationManager.userNotificationCenter(_:didReceive:)`.

### 3.4 Platform guards — `#if os(iOS)` not `#if !targetEnvironment(macCatalyst)`

The project builds as **native macOS** (not Catalyst). Use:
```swift
#if os(iOS)
    .navigationBarTitleDisplayMode(.inline)  // iOS only
#endif
```

Using `#if !targetEnvironment(macCatalyst)` does NOT exclude native macOS builds. This was a source of multiple compile errors: `navigationBarTitleDisplayMode` and `buttonStyle(.plain)` placed outside `#if os(iOS)` blocks.

### 3.5 `UIColor`-based adaptive `Color` extensions

`AuDHDComponents.swift` defines adaptive colors using `UIColor`:
```swift
static let appBackground = Color(UIColor { trait in
    trait.userInterfaceStyle == .dark ? UIColor(AppColor.slate900) : UIColor(AppColor.white)
})
```

This compiles only on iOS. On macOS, `UIColor` doesn't exist — the equivalent is:
```swift
Color(NSColor { appearance in
    appearance.name == .darkAqua ? NSColor(AppColor.slate900) : NSColor(AppColor.white)
})
```

**Status:** flagged for fix in a separate task. Until resolved, `AuDHDComponents.swift` will produce compile errors in the macOS target. Workaround: wrap each static property in `#if os(iOS) / #else / #endif`.

### 3.6 CloudKit eventual consistency

**No `@Attribute(.unique)` is used anywhere.** CloudKit does not enforce uniqueness constraints. If a user syncs from two devices simultaneously, duplicate records are possible. The `clientID: UUID` field on every model is the deduplication key — but deduplication logic is not yet implemented. The app currently trusts CloudKit's last-write-wins behaviour.

**CloudKit sync is not active yet** — `AppContainer.preview` (in-memory) is used in production code. Every app launch starts with `SampleData.populate()`. This must be changed to `AppContainer.production` before shipping.

### 3.7 WatchConnectivity delivery guarantees

`sendMessage(_:replyHandler:)` delivers only if the Watch is reachable (screen on, app in foreground). It silently fails on error (error is logged to console only).

`updateApplicationContext(_:)` delivers **only the most recent** context when the Watch next wakes. If you call `sendSyncSnapshot()` rapidly (e.g. completing three tasks in quick succession), only the last snapshot reaches the Watch. This is acceptable for sync payloads (they're always full snapshots) but would lose intermediate state if you were sending deltas.

**The `sessionDidDeactivate` handler** calls `WCSession.default.activate()` to handle iPhone handoff between Watch pairs:
```swift
nonisolated func sessionDidDeactivate(_ session: WCSession) {
    WCSession.default.activate()
}
```
This is required and must not be removed.

### 3.8 WeatherKit requires entitlement + capability

`BlockManager` calls `WeatherService.shared.weather(for: location)` which requires:
1. `com.apple.developer.weatherkit: true` in the entitlements file (currently missing)
2. WeatherKit capability enabled in Xcode → Signing & Capabilities
3. Corresponding entry in App Store Connect for the App ID

Without the entitlement, WeatherKit calls throw an authentication error at runtime. `BlockManager.fetchWeather(for:)` catches errors silently (`print` only), so the app won't crash — it just returns no weather suggestions.

### 3.9 Location services

`BlockManager` sets:
```swift
locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
```

Location is only requested when an outdoor block is started (`block.type.isOutdoor && block.weatherCheckEnabled`). Without `NSLocationWhenInUseUsageDescription` in Info.plist, the app will crash (required by App Store since iOS 10). This string is not currently in the generated Info.plist.

### 3.10 RecurrenceEngine — missing monthly/biweekly support

`RecurrenceEngine.shouldFire(template:today:using:)` returns `false` for any rule other than `"daily"`, `"weekly"`, `"weekdays"`. Tasks created with a `recurrenceRule` of `"monthly"` or any other string will silently never generate instances. There is no validation at creation time.

### 3.11 Energy filter — minimum floor

`EnergyFilter.apply(_:energyLevel:)` in `AuDHDNDComponents.swift`:
```swift
item.frictionLevel <= max(energyLevel, 2)
```
The `max(_, 2)` ensures friction-1 and friction-2 tasks always show even at "Survival" energy (level 1). This prevents the list going completely empty at low energy. If you remove this floor, a user with `energyLevel = 1` will see zero tasks (since `frictionLevel` 1 == `max(1, 1)` = 1 — fine, but `energyRequired <= 1` is very restrictive and most tasks will be energy 2+).

### 3.12 `presentationDetents` — iOS only

`.presentationDetents([.height(240)])` is unavailable on macOS. All usages are wrapped in `#if os(iOS)`. If you add new bottom sheets, remember this guard.

---

## 4. BUILD ARTIFACTS & PATHS

### 4.1 DerivedData

```
~/Library/Developer/Xcode/DerivedData/AuGenda-{hash}/
  Build/Products/
    Debug-iphoneos/AuGenda.app            ← device build
    Debug-iphonesimulator/AuGenda.app     ← simulator build
    Debug/AuGenda.app                     ← macOS build
```

Find the current hash:
```bash
ls ~/Library/Developer/Xcode/DerivedData/ | grep AuGenda
```

### 4.2 SwiftData store (when production is active)

```
# iOS device:
~/Library/Containers/ensdev.AuGenda/Data/Library/Application Support/default.store
# (WAL files: default.store-wal, default.store-shm)

# macOS:
~/Library/Containers/ensdev.AuGenda/Data/Library/Application Support/default.store
```

The **preview/debug container** (`AppContainer.preview`) is `isStoredInMemoryOnly: true` — no files on disk, wipes on launch.

To inspect the SQLite store during development:
```bash
sqlite3 ~/Library/Containers/ensdev.AuGenda/Data/Library/Application\ Support/default.store \
  ".tables"
```

### 4.3 UserDefaults keys

Persistent across launches (not wiped with in-memory SwiftData):

| Key | Set by | Value |
|---|---|---|
| `"activeProfileID"` | `ActiveProfileManager.persistActiveProfileID()` | `UUID.uuidString` of the last-used `Profile` |
| `"irp.lastItemTitle"` | `InterruptionContext.recordActivity(itemTitle:)` | Title of last interacted task |
| `"irp.lastActiveDate"` | `InterruptionContext.recordActivity()` | `TimeInterval` since epoch |
| `"irp.lastContextLabel"` | `InterruptionContext.recordActivity(contextLabel:)` | Human description of last action |

### 4.4 Notification identifiers in flight

Pending notification IDs follow these patterns — useful when debugging via `UNUserNotificationCenter.current().getPendingNotificationRequests`:

```
{UUID}-advance          AgendaItem advance warning
{UUID}-attime           AgendaItem at-time
{UUID}-overdue          AgendaItem 15-min-late nudge
{UUID}-snooze           AgendaItem snooze reminder
focus-session-end       Focus session end
focus-session-halfway   Focus session halfway check-in
hyperfocus-guard-warning  75% of session elapsed (hyperfocusGuard profiles)
hyperfocus-guard-stop     Session end hard-stop (hyperfocusGuard profiles)
hyperfocus-warning      Standalone hyperfocus risk timer (45 min)
low-ef-nudge            Low executive function task suggestion
```

### 4.5 Build phases

No custom build phases or Run Script phases. No code generation, no SwiftGen, no R.swift, no Sourcery. The SwiftData schema is inferred at runtime from the model class list in `AppContainer.swift` — there are no migration descriptors yet. **Schema migrations are not configured.** Adding, removing, or renaming a `@Model` property without a `VersionedSchema + MigrationPlan` will crash on first launch against an existing store.

### 4.6 Test targets

`AuGendaTests` and `AuGendaUITests` exist but contain only the Xcode-generated stub files. No tests have been written yet. Use `AppContainer.makeTestContainer()` in tests — it creates an in-memory container pre-configured with the full schema.

---

## 5. QUICK REFERENCE — THINGS TO DO BEFORE SHIPPING

- [ ] Replace `AppContainer.preview` → `AppContainer.production` in `AuGendaApp.swift`
- [ ] Set real CloudKit container ID in `AppContainer.swift` (currently `"iCloud.com.yourname.audhd-agenda"`)
- [ ] Fill `com.apple.developer.icloud-container-identifiers` array in `AuGenda.entitlements`
- [ ] Add `com.apple.developer.weatherkit: true` to entitlements
- [ ] Add WeatherKit capability in Xcode Signing & Capabilities
- [ ] Add `NSLocationWhenInUseUsageDescription` to Info.plist
- [ ] Add `NSWeatherKitClientIdentifier` / WeatherKit App ID on developer.apple.com if needed
- [ ] Add font files to bundle + `UIAppFonts` in Info.plist (Atkinson, OpenDyslexic)
- [ ] Fix `UIColor` adaptive extensions in `AuDHDComponents.swift` for macOS target
- [ ] Configure `VersionedSchema` + `SchemaMigrationPlan` before any schema change to a shipped store
- [ ] Switch `aps-environment` to `production` in entitlements for App Store build
- [ ] Write unit tests using `AppContainer.makeTestContainer()`
