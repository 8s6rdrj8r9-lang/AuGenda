# AuGenda All-Domain Audit — Remediation Closure

- **Audit ID:** `2026-07-24-code-augenda-all-domain`
- **Remediation date:** 2026-07-24
- **Repository:** `/Users/arthur/Development/AuGenda`
- **Snapshot:** post-remediation working tree based on `d7f059e`
- **Decision:** source remediation is materially complete; the product is
  **not release-ready** until the external gates below pass

## Closure Meaning

- **Fixed:** the finding's source/configuration acceptance condition is
  implemented and supported by local automated evidence.
- **Partially fixed:** containment or a substantial repair shipped in the
  working tree, but part of the finding's required product behavior or failure
  matrix remains unfinished.
- **External-unverified:** source controls are implemented or the unsafe feature
  is disabled, but closure requires a signed archive, physical device,
  assistive technology, credentials, provider traffic, hosted CI, or legal/App
  Store review. These remain release blockers rather than assumed passes.

| Closure state | Count |
|---|---:|
| Fixed | 7 |
| Partially fixed | 9 |
| External-unverified | 11 |
| **Total** | **27** |

## Finding-by-Finding Closure

| Finding | State | Remediation and local evidence | Remaining exit condition |
|---|---|---|---|
| FIND-001 | **Fixed** | `AppContainer.productionStartup(using:)` returns an explicit blocking recovery state and never substitutes a writable in-memory production store. `PersistenceSafetyTests.startupFailureNeverReturnsAnInMemoryProductionStore` passes. | A future schema release must still run its frozen-store migration gate under FIND-024. |
| FIND-002 | **External-unverified** | Focus state is keyed by persisted session ID, reconciled at launch/deadline, duplicate active records are closed, and `FocusSessionView` is routed from the main shell. Focus and notification reconciliation tests pass. | Foreground/background/terminated lifecycle and notification timing on supported physical devices. |
| FIND-003 | **External-unverified** | The demo store/models were removed. A versioned, profile-scoped, freshness-bounded `WatchSnapshot` now drives Watch presentation from a fail-closed App Group store. Contract tests and unsigned builds pass. | Paired iPhone/Watch tests for profile switching, deletion, reinstall, stale/redacted state, and out-of-order delivery. |
| FIND-004 | **External-unverified** | Watch mutations use stable event IDs, a durable outbox, `transferUserInfo`, retries, phone acknowledgements, and an idempotency ledger; capture is forwarded to the phone. Contract/outbox source tests build. | Airplane-mode, force-quit, duplicate, acknowledgement-loss, and Double Tap tests on a paired Watch. |
| FIND-005 | **External-unverified** | Main/Watch/widget targets apply the same App Group, widget state reads the shared snapshot, timelines are bounded, reloads occur on changes, and template controls/models were removed. Unsigned Release Watch/widget compilation passes. | Signed App Group entitlement inspection plus physical complication freshness, privacy, and timeline-budget tests. |
| FIND-006 | **Partially fixed** | The UI and documentation now call this a task-list export rather than a backup. The envelope is versioned, stable IDs and fields round-trip, import is idempotent/atomic, encryption is PBKDF2-HMAC-SHA256 + AES-GCM and fails closed. Import/export regression tests pass. | A true whole-product backup/restore still needs every entity, relationship, preference, history record, and a completeness manifest. |
| FIND-007 | **Fixed** | Usage and personalization use symmetric versioned date envelopes, migrate legacy forms, quarantine corruption, and fail closed when spend state is untrusted. Relaunch/migration/cap tests pass. | None for this finding. |
| FIND-008 | **External-unverified** | Local-only policy is enforced at the protected outbound boundary; Ollama host classification uses exact IP ranges and remote TLS; consent version 3 enumerates title, note, neurotypes, capacity, tone, interest setting, About-you text, and optional history; official API-data terms links are adjacent to provider selection. Tests pass. | Provider-by-provider proxy capture, current vendor-terms/legal review, and final App Store privacy questionnaire. |
| FIND-009 | **External-unverified** | Entitlement files are applied to all three shipping targets; App Group/local-network/network/location settings and OAuth bundle configuration/validation paths were repaired; unsigned Release iOS and Watch builds pass. | Signed Release archive effective-entitlement inspection and real WeatherKit, OAuth callback/refresh/sign-out, network, local Ollama, and export tests. |
| FIND-010 | **Fixed** | The three HTML files masquerading as fonts were removed, only system typography is exposed, and Release package inspection confirms none of the invalid fonts ship. | None for the corrupt-asset finding; custom dyslexia fonts remain a future capability, not a current claim. |
| FIND-011 | **External-unverified** | UI scale, large targets, contrast, low-stimulation motion/shadows/density, and sensory-context preferences now affect rendering and are exposed in Settings. State tests pass. | VoiceOver, Switch Control, Dynamic Type, Reduce Motion, Increase Contrast, and clipping checks on the supported device matrix. |
| FIND-012 | **Fixed** | `TaskRelationshipService` enforces existence, self-link, duplicate, and cycle invariants. `ProfileDeletionService` blocks unsafe deletion and clears historical assigner references. Transactional tests pass. | None for the modeled invariants covered by this finding. |
| FIND-013 | **Fixed** | PRD/developer documentation now distinguish intended compatibility from the actual iOS 26.5, macOS 26.3, watchOS 26.5, Swift 5, and staged-concurrency contract. Unsigned generic iOS and watchOS Release lanes compile. | Broader OS/Swift support is a future product change, not a current shipping claim. |
| FIND-014 | **Fixed** | Retired DeepSeek aliases are rejected, the provider is hidden from release selection, stale selections are cleared, and `AIEnricherRegistry` returns `nil` for DeepSeek. The release-disable test passes. | A live minimal chat smoke test is required before changing `isReleaseEnabled` to true. |
| FIND-015 | **External-unverified** | Privacy reconciliation removes stale pending/delivered agenda notifications before rebuilding; erase clears all notifications; focus actions use durable model state and launch reconciliation. Unit tests pass. | Terminated/background notification-action and privacy-change tests on signed devices. |
| FIND-016 | **Partially fixed** | Focus transitions, duplicate session repair, optional-block completion, blocked-task behavior, and documented state semantics were repaired. Recurrence fields are explicitly documented as pass-through only. | Recurrence generation/editor and the remaining abandonment/history state-machine depth are not implemented. |
| FIND-017 | **Partially fixed** | Parsers enforce declared format, size/count/range limits and reject malformed/mismatched input; CSV formula prefixes are neutralized; YAML/CSV/JSON and encryption tests pass. | Broader fuzz/malicious-fixture coverage and user-facing per-row diagnostics remain. |
| FIND-018 | **External-unverified** | One validator rejects unknown/out-of-range/empty provider output before mutation; OAuth uses PKCE, state, cryptographic randomness, form encoding, expiry/refresh, truthful Boolean sign-out/reset results, and provider health checks. Tests pass. | Credentialed negative-path/live-provider and signed OAuth lifecycle tests. |
| FIND-019 | **External-unverified** | Adaptive `NavigationSplitView`/compact navigation and a capacity-first, resumable onboarding state machine replaced the contradictory launch flow. | Clean-install, rotation/window-size, iPad and Mac keyboard/navigation UI journeys. |
| FIND-020 | **External-unverified** | Production controls gained semantic labels/identifiers, target sizing, system text styles, contrast-aware tokens, and low-motion behavior. | Physical-device assistive-technology and visual contrast/target measurements. |
| FIND-021 | **Partially fixed** | Core dashboard/backlog/notification fetches now have bounded limits and several repeated projections were reduced. | Release Instruments evidence with 1,000/10,000-record fixtures and documented launch, memory, and frame budgets. |
| FIND-022 | **Partially fixed** | `.github/workflows/ci.yml` now validates metadata/hygiene, runs the macOS unit suite, enforces a 7% production floor, builds unsigned iOS/Watch Release products, and rejects accidental package contents. The final local suite is 85/85 with 7.5475% production coverage. | Hosted clean-checkout run, assertion-bearing UI/Watch journeys, failure-path expansion, and sustained coverage growth toward the >80% goal. |
| FIND-023 | **Partially fixed** | Internal prompt/script/README/font resources and template widget controls were removed; iOS, macOS, and Watch icons are assigned; shared schemes are corrected; package inspection and unsigned Release iOS/Watch lanes pass without asset warnings. | Signed archive/Organizer validation, effective entitlements, Mac distribution/notarization, thinned size, and actual UI test runners. |
| FIND-024 | **Partially fixed** | Current migration tests verify v1-to-v2 field survival/queryability and production startup fails closed. | A checked-in sanitized store produced by the actual prior binary/schema plus interrupted/corrupt migration cases is still required before any schema-changing release. |
| FIND-025 | **Fixed** | `PRD.md` and `DEVELOPER_DOCUMENTATION.md` now separate requirements, current implementation, dated evidence, and outstanding release gates; current test/coverage/build facts are recorded. | Update dated evidence on every release candidate. |
| FIND-026 | **Partially fixed** | Personal `xcuserdata` is removed from the worktree, ignore rules cover personal IDE/audit artifacts, and CI rejects tracked `xcuserdata`. | Commit the deletion, prove the gate from a clean clone, and keep unrelated Resonator material in its owning repository. |
| FIND-027 | **Partially fixed** | Tested rollback support, atomic/idempotent import, profile-deletion ordering, post-save Watch publication, notification reconciliation, fail-closed AI ledger/memory, and erase-result aggregation cover the highest-risk paths. | Complete injected-save-failure coverage for every edit/complete/snooze/erase/AI path and a durable outbox for every retryable external side effect. |

## Final Local Verification

### macOS unit suite and coverage

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

- **Passed:** 85
- **Failed:** 0
- **Skipped:** 0
- **Production coverage:** 2,942 / 38,980 lines = **7.5475%**
- **CI floor:** 7% = **passed**

### Unsigned Release build lanes

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -quiet \
  -project AuGenda.xcodeproj \
  -scheme AuGenda \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  build
```

Result: **passed**, including embedded Watch/widget dependencies.

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -quiet \
  -project AuGenda.xcodeproj \
  -scheme 'AuGendaWatch Watch App' \
  -configuration Release \
  -destination 'generic/platform=watchOS' \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  ENABLE_TESTABILITY=YES \
  build-for-testing
```

Result: **passed**.

### Static, configuration, asset, and package checks

- Every Swift file passed `swiftc -frontend -parse`.
- `git diff --check` passed.
- Every plist, entitlement, privacy manifest, and
  `AuGenda.xcodeproj/project.pbxproj` passed `plutil -lint`.
- CI workflow YAML, shell syntax, and both app-icon JSON manifests parsed.
- The targeted current-tree credential/private-key scan found no match.
- The unsigned Release iOS package contains none of the former prompt,
  README, validation script, or invalid font resources.
- The final iOS and Watch Release builds emitted no asset-catalog warnings.

## Release Blockers

No external release should be cut until all of the following evidence is
attached:

1. signed Release archives with effective entitlements, validation,
   notarization where applicable, export-compliance review, and thinned size;
2. paired physical iPhone/Watch/App Group/complication/outbox/Double Tap tests;
3. real WeatherKit, Google OAuth, supported external AI providers, and Ollama
   topology tests, with proxy-captured payload confirmation;
4. VoiceOver, Switch Control, Dynamic Type, Reduce Motion, Increase Contrast,
   localization, and adaptive iPhone/iPad/Mac journeys;
5. frozen prior-version migration fixture and the complete injected
   persistence-failure/side-effect matrix;
6. hosted CI from a clean checkout plus meaningful UI/Watch assertions;
7. Instruments and release-size budgets at representative data volumes.

No risk was accepted or waived during remediation.
