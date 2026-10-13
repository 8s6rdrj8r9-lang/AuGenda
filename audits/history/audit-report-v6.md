# AuGenda v6 Re-Audit

Date: 2026-07-19 MDT
Scope: `/Users/arthur/Development/AuGenda`
Result: A+ for source, static analysis, build, and unit-test readiness

## Executive Verdict

AuGenda now grades as **A+** for the codebase surfaces covered by this remediation pass:

- The previously reportable security, privacy, data-integrity, concurrency, and release-readiness findings from `audit-report-v5.md` are closed.
- The iOS app builds cleanly for a generic iOS destination with no `warning:` or `error:` lines in the final build log.
- Static analysis completes cleanly with no `warning:` or `error:` lines in the final analyzer log.
- The unit test target passes on macOS with 46 tests executed and 0 failures.
- Target/project metadata linting passes.
- Final source pattern sweeps found no stale biometric-gated Keychain access-control usage and no stale CloudKit/TestFlight blocker copy in the app sources.

One environment-only caveat remains: full iOS simulator/UI-test execution could not be completed on this machine because CoreSimulator is out of sync/disabled, and the macOS full-scheme UI-test runner crashed before test bootstrap. That does not leave an open source finding from this audit, but a release checklist should still include one smoke run on an updated simulator or physical device.

## Findings Closed

### 1. OAuth and API-Key Secret Storage

Status: Closed

What changed:

- `KeychainStore` now exposes shared data helpers for binary/JSON secret payloads.
- OAuth token persistence moved from `UserDefaults` into Keychain storage.
- Production Keychain entries no longer use biometric access-control flags that could strand background refresh and extension-adjacent flows.
- Keychain updates preserve accessibility attributes and recover from interaction/auth errors by replacing the entry.
- Added an OAuth-shaped Keychain round-trip test.

Risk after fix: Low. Secrets are now stored in the Keychain with app-local accessibility and test coverage for the shared data path.

### 2. AI Budget Enforcement and Auto-Enrichment

Status: Closed

What changed:

- Manual task enrichment now blocks provider calls once the configured monthly budget is capped.
- Successful enrichment calls now record usage in the AI usage ledger.
- The "auto enrich new tasks" setting now has an implementation path during new task save.
- Auto-enrichment respects provider configuration, AI enablement, excluded tasks, draft state, and budget caps.
- Interest inference is only applied when personalization allows it.

Risk after fix: Low. The cost-control UI now maps to actual provider-call gating and accounting behavior.

### 3. Local-Only Runtime and Privacy Copy

Status: Closed

What changed:

- The app now uses an explicit local-only persistent SwiftData container.
- Removed the misleading CloudKit production placeholder path.
- Removed stale user-facing copy that implied private iCloud task sync.
- Google OAuth placeholder copy now frames OAuth as optional and clearly states the API-key path works.
- In-memory test container creation now fails loudly instead of falling back into persistent runtime state.

Risk after fix: Low. Runtime behavior and user-facing privacy promises now match.

### 4. Erase-All-Data Defaults Coverage

Status: Closed

What changed:

- Added `AppDefaultsKeys.resettable` as a central registry of app-owned resettable defaults.
- `eraseAllData()` now clears the registry instead of a narrow hand-written subset.
- Added a test proving every registered default key is removed from a suite-specific `UserDefaults`.

Risk after fix: Low. Future resettable settings now have a single obvious place to register.

### 5. Watch and Widget Model Drift

Status: Closed for stored-property parity

What changed:

- Watch app and widget SwiftData models now include the app-side task fields added since the original companion schemas:
  - `interestLevel`
  - `sensoryLoad`
  - `socialLoad`
  - `initiationCost`
  - `specialInterest`
  - `excludeFromAI`
- Companion profile models now include current UI/accessibility preference fields:
  - `showCheckInNudges`
  - `lowStimulationMode`
  - `reduceMotion`
  - `uiScale`

Risk after fix: Low. Stored-property drift is closed. Relationship behavior remains intentionally app-only until a watch/widget feature needs relationship traversal.

### 6. Watch and Widget Actor-Isolation Warnings

Status: Closed

What changed:

- Removed unnecessary `@MainActor` isolation from static model-container builders in watch/widget container helpers.
- Final generic iOS build log has no warning lines.

Risk after fix: Low.

### 7. Export Encryption

Status: Closed

What changed:

- Encrypted task export now uses a versioned envelope: `AuGendaExportV2:`.
- V2 encryption uses random salt, random nonce, PBKDF2-HMAC-SHA256 with 210,000 iterations, and AES-GCM.
- Empty passwords and random-generation failures now fail explicitly.
- Legacy V1 decrypt compatibility is retained.
- Added an encrypted export round-trip test that verifies the versioned envelope.

Risk after fix: Low. Password-based export encryption now uses a proper KDF and authenticated encryption.

### 8. CSV Multiline Import

Status: Closed

What changed:

- CSV parsing now walks the full input stream and preserves quoted newlines.
- Added a round-trip test for multiline task notes.

Risk after fix: Low.

### 9. Build, Platform, and Test Hygiene

Status: Closed for source/build/test target

What changed:

- The main app target no longer tries to embed the watch app for macOS test builds.
- `InboxView` now uses platform-appropriate list styles.
- Migration tests now use a unique temporary store URL per run.
- State engine equality assertions avoid Swift 6 actor-isolation warnings.
- Project file linting passes.

Risk after fix: Low.

## Verification

Commands run:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project AuGenda.xcodeproj -scheme AuGenda -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build 2>&1 | tee /tmp/augenda-build-final2.log
rg -n "warning:|error:" /tmp/augenda-build-final2.log
```

Result: `** BUILD SUCCEEDED **`; warning/error sweep returned no matches.

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project AuGenda.xcodeproj -scheme AuGenda -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO analyze 2>&1 | tee /tmp/augenda-analyze-final2.log
rg -n "warning:|error:" /tmp/augenda-analyze-final2.log
```

Result: `** ANALYZE SUCCEEDED **`; warning/error sweep returned no matches.

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project AuGenda.xcodeproj -scheme AuGenda -destination 'platform=macOS,arch=arm64' -only-testing:AuGendaTests CODE_SIGNING_ALLOWED=NO 2>&1 | tee /tmp/augenda-unit-tests-final2.log
```

Result: `** TEST SUCCEEDED **`; 46 tests passed with 0 failures.

Note: Xcode emitted one test-bundle metadata warning:

```text
Metadata extraction skipped. No AppIntents.framework dependency found.
```

This warning is from `appintentsmetadataprocessor` during test-bundle metadata extraction, not a Swift compiler warning or app build warning.

```sh
plutil -lint AuGenda.xcodeproj/project.pbxproj
```

Result: `AuGenda.xcodeproj/project.pbxproj: OK`.

```sh
rg -n "SecAccessControl|kSecAttrAccessControl|biometryCurrentSet" AuGenda AuGendaTests -g '*.swift'
```

Result: no matches.

```sh
rg -n "iCloud private database|Task content is stored privately|iCloud copies|data syncs|CloudKit sync silently fails|TESTFLIGHT BLOCKER|TestFlight checklist|AppContainer\\.dev|AppContainer\\.production|cloudKitContainerID" AuGenda -g '*.swift'
```

Result: no matches.

## Remaining Release Smoke Check

The remaining validation item is environmental rather than source-level:

- Re-run the UI smoke path on a healthy iOS simulator or physical iOS device after fixing the local CoreSimulator mismatch.
- The prior full-scheme macOS UI-test runner crashed before test bootstrap, while the unit-test target passed. Treat this as a runner/environment gap unless it reproduces on a supported UI-test destination.

## Worktree Note

This audit did not touch the pre-existing deleted widget AppIcon assets or the unrelated untracked `resonator-*.md` files present in the working tree. They remain visible in `git status` but are outside this remediation scope.
