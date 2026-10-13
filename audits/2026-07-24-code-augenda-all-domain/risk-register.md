# AuGenda All-Domain Code Audit — Risk Register

- **Audit ID:** `2026-07-24-code-augenda-all-domain`
- **Opened:** 2026-07-24
- **Capacity:** Full
- **Review cadence:** Daily while High risks are open; weekly thereafter; mandatory before any external build

## Scoring

- **Likelihood:** Rare, Possible, Likely, Almost certain
- **Impact:** Minor, Moderate, Major, Severe
- **Exposure:** Low, Medium, High, Extreme
- **Status:** Open, Mitigating, Accepted, Deferred, Closed

No risk is accepted by this audit. Acceptance requires the user’s explicit decision, rationale, expiry/review date, and compensating control.

## Register

| Risk | Findings | Scenario and consequence | Likelihood | Impact | Exposure | Current control | Required mitigation | Trigger / indicator | Owner | Review / status |
|---|---|---|---|---|---|---|---|---|---|---|
| RISK-001 Ephemeral production writes | FIND-001, FIND-024 | Store open/migration fails; app opens empty memory store; user creates data that vanishes on termination. | Possible | Severe | Extreme | Error is caught; app remains launchable. | Explicit recovery state, preserved store, no unlabeled writable fallback, frozen migration fixtures. | Empty app after update; `ModelContainer` startup error; migration failure. | Persistence | Daily; **Open**, due 2026-07-31 |
| RISK-002 Backup cannot restore the product | FIND-006, FIND-017 | User relies on task export as backup; records/relationships/settings are omitted, duplicates appear, or requested encryption silently falls back to plaintext. | Likely | Severe | Extreme | AES-GCM/PBKDF2 succeeds on normal path; system file exporter. | Versioned full backup, stable IDs, completeness manifest, transactional restore, fail-closed encryption. | Re-import duplicates; restore mismatch; encryption returns nil; lost device. | Data portability | Daily; **Open**, due 2026-07-31 |
| RISK-003 Focus history/state corruption | FIND-002, FIND-016 | Timer expires or app relaunches without state transition; multiple active sessions persist; wrong session completes. | Likely | Major | High | End notification and manual end action. | Persisted session ID, deadline reconciliation, idempotent coordinator, transition tests. | Zero timer still active; duplicate active records; Watch disagreement. | Focus/notifications | Daily; **Open**, due 2026-07-31 |
| RISK-004 False or cross-profile Watch state | FIND-003 | Watch displays a seeded task and sends a completion the phone ignores; the phone also transmits unfiltered `AgendaItem` fields that the current Watch task handler ignores but a future merge could display. | Almost certain when Watch feature used | Major | Extreme | Placeholder/demo seed and best-effort snapshot. | Versioned profile-scoped snapshot, freshness, no demo data, acknowledged actions. | Welcome task on Watch; phone unchanged after Done; unfiltered title in payload. | Watch | Daily; **Open**, due 2026-07-31 |
| RISK-005 Lost offline Watch mutations | FIND-004 | Multiple offline mutations overwrite each other or capture remains Watch-only. | Likely | Major | High | `sendMessage` when reachable; latest application context otherwise. | Durable outbox, ordered transfer, acknowledgements, idempotent phone apply. | Action disappears after reconnect; capture absent on phone. | Watch | Daily; **Open**, due 2026-07-31 |
| RISK-006 Stale/non-functional complication | FIND-005, FIND-023 | Widget cannot read host data, never reloads, repeats an item, or exposes inert control. | Almost certain | Moderate | High | Calm placeholder. | Shared snapshot/App Group, bounded timeline, reloads, remove template control. | Placeholder never changes; “Start Timer” does nothing. | Widget/release | Daily; **Open**, due 2026-07-31 |
| RISK-007 Inadequate AI consent or accidental remote disclosure | FIND-008 | Sensitive task/profile/personalization content is sent beyond the user-understood destination or over an unsafe remote self-hosted path. | Possible | Severe | Extreme | AI off by default; first-provider disclosure; HTTPS fixed cloud endpoints. | Exact payload/destination preview, versioned consent, host classification/TLS, provider terms, accurate privacy declaration. | Provider/prompt field changes; remote Ollama host; privacy complaint; App Review question. | Privacy/AI | Daily; **Open**, due 2026-07-31 |
| RISK-008 Spend cap bypass and lost AI memory | FIND-007 | Restart makes ledger/memory unreadable, clearing perceived spend and personalization history. | Almost certain after data is written and app restarts | Major | Extreme | Decode error logging. | Symmetric versioned Codable strategy, migration, fail-closed paid usage. | Decode log; empty usage after restart; cap exceeded. | AI platform | Daily; **Open**, due 2026-07-31 |
| RISK-009 Provider/configuration outage | FIND-009, FIND-014, FIND-018 | A scheduled-for-discontinuation DeepSeek alias, OAuth placeholder, expired token, missing capability, or macOS sandbox causes an enabled feature failure. | Likely | Major | High | Availability checks and user-facing errors on some paths. | Supported model registry, built-product validation, signed capability matrix, real health checks, token lifecycle fixes. | Provider 4xx; OAuth callback failure; network denied; WeatherKit auth failure. | AI/release/auth | Daily; **Open**, DeepSeek due 2026-07-26; remainder 2026-07-31 |
| RISK-010 Accessibility settings create false assurance | FIND-010, FIND-011, FIND-020 | User selects dyslexia font, large targets, contrast, scale, or motion reduction but rendering is unchanged or inaccessible. | Almost certain for affected settings | Major | Extreme | System accessibility on isolated surfaces; one app-font consumer. | Valid assets, semantic tokens, complete consumers, hide unsupported toggles, device matrix. | Font fallback; clipping; motion continues; target/contrast failure. | Accessibility | Daily; **Open**, due 2026-07-31 and before release |
| RISK-011 Orphaned or invalid domain graph | FIND-012, FIND-016 | Profile deletion leaves data visible elsewhere; relationship IDs dangle/cycle; blocked work completes; optional tasks prevent block completion. | Possible | Major | High | Some view-specific filtering and `isBlocked` checks. | Enforced deletion policy, graph invariants, centralized actionability/transitions. | Deleted-profile task appears; dependency disagreement; block cannot complete. | Domain model | Daily; **Open**, due 2026-07-31 |
| RISK-012 Notifications outlive privacy/data state | FIND-015 | Erased or newly private content remains in pending/delivered notifications; terminated action is lost. | Possible | Major | High | Strict privacy defaults for newly scheduled requests. | Full reconciliation on erase/privacy/profile change; direct durable action handling. | Old title appears; action changes nothing; dead Start Focus action. | Notifications | Daily; **Open**, due 2026-07-31 |
| RISK-013 Unsupported product contract | FIND-013, FIND-019, FIND-025 | Release excludes documented OS versions, lacks promised iPad/Mac UI, or claims unverified strict concurrency/feature status. | Almost certain | Major | High | Current high deployment target avoids older API paths. | Decide truthful contract, build minimum-OS matrix, adaptive shell, evidence-backed docs. | User/device incompatibility; App Store metadata mismatch; Swift 6 diagnostic. | Product/release | Daily until decision; **Open**, due 2026-07-31 |
| RISK-014 Performance collapse at promised scale | FIND-021 | Full fetch/filter/sort work causes launch or scroll jank with 1,000+ records. | Possible | Moderate | Medium | Lazy view creation. | Predicate/sort pushdown, caching/paging, release Instruments budgets. | Frame hitches; memory spike; launch >2s. | Performance | Weekly; **Open**, due 2026-08-07 |
| RISK-015 Regression escapes due to weak gates | FIND-022, FIND-023, FIND-024 | A High defect returns because UI/Watch/migration paths are untested and no CI/archive gate runs. | Likely | Severe | Extreme | 46 passing macOS unit tests and manual builds. | Risk-based CI, frozen fixtures, device journeys, archive/resource/entitlement checks. | Clean checkout differs; template test passes without assertions; coverage regression. | Test/release | Daily; **Open**, due 2026-08-07 |
| RISK-016 Misleading or contaminated workspace evidence | FIND-025, FIND-026 | Stale docs, tracked personal IDE state, or unrelated working-tree artifacts lead to bad release or review decisions. | Likely | Moderate | Medium | Human review. | Generated facts, authoritative status doc, hygiene checks, artifact relocation. | Docs disagree with build; unrelated file staged; personal scheme change. | Repository/docs | Weekly; **Open**, due 2026-08-07 / 2026-10-24 |
| RISK-017 Partial mutation after persistence failure | FIND-027 | A command changes the in-memory model and notifications/sync state, its save fails, and downstream surfaces publish a state that was never durably committed. | Possible | Severe | Extreme | Error banner on some save failures. | Failure-atomic commands, rollback, post-commit side effects, durable idempotent outbox, injected-failure tests. | “Couldn’t save” banner followed by changed UI, stale reminder, or Watch snapshot. | Persistence/domain services | Daily; **Open**, due 2026-07-31 |

## Post-Remediation Review — 2026-07-24

This table supersedes the baseline **Review / status** column above for the
post-remediation working tree. No risk was accepted. “Mitigating” means source
controls materially reduced exposure but the listed exit evidence remains
mandatory.

| Risk | Current status | Current control and remaining exit |
|---|---|---|
| RISK-001 | **Mitigating** | Production startup now fails closed with explicit recovery and a regression test. Close after a frozen prior-store migration/failure fixture proves the next schema change. |
| RISK-002 | **Mitigating** | Task-list export is truthfully named, stable, idempotent, atomic, and fail-closed encrypted. Close only after a complete all-entity backup/restore with a completeness manifest. |
| RISK-003 | **Mitigating** | Focus is persisted, ID-scoped, deadline-reconciled, and duplicate-repaired with unit coverage. Close after signed foreground/background/terminated device tests. |
| RISK-004 | **Mitigating** | Watch now consumes a versioned profile-scoped snapshot and rejects stale/invalid state; demo data is gone. Close after paired-device privacy/freshness/profile tests. |
| RISK-005 | **Mitigating** | Durable Watch outbox, retry, acknowledgements, idempotency, and phone capture apply are implemented. Close after offline/force-quit/duplicate/ack-loss paired tests. |
| RISK-006 | **Mitigating** | App Group snapshot, bounded widget timeline, reloads, and template removal compile in unsigned Release. Close after signed entitlement and physical complication tests. |
| RISK-007 | **Mitigating** | Outbound local-only/TLS enforcement and version-3 exact consent with provider terms are tested. Close after proxy capture, current vendor/legal review, and App Store privacy reconciliation. |
| RISK-008 | **Closed** | Symmetric versioned ledger/memory persistence, migration, quarantine, and fail-closed spend behavior pass relaunch/corruption tests. |
| RISK-009 | **Mitigating** | Entitlement/configuration paths, PKCE/token lifecycle, and health checks are repaired; DeepSeek is disabled until smoke-tested. Close after signed capability and credentialed service tests. |
| RISK-010 | **Mitigating** | Invalid fonts are removed and display/accessibility preferences now affect rendering. Close after the physical assistive-technology, text-size, contrast, target, and motion matrix. |
| RISK-011 | **Mitigating** | Relationship/profile invariants and key block/focus transitions have tests. Close after remaining recurrence/abandonment state-machine work and lifecycle verification. |
| RISK-012 | **Mitigating** | Notification privacy reconciliation and comprehensive erase clearing are implemented. Close after terminated/background action and privacy-change device tests. |
| RISK-013 | **Mitigating** | The documented product contract now matches configured platforms/language and unsigned Release builds pass. Close after adaptive UI journeys and signed release validation. |
| RISK-014 | **Mitigating** | High-volume fetches are capped and repeated work reduced. Close after Release Instruments evidence at 1,000/10,000 records meets documented budgets. |
| RISK-015 | **Mitigating** | CI, 85 unit tests, a 7% floor, unsigned Release lanes, and package checks now exist. Close after hosted clean-checkout CI, frozen migration fixtures, signed archive gates, and meaningful UI/Watch journeys. |
| RISK-016 | **Mitigating** | Documentation is reconciled, personal Xcode state is removed/ignored, and CI rejects `xcuserdata`. Close after commit/clean-clone proof and unrelated-artifact ownership is resolved. |
| RISK-017 | **Mitigating** | Rollback support and post-save ordering cover the highest-risk import/profile/Watch/AI/erase paths. Close after the complete injected failure matrix and durable retry for all external effects. |

## Risk Acceptance Template

Use only if remediation is consciously declined:

```markdown
### Acceptance: RISK-XXX

- Decision owner:
- Date:
- Accepted scenario:
- Business/user rationale:
- Compensating controls:
- Users informed:
- Expiry / next review:
- Evidence:
```

## Closure Requirements

A risk may be closed only when:

1. the mapped finding’s remediation is implemented;
2. its regression test or manual evidence in `verification.md` passes;
3. the built/archive product, not just source, is inspected where signing/resources/privacy are involved;
4. documentation and user-facing claims are updated;
5. no fallback silently changes data durability, confidentiality, or source of truth.
