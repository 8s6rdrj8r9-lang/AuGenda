# AGENTS.md — AuGenda

Guidance for AI coding agents working in this repository. The reader is assumed
to know nothing about the project. Everything below describes the current
working tree; product aspirations live in `PRD.md` and are not proof that a
feature has shipped.

## Project overview

AuGenda is a SwiftUI + SwiftData agenda app for AuDHD (autism + ADHD) brains,
built around the posture: **calm, glanceable, opt-in, no demands, no
surprises.** Core ideas:

- **Brain dump → inbox → mandatory review → task.** Nothing auto-files; the
  user always confirms (`BrainDumpView` in `TaskBacklogView.swift`,
  `InboxView`, `InboxItemReviewSheet`).
- **Six-axis difficulty model** (`DifficultyEngine.swift`): friction, energy,
  sensory load, social load, initiation cost, and interest are projected into a
  computed 0–10 rank and a named `DifficultyBand`. The rank is computed, never
  stored, so the formula can evolve without migrations.
- **Capacity-adaptive UI**: energy filters, density modes, and configurable
  "Are you overwhelmed?" check-ins (`CognitiveStateSelector.swift`,
  `CognitiveCheckInTracker` enum in the same file).
- **Opt-in AI enrichment** (`AITaskEnricher` protocol + per-provider adapters):
  off by default, API keys in the Keychain, per-task `excludeFromAI` opt-out,
  and the user always previews a proposal before it is applied.
- **Multi-profile household support** with per-profile preferences
  (notification style, hyperfocus guard, language style, etc.).
- **watchOS companion app + widget** synced over WatchConnectivity
  (`Shared/WatchSyncContract.swift`).

## Technology stack

- **Language:** Swift 5 language mode (NOT Swift 6) with staged-concurrency
  settings: `SWIFT_APPROACHABLE_CONCURRENCY = YES`,
  `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` on the app and Watch app targets.
  Do not describe the codebase as verified Swift 6 strict concurrency.
- **Deployment targets:** iOS 26.5, macOS 26.3, watchOS 26.5
  (`TARGETED_DEVICE_FAMILY = "1,2"` — iPhone + iPad; native macOS is a
  separate destination of the same app target, selected via
  `SUPPORTED_PLATFORMS`).
- **UI:** SwiftUI only. **Persistence:** SwiftData (file-backed, local-only;
  CloudKit is a documented future direction, not implemented).
- **Dependencies:** zero SPM packages (no `Package.resolved`, no
  `project.xcworkspace/xcshareddata/swiftpm`); Apple system frameworks only
  (SwiftUI, SwiftData, Combine, UserNotifications, WatchConnectivity,
  WeatherKit, CoreLocation, Contacts/ContactsUI, UIKit, WidgetKit).
- **Concurrency pattern:** managers are `@MainActor final class … NSObject,
  ObservableObject` with an explicit `nonisolated let objectWillChange =
  ObservableObjectPublisher()` so nonisolated delegate callbacks can publish.
  Hop to the main actor inside delegate callbacks:
  `Task { @MainActor in … }`.
- **Typography:** Apple system fonts only (`AppFont` has one `.system` case,
  no `UIAppFonts` in `Info.plist`). See `AuGenda/Fonts/README.md` for the
  gates any custom-font reintroduction must pass.
- **No external tools:** no code generation, no SwiftGen/Sourcery, no custom
  build phases.

## Build and test commands

There is no `Package.swift` / `pyproject.toml` / `package.json` — this is a
plain Xcode project (`AuGenda.xcodeproj`). Build from the terminal with
`xcodebuild`:

```bash
# List available simulators
xcrun simctl list devices available

# Build for an iOS Simulator
xcodebuild build -project AuGenda.xcodeproj -scheme AuGenda \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'

# Run the main unit test suite (macOS destination is the CI path)
xcodebuild test -project AuGenda.xcodeproj -scheme AuGenda \
  -destination 'platform=macOS' -only-testing:AuGendaTests \
  -enableCodeCoverage YES

# Build for macOS / Watch
xcodebuild build -project AuGenda.xcodeproj -scheme AuGenda \
  -destination 'platform=macOS'
xcodebuild build -project AuGenda.xcodeproj \
  -scheme 'AuGendaWatch Watch App' \
  -destination 'generic/platform=watchOS' \
  CODE_SIGNING_ALLOWED=NO ENABLE_TESTABILITY=YES
```

Prerequisites: macOS with Xcode 26.x (CI selects an Xcode whose iOS SDK is
26.5+), Apple Developer account for device builds (automatic signing; set your
team ID in Signing & Capabilities). Optional Google OAuth is configured via the
`AUGENDA_GOOGLE_CLIENT_ID` user-defined build setting (placeholder in
`project.pbxproj`; see `GETTING_STARTED.md` and `AuGenda/Scripts/validate-oauth.sh`).

**Keychain tests must run signed.** Unsigned simulator runs fail Keychain tests
with `errSecMissingEntitlement`; CI runs the unit suite unsigned on macOS
(Keychain works there) and skips those failures on iOS.

## Targets and layout

Seven native targets (bundle ID prefix `ensdev.`):

| Target | Bundle ID | Kind |
|---|---|---|
| AuGenda | `ensdev.AuGenda` | iOS/iPadOS/macOS app |
| AuGendaTests / AuGendaUITests | `ensdev.AuGendaTests` / `…UITests` | test bundles |
| AuGendaWatch Watch App | `ensdev.AuGenda.watchkitapp` | watchOS app |
| AuGendaWatch Watch AppTests / UITests | `ensdev.AuGendaWatch-Watch-AppTests` / `…UITests` | Watch test bundles |
| AuGendaWatchWidgetsExtension | `ensdev.AuGenda.watchkitapp.AuGendaWatchWidgets` | watchOS widget |

Directory map:

- `AuGenda/` — the main app; flat file layout, one concern per file (see the
  domain table below). `Shared/` — code compiled into phone, Watch, and widget
  targets (`WatchSyncContract.swift`, `WatchSharedStateStore.swift`).
  `AuGendaWatch Watch App/`, `AuGendaWatchWidgets/` — Watch-side code.
- `AuGendaTests/` — unit tests; `AuGendaTests/Fixtures/` holds a real v1
  SwiftData store (`AuGendaV1.store` + manifest) used by migration tests.
- `docs/`, `audits/` — concept notes and dated audit snapshots
  (`audits/history/` for older ones).
- `build/`, `local-artifacts/` — gitignored scratch/build outputs; never
  commit contents there.
- Top-level docs: `SPEC.md` (feature spec, living document), `PRD.md`
  (requirements), `DEVELOPER_DOCUMENTATION.md` (deep-dive: schema, quirks,
  dated verification evidence), `DESIGN_SYSTEM_USAGE.md` (design tokens quick
  reference), `GETTING_STARTED.md`. `KIMI-CODE-PROMPT.md`,
  `PRD-compliance-audit.md`, and `PRD-GAP-FIX-PROMPT.md` are working
  scratch/prompt documents, not product docs.

Main app domains (all in `AuGenda/`):

- **Models / schema:** `AgendaItem.swift` (`AgendaItem`, `SubTask`),
  `AgendaTask.swift` (`AgendaTask`, `TaskStep`), `InboxItem.swift`,
  `BlockModels.swift` (blocks, bundles), `ProfileModels.swift` (`Profile`,
  `ProfilePreferences`, `ActiveProfileManager`), `FocusSession.swift`,
  `TaskRelationship.swift`, `Note.swift`, `CognitiveProfile.swift`,
  `AppContainer.swift` (`AuGendaSchemaV1`/`AuGendaSchemaV2` +
  `AuGendaMigrationPlan`, persistence startup).
- **Logic engines (pure, testable):** `DifficultyEngine.swift`,
  `TaskLifecycle.swift`, `TaskListProjection.swift`, `TaskFieldDomain.swift`.
- **AI layer:** `AITaskEnricher.swift` (protocol, `AIProvider` enum,
  `AIEnrichmentManager`), one `AIEnricher_<Provider>.swift` adapter per
  provider (Apple Foundation Models, Claude, OpenAI, Gemini, DeepSeek,
  Mistral, Ollama, Perplexity, Grok, plus a shared `AIEnricher_OpenAICompatible`
  base), `AIEnrichmentMutation.swift`, `AIUsageLedger.swift`,
  `AIPersonalization.swift`, `KeychainStore.swift`, OAuth (`OAuthCoordinator`,
  `GoogleOAuth`).
- **Managers (singletons, `@EnvironmentObject`):** `NotificationManager`,
  `BlockManager` (in `BlockView.swift`), `ActiveProfileManager` (in
  `ProfileModels.swift`), `WatchConnectivityManager`.
- **Views:** `RootView` (in `AuGendaApp.swift`; injects `modelContext` into
  managers), `ContentView` (tab/sidebar shell), `HomeDashboardView`
  (also holds `InboxReadyBanner`), `TaskBacklogView` (also holds the shared
  `AddTaskView` create/edit form and `BrainDumpView` capture sheet),
  `TaskDetailView`, `InboxView` (also holds `InboxItemReviewSheet`),
  `BlockView`, `HouseholdView`, `ProfileViews`, `SmartSuggestView`,
  `FocusSessionView`, `OnboardingView`, `AIEnrichmentSettingsView`,
  `FocusSessionHistoryView`, `MorningSetupView`, `AddNoteSheet.swift`,
  `InterruptionPickerSheet.swift`.
- **Design system:** `DesignTokens.swift` (`Tokens.*`, `AppColor`),
  `AuDHDComponents.swift`, `AuDHDProgressComponents.swift`, `AuDHDLayout.swift`,
  `AuDHDNDComponents.swift` (also holds `EnergyFilter`). New UI should use
  these tokens/components, not ad-hoc values.
- **Services/utilities:** `TaskImportExport.swift`, `EraseAllDataService.swift`,
  `ProfileDeletionService.swift`, `AppDefaultsKeys.swift`, `ErrorBanner.swift`,
  `Scripts/validate-oauth.sh`.

## Architecture conventions

- **No MVVM.** Views fetch directly with `@Query`, write via
  `@Environment(\.modelContext)`, and observe the four singleton managers via
  `@EnvironmentObject` (injected in `AuGendaApp` onto `RootView`). Do not add
  ViewModel layers.
- **Managers get their `ModelContext` after init**: `RootView.onAppear` sets
  `manager.modelContext = modelContext`. Always `guard let context = modelContext`
  before fetching/saving in a manager.
- **Persistence:** production uses `AppContainer.makePersistentLocalStartupState()`
  (file-backed, no CloudKit). Open failure yields a read-only recovery surface —
  never silently substitute an in-memory store in production. Use
  `AppContainer.makeTestContainer()` in tests and `AppContainer.preview` in
  previews. The `-ui-testing` launch argument selects the in-memory test container.
- **Schema changes require a new `VersionedSchema` version + an explicit
  migration stage + a prior-store fixture + failure-path tests.** See
  `MigrationTests.swift` and `AuGendaTests/Fixtures/AuGendaV1.store`.
- **Naming:** the task model is `AgendaTask` (in `AgendaTask.swift`), renamed
  from `Task` to avoid colliding with Swift's concurrency `Task` type. The old
  compatibility `typealias Task = AgendaTask` documented in
  `DEVELOPER_DOCUMENTATION.md` no longer exists in the tree — always write
  `AgendaTask`.
- **Platform guards:** the macOS build is native, not Catalyst — always use
  `#if os(iOS)`, never `#if !targetEnvironment(macCatalyst)`. `.presentationDetents`
  is iOS-only. Adaptive colors need `#if os(iOS)` (`UIColor`) / macOS (`NSColor`)
  branches.
- **Errors surface calmly:** user-facing failures map to short, blame-free
  messages (see `AIEnricherError`, `ErrorBannerController`), never raw error dumps.
- **Recurrence is completion-driven.** `TaskLifecycle.swift` supports daily,
  weekdays, weekly, and monthly rules with idempotent next occurrences. Preserve
  the original series anchor, advance beyond the current occurrence and
  completion time, and keep monthly day clamping. No launch-time generation,
  biweekly, or custom recurrence is implemented.
- **Comments:** header comments state what a file is for and the "why" behind
  non-obvious decisions; doc comments on public API. Match this style.

## Testing strategy

- **Frameworks:** a mix of XCTest and Swift Testing (`import Testing`,
  `@Test`, `#expect`). Match the style of the neighboring test file.
- `DifficultyEngineTests` pins exact formula outputs — intentionally brittle
  regression locks. Engine tests are pure/deterministic; model tests use
  `AppContainer.makeTestContainer()`; UI automation uses `-ui-testing`.
- Coverage: CI enforces a **7% line-coverage floor** on `AuGenda.app` (the
  >80% goal in the PRD is aspirational — do not claim it).
- UI test targets are mostly launch/smoke templates; CI runs one onboarding
  smoke test (`testCleanLaunchShowsCapacityChoice`) on iOS Simulator and one
  launch test (`testLaunchShowsCaptureSurface`) on the Watch Simulator.
- Never present build/test results as verified without running them. Dated
  evidence lives in `DEVELOPER_DOCUMENTATION.md` §4.7; audit snapshots live in
  `audits/`.

## CI / deployment

`.github/workflows/ci.yml` (macos-26 runner) on every PR and push to `main`:
repo hygiene checks (no tracked `xcuserdata`, no scratch audit files at root,
`plutil -lint` on all plists/entitlements/privacy manifests/pbxproj), macOS
unit tests with coverage floor, an iOS onboarding UI smoke test, Release builds
for iOS and watchOS, Watch unit + launch UI tests, and a package-content check
that rejects stray files (prompts, READMEs, scripts, font binaries) inside the
built `.app`. There is no deployment step; release archiving, signing, and App
Store submission are manual.

## Security and privacy considerations

- **API keys and OAuth tokens live in the Keychain** (`KeychainStore`;
  OAuth tokens use an `oauth-{provider}` account name, see `OAuthCoordinator`) —
  never `@AppStorage`, never iCloud-synced. Do not add keys to UserDefaults,
  plists, or source.
- AI is **off by default**; nothing leaves the device until the user enables a
  provider. On-device speech recognition (`requiresOnDeviceRecognition = true`)
  for dictation; Apple Foundation Models runs report zero tokens.
- Do not commit secrets; `*.env` is gitignored. Google OAuth uses a public
  iOS client (no client secret; PKCE via `ASWebAuthenticationSession`).
- Location is requested only when an outdoor block with weather check starts;
  notifications are local-only (no push entitlement). WeatherKit and the Watch
  App Group (`group.ensdev.AuGenda.watch`) require correct portal provisioning.
- Keep `PrivacyInfo.xcprivacy` manifests consistent with actual behavior when
  adding features.

## Key gotchas (details in `DEVELOPER_DOCUMENTATION.md` §3)

- Apple Foundation Models is effectively unavailable in the iOS Simulator —
  test enrichment with a real device or a cloud provider.
- Non-Sendable values (e.g. notification `userInfo`) must be unpacked into
  primitives in the `nonisolated` delegate method before entering a
  `Task { @MainActor in … }`.
- `EnergyFilter.apply` (in `AuDHDNDComponents.swift`) has a
  `max(energyLevel, 2)` floor so low-energy users never see an empty list —
  intentional.
- `sessionDidDeactivate` re-activating `WCSession.default` is required and
  must not be removed.
- Watch sync: phone→Watch uses `updateApplicationContext` (full-replacement
  snapshot) + `sendMessage` as a latency optimization; Watch→phone mutations
  use durable `transferUserInfo` with an outbox, event IDs, and
  acknowledgements.

## When you change things

- Keep `SPEC.md`, `PRD.md`, and `DEVELOPER_DOCUMENTATION.md` in sync with
  behavior changes — they are living documents with explicit "last updated"
  discipline.
- This file: update it when build commands, targets, conventions, or the
  directory layout change.
