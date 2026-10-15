# AuGenda — Developer Documentation

**Last updated:** 2026-10-15
**Swift:** Swift 5 language mode with staged concurrency settings
**Project type:** SwiftUI + SwiftData, iOS/iPadOS/macOS app with Watch app and widget targets, no external packages

> **Evidence discipline:** This document describes the current working tree.
> Product goals belong in `PRD.md`; they are not proof that a feature has
> shipped or passed release validation. Build, test, accessibility, size, and
> device claims below are dated and scoped to the command that produced them.

---

## 1. BUILD & SETUP

### 1.1 Deployment targets

| Setting | Value |
|---|---|
| `IPHONEOS_DEPLOYMENT_TARGET` | 26.5 |
| `MACOSX_DEPLOYMENT_TARGET` | 26.3 |
| `WATCHOS_DEPLOYMENT_TARGET` | 26.5 |
| `SWIFT_VERSION` | 5.0 |
| `SWIFT_APPROACHABLE_CONCURRENCY` | `YES` |
| `SWIFT_DEFAULT_ACTOR_ISOLATION` | `MainActor` on the app and Watch app targets |
| `TARGETED_DEVICE_FAMILY` | `"1,2"` — iPhone (1), iPad (2); native macOS is selected separately through `SUPPORTED_PLATFORMS` |
| `SDKROOT` | `auto` — Xcode picks the right SDK per destination |
| `CODE_SIGN_STYLE` | Automatic |
| `DEVELOPMENT_TEAM` | `GAB62HZP25` |

These are the configured minimums, not the broader compatibility goals in the
PRD. The main target has iPhone, iPad, and macOS destinations and contains
platform-specific SwiftUI branches. The Watch app and Watch widget are native
watchOS targets.

The project is **not** in Swift 6 language mode and does not set
`SWIFT_STRICT_CONCURRENCY = complete`. It uses Swift 5 language mode plus
approachable-concurrency, default-main-actor, and member-import-visibility
settings as staged migration aids. Code should still respect actor isolation,
but documentation and reviews must not describe this as verified Swift 6 strict
concurrency.

### 1.2 Bundle identifiers and targets

| Target | Bundle ID | Type |
|---|---|---|
| AuGenda | `ensdev.AuGenda` | Application |
| AuGendaTests | `ensdev.AuGendaTests` | Unit test bundle |
| AuGendaUITests | `ensdev.AuGendaUITests` | UI test bundle |
| AuGendaWatch Watch App | `ensdev.AuGenda.watchkitapp` | watchOS application |
| AuGendaWatch Watch AppTests | `ensdev.AuGendaWatch-Watch-AppTests` | Watch unit test bundle |
| AuGendaWatch Watch AppUITests | `ensdev.AuGendaWatch-Watch-AppUITests` | Watch UI test bundle |
| AuGendaWatchWidgetsExtension | `ensdev.AuGenda.watchkitapp.AuGendaWatchWidgets` | watchOS widget extension |

There are seven native targets. Target existence and compilation are not
equivalent to paired-device or App Store validation; see §4.7.

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
| `WidgetKit` | Watch widget and Watch-side timeline reloads |

**Typography:** the current app intentionally exposes only Apple system
typography. `AppFont` has one `.system` case, typography tokens use semantic
SwiftUI text styles, `Info.plist` has no `UIAppFonts`, and the former invalid
font artifacts were removed. Custom dyslexia-font choices remain a product
requirement, not a current capability. Any reintroduction must include
authoritative font binaries and licenses, verified PostScript names, bundle
registration, and Dynamic Type/device testing.

### 1.4 Capabilities and entitlements

Applied entitlement files in the working tree:

- `AuGenda/AuGenda.entitlements`: WeatherKit only. Push and CloudKit
  entitlements are deliberately absent because notifications are local and the
  main SwiftData store is local-only.
- `AuGendaWatch Watch App/AuGendaWatch.entitlements` and
  `AuGendaWatchWidgets/AuGendaWatchWidgets.entitlements`: the shared App Group
  `group.ensdev.AuGenda.watch`.
- The Xcode build settings point the corresponding targets at those files.

The main `Info.plist` contains location, microphone, speech-recognition, and
local-network usage descriptions, plus a local-network ATS exception for an
explicitly configured Ollama host. Google OAuth values are build-setting
placeholders until valid credentials are supplied.

Repository configuration is not provisioning evidence. Before release, verify
that WeatherKit and the Watch App Group are enabled for the exact App IDs and
signing profiles, then inspect the signed archive entitlements. Also reconcile
each privacy manifest with actual runtime behavior and the App Store privacy
questionnaire.

### 1.5 Terminal build commands

```bash
# List available simulators
xcrun simctl list devices available

# Build the main scheme for an available iOS Simulator
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild build \
  -project AuGenda.xcodeproj \
  -scheme AuGenda \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'

# Run main unit tests
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild test \
  -project AuGenda.xcodeproj \
  -scheme AuGenda \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:AuGendaTests

# Build for macOS
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild build \
  -project AuGenda.xcodeproj \
  -scheme AuGenda \
  -destination 'platform=macOS'

# Build the Watch scheme using a destination available on the host
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild build \
  -project AuGenda.xcodeproj \
  -scheme 'AuGendaWatch Watch App' \
  -destination '<paired or simulator Watch destination>'
```

### 1.6 Persistence — file-backed and local-only

Production startup calls
`AppContainer.makePersistentLocalStartupState()`. The resulting
`ModelConfiguration` is file-backed (`isStoredInMemoryOnly: false`) and has no
`cloudKitDatabase`. A persistent-store open failure produces a read-only
recovery surface; production does not substitute an empty in-memory store.

`AppContainer.preview` and `AppContainer.makeTestContainer()` remain
in-memory-only for previews and tests. The `-ui-testing` launch argument also
selects the test container.

CloudKit is a future product direction only. It is not configured in the
production container or main-app entitlements, and the current data model must
not be documented as multi-device synced.

---

## 2. ARCHITECTURE & PATTERNS

### 2.1 SwiftData schema — 17 current models

The production local store uses `AuGendaSchemaV2` and
`AuGendaMigrationPlan`. Several models retain CloudKit-compatible shapes as a
future-facing design constraint, but the current store is not connected to
CloudKit.

**Scheduling domain:**

| Model | File | Key fields |
|---|---|---|
| `AgendaItem` | `AgendaItem.swift` | `title`, `scheduledDate`, `frictionLevel` (1–4), `energyRequired` (1–4), `contextTag`, `snoozedUntil`, `recurrenceRule`, `priority` (0/1/2), `assignedToProfileID`, `assignedByProfileID` |
| `SubTask` | `AgendaItem.swift` | `title`, `isComplete`, `sortOrder`; `@Relationship(deleteRule: .cascade, inverse: \SubTask.parentItem)` from `AgendaItem` |
| `AgendaTask` | `AgendaTask.swift` | Like `AgendaItem` but no `scheduledDate` — lives in backlog. Adds `interestLevel`, `estimatedMinutes`, `waitingOn`, `isAbandoned`, `hyperfocusRisk`. Has `ndPriorityScore` computed property. |
| `TaskStep` | `AgendaTask.swift` | Subtask of `AgendaTask`; adds `estimatedMinutes` |
| `InboxItem` | `InboxItem.swift` | Low-friction unscheduled capture from text or voice brain dumps |

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

**Focus, relationship, and note domains:**

| Model | File | Key fields |
|---|---|---|
| `FocusSession` | `FocusSession.swift` | Durable session state, planned/end time, linked task, interruption history |
| `TaskRelationship` | `TaskRelationship.swift` | Directed relationship between task UUIDs with validated relationship type |
| `Note` | `Note.swift` | Standalone note content with optional task/item references |

**Legacy model retained in the schema:**

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
do {
    try modelContext.save()
} catch {
    modelContext.rollback()
    ErrorBannerController.shared.show("Could not save changes.")
}
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
| `WatchConnectivityManager` | `WatchConnectivityManager.swift` | Build versioned full snapshots; validate and idempotently apply Watch mutation envelopes; acknowledge outcomes |

The managers use an **actor-isolated `ObservableObject`** pattern while the
project remains in Swift 5 language mode:
```swift
@MainActor
final class SomeManager: NSObject, ObservableObject {
    nonisolated let objectWillChange = ObservableObjectPublisher()
    // ...
}
```
The explicit `nonisolated objectWillChange` accommodates delegate callbacks
that arrive outside the main actor. Delegate work that mutates UI-observable or
SwiftData state must hop to `@MainActor`.

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
iPhone app (durable source of truth)
  │
  ├── builds a versioned, active-profile-scoped full snapshot
  ├── updateApplicationContext         durable latest-state delivery
  ├── sendMessage                      reachable latency optimization
  └── receives idempotent Watch mutations and returns acknowledgements
  │
  └── WatchSnapshot:
       schemaVersion, snapshotID, generatedAt, profileID,
       agendaItems, backlogTasks, energy/density, focus state,
       pending/low-friction counts, pendingRecovery

Watch app
  │
  ├── validates and stores the newest full snapshot
  ├── queues complete/snooze/energy/capture mutations in a durable outbox
  ├── transferUserInfo                durable mutation delivery
  ├── retries until phone acknowledgement
  └── writes snapshot + outbox to the Watch App Group
          │
          └── Watch widget reads the same presentation snapshot and reloads
```

`Shared/WatchSyncContract.swift` is compiled by the phone, Watch app, and Watch
widget targets. It standardizes the envelope, millisecond date coding, schema
version, freshness window, and mutation/acknowledgement types.
`Shared/WatchSharedStateStore.swift` is shared by the Watch app and widget and
uses `UserDefaults(suiteName: "group.ensdev.AuGenda.watch")`. Pending
mutations are overlaid on the last snapshot so a completed or snoozed item is
not re-presented while acknowledgement is pending.

This source-level contract has unit coverage, but the App Group still requires
matching Developer Portal/App ID/profile provisioning. Paired physical
iPhone/Watch delivery, offline retry, complication refresh, freshness redaction,
and profile isolation remain release QA gates.

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

Agenda reminders resolve privacy and style from the item's assigned owner.
Unassigned or unavailable owners use redacted previews and minimal reminders.
Changing the active profile cannot unredact another owner's content. Refresh
and backup restore rebuild incomplete items using the persisted snooze deadline
when present; a snooze replaces the original schedule, including for overdue
items, and an expired snooze does not reinstate that schedule.

Notification actions are handled by `NotificationManager`, which resolves the
target record, persists completion or snooze state, then performs notification
and Watch-sync side effects. The delegate completion handler runs only after
that main-actor action path finishes.

### 2.8 Completion-driven recurrence

`TaskLifecycleService` and `AgendaItemLifecycleService` generate the next
occurrence transactionally on completion for daily, weekdays, weekly, and
monthly rules. Replays reuse the persisted completion time and existing
occurrence identity. There is no launch-time generation or catch-up burst.
The next date is strictly after both the completion time and the occurrence
being completed, so early completion cannot return the current occurrence.
Monthly series retain the original preferred day after shorter-month clamping.
Biweekly and custom rules remain unsupported.

### 2.9 Design system files (new in May 2026)

| File | Contents |
|---|---|
| `DesignTokens.swift` | `Tokens.Color`, `Tokens.Spacing`, `Tokens.Typography`, `Tokens.Border`, `Tokens.Shadow`, `Tokens.Animation`, `Tokens.Layout`, `AppColor` palette, environment keys for reduced motion, low stimulation, UI scale, and density |
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

### 3.2 Staged concurrency — `@MainActor` + `ObservableObject`

The app and Watch app targets use default main-actor isolation with Swift 5
language mode and approachable concurrency. Managers with nonisolated
framework delegates declare `objectWillChange` explicitly:
```swift
@MainActor
final class SomeManager: NSObject, ObservableObject {
    nonisolated let objectWillChange = ObservableObjectPublisher()
```

Without the isolation bridge, delegate callbacks arriving off the main thread
cannot safely mutate main-actor state. The current pattern is:
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

`[AnyHashable: Any]` (for example,
`UNNotification.request.content.userInfo`) is not `Sendable`. Extract
primitive values in the `nonisolated` delegate method before entering a
main-actor task:

```swift
// ❌ Non-Sendable value crosses an isolation boundary:
let userInfo = response.notification.request.content.userInfo
Task { @MainActor in self?.handleAction(userInfo: userInfo) }

// ✅ Correct:
let clientID = response.notification.request.content.userInfo["clientID"] as? String ?? ""
Task { @MainActor in
    await self?.handleAction(clientID: clientID)
}
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

**Current status:** the color helpers have `#if os(iOS)`/macOS branches using
`UIColor` and `NSColor`, respectively. Keep that split when adding adaptive
colors.

### 3.6 Local-only persistence and future sync

The main app opens a file-backed local SwiftData store and performs a
lightweight v1-to-v2 migration. It does not configure a CloudKit database.
`clientID` values and CloudKit-friendly model shapes are useful future
preparation, but there is no production multi-device merge, conflict
resolution, or deduplication contract today. Enabling CloudKit is a separate
feature requiring design, migration, entitlement, failure-mode, and
multi-device testing.

### 3.7 WatchConnectivity delivery guarantees

`sendMessage(_:replyHandler:)` is used only as a reachable latency
optimization. `updateApplicationContext(_:)` retains the newest
full-replacement phone snapshot, so coalescing does not lose a state delta.
Watch-originated mutations use `transferUserInfo`, a durable local outbox, event
IDs, phone-side processed-event tracking, and explicit acknowledgements.

**The `sessionDidDeactivate` handler** calls `WCSession.default.activate()` to handle iPhone handoff between Watch pairs:
```swift
nonisolated func sessionDidDeactivate(_ session: WCSession) {
    WCSession.default.activate()
}
```
This is required and must not be removed.

The transport logic has source-level tests, not paired-device certification.
Do not describe background delivery, offline convergence, or complication
refresh as release-verified until the physical-device matrix in §4.7 passes.

### 3.8 WeatherKit requires entitlement + capability

`BlockManager` calls `WeatherService.shared.weather(for: location)`. The
repository entitlement file declares `com.apple.developer.weatherkit: true`,
but source presence alone does not establish service authorization. The
capability must also be enabled for the exact App ID and signing profile, and
the effective entitlement must be inspected in the signed archive. Runtime
success and the unavailable-service path still require device testing.

### 3.9 Location services

`BlockManager` sets:
```swift
locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
```

Location is requested only when an outdoor block is started
(`block.type.isOutdoor && block.weatherCheckEnabled`). The main `Info.plist`
contains `NSLocationWhenInUseUsageDescription`. Verify the system prompt,
denial/revocation behavior, WeatherKit degradation, and privacy copy on a
signed device build.

### 3.10 Completion-driven recurrence and whole-product encrypted backup

**Recurrence engine:**
AuGenda implements completion-driven recurrence in `TaskLifecycle.swift` (`TaskLifecycleService` and `AgendaItemLifecycleService`). It supports `daily`, `weekdays`, `weekly`, and `monthly` rules with idempotent next-occurrence calculation (`RecurrenceCalendar`). It advances strictly beyond the completion time and anchor date to prevent catch-up bursts, preserving original series anchors and applying monthly day clamping. Launch-time generation, biweekly, and arbitrary cron/custom recurrence remain intentionally unsupported.

**Whole-product encrypted backup contract:**
Whole-product backup and restore lives in `TaskImportExport.swift` (`AuGendaBackupArchive`). It uses authenticated encryption (PBKDF2-derived key + AES-GCM with prefix `AuGendaBackupV1:`) and enforces a 100 MB restore limit and payload SHA256 integrity check. It preserves the complete product graph across all 17 schema entities:
`AgendaItem`, `AgendaTask`, `AttachedBundle`, `AttachedBundleItem`, `Block`, `BlockTask`, `BundleTemplate`, `BundleTemplateItem`, `FocusSession`, `InboxItem`, `Note`, `Profile`, `ProfilePreferences`, `SubTask`, `TaskRelationship`, `TaskStep`, and `UserPreferences`.
It also archives resettable UserDefaults preferences and local AI usage/memory history, while strictly excluding Keychain secrets, Watch transport IDs, and transient consent receipts (which must be confirmed after restore).

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

### 4.2 SwiftData store

```
# iOS device:
~/Library/Containers/ensdev.AuGenda/Data/Library/Application Support/default.store
# (WAL files: default.store-wal, default.store-shm)

# macOS:
~/Library/Containers/ensdev.AuGenda/Data/Library/Application Support/default.store
```

Normal production and development launches use the file-backed local store.
`AppContainer.preview`, `AppContainer.makeTestContainer()`, and the explicit
`-ui-testing` launch path are in-memory-only.

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

No custom build phases or Run Script phases are configured. There is no code
generation, SwiftGen, R.swift, or Sourcery. SwiftData uses
`AuGendaSchemaV1`, `AuGendaSchemaV2`, and `AuGendaMigrationPlan`; the current
v1-to-v2 stage is lightweight. Any future schema change still requires a new
version, an explicit migration stage, fixtures representing an actual prior
store, and failure-path testing before release.

### 4.6 Test targets

`AuGendaTests` contains XCTest and Swift Testing suites for persistence,
migration, import/export, difficulty and state engines, AI policy, Keychain,
focus/notifications, task relationships, profile deletion, defaults, and the
Watch contract. The Watch test target includes shared-state/outbox tests.

The UI test targets remain mostly launch templates and do not establish
end-to-end journey coverage. Use `AppContainer.makeTestContainer()` for
isolated model tests and the `-ui-testing` launch argument for UI automation.

### 4.7 Dated verification and evidence

**2026-09-08 audit remediation:** The main macOS unit suite passed with
`xcodebuild test -project AuGenda.xcodeproj -scheme AuGenda -destination 'platform=macOS' -only-testing:AuGendaTests -derivedDataPath build/audit-derived CODE_SIGNING_ALLOWED=NO`.
New regression coverage verifies owner-scoped agenda privacy/style, conservative
fallback, snooze precedence for overdue and future items, and early daily/monthly
completion with replay idempotency for backlog and agenda models. Result bundle:
`build/audit-derived/Logs/Test/Test-AuGenda-2026.09.08_09-39-33--0600.xcresult`.
This run does not verify device notification delivery or iOS/watchOS behavior.


**2026-07-24 pre-remediation audit baseline**

- macOS main unit suite: **46 passed, 0 failed, 0 skipped**.
- Production-line coverage from that exact macOS result bundle:
  **4,161 / 35,484 lines (11.7264%)** for `AuGenda.app`.
- Unsigned iOS Simulator unit run: **43 passed, 3 failed**; all three failures
  were Keychain `errSecMissingEntitlement` failures caused by disabling code
  signing.
- Focused signed iOS Keychain rerun: **5 passed, 0 failed**.
- Main-scheme signed build compiled Watch/widget dependencies. A standalone
  Watch build compiled and linked Watch/widget code but was prevented from
  completing by unavailable CoreSimulator services.

Those results belong to the audit snapshot before the current remediation
edits and must not be presented as current-tree status.

**2026-07-24 post-remediation working tree**

- macOS main unit suite: **85 passed, 0 failed, 0 skipped** with unsigned test
  products; result bundle:
  `/private/tmp/AuGendaClosureFinal2-20260724.xcresult`.
- Production-line coverage from that exact result:
  **2,942 / 38,980 lines (7.5475%)** for `AuGenda.app`. CI enforces a 7% floor;
  the product target remains well below the >80% goal.
- Unsigned generic iOS Release build succeeded, including Watch/widget
  dependencies.
- Unsigned generic watchOS Release `build-for-testing` succeeded with
  `ENABLE_TESTABILITY=YES`.
- The Release iOS package contains the executable, generated icons,
  `Assets.car`, `Info.plist`, `PkgInfo`, `PrivacyInfo.xcprivacy`, and its Watch
  app; it contains none of the former prompt, README, validation script, or
  invalid font files.
- Static validation passed for all Swift parses, plists, entitlements, privacy
  manifests, the Xcode project file, workflow YAML, shell syntax, asset JSON,
  diff whitespace, and targeted current-tree secret patterns.

**Not yet verified as of 2026-07-24**

- App Store-style Release archive, signed-entitlement inspection, validation,
  notarization, install size, memory, launch-time, scroll, and timer targets;
- paired physical iPhone/Watch delivery, outbox retry/acknowledgement,
  complication refresh, stale-title redaction, and App Group provisioning;
- full VoiceOver, Switch Control, Dynamic Type, Reduce Motion, Increase
  Contrast, localization, and physical-device accessibility passes;
- WeatherKit, Google OAuth, local-network Ollama, and external AI providers
  with release credentials.

---

## 5. QUICK REFERENCE — THINGS TO DO BEFORE SHIPPING

- [ ] Run the full current-tree iOS, macOS, Watch, widget, unit, and UI matrix
      and retain result bundles.
- [ ] Produce and validate signed Release archives; inspect effective
      entitlements rather than inferring them from source files.
- [ ] Provision WeatherKit and `group.ensdev.AuGenda.watch` for the exact App
      IDs and distribution profiles.
- [ ] Supply release Google OAuth settings and validate the registered callback
      scheme; do not ship placeholder values.
- [ ] Complete paired physical iPhone/Watch, complication, offline-outbox, and
      profile-isolation testing.
- [ ] Complete the accessibility/device matrix; do not claim WCAG/VoiceOver/
      Dynamic Type completeness from source review alone.
- [ ] Verify privacy manifests and the App Store privacy questionnaire against
      optional AI, speech, location, local-network, Watch, and widget behavior.
- [ ] Measure release archive/install size, memory, launch, scrolling, and timer
      behavior on supported hardware.
- [ ] Add a new `VersionedSchema` and migration stage before the next persistent
      model change; preserve prior-store fixtures.
- [ ] Keep system Dynamic Type as the only font option unless licensed custom
      assets and their full verification gate are added.
- [ ] Treat CloudKit as an unimplemented future feature unless a separate
      sync/migration/recovery program is completed.

### Mac local store isolation (2026-09-12)

New native Mac stores use `Application Support/ensdev.AuGenda/AuGenda.store`
with CloudKit explicitly disabled. Before using that location, startup checks
an existing legacy `Application Support/default.store` using read-only model
metadata. Recognized AuGenda stores continue at their existing path; unrelated
apps' stores are left untouched. Unreadable legacy metadata still produces the
recovery surface rather than silently creating an empty account. Existing
dedicated stores take precedence. iOS store placement is unchanged.


## UI clarity update — 2026-10-15

- Inbox has a labeled, profile-scoped pending count in the sidebar and Tasks toolbar. Inbox has Close; capture review has Back to Inbox separately from Discard.
- Today uses the same title as navigation, labels its scheduled list “Scheduled today,” and calls the near-term empty state “Nothing coming up soon.” Scheduled AgendaItem records and the AgendaTask list remain separate; Tasks explains where scheduled items live. No persistence migration is involved.
- Blocks is the consistent section name on Today. Energy matching uses “Matches energy,” priority ranking uses “Suggested order,” and sorting uses a menu to reduce competing controls.
- New tasks start with a title and optional-details toggle; editing opens details. Hidden fields retain their existing defaults and values. Review labels collapsed difficulty Optional, or Suggested when AI suggestions exist; expanded scores are estimates.
- Focus duration can be adjusted locally for the session (5–480 minutes), including accepting the historical suggestion, without changing profile defaults. Settings explains the Today layout in user-facing terms and distinguishes AI setup needed from enabled with a provider.
- Validation (2026-10-15): [GitHub CI run 38787188369](https://github.com/8s6rdrj8r9-lang/AuGenda/actions/runs/38787188369) passed for commit `5f7f935a2d6f5dc2d0e26f4938ac62a35205f881`: macOS unit tests, 20.36% app line coverage (7% floor), iOS onboarding UI smoke test, iOS Release build, Watch app/test/widget build, six Watch unit tests, Watch launch UI smoke test, and package-content validation. Swift syntax and whitespace checks also passed locally. The changed screens still need a visual walkthrough; these automated checks do not establish usability or accessibility compliance. The installed local app has not been replaced.

### GitHub validation routing — 2026-10-15

The CI workflow now runs on pushes to `active-dev` (the remote default branch), `main`, and `codex/**` work branches, as well as pull requests. This allows branch builds without requiring pull-request creation access. The separate TestFlight workflow is unchanged.

CI enablement also corrected shallow checkout history for commit whitespace checks and uses JSON validation for asset catalog Contents.json files. The existing Apple Foundation Models zero-cost test now uses the supported cost-estimation API rather than a private pricing helper.
