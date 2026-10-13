# AuGenda All-Domain Code Audit — Remediation Plan

- **Audit ID:** `2026-07-24-code-augenda-all-domain`
- **Capacity:** Full
- **Planning assumption:** One primary engineer, with product/privacy review available for release decisions
- **Rule:** No external release until the High-severity exit gate is satisfied

> **Post-remediation state:** The implementation pass is complete. See
> [`closure.md`](closure.md) for the authoritative 27-finding disposition,
> final 85-test/Release-build evidence, and unresolved external gates.

## Outcome

Use five workstreams, in this order:

1. **Data safety and recoverability**
2. **Truthful cross-device behavior**
3. **Privacy, AI, and signed capabilities**
4. **Core workflow and accessibility integrity**
5. **Verification and release governance**

These five workstreams are the active queue. Do not fix isolated UI symptoms before the persistence, identity, and synchronization contracts are decided; those contracts determine most downstream work.

## Immediate Containment — 2026-07-24 to 2026-07-26

| Action | Findings | Owner | Completion evidence |
|---|---|---|---|
| Mark the current tree “not release-ready”; do not distribute an AI/Watch-enabled external build. | All High | Product/release | Release checklist has a blocking audit link. |
| Disable or hide DeepSeek until a supported versioned model passes a live smoke test. | FIND-014 | AI | Unsupported alias is unreachable; provider smoke test passes. |
| Rename current “backup” behavior to “Export active task list” and make password encryption fail closed. | FIND-006 | Data portability | Forced encryption failure cannot produce a file; UI states that formats are partial/lossy. |
| Remove the seeded Watch task, the inert control widget, and live-action affordances that cannot be delivered reliably. | FIND-003, FIND-004, FIND-023 | Watch/widget | A stale/unconfigured Watch shows a truthful non-actionable state. |
| Remove unsupported accessibility choices or label them unavailable until their assets/consumers exist. | FIND-010, FIND-011 | Accessibility | No setting can save successfully while doing nothing. |
| Cancel pending/delivered notifications during erase and remove the dead Start Focus action until durable handling exists. | FIND-015 | Notifications | Erase leaves no notification content; every exposed action has a handler. |
| Add a temporary release script that fails on OAuth placeholders, HTML masquerading as fonts, unassigned app-icon slots, internal prompt/script resources, and missing applied entitlements. | FIND-009, FIND-010, FIND-023 | Release | Script fails on the current defects and runs in a clean preflight. |

## Workstream 1 — Data Safety and Recoverability

### 1.1 Production store recovery

- **Findings:** FIND-001, FIND-024
- **Due:** 2026-07-31
- **Dependencies:** Decide supported schema/store versions before changing models.
- **Actions:**

  1. Replace production in-memory fallback with a typed `PersistenceStartupState`.
  2. Preserve the failed store and related WAL/SHM files.
  3. Offer retry, read-only diagnostics/export, restore, and explicit destructive reset.
  4. Record a privacy-safe error code and store URL class, not user content.
  5. Freeze v1 schema types or add a sanitized store created by the prior release.
  6. Test every supported migration hop, interrupted migration, disk-full, corrupt store, and reset.

- **Exit criteria:** No production code path opens a writable ephemeral store without an unmistakable test/preview flag. A real legacy fixture migrates with complete field/relationship parity.
- **Fallback:** Fail launch recoverably and preserve data.

### 1.2 Versioned full backup and restore

- **Findings:** FIND-006, FIND-017
- **Due:** 2026-07-31
- **Dependencies:** Stable entity IDs and profile/dependency deletion rules.
- **Actions:**

  1. Split “share task list” from “full backup.”
  2. Define a versioned canonical backup envelope covering every user-controlled entity, relationship, profile preference, and required setting.
  3. Preserve stable IDs and timestamps.
  4. Include schema version, created-at, checksum/MAC, encryption/KDF parameters, and completeness metadata.
  5. Detect encrypted envelopes before format parsing.
  6. Parse into a staging graph, report every rejected/coerced field, validate referential integrity, then apply transactionally.
  7. Neutralize spreadsheet formula prefixes in CSV exports.
  8. Make wrong-password, randomness, KDF, encode, and write failures explicit and fail closed.

- **Exit criteria:** A populated golden fixture exports, erases, restores, and matches all included entities/relationships; repeated import is idempotent; a requested encrypted export can never become plaintext.
- **Fallback:** Support validated JSON only and keep other formats explicitly lossy/share-only.

### 1.3 Failure-atomic mutations and side effects

- **Findings:** FIND-027
- **Due:** 2026-07-31
- **Dependencies:** Central mutation services and injectable save/notification/sync boundaries.
- **Actions:**

  1. Define command boundaries for completion, snooze, edit, import, profile deletion, erase, AI apply, notification actions, and Watch actions.
  2. Validate first, mutate the model context, save, and roll back/discard on failure.
  3. Execute notification, Watch/widget, AI-memory, and other external effects only after durable commit.
  4. Persist an idempotent outbox when a post-commit effect cannot complete synchronously.
  5. Do not publish snapshots or dismiss a surface after a failed save.
  6. Inject save and side-effect failures in every command-path test.

- **Exit criteria:** Each tested command produces either a complete durable state plus matching external effects or the exact prior state; no partial in-memory/UI/sync state remains after failure.
- **Fallback:** Reload the affected context from durable state and suppress every downstream effect until the user retries.

## Workstream 2 — Truthful Cross-Device Behavior

### 2.1 Phone/Watch synchronization contract

- **Findings:** FIND-003, FIND-004
- **Due:** 2026-07-31
- **Dependencies:** Stable IDs, profile scope, and authoritative task-action service.
- **Actions:**

  1. Write a versioned protocol document: snapshot fields, profile scope, source of truth, freshness, acknowledgements, conflict rules, deletions, and schema compatibility.
  2. Cache a redacted, profile-scoped phone snapshot on Watch; never seed production demo models.
  3. Put discrete mutations in a persisted Watch outbox with UUID, sequence, timestamp, retry count, and status.
  4. Transfer durable events, acknowledge from the phone, and apply idempotently through the same service used by app and notification actions.
  5. Forward capture as an acknowledged inbox event.
  6. Reconcile phone notification schedules after Watch mutations.
  7. Use one Codable wire contract for field names and date encoding; reject unsupported schema versions.

- **Exit criteria:** No action disappears during offline, activation, force-quit, duplicate-delivery, or out-of-order scenarios. A Watch never displays another profile’s title.
- **Fallback:** Read-only, freshness-labeled, redacted Watch surface.

### 2.2 Widget/complication lifecycle

- **Findings:** FIND-005, FIND-023
- **Due:** 2026-07-31
- **Dependencies:** Snapshot contract and App Group decision.
- **Actions:**

  1. Use a minimal shared snapshot file or shared database appropriate for an extension; do not let the widget invent a separate source of truth.
  2. Apply App Group entitlements to exactly the host/extension targets that need them.
  3. Build timeline entries for bounded upcoming changes and choose `.after`/`.atEnd` appropriately.
  4. Reload timelines after meaningful phone/Watch state changes.
  5. Delete the template control or implement real state and intent handling.
  6. Correct the shared widget scheme so it targets/launches the intended host.

- **Exit criteria:** Physical-Watch complication changes on task rollover/completion, reports stale state honestly, and remains within timeline/energy budgets.
- **Fallback:** Remove complication/control from the shipping bundle.

## Workstream 3 — Privacy, AI, and Signed Capabilities

### 3.1 Data-flow and consent contract

- **Findings:** FIND-008, FIND-018
- **Due:** 2026-07-31
- **Dependencies:** Provider inventory and current vendor terms.
- **Actions:**

  1. Inventory exact outbound fields for every provider and feature.
  2. Classify destinations as on-device, LAN self-hosted, remote user-hosted, or third-party cloud.
  3. Show an exact payload-category preview, destination, transport, retention/training link, and opt-out immediately before first transmission.
  4. Persist consent with provider and disclosure version; re-prompt on material change.
  5. Correct “never to Apple or anyone else” and similar absolute copy.
  6. Validate hostnames/IPs with real RFC1918/loopback/link-local rules; require TLS for remote endpoints.
  7. Enforce local-only policy at the provider registry/outbound service boundary, even if defaults are stale, migrated, or externally altered.
  8. Reconcile the privacy manifest and App Store privacy answers with actual code paths.

- **Exit criteria:** A data-flow test can account for every outbound field, and release privacy material matches that inventory.
- **Fallback:** Apple on-device provider only.

### 3.2 AI persistence and validation

- **Findings:** FIND-007, FIND-014, FIND-018
- **Due:** 2026-07-31
- **Actions:**

  1. Version the ledger/personalization JSON and align date encode/decode.
  2. Quarantine unreadable files; make non-zero spend caps fail closed.
  3. Validate all provider output: scalar ranges, string/array lengths, context allow-list, title emptiness, time bounds, and unknown fields.
  4. Align memory-depth UI with the transmitted window.
  5. Require review before applying AI output until negative-path tests are complete.
  6. Disable scheduled-for-discontinuation model aliases until a supported model passes a live smoke test; maintain provider capability/deprecation metadata.
  7. Add real, non-sensitive provider health checks.

- **Exit criteria:** Restart cannot clear/bypass budget state; malformed output never enters the model; each enabled provider passes a live smoke test.
- **Fallback:** Disable auto-enrich and paid providers.

### 3.3 Authentication, secrets, and platform capabilities

- **Findings:** FIND-009, FIND-018
- **Due:** 2026-07-31
- **Actions:**

  1. Apply minimal signed entitlements per target and configuration.
  2. Generate the Google client ID and callback scheme into the built `Info.plist`; validate the expanded archive rather than grepping source.
  3. Enable required macOS sandbox entitlements for outbound network and location; verify system-mediated and direct user-selected export behavior before changing file permissions; add truthful local-network permission/transport configuration for Ollama; disable unavailable UI otherwise.
  4. Reject expired OAuth tokens that cannot refresh; surface deletion/sign-out failures and provide revocation guidance.
  5. Prefer supported API-key headers over URLs.
  6. Remove unused remote-notification and push entitlements unless a full push flow exists, and complete an export-encryption classification review using the built archive.

- **Exit criteria:** Signed archive entitlement diff matches the capability matrix; Google authorize/callback/refresh/sign-out passes; macOS provider/weather/export flows pass.
- **Fallback:** Compile unsupported features out per platform.

## Workstream 4 — Core Workflow and Accessibility Integrity

### 4.1 Domain state and invariants

- **Findings:** FIND-002, FIND-012, FIND-015, FIND-016
- **Due:** 2026-07-31 for focus/profile/notification privacy integrity; 2026-08-07 for remaining state coverage
- **Actions:**

  1. Introduce centralized task, relationship, focus, block, and notification action services.
  2. Make focus state deadline-based, persisted by session ID, reconciled on launch, and idempotent.
  3. Define profile deletion as reassign, cascade, archive, or block-with-explanation; enforce it transactionally.
  4. Enforce task-relationship existence, uniqueness, direction, and cycle rules; make actionability central.
  5. Exclude optional tasks from required block completion.
  6. Persist block completion/history independently from task instances that are reset for a later run.
  7. Restore active blocks or close them deterministically at launch.
  8. Implement recurrence/abandonment transitions or remove those states from v1.
  9. Make notification actions persist directly before completion; reconcile schedules on erase/privacy/profile changes.

- **Exit criteria:** Table-driven state tests pass for every transition and entry point (app, notification, Watch, widget); no dangling IDs remain after deletion.
- **Fallback:** Remove incomplete state/actions from UI and documentation.

### 4.2 Accessibility system

- **Findings:** FIND-010, FIND-011, FIND-020
- **Due:** 2026-07-31; physical-device evidence is required before release
- **Actions:**

  1. Replace fake font files with licensed binaries, checksums, and verified PostScript names.
  2. Replace fixed typography tokens with semantic Dynamic Type styles and scaled metrics.
  3. Make system Reduce Motion/Increase Contrast authoritative; combine app preferences only as stricter overrides.
  4. Route font, scale, touch target, contrast, stimulation, and sensory settings through semantic environment tokens consumed everywhere.
  5. Enforce 44pt minimums (and the advertised 60pt mode), accessible labels/hints/traits, and tested color pairs.
  6. Remove any preference that does not have end-to-end consumers.

- **Exit criteria:** Accessibility matrix passes on iPhone, iPad, Mac, and Watch; every visible preference has a tested effect.
- **Fallback:** System font, system Dynamic Type, system motion settings, and fewer truthful controls.

### 4.3 Adaptive and cognitive UX

- **Findings:** FIND-019
- **Due:** 2026-08-07
- **Actions:**

  1. Use one adaptive shell with tabs on compact width and sidebar/split detail on regular width/macOS.
  2. Use one launch state machine with separate persisted milestones for capacity, profile, onboarding, check-in preference, and permissions.
  3. Request notifications at the point a user enables a reminder.
  4. Make resume navigate to and restore the captured item/activity, or label it as dismiss-only.

- **Exit criteria:** Clean-install and returning-user flows are deterministic across all dismissal and permission choices.
- **Fallback:** Compact tab UI everywhere with documentation corrected; remove false resume behavior.

## Workstream 5 — Verification and Release Governance

### 5.1 Performance

- **Findings:** FIND-021
- **Due:** 2026-08-07
- **Actions:** Move predicates/sorts to fetches, reduce repeated projections, create 1,000/10,000-record fixtures, and set launch/scroll/memory budgets.
- **Exit criteria:** Release build meets a documented frame-time and launch budget on the minimum supported hardware.

### 5.2 Tests and CI

- **Findings:** FIND-022, FIND-024
- **Due:** 2026-08-07 for blocking gates; ongoing coverage growth
- **Actions:**

  1. Add CI for clean Debug and Release builds, all shared schemes, unit tests, lint/config validation, asset checks, and archive inspection.
  2. Add deterministic launch arguments and accessibility identifiers.
  3. Replace template UI/Watch tests with assertion-bearing critical journeys.
  4. Prioritize branch/negative-path coverage over a vanity aggregate percentage.
  5. Report production-target coverage and fail when critical modules regress.

- **Exit criteria:** A clean checkout produces the same results; all High finding verification tests are blocking.
- **Fallback:** Signed manual release evidence attached to every build.

### 5.3 Packaging, documentation, and repository hygiene

- **Findings:** FIND-013, FIND-023, FIND-025, FIND-026
- **Due:** 2026-07-31 for FIND-013 compatibility/contract closure; 2026-08-07 for packaging/docs; hygiene by 2026-10-24
- **Actions:**

  1. Decide and test real minimum OS and Swift language/concurrency support.
  2. Explicitly include only shipping resources; inspect Release archive contents and size.
  3. Fix app icon assignments and remove template/internal assets.
  4. Make schemes single-purpose and shared.
  5. Rewrite docs into requirements, current status, known gaps, and generated evidence.
  6. Remove tracked `xcuserdata`, relocate unrelated Resonator material, and add repository hygiene checks.

- **Exit criteria:** Release archive, docs, schemes, and clean clone agree on targets, features, tests, entitlements, size, and compatibility.

## High-Severity Release Exit Gate

All of the following must be true:

- No silent in-memory production fallback.
- Full backup is truthful and encrypted export fails closed.
- Focus state expires/restores deterministically.
- Watch and widget either show verified synchronized data or are removed/clearly disabled.
- AI payload disclosures, consent versions, and privacy declarations match actual traffic.
- Every enabled provider uses a supported model and passes a smoke test.
- Required capabilities appear in signed archive entitlements; Google OAuth and macOS sandbox flows work.
- Valid accessibility fonts ship, and no inert accessibility preference remains visible.
- Profile deletion and task dependency invariants are enforced.
- Mutations and their notification/sync/AI side effects are failure-atomic.
- Actual supported OS versions and concurrency mode are documented and tested.
- Regression tests for each High finding pass from a clean checkout.

## Sequenced Icebox After the High Gate

“Icebox” means sequenced, not accepted or forgotten. With Full capacity, any slice required to close a High finding is pulled into the active queue immediately; the remaining Medium/Low scope is promoted only after the High release gate is green.

- **Immediate Medium containment, not iceboxed:** `FIND-014` remains due 2026-07-26 because the provider notice is time-sensitive.
- **Product-depth queue:** remaining non-blocking portions of `FIND-016`–`FIND-021`, due 2026-08-07.
- **Verification/release-quality queue:** remaining non-blocking portions of `FIND-022`–`FIND-025`, due 2026-08-07. Tests, archive checks, and documentation needed to prove a High fix are active dependencies, not deferred.
- **Hygiene queue:** `FIND-026`, due 2026-10-24.

## Finding-to-Workstream Map

| Finding | Primary workstream |
|---|---|
| FIND-001, FIND-024 | 1.1 Production store recovery |
| FIND-006, FIND-017 | 1.2 Backup/import |
| FIND-027 | 1.3 Atomic mutations |
| FIND-003, FIND-004 | 2.1 Watch synchronization |
| FIND-005 | 2.2 Widget/complication |
| FIND-008 | 3.1 AI privacy/consent |
| FIND-007, FIND-014 | 3.2 AI persistence/providers |
| FIND-009, FIND-018 | 3.3 Auth/capabilities |
| FIND-002, FIND-012, FIND-015, FIND-016 | 4.1 Domain state |
| FIND-010, FIND-011, FIND-020 | 4.2 Accessibility |
| FIND-019 | 4.3 Adaptive/cognitive UX |
| FIND-021 | 5.1 Performance |
| FIND-022 | 5.2 Tests/CI |
| FIND-013, FIND-023, FIND-025, FIND-026 | 5.3 Release governance |
