# AuGenda v5 Full Codebase Audit

**Branch:** `active-dev`  
**Commit:** `d7f059e`  
**Audit Date:** 2026-07-19 MDT  
**Scope:** All 85 Swift files across iOS app, watch app, widgets, unit tests, UI tests, entitlements, privacy manifests, AI/networking, import/export, persistence, and release-facing settings copy.  
**Swift LOC:** 25,684, excluding `build/`.

## Executive Summary

**Verdict: B-.** The codebase is cohesive and still has several strong safety choices: local-first architecture, opt-in AI, per-task AI exclusion, Keychain storage for provider secrets, notification redaction defaults, and no hardcoded provider API keys found in Swift/plist/entitlement sources.

It is not release-ready as-is. I found three high-priority issues that can affect real users: the production Keychain/OAuth secret-write paths are weaker than the tested path and likely to fail on some biometric/device configurations; AI monthly-budget enforcement is bypassed from existing task detail enrichment; and the app tells users their data syncs through iCloud while the main runtime still injects the local-only dev SwiftData container.

No P0 issue was found. The highest-risk work is clustered and fixable.

## Verification Run

Commands run:

- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -list -project AuGenda.xcodeproj`
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project AuGenda.xcodeproj -scheme AuGenda -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild analyze -project AuGenda.xcodeproj -scheme AuGenda -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO`
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project AuGenda.xcodeproj -scheme AuGenda -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO`
- `rg` sweeps for AI settings, Keychain/OAuth paths, URL/networking, logging, UserDefaults keys, model drift, tests, entitlements, and hardcoded secret patterns.

Results:

- Generic iOS build: **succeeded**.
- Static analyzer: **succeeded**.
- Unit/UI tests: **not runnable in this environment**. Xcode reported CoreSimulator is out of date: installed `1051.54.0`, expected `1051.55.0`; no `iPhone 17` simulator destination was available.
- The build emitted Swift concurrency warnings in the widget timeline provider that become errors under Swift 6 language mode.

Limitations:

- No simulator/device runtime validation because local CoreSimulator is not usable.
- No real iCloud, OAuth, biometric Keychain, notification, watch, or widget device test was possible.
- This was a parent-agent/manual audit. The local Codex Security scan skill was used for workflow guidance, but no connected security-scan app setup tool was available.

## Findings

### P1 - Production Keychain/OAuth secret writes do not match the safe tested path

**Evidence:**

- `AuGenda/KeychainStore.swift:97-117` inserts provider API keys with both `kSecAttrAccessible` and `kSecAttrAccessControl`, then throws immediately on `SecItemAdd` failure.
- `AuGenda/OAuthCoordinator.swift:148-172` does the same for OAuth tokens and has no no-biometry fallback.
- `AuGenda/AIEnrichmentSettingsView.swift:721-729` surfaces provider key save failure as "Couldn't save key".
- `AuGenda/AIEnrichmentSettingsView.swift:551-557` routes Google sign-in through `OAuthCoordinator.shared.authorize`, whose token write can fail after successful auth.
- `AuGenda/KeychainStore.swift:241-273` has a fallback without access control, but this is the string/account overload used by tests, not the production `AIProvider` overload.
- `AuGendaTests/KeychainStoreTests.swift:17-39` only covers the string helper path.

**Impact:** Real users can be unable to save AI provider API keys or Google OAuth tokens on device/simulator configurations where the access-control insert is rejected. The test suite gives a false sense of coverage because it exercises a more forgiving helper path.

**Fix:** Factor shared Keychain insertion into one implementation. When using `SecAccessControl`, do not also pass a conflicting accessible attribute in the same add/update dictionary. Add an explicit no-biometry fallback when biometric access is unavailable or denied. Add tests for the `AIProvider` overload and an OAuth token-store seam, with injected `SecItem` behavior so both success and fallback paths are covered.

### P1 - Existing-task enrichment bypasses monthly AI budget and usage accounting

**Evidence:**

- `AuGenda/TaskDetailView.swift:62-64` enables enrichment using only app/provider/task flags.
- `AuGenda/TaskDetailView.swift:423-454` calls the selected AI provider directly without `AIUsageLedger.shared.canEnrich()`.
- `AuGenda/TaskDetailView.swift:456-488` applies the AI result and records personalization memory, but never calls `AIUsageLedger.shared.record(...)`.
- The new-task path does enforce and record usage at `AuGenda/ContentView.swift:1443-1478`.

**Impact:** A user who hits the monthly cap can still enrich existing tasks from the detail screen. Usage/cost reporting also undercounts those calls, so Settings can show a reassuring number while real provider spend keeps moving.

**Fix:** Move AI budget enforcement into a shared enrichment service or guard that all entry points use. Record the ledger on every successful provider response, including detail-screen enrichment. Add a test that exercises both new-task and existing-task enrichment paths against a capped ledger.

### P1 - iCloud sync/privacy copy is false for the current app runtime

**Evidence:**

- `AuGenda/AuGendaApp.swift:38-42` injects `.modelContainer(AppContainer.dev)`.
- `AuGenda/AppContainer.swift:73-90` defines the production CloudKit container but falls back to dev on error.
- `AuGenda/AppContainer.swift:93-107` defines the dev container as local-only.
- `AuGenda/AppContainer.swift:25-26` still labels the CloudKit container ID as a placeholder.
- `AuGenda/ContentView.swift:944` tells users task content is stored privately in iCloud.
- `AuGenda/OnboardingView.swift:90-91` tells users their data syncs only through their iCloud private database.
- `find . -name '*.entitlements'` found only `AuGenda/AuGenda.entitlements`; no watch/widget entitlements are present.
- `AuGendaWatchWidgets/WatchAppContainer.swift:40-47` still has CloudKit commented out.

**Impact:** Users are told their data is synced and recoverable through iCloud, but the shipped runtime path is local-only. This is a trust, support, privacy-copy, and App Review risk. It also affects wipe semantics: erase dialogs reference iCloud copies that the app is not currently writing.

**Fix:** Decide the release mode. If CloudKit is not ready, change onboarding/settings/erase copy to say local-only and remove iCloud recovery claims. If CloudKit is ready, inject `AppContainer.production`, remove the silent fallback or surface a blocking error, configure watch/widget entitlements, and run real-device CloudKit migration/sync tests.

### P2 - "Auto-enrich new tasks" is a visible setting but has no save-time implementation

**Evidence:**

- `AuGenda/AIEnrichmentSettingsView.swift:408-417` exposes the toggle and says enrichment runs automatically when a new task is saved.
- `AuGenda/ContentView.swift:1164` reads `@AppStorage("ai.autoEnrichNewTasks")`.
- `rg "autoEnrich"` found no save-time use beyond settings/state/erase.
- `AuGenda/ContentView.swift:1514-1570` saves new tasks without invoking enrichment.

**Impact:** Users can enable a setting that does nothing. Because this feature can spend money and send task content to cloud providers, an incomplete implementation is especially risky: it either breaks trust by not running or, if later wired in hastily, can skip consent/budget gates.

**Fix:** Either hide the toggle until implemented, or implement it through the same shared enrichment path recommended above, with explicit consent, budget check, per-task `excludeFromAI`, preview/apply behavior, and ledger recording.

### P2 - Watch/widget SwiftData model copies have drifted behind the iOS schema

**Evidence:**

- iOS `AgendaItem` has six-axis and AI privacy fields at `AuGenda/AgendaItem.swift:47-75`; the watch copy jumps from `needsBodyDouble` to completion at `AuGendaWatch Watch App/AgendaItem.swift:44-48`.
- iOS `AgendaTask` has `sensoryLoad`, `socialLoad`, `initiationCost`, `specialInterest`, and `excludeFromAI` at `AuGenda/AgendaTask.swift:54-82`; the watch copy does not at `AuGendaWatch Watch App/AgendaTask.swift:51-82`.
- iOS `AgendaTask` has `isBlocked(in:)` at `AuGenda/AgendaTask.swift:186-207`; the watch copy lacks it.
- iOS `ProfilePreferences` has `showCheckInNudges`, `lowStimulationMode`, `reduceMotion`, and `uiScale` at `AuGenda/ProfileModels.swift:336-339`; the watch copy stops at `highContrastMode` around `AuGendaWatch Watch App/ProfileModels.swift:324-330`.
- `AuGendaWatchWidgets/WatchAppContainer.swift:30-38` builds a separate schema from these copied model files.

**Impact:** Even before CloudKit, watch/widget views can render a different notion of task difficulty and user preference than iOS. Once CloudKit is enabled, schema drift can become a migration/sync failure risk.

**Fix:** Move shared model definitions into a shared target/module used by iOS, watch, and widget targets, or add an automated parity test that fails whenever duplicated model stored properties diverge. Do the same for migration plan/schema lists.

### P2 - "Erase all data" does not clear all UserDefaults keys it claims to clear

**Evidence:**

- `AuGenda/ContentView.swift:1007` promises every task, block, profile, preference, AI key/sign-in, and AI personalization profile is removed.
- `AuGenda/ContentView.swift:1021-1024` says every UserDefaults key the app reads or writes is wiped.
- `AuGenda/ContentView.swift:1069-1083` removes only a subset of keys.
- Missing examples include `ai.localOnlyMode` from `AuGenda/AIEnrichmentSettingsView.swift:40`, `ai.maxMonthlyCostUSD` from `AuGenda/AIUsageLedger.swift:108-110`, `ai.personalization.*` keys from `AuGenda/AIPersonalization.swift:97-101`, cognitive check-in keys from `AuGenda/CognitiveStateSelector.swift:60-63`, and first-launch/onboarding keys found in `AuGenda/AuGendaApp.swift:105-119`.

**Impact:** The most sensitive personalization text is reset to empty by `PersonalizationStore.shared.resetAll()`, and usage history is cleared by `AIUsageLedger.shared.clear()`, so this is not currently a credential leak. It is still a privacy/product correctness bug: after "erase everything", onboarding, local-only mode, budget cap, check-in cadence, and some AI defaults can survive.

**Fix:** Centralize UserDefaults keys in one registry and have erase call that registry. Prefer deleting personalization AppStorage keys rather than setting benign defaults. Add an erase test that seeds every registered key, calls the wipe path through a testable service, and asserts removal.

### P2 - Widget timeline provider has Swift 6 actor-isolation build warnings

**Evidence:**

- The generic iOS build succeeded, but warned that `AuGendaWatchWidgets/AuGendaWatchWidgets.swift:131` and `:150` reference main actor-isolated `WatchAppContainer.production` from nonisolated functions.
- `AuGendaWatchWidgets/WatchAppContainer.swift:30` declares `@MainActor static let production`.
- The build warning says this becomes an error in Swift 6 language mode.

**Impact:** Current Swift 5 builds pass, but migration to Swift 6 or stricter concurrency settings can break widgets. WidgetKit timeline provider callbacks are also not a great place to rely on implicit main-actor model-container access.

**Fix:** Make the widget data-access path actor-safe. Options include removing unnecessary `@MainActor` from static container initialization if safe, moving timeline work onto a main-actor async boundary, or creating a widget-specific data service with explicit isolation.

### P2 - Export encryption uses a fast single-hash password derivation

**Evidence:**

- `AuGenda/TaskImportExport.swift:315-327` derives the AES key as `SHA256(password + salt)`.
- `AuGenda/TaskImportExport.swift:319-321` ignores the return status from `SecRandomCopyBytes`.
- `AuGenda/TaskImportExport.swift:347-368` repeats the same single-hash derivation for decrypt.

**Impact:** AES-GCM is the right authenticated-encryption primitive, but a single SHA-256 hash is not a password-hard KDF. If an encrypted export is captured, weak user passwords are cheaper to brute-force offline than they need to be.

**Fix:** Version the encrypted export envelope and move new exports to PBKDF2-HMAC-SHA256, Argon2id, or another platform-approved password KDF with salt and iteration/memory parameters. Check `SecRandomCopyBytes` and fail closed if random generation fails. Keep old SHA-256 exports readable as legacy v1.

### P3 - CSV export is documented as lossless but cannot re-import multiline fields

**Evidence:**

- `AuGenda/TaskImportExport.swift:9` documents CSV as lossless within the exposed task field set.
- `AuGenda/TaskImportExport.swift:251-254` correctly quotes strings that contain `\n`.
- `AuGenda/TaskImportExport.swift:483-491` imports CSV by splitting the entire file on newline before parsing quoted fields.
- `rg -g '*.swift' "CSV|csv"` found no CSV round-trip tests in `AuGendaTests`.

**Impact:** A task note containing a newline can be exported to CSV, then skipped or corrupted on import because the parser sees the second line as a separate row. JSON/YAML tests cover embedded newlines; CSV does not.

**Fix:** Replace the line-splitting CSV importer with a small state-machine parser over the whole file, or use a CSV library if one is already acceptable for the project. Add round-trip tests for commas, quotes, and embedded newlines in CSV.

### P3 - Test coverage is thin around the riskiest release paths

**Evidence:**

- `AuGendaTests/AuGendaTests.swift:12-15` is still the template placeholder test.
- Keychain tests cover only the string helper path at `AuGendaTests/KeychainStoreTests.swift:17-39`.
- No tests were found for OAuth token persistence, AI budget enforcement across all enrichment entry points, erase-all-data key coverage, CloudKit container selection, watch/iOS model parity, or CSV round-trip.

**Impact:** The current test suite catches some domain logic, migrations, notifications, relationships, and import/export basics, but it does not guard the highest-risk release contracts found in this audit.

**Fix:** Add focused, testable services for Keychain/OAuth storage, AI enrichment orchestration, erase-data behavior, model parity, and CSV parsing. These should be pure/unit-testable where possible so they do not depend on CoreSimulator availability.

## Positive Findings

- No hardcoded provider API keys or OAuth secrets were found in Swift/plist/entitlement sources. The only secret-like strings found were request headers, settings URLs, and test fixtures.
- AI is opt-in and cloud-provider behavior is disclosed in settings.
- Per-task AI exclusion is present on both `AgendaItem` and `AgendaTask` in the iOS app model.
- New-task AI enrichment already has budget gating and ledger recording.
- Notification privacy defaults are conservative; strict redaction is enabled by default in profile preferences.
- The AI networking layer avoids logging prompt bodies or task content in the inspected paths.
- Build and static analysis pass on a generic iOS destination with code signing disabled.

## Recommended Fix Order

1. Repair shared Keychain/OAuth secret storage and add tests for production paths.
2. Move AI budget checks and usage recording into one shared enrichment service used by every entry point.
3. Decide CloudKit release posture, then make runtime behavior and user-facing copy match.
4. Hide or fully implement "Auto-enrich new tasks" with the same consent/budget/ledger behavior.
5. Eliminate watch/widget model drift through a shared model module or parity tests.
6. Centralize and fully clear UserDefaults keys for erase-all-data.
7. Make widget timeline data access Swift 6-safe.
8. Upgrade export encryption KDF and fix CSV multiline round-trip.

## Working Tree Note

The worktree was already dirty before this report was written. I did not modify or restore the pre-existing deleted widget app-icon assets or untracked `resonator-*.md` files. This audit adds only `audit-report-v5.md`.
