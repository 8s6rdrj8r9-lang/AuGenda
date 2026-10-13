# Gemini Project Instructions — AuGenda

## Project Identity

AuGenda is a SwiftUI + SwiftData agenda app for AuDHD (autism + ADHD) brains.
Core posture: **calm, glanceable, opt-in, no demands, no surprises.**

Nothing auto-files; the user always confirms. The app adapts to cognitive state
rather than demanding performance.

## Technology Stack (Hard Constraints)

- **Swift 5** language mode — NOT Swift 6 strict concurrency
  - `SWIFT_APPROACHABLE_CONCURRENCY = YES`
  - `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`
- **Deployment:** iOS 26.5, macOS 26.3, watchOS 26.5
- **UI:** SwiftUI only. No UIKit view controllers except where SwiftUI requires it.
- **Persistence:** SwiftData, file-backed, local-only. CloudKit is documented future, NOT implemented.
- **Dependencies:** ZERO SPM packages. Apple system frameworks only.
- **Concurrency:** Managers are `@MainActor final class … NSObject, ObservableObject`
  with explicit `nonisolated let objectWillChange = ObservableObjectPublisher()`.
  Non-isolated delegate callbacks must hop: `Task { @MainActor in … }`.
- **Fonts:** Apple system fonts only. No custom fonts.
- **No external tools:** No code generation, SwiftGen, Sourcery, custom build phases.

## Architecture Rules

- **NO MVVM.** Views fetch with `@Query`, write via `@Environment(\.modelContext)`,
  observe singleton managers via `@EnvironmentObject`. Do NOT add ViewModels.
- Managers get `ModelContext` after init via `RootView.onAppear`.
  Always `guard let context = modelContext` before fetching/saving.
- Production uses `AppContainer.makePersistentLocalStartupState()`.
  Open failure → read-only recovery surface. Never silently use in-memory store in production.
- Use `AppContainer.makeTestContainer()` in tests, `AppContainer.preview` in previews.
- The `-ui-testing` launch argument selects the in-memory test container.

## Model Naming

- Task model is **`AgendaTask`** (in `AgendaTask.swift`). Never use `Task` — it collides
  with Swift concurrency `Task`. The old `typealias Task = AgendaTask` no longer exists.

## Platform Guards

- macOS is **native**, not Catalyst. Use `#if os(iOS)`, never `#if !targetEnvironment(macCatalyst)`.
- `.presentationDetents` is iOS-only.
- Adaptive colors need `#if os(iOS)` (UIColor) / macOS (NSColor) branches.

## Key File Locations

| Domain | Key Files |
|---|---|
| Models | `AgendaItem.swift`, `AgendaTask.swift`, `InboxItem.swift`, `BlockModels.swift`, `ProfileModels.swift`, `FocusSession.swift`, `TaskRelationship.swift`, `CognitiveProfile.swift`, `AppContainer.swift` |
| Logic | `DifficultyEngine.swift`, `TaskLifecycle.swift`, `TaskListProjection.swift`, `TaskFieldDomain.swift` |
| AI Layer | `AITaskEnricher.swift`, `AIEnricher_*.swift`, `AIEnrichmentMutation.swift`, `AIUsageLedger.swift`, `AIPersonalization.swift`, `KeychainStore.swift` |
| Managers | `NotificationManager`, `BlockManager`, `ActiveProfileManager`, `WatchConnectivityManager` |
| Views | `RootView`, `ContentView`, `HomeDashboardView`, `TaskBacklogView`, `TaskDetailView`, `InboxView`, `BlockView`, `HouseholdView`, `ProfileViews`, `FocusSessionView` |
| Design System | `DesignTokens.swift`, `AuDHDComponents.swift`, `AuDHDProgressComponents.swift`, `AuDHDLayout.swift`, `AuDHDNDComponents.swift` |

## Build Commands

```bash
# Build iOS Simulator
xcodebuild build -project AuGenda.xcodeproj -scheme AuGenda \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'

# Run unit tests (macOS destination — CI path)
xcodebuild test -project AuGenda.xcodeproj -scheme AuGenda \
  -destination 'platform=macOS' -only-testing:AuGendaTests -enableCodeCoverage YES

# Build macOS
xcodebuild build -project AuGenda.xcodeproj -scheme AuGenda -destination 'platform=macOS'

# Build Watch
xcodebuild build -project AuGenda.xcodeproj \
  -scheme 'AuGendaWatch Watch App' \
  -destination 'generic/platform=watchOS' \
  CODE_SIGNING_ALLOWED=NO ENABLE_TESTABILITY=YES
```

## When Modifying Code

1. **Read before editing.** Do not edit from memory.
2. Use minimal, focused changes. Do not refactor unrelated code.
3. Match existing comment style: headers explain "what/why", doc comments on public API.
4. New UI must use `Tokens.*` / `AppColor` / design system components. No ad-hoc values.
5. Schema changes require: new `VersionedSchema` + explicit migration stage + prior-store fixture + failure-path tests.
6. Keep `SPEC.md`, `PRD.md`, `DEVELOPER_DOCUMENTATION.md` in sync with behavior changes.

## Security & Privacy (Non-Negotiable)

- API keys and OAuth tokens live in **Keychain** (`KeychainStore`).
  Never `@AppStorage`, never plists, never source.
- AI is **off by default**. Nothing leaves the device until user enables a provider.
- On-device speech recognition (`requiresOnDeviceRecognition = true`).
- Do not commit secrets. `*.env` is gitignored.

## Known Gotchas

- Apple Foundation Models is unavailable in iOS Simulator. Test enrichment with real device or cloud provider.
- Non-Sendable values in `nonisolated` delegate methods → unpack to primitives before `Task { @MainActor in … }`.
- `EnergyFilter.apply` has a `max(energyLevel, 2)` floor — intentional, do not remove.
- `sessionDidDeactivate` re-activating `WCSession.default` is required — do not remove.
- Watch sync: phone→Watch uses `updateApplicationContext` + `sendMessage`; Watch→phone uses `transferUserInfo` with outbox + acknowledgements.
- Recurrence is **completion-driven** in `TaskLifecycle.swift` (daily, weekdays, weekly, monthly); biweekly and custom rules are not implemented.

## Testing

- Mix of XCTest and Swift Testing (`import Testing`, `@Test`, `#expect`).
- Match the style of the neighboring test file.
- `DifficultyEngineTests` pins exact formula outputs — intentionally brittle regression locks.
- CI enforces **7% line-coverage floor** on `AuGenda.app`.
- Never present build/test results as verified without running them.
