# AuGenda All-Domain Code Audit — Findings

- **Audit ID:** `2026-07-24-code-augenda-all-domain`
- **Snapshot:** branch `active-dev`, commit `d7f059e`, including the uncommitted working tree
- **Date:** 2026-07-24
- **Capacity calibration:** Full
- **Disposition:** **Not release-ready**

## Executive Summary

The current tree compiles and its macOS unit suite passes, but it is not safe to represent as a complete, release-ready multi-platform product. The audit found **27 consolidated findings: 15 High, 11 Medium, 1 Low, and no confirmed Critical findings**. “No Critical” does not mean low risk: several independent High findings can produce apparent data loss, incomplete backups, false Watch state, privacy-disclosure mismatch, inaccessible promised features, or non-functional release capabilities.

The five action groups with the highest return are:

1. **Protect user data first:** remove silent in-memory persistence fallback, make mutations failure-atomic, and replace the current task-only export with a versioned, identity-preserving, fail-closed backup (`FIND-001`, `FIND-006`, `FIND-027`).
2. **Stop presenting Watch surfaces as synchronized:** establish one real phone/Watch/widget data contract with durable offline mutations and explicit freshness (`FIND-003`–`FIND-005`).
3. **Correct privacy and release boundaries:** reconcile actual AI payloads, Ollama networking, the privacy manifest, signed capabilities, Google OAuth, and macOS sandbox permissions (`FIND-008`, `FIND-009`, `FIND-014`).
4. **Restore core workflow integrity:** make focus sessions expire and recover deterministically, and enforce profile/dependency invariants in the model layer (`FIND-002`, `FIND-012`).
5. **Make accessibility controls real:** replace corrupt font assets and connect Dynamic Type, Reduce Motion, touch-size, contrast, and display preferences to every production surface (`FIND-010`, `FIND-011`, `FIND-020`).

## Severity and Evidence

- **High:** credible path to data loss, privacy/compliance failure, core-feature failure, or major release-contract breach. Full-capacity target: within one week and before external release.
- **Medium:** material correctness, reliability, accessibility, maintainability, or verification gap. Target: one sprint / two weeks.
- **Low:** hygiene or localized quality risk. Target: next quarter.
- **Static-confirmed:** source/configuration establishes the defect without needing runtime behavior.
- **Reproduced:** a controlled check demonstrated the behavior.
- **Test-observed:** build or test output demonstrated the behavior.
- **Verification gap:** plausible risk whose final behavior needs a device, provider, migration fixture, or performance harness.

---

## FIND-001 — Persistent-store failure silently becomes an ephemeral store

- **Severity:** High
- **Domains:** persistence, resilience, error handling
- **Status:** Static-confirmed
- **Locations:** `AuGenda/AppContainer.swift:52-71`; `AuGendaWatch Watch App/WatchAppContainer.swift:27-57`; `AuGendaWatchWidgets/WatchAppContainer.swift:27-57`
- **Description:** Each production container catches any file-backed `ModelContainer` failure and returns an in-memory test container. The app then looks empty, accepts new writes, and loses those writes at termination without telling the user.
- **Impact:** A corrupt store, failed migration, permissions problem, or disk error is converted into apparent data deletion followed by real session data loss. This conflicts with the PRD’s zero-data-loss requirement at `PRD.md:749-754`.
- **Evidence:** `AppContainer.persistentLocal` calls `Self.makeTestContainer()` from its catch block. Equivalent fallback logic exists in the Watch and widget containers.
- **Required remediation:** Replace fallback with an explicit recovery state. Preserve the failed store, surface a blocking diagnostic, offer retry/read-only/export/reset choices, and log a non-sensitive failure code. Never accept user mutations in an unlabeled ephemeral production session.
- **Fallback:** If recovery UI cannot ship immediately, fail launch with a clear recoverable error and support bundle rather than opening an empty writable store.
- **Owner / due:** Persistence owner — 2026-07-31, before external release.
- **Verification:** Inject an unreadable store and an incompatible schema; prove the original store remains intact, the user is warned, no ephemeral writes are accepted, and each recovery action is tested.

## FIND-002 — Focus sessions neither expire nor restore deterministically, and the richer workflow is unreachable

- **Severity:** High
- **Domains:** functional correctness, state management, notifications, UX
- **Status:** Static-confirmed
- **Locations:** `AuGenda/NotificationManager.swift:69-73,299-417`; `AuGenda/ContentView.swift:102`; `AuGenda/FocusSessionView.swift:1-276,281-328`; `AuGenda/FocusSession.swift`
- **Description:** Focus state is held in process memory. The timer view clamps remaining time to zero but never completes the session. Launch does not restore the persisted active session, and `endFocusSession()` completes the first unordered active record. The main Focus tab routes to `FocusView`; `FocusSessionView` has no production call site, leaving task selection, interruption tracking, break handling, and the richer countdown inaccessible. Focus history itself is reachable from Settings.
- **Impact:** Sessions can remain active forever, multiple active records can accumulate across launches, Watch state can diverge, and the product’s richer focus workflow is not reachable.
- **Evidence:** `startFocusSession` persists an active record and schedules alerts, but only an explicit `endFocusSession` mutates it to completed. `ActiveFocusRing` only formats `max(0, remaining)`. Repository-wide call-site search found only the `FocusSessionView` declaration.
- **Required remediation:** Implement one `FocusSessionCoordinator` with a persisted session ID, deadline-based state transitions, launch reconciliation, idempotent completion, and scene/background handling. Route the Focus tab to the supported workflow or remove the dead implementation and its claims.
- **Fallback:** Limit v1 to a clearly labeled non-persistent timer and remove history/Watch synchronization claims until the coordinator exists.
- **Owner / due:** Focus + notifications owner — 2026-07-31.
- **Verification:** Test natural expiry foreground/background/terminated, early end, interruption, relaunch before/after deadline, duplicate-start prevention, task ID retention, Watch state, and history.

## FIND-003 — Watch renders seeded demo data instead of the phone’s agenda

- **Severity:** High
- **Domains:** WatchConnectivity, data integrity, privacy, cross-target parity
- **Status:** Static-confirmed
- **Locations:** `AuGenda/AppContainer.swift:52-65`; `AuGenda/WatchConnectivityManager.swift:55-75,175-222,260-273`; `AuGendaWatch Watch App/WatchAppContainer.swift:27-57,89-102`; `AuGendaWatch Watch App/WatchSessionClient.swift:171-190`; `AuGendaWatch Watch App/NowView.swift:42-48,282-292`
- **Description:** The phone and Watch use separate local-only stores. The phone sends a task snapshot, but Watch snapshot handling applies only focus/recovery state and explicitly defers task merging. `NowView` queries the independent Watch store and seeds “Welcome — tap to mark done.” The phone also fetches the next `AgendaItem` without applying the active-profile filter used for `AgendaTask`.
- **Impact:** The Watch can display and complete a fake task. Its random ID is absent on the phone, so the phone silently ignores completion. Separately, the phone transmits potentially cross-profile `AgendaItem` fields to the paired Watch; the current Watch handler ignores those task fields, but the transfer is still an unnecessary disclosure path and a future merge could expose them in UI.
- **Evidence:** The missing merge and seeded row are direct code paths. This contradicts `PRD.md:877-883`.
- **Required remediation:** Define a versioned snapshot schema, profile scope, source-of-truth rules, freshness timestamp, deletion semantics, and an idempotent Watch-side cache. Remove sample seeding from production.
- **Fallback:** Show a non-actionable “Open AuGenda on iPhone to sync” state and redact titles until a current, profile-scoped snapshot is present.
- **Owner / due:** Watch integration owner — 2026-07-31.
- **Verification:** Pair-device tests for empty/fresh/stale states, profile switching, complete/snooze, deletion, reinstall, out-of-order snapshots, and sensitive-title redaction.

## FIND-004 — Offline Watch actions are lossy and Watch capture never reaches the phone

- **Severity:** High
- **Domains:** WatchConnectivity, offline resilience, data integrity
- **Status:** Static-confirmed
- **Locations:** `AuGendaWatch Watch App/WatchSessionClient.swift:90-170`; `AuGendaWatch Watch App/NowView.swift:98-110,288-340,478-516`; `AuGenda/WatchConnectivityManager.swift:260-310`
- **Description:** Mutations are dropped before activation, reachable `sendMessage` failures have no retry, and offline discrete events use replaceable `updateApplicationContext`, so successive events overwrite one another. Watch capture saves only to the Watch store and ends at a forwarding TODO. Snapshot restoration reads `focusEndsAt` while the encoded field is `focusSessionEndsAt`; even with the key corrected, the phone’s default Codable `Date` encoding and the Watch’s Unix-epoch reconstruction disagree. The phone’s Watch completion/snooze handlers do not reconcile related notifications. Snooze and energy-send methods have no production call sites, and the Double Tap shortcut is attached to the outer `ScrollView` rather than the Done control.
- **Impact:** Apparently successful completions and captures can disappear or remain trapped on the Watch; required snooze/energy actions are absent; pending notifications can contradict a Watch mutation; Double Tap may not invoke Done.
- **Evidence:** `send` has no durable queue or acknowledgement. Apple documents application context as latest-state transfer; discrete ordered events should use an acknowledged durable mechanism such as [`transferUserInfo`](https://developer.apple.com/documentation/watchconnectivity/wcsession/transferuserinfo%28_%3A%29). Repository-wide call-site search found no production caller for Watch snooze or energy sending.
- **Required remediation:** Create a durable local outbox with event IDs, ordering, retry/backoff, phone acknowledgements, and idempotent apply. Use snapshots for replaceable state and queued events for mutations.
- **Fallback:** Disable offline mutation controls and label capture as Watch-only until delivery is guaranteed.
- **Owner / due:** Watch integration owner — 2026-07-31.
- **Verification:** Airplane-mode queue tests with repeated actions, activation races, force quit, reinstall, duplicate delivery, and acknowledgement loss.

## FIND-005 — The complication has no live shared data or refresh lifecycle

- **Severity:** High
- **Domains:** widgets, complications, data sharing, release configuration
- **Status:** Static-confirmed
- **Locations:** `AuGendaWatchWidgets/WatchAppContainer.swift:27-57`; `AuGendaWatchWidgets/AuGendaWatchWidgets.swift:70-90,98-153`; `AuGenda.xcodeproj/project.pbxproj`
- **Description:** The extension opens another default sandbox store, there is no App Group entitlement or applied entitlements configuration, timelines use `.never`, and production source contains no `WidgetCenter` reload call. The rollover fetch also does not filter after the scheduled date and can return the same item.
- **Impact:** The complication normally remains a placeholder or stale; even after storage is shared, it can repeat the current item.
- **Evidence:** The only reload reference is a comment. No `CODE_SIGN_ENTITLEMENTS`, App Group identifier, or `WidgetCenter.shared.reload…` call exists. Apple requires a shared App Group container for host/extension file sharing: [Configuring App Groups](https://developer.apple.com/documentation/xcode/configuring-app-groups/).
- **Required remediation:** Choose a supported shared snapshot store, apply App Group entitlements to the correct targets, generate bounded future entries, reload on meaningful mutations, and define stale/redacted behavior.
- **Fallback:** Remove the complication from the shipping bundle until it can display truthful state.
- **Owner / due:** Widget + signing owner — 2026-07-31.
- **Verification:** Install on a physical paired Watch; verify initial load, task rollover, complete/snooze, offline freshness, privacy redaction, restart, and timeline budget.

## FIND-006 — “Backup” is incomplete, non-idempotent, and can silently export plaintext

- **Severity:** High
- **Domains:** import/export, backup, data integrity, confidentiality
- **Status:** Static-confirmed
- **Locations:** `AuGenda/TaskImportExport.swift:74-134,144-180,220-264,320-356,479-526`; `AuGenda/TaskBacklogView.swift:127-216`
- **Description:** Export covers only a subset of `AgendaTask` fields and excludes agenda items, profiles, preferences, blocks, relationships, focus history, standalone `Note` records, completion/abandonment history, and AI settings. It exports only currently queried incomplete/non-abandoned tasks. Stable task IDs are omitted, so import constructs new UUIDs and its duplicate check can never identify an earlier import. If password encryption returns `nil`, `beginExport` proceeds with plaintext without warning.
- **Impact:** A user can believe they have an encrypted complete backup when they have a partial plaintext task list. Re-import duplicates records and cannot restore the application state.
- **Evidence:** `ExportedTask` has no `clientID`; `toAgendaTask()` invokes a new model initializer; duplicate detection compares that new ID. The encryption branch changes the payload only on success and has no failure branch.
- **Required remediation:** Separate “task sharing” from “full backup.” Define a versioned backup envelope with stable IDs, all required entities/relationships/preferences, integrity metadata, explicit lossy-format warnings, import transaction/rollback, and fail-closed encryption.
- **Fallback:** Rename the current UI to “Export active task list,” remove “backup” claims, and block password-protected export on any encryption failure.
- **Owner / due:** Data portability owner — 2026-07-31.
- **Verification:** Golden round trips from populated fixtures, repeated-import idempotency, wrong-password/corruption tests, completeness diff, relationship preservation, rollback, and plaintext-negative checks.

## FIND-007 — AI cost caps and personalization memory reset after restart

- **Severity:** High
- **Domains:** AI, persistence, budget controls, privacy
- **Status:** Reproduced by focused Codable check; source-confirmed
- **Locations:** `AuGenda/AIUsageLedger.swift:169-200`; `AuGenda/AIPersonalization.swift:214-245`
- **Description:** Both stores encode `Date` with `.iso8601` but decode using a default `JSONDecoder` (`.deferredToDate`). Files written by the app fail to decode on the next launch.
- **Impact:** Usage history disappears in memory, monthly spend caps can be bypassed after restart, and recent personalization memory does not persist as represented.
- **Evidence:** The save/load strategies are asymmetric in both classes. Decode failures are logged and otherwise ignored, leaving empty collections.
- **Required remediation:** Use the same versioned date strategy in both directions, migrate any existing files, quarantine corrupt data, and make a configured budget cap fail closed when ledger state is unreadable.
- **Fallback:** Disable paid-provider enrichment when a non-zero cap is configured and ledger persistence cannot be verified.
- **Owner / due:** AI platform owner — 2026-07-31.
- **Verification:** Write-relaunch-read tests across time zones and schema versions; verify cap enforcement after restart and corrupt/truncated-file behavior.

## FIND-008 — AI consent and “local-only” boundaries do not match the payload or transport

- **Severity:** High
- **Domains:** privacy, AI governance, networking, App Store compliance
- **Status:** Static-confirmed
- **Locations:** `AuGenda/AITaskEnricher.swift:139-151,344-367`; `AuGenda/AIEnrichmentSettingsView.swift:61-70,117-120,155-205,625-706`; `AuGenda/TaskDetailView.swift:430-450`; `AuGenda/ContentView.swift:1443-1474`; `AuGenda/InboxView.swift:467-492`; `AuGenda/PrivacyInfo.xcprivacy:5-23`
- **Description:** Generic cloud consent mentions task titles, notes, and neurotype context, while prompts can additionally include About Me text, recent task titles/bands, tone, capacity and difficulty context. Settings says personalization goes to the provider “never to Apple or anyone else,” which is false for a third-party provider. “Local AI only” accepts any configured Ollama host; plain HTTP validation treats every `172.*` address as private instead of only `172.16.0.0/12`. More importantly, local-only mode is enforced only by filtering/clearing the provider in the Settings UI: the task, agenda-item, and inbox outbound paths read `ai.activeProvider` without re-checking `ai.localOnlyMode`. A restored, migrated, or externally altered defaults state can therefore retain local-only mode while still invoking a cloud provider. The privacy manifest comment says all user data stays in iCloud even though the store is local-only and opted-in content is sent to vendors.
- **Impact:** Consent is not specific enough for sensitive task/profile data, a remote endpoint can be represented as local, a stale configuration can bypass the stated local-only policy, and release privacy declarations can be inaccurate.
- **Evidence:** Prompt construction includes personalization memory via `.suffix(5)` and About Me. The only local-only/cloud-provider conflict cleanup is an `AIEnrichmentSettingsView.onChange`; the outbound call sites do not consult that flag. Apple’s guideline requires disclosure of where personal data is shared, including third-party AI, and explicit permission: [App Review Guideline 5.1.2](https://developer.apple.com/app-store/review/guidelines/).
- **Required remediation:** Enforce local-only policy at the provider registry/outbound service boundary, independent of UI/defaults state. Present a payload preview and provider-specific destination/retention disclosure immediately before first transmission; persist consent by disclosure version; distinguish on-device, LAN, user-hosted remote, and third-party cloud; validate literal private address ranges; update the privacy manifest and App Store privacy answers from actual data flows.
- **Fallback:** Ship only Apple on-device AI; hide Ollama and cloud providers until their disclosures and transport policies are verified.
- **Owner / due:** Privacy + AI owner — 2026-07-31, before any external AI-enabled build.
- **Verification:** Provider-by-provider data-flow tests and proxy capture, consent-version migration, remote-Ollama negative cases, and App Store privacy questionnaire review. Review current vendor terms, including [Gemini API terms](https://ai.google.dev/gemini-api/terms) and [xAI retention](https://docs.x.ai/developers/faq/security).

## FIND-009 — Declared capabilities are not signed, OAuth cannot be configured as documented, and macOS networking is disabled

- **Severity:** High
- **Domains:** build configuration, signing, OAuth, networking, platform support
- **Status:** Static-confirmed; supporting built-product observation
- **Locations:** `AuGenda/AuGenda.entitlements:5-26`; `AuGenda.xcodeproj/project.pbxproj:844-920`; `AuGenda/GoogleOAuth.swift:33-62`; `AuGenda/Info.plist:35-57`; `AuGenda/Scripts/validate-oauth.sh:1-14`
- **Description:** The project contains push, WeatherKit, and CloudKit entitlements but no target sets `CODE_SIGN_ENTITLEMENTS`; a signed simulator product emitted no custom entitlements, which supports the static finding but is not a substitute for archive/device inspection. macOS sandbox settings deny outgoing network and location, blocking cloud AI/OAuth/Ollama and WeatherKit/location. `ENABLE_USER_SELECTED_FILES = readonly` may constrain direct writes/export and requires signed macOS verification; the system-mediated SwiftUI exporter was not proven broken. The iOS plist has no local-network purpose string or local-network ATS policy despite documented plain-HTTP LAN Ollama use. Google OAuth reads a runtime environment variable that a build setting does not automatically inject, while the callback scheme remains a literal placeholder. The validation script always finds the source fallback and is not a build phase. The export-compliance comment says no custom crypto even though task export implements AES-GCM/PBKDF2, so the App Store declaration needs a qualified review rather than assumption.
- **Impact:** Documented capabilities can fail at runtime, Google sign-in is not shippably configurable, and macOS cannot provide the promised full feature set.
- **Evidence:** `ENABLE_OUTGOING_NETWORK_CONNECTIONS = NO`, `ENABLE_RESOURCE_ACCESS_LOCATION = NO`, and `ENABLE_USER_SELECTED_FILES = readonly` appear in Debug and Release. Running `validate-oauth.sh` exits 1. `Info.plist` contains `YOUR_CLIENT_ID_REVERSED`.
- **Required remediation:** Build a platform/capability matrix; apply minimal per-target entitlements; add the required local-network purpose/transport declarations for the supported Ollama topology; generate OAuth client/callback configuration into the bundle; validate the expanded built product in CI; enable only required macOS sandbox permissions and verify system-mediated/direct export behavior; remove unused push/background modes; review export classification against Apple’s current encryption-export guidance.
- **Fallback:** Disable unsupported features by platform and remove their UI/claims until signed capabilities are proven.
- **Owner / due:** Release engineering owner — 2026-07-31.
- **Verification:** Inspect archive entitlements, exercise WeatherKit/location/export/network on signed macOS and iOS builds, and complete Google PKCE login/callback/refresh/sign-out on a device.

## FIND-010 — All three bundled accessibility font files are HTML pages

- **Severity:** High
- **Domains:** accessibility, assets, release packaging
- **Status:** Reproduced
- **Locations:** `AuGenda/Fonts/AtkinsonHyperlegible-Regular.ttf`; `AuGenda/Fonts/AtkinsonHyperlegible-Bold.ttf`; `AuGenda/Fonts/OpenDyslexic-Regular.otf`; `AuGenda/ProfileModels.swift:103-145`; `AuGenda/Info.plist:59-64`
- **Description:** `file` identifies each alleged font as an HTML document containing a GitHub page. They are copied into the built app and registered in `UIAppFonts`.
- **Impact:** Atkinson/OpenDyslexic selections silently fall back or fail to render as promised, directly undermining a primary accessibility feature.
- **Evidence:** The built macOS app contains the same invalid files. `PRD.md:756-763,964-972` claims bundled, universal dyslexia font support.
- **Required remediation:** Obtain authentic licensed font binaries, verify checksums and PostScript names, document licenses, register exact names, and add an automated asset-signature test.
- **Fallback:** Remove the font choices and claims; retain system Dynamic Type until valid assets ship.
- **Owner / due:** Accessibility + release owner — 2026-07-31.
- **Verification:** `file`/font parser checks, runtime enumeration, snapshot comparison for every text style, Dynamic Type, VoiceOver, and clean-install test.

## FIND-011 — Accessibility/display preferences are largely disconnected from rendering

- **Severity:** High
- **Domains:** accessibility, UI architecture, product correctness
- **Status:** Static-confirmed; device visual verification outstanding
- **Locations:** `AuGenda/ProfileViews.swift:1062-1118`; `AuGenda/ProfileModels.swift:330-339,394-418`; `AuGenda/AuGendaApp.swift:38-53`; `AuGenda/DesignTokens.swift:84-115`; `AuGenda/ContentView.swift:116-124`; `AuGenda/FocusSessionView.swift:281-350`
- **Description:** `largeTouchTargets`, `highContrastMode`, and `sensoryContextTagsEnabled` have no rendering consumers. `lowStimulationMode` is injected but never read. Stored `minimalMode` is not consumed by the app shell. `uiScale` reaches only three legacy components, and the selected app font reaches only one agenda-row title. Core typography widely reuses fixed `Font.system(size:)` tokens. The custom Reduce Motion value is injected but no view reads it; only Home reads the system value. “Reset to preset” reapplies only preset overrides without first restoring a baseline, so unrelated/customized values remain despite the promise to reset all settings.
- **Impact:** Settings visibly save while producing little or no effect; text and fixed timer rings risk clipping at accessibility sizes; motion continues despite user/system preference.
- **Evidence:** Repository-wide consumer search and fixed-size typography references. This contradicts `PRD.md:756-763,964-972`.
- **Required remediation:** Establish environment-backed semantic tokens for typography, contrast, motion, density, font, and target size; make system accessibility settings authoritative; inventory every interactive/text surface and remove unsupported toggles.
- **Fallback:** Hide controls that do not have complete consumers and avoid 100% accessibility claims.
- **Owner / due:** Accessibility owner — 2026-07-31 for complete High-severity closure; physical-device verification is required before release.
- **Verification:** Accessibility Inspector plus a matrix for all Dynamic Type sizes, Reduce Motion, Increase Contrast, VoiceOver, keyboard, Switch Control, and each profile preference.

## FIND-012 — Profile deletion and task dependencies lack model-level integrity

- **Severity:** High
- **Domains:** data integrity, multi-profile privacy, task correctness
- **Status:** Static-confirmed
- **Locations:** `AuGenda/ContentView.swift:1074-1098`; `AuGenda/AgendaTask.swift:173-206`; `AuGenda/TaskRelationship.swift:36-90`; `AuGenda/TaskDetailView.swift:231-267,530-547`
- **Description:** Task/profile assignment is a raw UUID, and deleting a profile deletes only the `Profile`; assigned tasks/items/sessions remain orphaned. Relationships are raw UUID pairs with no uniqueness, cycle, existence, or cascade rules. Production UI shows relationships but has no creation path. `AgendaTask.isActionable` ignores relationships, so several surfaces can complete a blocked target unless they separately call `isBlocked`.
- **Impact:** Deleted-profile data can leak into unassigned/legacy views, dependencies can dangle or cycle, and blocked work can be acted on inconsistently.
- **Evidence:** `deleteProfiles` directly calls `modelContext.delete(profile)`. `isActionable` checks only complete/abandoned/deferred state. The only model relationships are ID lookups.
- **Required remediation:** Define deletion/reassignment behavior, use enforceable relationships or centralized integrity services, validate graph invariants, and make one actionability predicate authoritative across all surfaces.
- **Fallback:** Block profile deletion when owned records exist and hide relationship editing/claims.
- **Owner / due:** Domain model owner — 2026-07-31.
- **Verification:** Orphan/cascade/reassign tests, cycle/duplicate prevention, deleted-source relationships, blocked completion from every UI/notification/Watch path, and multi-profile privacy checks.

## FIND-013 — Shipping deployment targets and concurrency settings contradict the product contract

- **Severity:** High
- **Domains:** release engineering, compatibility, documentation
- **Status:** Static-confirmed
- **Locations:** `PRD.md:651-668,765-771`; `AuGenda.xcodeproj/project.pbxproj:618-840,844-895`
- **Description:** The PRD promises iOS/iPadOS 17, macOS 14, and watchOS 10, but targets require iOS/watchOS 26.5 and macOS 26.3. The PRD says Swift 6 strict concurrency; the project compiles in Swift 5 language mode with selected upcoming features.
- **Impact:** Every documented minimum-version device is excluded, and the project has not proven the language/concurrency guarantee represented by its docs.
- **Evidence:** Direct build settings and PRD comparison.
- **Required remediation:** Decide the actual support contract. Either lower targets and compile/test all availability paths or update the product contract and release messaging. Enable complete Swift 6 mode deliberately and remediate diagnostics, or document the current staged-concurrency configuration accurately.
- **Fallback:** Mark compatibility and strict-concurrency claims as unverified and restrict release to the actual target versions.
- **Owner / due:** Product + release owner — truthful contract, tested minimum-OS/concurrency matrix, and release metadata by 2026-07-31; otherwise no release.
- **Verification:** Clean build/test matrix at every declared minimum OS plus current OS; Swift 6 complete-concurrency build with warnings treated as errors.

## FIND-014 — DeepSeek scheduled the hard-coded model alias for discontinuation on the audit date

- **Severity:** Medium
- **Domains:** AI provider integration, availability, dependency management
- **Status:** Static-confirmed against the official provider schedule; live availability unverified
- **Locations:** `AuGenda/AITaskEnricher.swift:98-112`
- **Description:** AuGenda hard-codes `deepseek-chat`. DeepSeek’s official changelog says legacy aliases including this one were scheduled to be discontinued on 2026-07-24. This audit did not issue a live provider request, so actual endpoint behavior remains unverified.
- **Impact:** Users who deliberately enable DeepSeek face immediate provider-availability risk even with valid credentials. AI is off and no provider is selected by default, limiting the default blast radius.
- **Evidence:** [DeepSeek API changelog](https://api-docs.deepseek.com/updates/) and the hard-coded default.
- **Required remediation:** Replace the alias with a currently supported versioned model, move provider capabilities/models to remotely reviewable configuration with safe defaults, and add a provider smoke test.
- **Fallback:** Hide/disable DeepSeek with an explanatory status until a supported model is verified.
- **Owner / due:** AI provider owner — 2026-07-26.
- **Verification:** Live minimal request in a non-sensitive test account, response-schema validation, deprecation monitoring, and graceful unsupported-model UI.

## FIND-015 — Notification erase, privacy changes, and background actions are not durable

- **Severity:** High
- **Domains:** notifications, privacy, lifecycle
- **Status:** Static-confirmed; background-loss behavior requires device reproduction
- **Locations:** `AuGenda/ContentView.swift:839-852,1021-1069`; `AuGenda/NotificationManager.swift:130-181,524-579`
- **Description:** “Erase all data” does not remove pending or delivered notifications, so old sensitive task content can still appear. Enabling strict notification privacy does not cancel/reschedule already-created requests. The delegate dispatches work asynchronously then calls its completion handler immediately, and actions depend on in-process observers. `LOW_EF_NUDGE` exposes `START_FOCUS`, but `handleAction` has no matching case.
- **Impact:** Deleted/private content may still surface, background actions may be lost, and one advertised action is inert.
- **Required remediation:** Centralize request reconciliation; erase pending and delivered notifications; reschedule on privacy/profile changes; persist action intents directly before completing the delegate callback; implement or remove every registered action.
- **Fallback:** Remove notification action buttons and task content until end-to-end persistence is proven.
- **Owner / due:** Notifications owner — 2026-07-31.
- **Verification:** Terminated/background action tests, privacy-toggle request inspection, erase-all inspection, and every category/action combination.

## FIND-016 — Several modeled workflow states are incomplete or inconsistent

- **Severity:** Medium
- **Domains:** task lifecycle, blocks, planning, correctness
- **Status:** Static-confirmed
- **Locations:** `AuGenda/BlockModels.swift:183-228`; `AuGenda/BlockView.swift:79-94,715-729`; `AuGenda/MorningSetupView.swift:15-45,265-281`; `AuGenda/AgendaTask.swift`; `AuGenda/AgendaItem.swift`
- **Description:** `Block.isComplete` is computed from every task flag, so optional tasks still gate completion. `completeBlock` stamps completion, executes a no-op `block.isComplete ? () : ()`, then immediately resets every task to incomplete; the just-completed block therefore computes incomplete again. Active blocks are not restored after relaunch. Morning Setup reads all profiles and “Build my day” only saves energy without scheduling tasks/blocks. Recurrence and abandonment fields are modeled but do not have complete production transitions/generation. Early focus completion loses some task/session semantics.
- **Impact:** A completed block immediately reports incomplete, while UI labels and persisted state promise other workflows the application does not execute.
- **Required remediation:** Specify a state machine for tasks, recurrence, blocks, focus, and daily planning; persist block completion/history independently from resettable task instances; centralize transitions; remove dead states or implement them; scope every query by profile.
- **Fallback:** Hide incomplete controls and rename Morning Setup to “Set today’s energy.”
- **Owner / due:** Product/domain owner — 2026-08-07.
- **Verification:** Table-driven state-transition tests, relaunch fixtures, recurrence calendar tests, optional-task completion, and multi-profile planning.

## FIND-017 — Import parsing silently coerces data and exports spreadsheet formulas

- **Severity:** Medium
- **Domains:** input validation, data quality, security
- **Status:** Static-confirmed
- **Locations:** `AuGenda/TaskImportExport.swift:82-134,228-264,479-731`; `AuGenda/TaskBacklogView.swift:173-260`
- **Description:** Model/UI domains disagree: energy is presented as 1–4 in parts of the app but import clamps to 1–3; friction accepts 1–5 while the AI/difficulty engine uses 1–4. Invalid dates/booleans/numbers are silently defaulted or dropped, malformed rows are skipped, and “no tasks found” conflates invalid content with empty content. CSV cells beginning with `=`, `+`, `-`, or `@` are not neutralized. Encrypted `.txt` content is first parsed as plaintext lines before decryption. YAML escape ordering can preserve a literal `\n` in some backslash cases.
- **Impact:** Hand-edited/foreign imports can be silently altered; spreadsheet opening can evaluate user-supplied formulas; encrypted text may import ciphertext as tasks.
- **Required remediation:** Publish one field-domain schema, validate with per-record diagnostics, detect encryption before format parsing, neutralize spreadsheet formulas, and make import transactional with an explicit preview.
- **Fallback:** Limit import/export to validated JSON until other formats have adversarial fixtures.
- **Owner / due:** Data portability owner — 2026-08-07.
- **Verification:** Fuzz/property tests, boundary matrices, malicious CSV fixtures, corrupt/wrong-format files, encrypted text, and round-trip golden files.

## FIND-018 — AI responses and account controls lack complete validation and truthfulness

- **Severity:** Medium
- **Domains:** AI correctness, OAuth, Keychain, UX
- **Status:** Static-confirmed
- **Locations:** `AuGenda/TaskDetailView.swift:451-492`; `AuGenda/ContentView.swift:1506-1566`; `AuGenda/AIPersonalization.swift:137-191`; `AuGenda/AITaskEnricher.swift:193-230,350-367`; `AuGenda/AIEnrichmentSettingsView.swift:470-492,671-706,742-760`; `AuGenda/OAuthCoordinator.swift:151-158,265-275`; `AuGenda/AIEnricher_Gemini.swift:81-100`
- **Description:** Provider output is decoded but not centrally range/length/allow-list validated before assignment. The memory-depth UI supports 1–20 while prompt construction always sends at most five. Settings says “any task” can be excluded, but only `AgendaItem` creation exposes the toggle; `AgendaTask` has no editing control. “Test connection” primarily proves credential presence rather than an authenticated provider round trip. Expired OAuth tokens without a refresh token are returned; sign-out suppresses deletion errors and does not revoke. Gemini puts API keys in the URL.
- **Impact:** Bad provider output can corrupt model domains, controls overstate behavior, and credential failures are harder to detect or contain.
- **Required remediation:** Add a provider-agnostic validator and bounded schema; align UI/prompt memory depth; expose consistent exclusions; implement a non-sensitive authenticated health check; reject expired unrefreshable tokens; report sign-out failures/revocation options; use provider-supported header authentication.
- **Fallback:** Require review of every AI suggestion and disable auto-apply/auto-enrich.
- **Owner / due:** AI + auth owner — 2026-08-07.
- **Verification:** Malformed/adversarial provider fixtures, boundary checks, 1/5/20-memory tests, expired-token matrix, OAuth deletion/revocation failures, and network-log secret review.

## FIND-019 — Adaptive navigation and first-launch state do not match the intended platform flow

- **Severity:** Medium
- **Domains:** UX, iPad/macOS, onboarding, cognitive accessibility
- **Status:** Static-confirmed; sheet ordering requires runtime verification
- **Locations:** `AuGenda/ContentView.swift:69-115,151-158`; `AuGenda/AuDHDLayout.swift:205-355`; `AuGenda/OnboardingView.swift:20-65`; `AuGenda/AuGendaApp.swift:120-210,288-310`; `AuGenda/HomeDashboardView.swift:444-458`
- **Description:** Runtime always uses the iPhone `TabView`; the sidebar layout is preview-only and no `NavigationSplitView`/size-class route exists. Onboarding can be closed from any page, but root treats every close as completion and as having offered the later check-in preference. At launch, the delayed check-in path sets `showCheckInSelector` without checking `firstLaunchStep`, while sibling `.sheet` modifiers can already be presenting the first-launch flow; the exact presentation conflict requires runtime verification. Notification permission is requested immediately at launch rather than in context. The “Resume” action only clears context; its `itemID` is not used to navigate or resume.
- **Impact:** iPad/macOS do not meet the product contract, skipped onboarding suppresses a preference choice, and a cognitive-recovery affordance does not perform its label.
- **Required remediation:** Build one explicit launch coordinator and adaptive navigation shell; record each onboarding milestone separately; request permission in context; make resume route to the stored entity/action.
- **Fallback:** Remove the resume action and sidebar claims; make onboarding skip explicit and reversible.
- **Owner / due:** App shell owner — 2026-08-07.
- **Verification:** Clean-install/returning-user UI tests on iPhone, iPad, and Mac; every skip/dismiss/permission order; scene restoration; keyboard navigation; resume destination.

## FIND-020 — Touch target, VoiceOver, and contrast gaps remain on production surfaces

- **Severity:** Medium
- **Domains:** accessibility, visual design
- **Status:** Static-confirmed with computed contrast evidence; device verification outstanding
- **Locations:** `AuGenda/OnboardingView.swift:25-35`; `AuGenda/CognitiveStateSelector.swift:178-190`; `AuGenda/AuGendaApp.swift:155-177`; `AuGenda/ErrorBanner.swift:50-70`; `AuGenda/ContentView.swift:397-430`; `AuGendaWatch Watch App/NowView.swift:260-282`; `AuGenda/ProfileViews.swift:880-900`; `AuGendaWatch Watch App/WatchTokens.swift:100-112`
- **Description:** Several plain icon controls have visual bounds well below 44pt. Agenda complete/snooze controls lack task-specific labels/hints. Watch headings are hidden from accessibility. For the cited normal-size/caption uses and sRGB backgrounds, `#3B82F6` on white computes to about 3.68:1 and Watch tertiary gray on black to about 4.43:1, both below the 4.5:1 normal-text threshold; this does not imply every large/bold use of those tokens fails.
- **Impact:** Motor, low-vision, and VoiceOver users can encounter hard-to-hit, ambiguous, or unreadable controls.
- **Required remediation:** Apply semantic minimum hit frames, task-specific accessible names/hints, heading traits, and contrast-tested semantic colors.
- **Fallback:** Increase targets/colors globally and avoid icon-only actions.
- **Owner / due:** Accessibility owner — 2026-08-07.
- **Verification:** Accessibility Inspector, VoiceOver rotor/order, Switch Control, keyboard, automated contrast checks, and physical Watch/iPhone testing.

## FIND-021 — Core lists perform unbounded in-memory filtering and sorting

- **Severity:** Medium
- **Domains:** performance, memory, energy
- **Status:** Verification gap; static risk identified but user-visible impact not benchmarked
- **Locations:** `AuGenda/TaskBacklogView.swift:41-115,513`; `AuGenda/HomeDashboardView.swift:52-216`
- **Description:** Backlog and Home fetch all incomplete records, then repeatedly profile-filter and sort computed arrays before lazy rendering. `LazyVStack` defers view creation but not fetch/filter/sort work.
- **Impact:** This risks the PRD’s 60fps/1,000-task target and increases launch/render work.
- **Required remediation:** Push stable predicates/sorts into fetch descriptors, cache derived sections per mutation, paginate where appropriate, and define performance budgets.
- **Fallback:** Cap displayed rows with an explicit “show more” path.
- **Owner / due:** Performance owner — 2026-08-07.
- **Verification:** Release build, 1,000/10,000-task fixtures, Instruments Time Profiler/Allocations, scroll hitch metric, cold/warm launch measurements.

## FIND-022 — Automated coverage cannot protect the promised product

- **Severity:** Medium
- **Domains:** testing, CI, release governance
- **Status:** Test-observed and static-confirmed
- **Locations:** `AuGendaUITests/AuGendaUITests.swift:10-42`; `AuGendaWatch Watch AppUITests/AuGendaWatch_Watch_AppUITests.swift:10-42`; `AuGendaWatch Watch AppTests/AuGendaWatch_Watch_AppTests.swift:11-17`; `PRD.md:938-946`
- **Description:** macOS unit coverage is **11.73% of executable app lines (4,161/35,484)**, not the PRD’s claimed ~45% or >80% target. The main and Watch UI tests only launch with no assertions, the Watch unit test is empty, production views define no accessibility identifiers, and there is no CI configuration.
- **Impact:** High-risk migration, backup, notification, accessibility, Watch, provider, and first-launch behaviors can regress without detection.
- **Evidence:** 46 macOS unit tests passed; coverage was read from the generated `.xcresult`. UI automation did not establish a usable runner connection in this audit environment.
- **Required remediation:** Build a risk-based test pyramid and CI gates around persistence recovery, migrations, import/export, focus, notifications, AI validation, Watch queues/snapshots, widgets, first launch, and accessibility; report coverage from production targets only.
- **Fallback:** Require a documented manual release checklist and signed-device evidence for each High-risk flow.
- **Owner / due:** Test/release owner — 2026-08-07 for gates; coverage growth staged by risk.
- **Verification:** CI run from clean checkout on supported destinations, mutation/negative tests, flaky-test reruns, and coverage threshold.

## FIND-023 — Release bundles and schemes contain unfinished or internal material

- **Severity:** Medium
- **Domains:** packaging, build configuration, release quality
- **Status:** Reproduced and static-confirmed
- **Locations:** `AuGenda.xcodeproj/project.pbxproj:98-145,508-513`; `AuGendaWatchWidgets/AuGendaWatchWidgetsControl.swift:12-75`; shared `.xcscheme` files; asset catalogs
- **Description:** File-system-synchronized membership excludes only `Info.plist`, so the built app ships the corrupt fonts plus `AuGenda-Watch-ClaudeCode-Prompt.md`, `README.md`, and executable `validate-oauth.sh`. The main app icon build reports ten unassigned children. The public widget bundle includes an Xcode-template “Start Timer” control that always reports running and performs no action. The widget scheme builds unrelated main/Watch targets and launches the main app, making direct widget destination selection invalid.
- **Impact:** Internal implementation material and a misleading branded control ship to users; icon/scheme quality can block or confuse release validation.
- **Required remediation:** Use explicit resource membership/exclusions, delete template controls, validate every catalog slot, and create single-purpose shared schemes with archive/test actions.
- **Fallback:** Remove the control widget and internal resources from the shipping target.
- **Owner / due:** Release engineering owner — 2026-08-07.
- **Verification:** Inspect a clean Release archive file list, validate asset catalogs, run each scheme independently, and exercise every exposed widget/control.

## FIND-024 — Migration testing is not a frozen legacy-schema test

- **Severity:** Medium
- **Domains:** SwiftData, migrations, test quality
- **Status:** Static-confirmed
- **Locations:** `AuGenda/AppContainer.swift:9-42`; `AuGendaTests/MigrationTests.swift:8-44`
- **Description:** `AuGendaSchemaV1` and the migration test both refer to the current model classes. Future edits to those classes mutate the supposed legacy schema in place. The test creates a “v1-style” current container rather than opening a frozen store produced by the released v1 model.
- **Impact:** A breaking model change can make the migration test pass while real installed stores fail, feeding directly into `FIND-001`.
- **Required remediation:** Freeze version-specific model types or checked-in sanitized legacy stores and test every supported migration hop plus interrupted/corrupt cases.
- **Fallback:** Do not ship schema changes until a real prior-version fixture migrates successfully.
- **Owner / due:** Persistence owner — 2026-08-07.
- **Verification:** Build/store with the prior released binary/schema, migrate with current code, compare all fields/relationships, and test failure recovery.

## FIND-025 — Product and developer documentation materially misstate the current tree

- **Severity:** Medium
- **Domains:** documentation, release governance, maintainability
- **Status:** Static-confirmed
- **Locations:** `DEVELOPER_DOCUMENTATION.md:1-82,416-445,491-544,548-560`; `PRD.md:651-668,730-735,877-883,938-972`
- **Description:** Developer documentation says no Watch target exists, fonts are missing rather than corrupt and bundled, production uses a preview store, WeatherKit/CloudKit migration configuration is absent, and tests are stubs. The opposite is true in several cases. The PRD marks v1 shipped and reports ~45% coverage, working Watch sync, and complete accessibility while current evidence contradicts those claims. Its ~15 MB app-size claim remains unverified because a comparable thinned/optimized Release archive was not produced.
- **Impact:** Engineers and release reviewers can make unsafe decisions from stale instructions; audit closure cannot be trusted if requirements are rewritten as implementation status.
- **Required remediation:** Separate requirements, current implementation status, known gaps, and release evidence. Generate target/build/test facts in CI and require evidence links for “shipped,” coverage, size, privacy, and accessibility claims.
- **Fallback:** Add a prominent “not authoritative / last verified” banner and use the audit artifacts as the temporary release baseline.
- **Owner / due:** Product documentation owner — 2026-08-07.
- **Verification:** Line-by-line docs-to-build reconciliation and release checklist review by someone other than the implementer.

## FIND-026 — Working-tree hygiene mixes personal IDE state and unrelated audit material

- **Severity:** Low
- **Domains:** repository hygiene, maintainability
- **Status:** Static-confirmed
- **Locations:** `AuGenda.xcodeproj/xcuserdata/arthur.xcuserdatad/xcschemes/xcschememanagement.plist`; repository root
- **Description:** Personal `xcuserdata` is tracked. The current working tree—not the committed repository—contains numerous untracked Resonator reports unrelated to AuGenda plus prior untracked audit reports. No runtime/project reference to the Resonator files was found.
- **Impact:** Reviews, backups, and future commits are easier to contaminate; personal scheme state can create non-reproducible behavior.
- **Required remediation:** Ignore/remove tracked personal IDE state, place unrelated artifacts in their owning repository, and define an audit-artifact retention policy.
- **Fallback:** Use a pre-commit check that rejects `xcuserdata` and unrelated root artifacts.
- **Owner / due:** Repository owner — by 2026-10-24.
- **Verification:** Clean clone contains only shared schemes and AuGenda-scoped artifacts; pre-commit/CI hygiene check passes.

## FIND-027 — Mutation paths publish side effects without failure-atomic persistence

- **Severity:** High
- **Domains:** persistence, transactions, notifications, synchronization, resilience
- **Status:** Static-confirmed; injected save-failure behavior requires reproduction
- **Locations:** `AuGenda/ContentView.swift:477-507,1025-1098,1541-1548`; `AuGenda/TaskDetailView.swift:461-492`; `AuGenda/WatchConnectivityManager.swift:260-299`
- **Description:** Multiple commands mutate SwiftData objects and cancel/schedule notifications before `modelContext.save()`, then only show a banner when saving fails. Profile deletion switches the active profile before save. Watch completion/snooze handlers send a new snapshot even after catching a failed save. AI enrichment mutates task fields and records personalization after a failed save. None of these paths rolls back the model context or compensates external side effects.
- **Impact:** The visible in-memory graph, durable store, pending notifications, AI memory, and paired-device snapshot can disagree after a disk, migration, or validation error. A later autosave/retry can make the eventual outcome nondeterministic from the user’s perspective.
- **Evidence:** Completion cancels notifications at `ContentView.swift:483-488`; snooze schedules before save at `495-504`; Watch handlers call `sendSyncSnapshot()` after the catch at `260-299`; profile deletion mutates and switches before the only save at `1074-1098`.
- **Required remediation:** Route mutations through failure-atomic commands: validate first, mutate and save as one durable unit, roll back/discard on error, then execute idempotent post-commit notification/sync/AI side effects. Persist an outbox when an external effect must be retried.
- **Fallback:** On any save failure, reload the affected context from durable state, suppress downstream sync/side effects, and require the user to retry.
- **Owner / due:** Persistence + domain-services owner — 2026-07-31.
- **Verification:** Inject save failures into completion, snooze, edit, import, profile deletion, erase, AI apply, and Watch actions; prove the store, UI, notifications, ledger/memory, and outbound snapshots either all commit or all remain at the prior state.

---

## Confirmed Strengths

- AI enrichment is off by default, and cloud providers require deliberate selection.
- API keys and OAuth tokens use Keychain rather than `UserDefaults`; focused signed iOS Keychain tests passed.
- Export encryption uses a versioned AES-GCM/PBKDF2 envelope when encryption succeeds.
- OAuth authorization includes PKCE and state verification.
- Fixed cloud provider endpoints use HTTPS.
- File writes for the AI ledger and personalization request atomic, protected storage.
- The importer appends without automatically deleting existing records.
- The project has zero third-party package dependencies, reducing supply-chain surface.

These strengths do not offset the findings above; they are useful foundations for remediation.
