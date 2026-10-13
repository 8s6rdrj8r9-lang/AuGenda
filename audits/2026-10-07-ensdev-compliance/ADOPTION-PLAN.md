# Proposed staged adoption plan

Audit: **AUGENDA-ENSDEV-2026-10-07**. Assessment only. This plan proposes separable work; it does not approve implementation, exceptions, migrations, deployment or release. Arthur George Ens is the governing decision owner identified by the supplied corpus; no additional approver or task assignee is invented.

## Stage 0 — establish the product contract and preserve the restart point

Preserve this frozen audit/input before remediation. Record the six exact EnsDev versions, identifiable product baseline/approval status, applicable criteria/gate states, known limits and unresolved decisions. Use links to governing sources rather than copied competing rules. Reconcile `PRD.md`, `SPEC.md`, `DEVELOPER_DOCUMENTATION.md` and `GETTING_STARTED.md` against the actual tree; correct obsolete CloudKit/setup/font instructions and document encrypted whole-product backup. Keep older test/audit claims at their original dates.

Supply or complete the missing core-task classification, security/privacy and authority/retention records. Decide whether household profiles represent separate people or one person's interchangeable configurations, then state actual rights for represented people, coordinators, adults and children. Role names alone cannot establish authority. Document intended release audience, accessible feedback/vulnerability route, realistic review expectations and bounded-pause operations before public release. External-obligation decisions require established facts and suitable capability; this audit provides no legal conclusion.

Acceptance: source versions/approval status and requirement→criterion→method→evidence links are inspectable; unresolved decisions stay visible; the affected documentation is accurate. These records do not by themselves pass operational gates. Relevant basis: CC-02/03/13/24/25/28/29/32, F-006, EG-01/02/06.

## Stage 1 — preserve captures and constrain profile access

Repair F-001's Watch rejection path first. Keep rejected captures in a recoverable, origin-scoped state, with useful retry/copy/discard or authorized reassignment. Preserve payloads across restart and failed acknowledgements; retain the existing bounded outbox and duplicate protections. Clarify Watch thought-capture versus explicit task-entry semantics before changing its destination.

Apply one consistent access/context policy to Inbox, Focus task picker/history, cognitive suggestions, personalization memory and whole-product export. Preserve coordinator workflows only within established authority; deny unrelated reads, mutations, AI processing and export. Design revocation/departure behavior and external-copy limitations. Avoid turning diagnosis or a caregiver label into authority or requiring accounts without a product need.

Acceptance: synthetic adult/child/coordinator scenarios verify allowed and denied paths; offline capture → phone profile change → rejection → restart retains the thought for its originator; changing active profile neither exposes unrelated records nor combines another person's memory into an AI request. Existing profile-scoped notification and Home/Backlog behavior must continue to pass. Relevant basis: CC-12/16/19/31, F-001/F-002, E-101/E-102/E-111.

Migration: if only queue-file structure changes, version that file and define old pending-event adoption. Any new persistent SwiftData ownership/access model needs a new VersionedSchema, explicit migration stage, a genuine prior-v2 store fixture and failure-path tests. Do not run migration against production data until its scope and recovery are authorized.

## Stage 2 — make AI authorization, usage and provenance truthful

Give each operation an identifiable lifecycle. Enforce AI enablement/current scope at initiation and before not-yet-committed work, track cancellation, and recheck material provider/destination/privacy changes. Disclose effects that were already committed and cannot be recalled. Preserve useful existing work when AI is disabled.

Count the request/usage event separately from applying task suggestions. A discarded preview, cancelled editor or failed task save must not erase a known provider request from accounting. Prevent duplicate accounting when results are applied or retried. Define $0, finite and Unlimited distinctly, label estimates and their pricing/version limits, and handle unknown billable responses or failed accounting according to the chosen spending contract. Define privacy-preserving deletion/recovery semantics rather than retaining detailed history indefinitely to enforce a cap.

Store minimal inspectable task-action provenance: actor/provider/model identifier, affected record/fields, time, authorization reference, and evidence/inference status where relevant. Record unavailable exact model revision as a limit. Avoid storing credentials, full sensitive prompts or private reasoning chains for traceability. Verification uses fake providers and disposable storage first; credentialed external verification is a separate evidence authorization.

Acceptance: AI disabled before initiation, disable/provider switch during a delayed fake request, rejected/cancelled/discarded proposal, failed model save, usage-file failure, repeated apply and retry all produce the specified authorization/accounting result. The user can inspect and delete the applicable records without losing unrelated core functions. Relevant basis: CC-06–09, F-003/F-004/F-005, E-103–E-105.

## Stage 3 — complete core workflow and recovery/accessibility evidence

Reconcile the first-launch smoke failure with the original scheme/test plan and correct the product route if established as a defect. Coordinate capacity/profile/onboarding/morning presentation and test empty-store plus clean-preference launches, low-capacity deferral and returning users. Keep opt-in check-in defaults.

Resolve the stated 60pt larger-target criterion and explicit scale-picker gap without overriding Dynamic Type. Check selected complete core workflows with VoiceOver, alternative navigation, text scaling, contrast, Reduce Motion and low-capacity layouts on named devices. Include consequential uncommon/combined needs and user input where feasible; suitable synthetic scenarios are valid when participation is unavailable. Record limits and practical workarounds.

Define/test interruption recovery for whole-product restore across model data, history files and preferences, using disposable copies and meaningful recovery targets. Check time-zone/DST/travel/date-only semantics and pause/start-time meaning. Verify actual paired iPhone/Watch/App Group delivery, rejected/late actions, widget freshness and mixed versions. Collect signed-release entitlement/privacy/provisioning and selected performance/size evidence for the intended audience before claiming release readiness.

Acceptance: appropriate existing and new requirement checks pass in declared configurations; original failure evidence is preserved; required unknowns are resolved or remain explicit. No numerical threshold, independent reviewer, paid service or certification is added beyond the accepted product/governance criteria. Relevant basis: CC-18/21/23/25–27/29–31, F-007 as supported by final verification, EG-03–07.

## Stage 4 — select one bounded feature extension

After the protection/core-workflow work, select from `FEATURE-PROPOSALS.md`. The strongest small product extension is independent notes with a Keep as note Inbox route. Voluntary body-double availability completes an existing stated requirement. Gentle routine history should follow an explicit Block/Routine occurrence and retention decision, C-001. Shortcuts and deeper capacity patterns remain optional extensions with their own access/retention/acceptance contracts.

Approve only the chosen PRD scope, derive bounded tasks, preserve manual/no-AI/offline paths and keep unselected proposals as proposals. Do not turn this plan into blanket permission for CloudKit, medical features, continuous sharing, new accounts or a rewrite.

## Restart record

- Accepted baseline: `active-dev`, reference HEAD `d7f059ef903c3675605943412ce9582069909798`, plus the 136-file frozen working-tree snapshot identified by the freeze record.
- Current task: audit and proposals; app implementation unchanged.
- Report/evidence: this directory; detailed local result bundles/logs and immutable sources remain under `local-artifacts/ensdev-audit-2026-10-07/`.
- Next decision after the audit: choose a bounded implementation stage and resolve only the product/authority choices that affect it.
- Release status: this audit grants no Releasable/Done/deployment state and accepts no residual risk or exception.
