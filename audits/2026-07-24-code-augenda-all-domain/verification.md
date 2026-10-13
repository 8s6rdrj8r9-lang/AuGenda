# AuGenda All-Domain Code Audit — Verification Record

- **Audit ID:** `2026-07-24-code-augenda-all-domain`
- **Repository:** `/Users/arthur/Development/AuGenda`
- **Snapshot:** `active-dev` at `d7f059e`, including all uncommitted changes present during the audit
- **Verification date:** 2026-07-24
- **Xcode:** full installation at `/Applications/Xcode.app`

## Inventory

The working tree contains **87 Swift files / 25,836 lines** across:

| Area | Swift files | Lines |
|---|---:|---:|
| Main AuGenda app | 55 | 21,528 |
| Main unit tests | 10 | 708 |
| Main UI tests | 2 | 78 |
| Watch app | 8 | 1,907 |
| Watch unit tests | 1 | 19 |
| Watch UI tests | 2 | 78 |
| Watch widget extension | 9 | 1,518 |

There are **seven native targets**:

1. `AuGenda`
2. `AuGendaTests`
3. `AuGendaUITests`
4. `AuGendaWatch Watch App`
5. `AuGendaWatch Watch AppTests`
6. `AuGendaWatch Watch AppUITests`
7. `AuGendaWatchWidgetsExtension`

There are three shared schemes:

- `AuGenda`
- `AuGendaWatch Watch App`
- `AuGendaWatchWidgetsExtension`

No Swift Package dependencies or CI configuration were found; this checkout also has no configured git remote. The audit covered production/test Swift, the Xcode project and schemes, plists, entitlements, privacy manifests, scripts, asset manifests/files, root documentation, and current working-tree hygiene. Untracked Resonator documents were checked for project coupling; no runtime/project reference was found.

The exhaustive file-to-domain assignment is recorded in [`inventory.md`](inventory.md). Grouped asset paths in that manifest include every file beneath the named directory at the audit snapshot.

## Review Method

Four parallel domain passes were reconciled:

- persistence, migrations, import/export, task relationships, blocks, focus, notifications;
- security, privacy, Keychain/OAuth, AI providers, usage accounting, transport and release capabilities;
- iPhone/iPad/macOS UI, accessibility, launch/navigation, performance and documentation;
- WatchConnectivity, Watch app, widgets/complications, offline behavior and cross-target parity.

Every consolidated finding was traced to current source/configuration. Cross-domain duplicates were merged under one finding owner. This section records the pre-remediation baseline; production remediation began only after the user’s follow-up request and is recorded separately below when verified.

## Build and Test Matrix

### Main scheme — macOS unit tests

Command:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild test \
  -project AuGenda.xcodeproj \
  -scheme AuGenda \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /private/tmp/AuGendaAuditMac \
  -only-testing:AuGendaTests \
  CODE_SIGNING_ALLOWED=NO
```

Result:

- **Succeeded**
- **46 passed, 0 failed, 0 skipped**
- Result bundle: `/private/tmp/AuGendaAuditMac/Logs/Test/Test-AuGenda-2026.07.24_08-45-00--0600.xcresult`

Production line coverage reported by the result bundle:

| Target | Covered / executable lines | Coverage |
|---|---:|---:|
| `AuGenda.app` | 4,161 / 35,484 | **11.7264%** |
| `AuGendaTests` | 579 / 581 | 99.6558% |
| UI, Watch, widget targets | 0 covered | 0% |

This directly contradicts `PRD.md:940-946`, which reports ~45% current coverage and a >80% target.

### Main scheme — iOS simulator unit tests, unsigned

Command used the iPhone 17 Pro simulator and:

```text
-only-testing:AuGendaTests CODE_SIGNING_ALLOWED=NO
```

Result bundle:

```text
/tmp/AuGendaAuditIOSUnit.xcresult
```

Result:

- The app and test bundles compiled, including Watch/widget dependencies.
- **43 passed, 3 failed, 0 skipped (46 total).**
- The three failures were Keychain cases with `errSecMissingEntitlement` / `-34018` or nil reads.
- The run also could not collect some simulator diagnostics because its environment lacked a usable `simctl`.

Interpretation: these failures occurred with code signing explicitly disabled and were treated as a harness hypothesis, not a product finding.

### Focused signed iOS Keychain rerun

The same Keychain suite was rebuilt with local ad-hoc signing enabled and a configured `DEVELOPER_DIR`.

Result:

- **Succeeded**
- **5 passed, 0 failed**
- Result bundle: `/tmp/AuGendaAuditIOSKeychain.xcresult`

Passing cases:

- `testNonExistentKey`
- `testRemove`
- `testSetAndGet`
- `testSharedDataStorageRoundTripsOAuthShapedPayload`
- `testUpdateExistingKey`

Conclusion: the unsigned `-34018` failures are confirmed harness artifacts. This audit does **not** report a current Keychain read/write functional failure. `FIND-018` is limited to token lifecycle and control truthfulness established by source.

### Watch and widget schemes

- The signed main-scheme build compiled the Watch app and widget extension as dependencies.
- A standalone Watch-scheme build compiled and linked Watch/widget code, then failed while compiling the **main iOS app asset catalog** because the sandbox could not access CoreSimulator services. This is an environment result, not a source compile failure.
- A standalone widget-scheme invocation could not select `generic/platform=watchOS Simulator`; the shared scheme includes the main app and Watch app and exposes iOS/macOS destinations. This supports the scheme-quality portion of `FIND-023`.
- Watch unit and UI tests were not successfully executed. Their source is an empty/template suite.

### UI automation

The main UI runner was attempted against an iOS simulator but did not establish an automation connection after 103 seconds. It was stopped rather than reported as a project failure. Existing UI tests contain only launch calls and no assertions, so even a green run would not validate a journey.

### Release and physical-device validation

Not completed:

- App Store-style Release archive and Organizer validation;
- notarization/macOS distribution;
- paired physical iPhone/Watch;
- Watch Double Tap and complication behavior;
- VoiceOver, Switch Control, full Dynamic Type, Reduce Motion, or Increase Contrast;
- real WeatherKit, Google OAuth, and external AI provider credentials;
- App Store privacy questionnaire or legal review.

These remain explicit exit-gate work, not assumed passes.

## Controlled Static and Asset Checks

### Plist syntax

```bash
plutil -lint \
  AuGenda/Info.plist \
  AuGenda/PrivacyInfo.xcprivacy \
  AuGenda/AuGenda.entitlements \
  AuGendaWatchWidgets/Info.plist
```

Result: all four files are syntactically valid. Syntax validity does not establish semantic accuracy or that entitlements are applied.

### Applied entitlements

- Repository search found no `CODE_SIGN_ENTITLEMENTS`, App Group identifier, or configured target capabilities.
- `codesign -d --entitlements -` on the signed simulator `AuGenda.app` emitted no custom entitlements.
- The existence of `AuGenda/AuGenda.entitlements` therefore does not prove push, WeatherKit, or CloudKit capability.

### OAuth validation

```bash
/bin/bash AuGenda/Scripts/validate-oauth.sh
```

Result:

```text
ERROR: Google OAuth client ID is still a placeholder
```

The script is not an Xcode build phase. It greps the deliberate source fallback, while the actual callback scheme in `Info.plist` remains `YOUR_CLIENT_ID_REVERSED`.

### Font validation

```bash
file AuGenda/Fonts/*
```

Result:

- `AtkinsonHyperlegible-Regular.ttf` — HTML document
- `AtkinsonHyperlegible-Bold.ttf` — HTML document
- `OpenDyslexic-Regular.otf` — HTML document

All three are included in the built app’s Resources directory.

### Built resource inspection

The Debug macOS app bundle is approximately **54 MB** and includes:

- the three invalid font files;
- `AuGenda-Watch-ClaudeCode-Prompt.md`;
- `README.md`;
- `validate-oauth.sh`;
- `PrivacyInfo.xcprivacy`;
- `Assets.car`.

The build also warned about ten unassigned children in the main app icon set.

### Secrets scan

A targeted scan for common private-key blocks and high-confidence OpenAI, Google, AWS, and GitHub token shapes found no obvious committed credential. This is not a substitute for provider-side secret scanning or history scanning.

### AI persistence reproduction

A focused Foundation Codable check confirmed that a `Date` encoded with `JSONEncoder.dateEncodingStrategy = .iso8601` is not decoded by an otherwise-default `JSONDecoder`. The same asymmetric strategy is present in both AI persistence files. Source inspection additionally confirmed that decode errors leave their in-memory arrays empty.

### Query/call-site and configuration scans

Repository-wide searches confirmed:

- no production call site for `FocusSessionView`;
- no task merge in Watch `handleSyncSnapshot`;
- no `transferUserInfo`;
- no production `WidgetCenter` reload call;
- no App Group;
- no rendering consumers for several accessibility preferences;
- no production `accessibilityIdentifier`;
- no relationship-creation UI;
- no CI workflow;
- tracked personal `xcuserdata`;
- no code reference to the untracked Resonator documents.

## Finding Verification Matrix

| Finding | Evidence state | Remaining verification |
|---|---|---|
| FIND-001 | Static-confirmed | Inject store/migration/disk failures. |
| FIND-002 | Static-confirmed | Foreground/background/terminated timer matrix. |
| FIND-003 | Static-confirmed | Physical paired-device data/freshness/privacy tests. |
| FIND-004 | Static-confirmed | Offline delivery, retry and acknowledgement tests. |
| FIND-005 | Static-confirmed | Physical complication/timeline tests. |
| FIND-006 | Static-confirmed | Golden full restore and forced encryption failure. |
| FIND-007 | Focused reproduction + static | Relaunch migration and cap enforcement. |
| FIND-008 | Static-confirmed | Proxy-captured provider data flows and privacy review. |
| FIND-009 | Static/build-artifact confirmed | Signed device/archive capability tests. |
| FIND-010 | Reproduced | Runtime font enumeration and visual tests. |
| FIND-011 | Static-confirmed | Full accessibility device matrix. |
| FIND-012 | Static-confirmed | Transactional graph/profile tests. |
| FIND-013 | Static-confirmed | Minimum-OS and Swift 6 build matrix. |
| FIND-014 | Official-provider schedule + static | Live provider availability smoke test. |
| FIND-015 | Static-confirmed | Terminated notification-action tests. |
| FIND-016 | Static-confirmed | State-machine/relaunch tests. |
| FIND-017 | Static-confirmed | Fuzz, malicious CSV, and encrypted-format fixtures. |
| FIND-018 | Static-confirmed | Provider/OAuth negative-path tests. |
| FIND-019 | Static-confirmed | Clean-install and adaptive-navigation UI tests. |
| FIND-020 | Static-confirmed + computed evidence | VoiceOver, touch, and contrast device checks. |
| FIND-021 | Verification gap; static risk | Instruments with 1,000/10,000 records. |
| FIND-022 | Test-observed | CI from clean checkout and real UI assertions. |
| FIND-023 | Reproduced/static | Clean Release archive and independent scheme runs. |
| FIND-024 | Static-confirmed | Frozen prior-version store migration. |
| FIND-025 | Static-confirmed | Independent docs/build reconciliation. |
| FIND-026 | Static-confirmed | Clean-clone hygiene gate. |
| FIND-027 | Static-confirmed | Injected save/side-effect failure matrix. |

## Reproduction Principles for Remediation

- Preserve the current failing fixture before changing code.
- Add a regression test that fails for the finding before or with the fix.
- Verify source-of-truth behavior, not just visible UI.
- For privacy or secrets, inspect the final built/archive product and actual network request.
- For Watch/widgets/notifications, test offline, background, terminated, duplicate, and out-of-order paths.
- For persistence/import, test failure atomicity and the user’s ability to recover.
- For accessibility, combine static checks with assistive-technology and visual evidence on real devices.

## Post-Remediation Verification — 2026-07-24

This section supersedes the baseline matrix above for the current working tree.
Finding closure and remaining release gates are recorded in
[`closure.md`](closure.md).

### Final macOS unit result

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -quiet \
  -project AuGenda.xcodeproj \
  -scheme AuGenda \
  -destination 'platform=macOS' \
  -derivedDataPath /private/tmp/AuGendaClosureFinalDerived \
  -resultBundlePath /private/tmp/AuGendaClosureFinal2-20260724.xcresult \
  -enableCodeCoverage YES \
  -only-testing:AuGendaTests \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  test
```

Result:

- **85 passed, 0 failed, 0 skipped**
- `AuGenda.app`: **2,942 / 38,980 executable lines = 7.5475%**
- the workflow's current 7% coverage floor passes

The added coverage includes persistence startup/rollback, AI envelope
migration/consent/output/transport policy, strict import/export,
profile/relationship integrity, focus reconciliation, display preferences, and
the Watch synchronization contract.

### Unsigned Release products

The following final-tree lanes both passed:

```text
xcodebuild ... -scheme AuGenda -configuration Release
  -destination 'generic/platform=iOS'
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build

xcodebuild ... -scheme 'AuGendaWatch Watch App' -configuration Release
  -destination 'generic/platform=watchOS'
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
  ENABLE_TESTABILITY=YES build-for-testing
```

The iOS product embedded the Watch app and widget dependencies. Final icon
catalogs compiled without the former unassigned-child or unknown-Watch-subtype
warnings.

### Final static and package checks

- all Swift files parsed with `swiftc -frontend -parse`;
- `git diff --check` passed;
- every plist, entitlement, privacy manifest, and the project file passed
  `plutil -lint`;
- workflow YAML, shell syntax, and app-icon JSON passed syntax validation;
- a targeted scan found no current-tree private-key block or high-confidence
  OpenAI, Anthropic, Google, AWS, or GitHub token shape;
- Release package inspection found none of:
  `AuGenda-Watch-ClaudeCode-Prompt.md`, `README.md`, `validate-oauth.sh`,
  `AtkinsonHyperlegible-Regular.ttf`, `AtkinsonHyperlegible-Bold.ttf`, or
  `OpenDyslexic-Regular.otf`.

### Evidence not produced

CoreSimulator services were not reliable in this environment, so no new
simulator UI result is claimed. This pass also did not fabricate results for
signed archives, effective provisioning entitlements, physical Watch behavior,
assistive technologies, provider credentials, OAuth callbacks, WeatherKit,
hosted GitHub Actions, App Store review, legal/privacy review, Instruments, or
release size. Those gates remain explicit in `closure.md`.
