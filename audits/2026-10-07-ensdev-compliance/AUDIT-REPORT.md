# AuGenda — EnsDev compliance and feature audit

**Audit:** AUGENDA-ENSDEV-2026-10-07  
**Audited date / issued date:** 2026-10-07, America/Edmonton  
**Mode:** BASELINE; assessment and proposals only  
**Method:** PAF v0.1 Evidence-Sufficiency Patch  
**Requested depth / assurance:** L3 systematic risk-based audit; A2 reasonable assurance within the accepted source/document/local-execution boundary  
**Completion:** Completed within the frozen boundary; several operational/record propositions remain inconclusive.  
**App changes:** None. No remediation, closure, exception, residual-risk acceptance, release approval or deployment was performed.

## 1. Executive determination

AuGenda has substantial implemented local functionality and useful preservation/security controls, but the audited snapshot does **not** support a blanket EnsDev-compliant or **Done** claim. Seven consequential findings are established within the inspected source or locally tested configuration. Additional stated feature criteria are unmet or partial, and material product/authority/device evidence is unresolved.

The highest-priority issues are loss of rejected Watch captures, inconsistent profile/context boundaries, missing AI revocation coordination, undercounted AI usage, missing task-level AI action provenance, inaccurate consequential documentation, and a reproducible first-launch capacity-choice test failure. These are distinct from the numerous controls that passed their actual checks.

Verified locally: **129 main macOS unit tests passed; 6 Watch simulator tests passed; unsigned iOS Release and Watch Release test builds succeeded; 21 metadata/JSON/shell checks passed.** Measured app line coverage was **9,521/43,841 lines (21.72%)**, above the configured 7% floor. The iOS capacity-choice smoke **failed**, including a reconciliation run with original scheme/test-plan bytes. No full accessibility, physical-device transport, signed release, live-provider, performance or legal-compliance conclusion follows from those checks.

The code includes **encrypted whole-product backup/restore**, not just detached task-list sharing. This is a positive implemented capability with representative passing tests; process-interruption, per-person export authority and physical recovery remain separate questions.

Detailed deliverables:

- [Compliance/applicability register](/Users/arthur/Development/AuGenda/audits/2026-10-07-ensdev-compliance/COMPLIANCE-REGISTER.md)
- [Feature/PRD matrix](/Users/arthur/Development/AuGenda/audits/2026-10-07-ensdev-compliance/FEATURE-MATRIX.md)
- [Prioritized feature proposals](/Users/arthur/Development/AuGenda/audits/2026-10-07-ensdev-compliance/FEATURE-PROPOSALS.md)
- [Staged adoption plan](/Users/arthur/Development/AuGenda/audits/2026-10-07-ensdev-compliance/ADOPTION-PLAN.md)
- [Verification methods/results](/Users/arthur/Development/AuGenda/audits/2026-10-07-ensdev-compliance/VERIFICATION.md)
- [Evidence register](/Users/arthur/Development/AuGenda/audits/2026-10-07-ensdev-compliance/EVIDENCE-REGISTER.csv)

## 2. Scope, baseline and method

The user accepted the input review and explicitly instructed **FREEZE & START AUDIT**. The [accepted input](/Users/arthur/Development/AuGenda/audits/2026-10-07-ensdev-compliance/AUDIT-INPUT-FROZEN.md) and [freeze record](/Users/arthur/Development/AuGenda/audits/2026-10-07-ensdev-compliance/FREEZE-RECORD.json) preserve that boundary. The accepted input retains its original review-time heading; the separate freeze record records its acceptance without editing those bytes.

Audited source: 136 selected existing project files from `active-dev`, reference HEAD `d7f059ef903c3675605943412ce9582069909798`, including staged/unstaged/untracked project changes. This is **not** an audit of HEAD alone. Immutable source manifest SHA-256: `e07ade3f53874b7175552d9b174689605a313e3ffd3fb296724accf41c3e38b7`.

Included: iPhone/iPad/native Mac app, shared code, Watch app/widget, tests/fixtures, Xcode/CI/configuration/resources, product requirements and current technical guidance. Examination was systematic and risk-based: source inventory, governing-criterion/feature mapping, deeper tracing of ownership/AI/persistence/capture/Watch paths, existing local verification, counterevidence review and cross-domain synthesis. It was not a claim of exhaustive inspection or execution of every source line, scenario or device combination.

Excluded: implementation, production/private stores and real credentials, external research/live services, accounts/portals, spending, publishing, release/production operations, legal certification, prior audit grades/verdicts, historical adjudications, author expected outcomes, obsolete task instructions, PAF regression/expected-answer payloads and review/validation answers. Tests used disposable stores/fixtures and audit-created simulators. Only synthetic test credential accounts were used.

Verification used a disposable execution copy. Mac tests used the existing `-ui-testing` path and a verified disposable Foundation home; Swift source, test definitions and build settings were unchanged. The final iOS reconciliation restored original scheme/test-plan bytes and used the test's own `-ui-testing` argument on an audit-created simulator. Exact execution transformations and commands are preserved. Unsigned builds establish compilation/package facts for this selected payload, not a signed/distributed original app.

This is an AI audit in one chat. Immutable files and an explicit phase boundary were maintained, but **perfect clean-context isolation, independent human review and professional certification are not claimed**. Interpretation and self-challenge are not independent evidence. Excluded materials and desired outcomes were not used as verdict evidence.

## 3. Governing criteria and evidence

| ID | Governing source | Version / role |
| --- | --- | --- |
| GR-1 | EnsDev Constitution | 6.0 — invariants |
| GR-2 | EnsDev Doctrine | 2.1 — implementation stances |
| GR-3 | EnsDev Engineering Handbook | 5.4 — controls, evidence, five gates, completion/release states |
| GR-4 | EnsDev Governance | 1.7 — authority, adoption, conflicts and decisions |
| GR-5 | EnsDev Ontology Standard | 4.0 — meanings and product mapping guide |
| GR-6 | EnsDev Product Manifesto | 4.2 — purpose, not operational commands |
| GR-7 | AuGenda PRD | 1.1, heading date 2026-09-12 — intended product criteria and separately dated status |
| GR-8 | AuGenda SPEC | Living spec dated 2026-09-12, including explicit superseding updates |

All six EnsDev source hashes/heading versions matched the supplied manifest. Loader 2.6 is non-normative. PAF controls audit method, not product requirements. Product approval/adoption history is a separate unresolved fact; selection of these criteria for this assessment does not retrospectively prove earlier adoption.

Key evidence groups: E-001–E-010 for framework/input/criteria/snapshot and documentary context; E-011–E-019 for actual local checks and controlled launch evidence; E-101–E-114 for traceable source/configuration/test-definition groups. The CSV register gives absolute immutable paths and limits. Each finding below identifies its admissible evidence and governing basis. Source inspection is OBSERVED; predicted consequences are INFERRED; dated prose is REPORTED; numerical coverage is DERIVED from executed results.

## 4. Proposition determinations

### P-1 — Current alignment with applicable EnsDev criteria

**Determination:** Supported nonconformance in the bounded criteria identified by F-001–F-007, alongside passing control subsets and material UNKNOWNs. Blanket conformance, all five gates passing, Done and release approval are **not established**.

**Basis:** GR-1–GR-5/GR-7/GR-8; CC-01–CC-33; E-003–E-019/E-101–E-114. The findings establish concrete deviations or a failed declared local workflow. Other record/operational matters remain unresolved where their missing evidence could change a specific criterion, not merely because stronger evidence is imaginable.

**Achieved assurance:** A2 for the stated source/configuration and reproducible local-test determinations; lower/none for untested device/operational assertions. No domain inherits runtime assurance from a different domain's passing unit tests.

**Material UNKNOWNs:** approved product baseline/control records, represented-person authority, complete security/retention/applicability records, interruption recovery, complete accessibility and offline journeys, paired-device/mixed-version behavior, signed release/provisioning, selected performance and actual external obligations. See EG-01–EG-07. In particular, absence from this selected package is not proof a record or activity never existed.

### P-2 — Implemented features and PRD gaps

**Determination:** Mixed implementation and verification. The feature matrix covers every FR group and additional whole-product backup. Core task/capture/focus/block/profile/AI/Watch functions exist in source. Specific missing/partial criteria include body-double availability, explicit UI-scale choices, some named block types, per-profile focus/context, biometric credential protection, $0 spending semantics, the chosen 60pt larger-target minimum, and first-launch behavior in the tested configuration. Roadmap features are not described as shipped.

**Basis:** GR-7/GR-8; E-005/E-011–E-019/E-101–E-114. Explicit completion-driven recurrence updates control over older launch-driven wording. Equivalent property/API names are not themselves functional failures; unapproved semantic/scope changes and material conflicts remain visible.

**Achieved assurance:** A2 for inspected implementation and tested engine/model/serialization scenarios, including the failed onboarding check's named configuration. UI completeness, actual outcome benefit, accessibility, physical-device support and release status remain lower/UNKNOWN as indicated per row. No universal feature-completion percentage is issued.

**Limit:** Feature proposals and future targets cannot be used to create new nonconformances in the current baseline. The schema need not contain a database object for every ontology concept.

### P-3 — Prioritized new features and staged adoption work

**Determination:** Recommendation deliverable completed. FP-01–FP-04 complete existing protection/core-workflow controls; FP-05–FP-11 identify bounded additions or existing roadmap gaps. The staged plan preserves working local/manual/no-AI paths and prioritizes data preservation, actual authority and truthful request accounting before deeper sharing/automation.

**Basis:** GR-1/GR-2/GR-6/GR-7, the P-1/P-2 evidence and explicit user request to include proposals. Recommendations are labeled as such; inferred benefit is not measured evidence or an approved requirement.

**Assurance:** A0 for hypothetical product outcomes. No implementation, scope amendment, policy waiver or release permission follows from delivery.

## 5. Confirmed findings

All findings remain **CONFIRMED / OPEN** at the audited date. No remediation or closure was performed. Root causes below distinguish directly observed implementation mechanisms from unknown design history. Likelihood of real incidents is UNKNOWN; no population/incident evidence was supplied. Severity uses PAF's S0–S5 consequence vocabulary, not a health score.

### F-001 — Rejected Watch captures lose their recoverable text

**Expected:** Preserve interrupted work and explain/recover incomplete actions; do not silently discard offline edits/captures. GR-1 Preservation/Graceful Degradation; GR-2 Offline-First; GR-3 Reliability and Data Integrity; PRD FR-7.1. CC-16.

**Observed:** Watch capture clears its local draft after successful enqueue. The phone rejects a mutation if the active profile has changed. Watch handles `.rejected` by acknowledging/removing that event from the outbox and retaining only an error reason. No recovery copy of the captured text is retained by those paths. E-101/E-111.

**Source:** [NowView.swift:500](</Users/arthur/Development/AuGenda/local-artifacts/ensdev-audit-2026-10-07/input-v1/project/AuGendaWatch Watch App/NowView.swift:500>), [WatchSessionClient.swift:269](</Users/arthur/Development/AuGenda/local-artifacts/ensdev-audit-2026-10-07/input-v1/project/AuGendaWatch Watch App/WatchSessionClient.swift:269>), [WatchConnectivityManager.swift:273](</Users/arthur/Development/AuGenda/local-artifacts/ensdev-audit-2026-10-07/input-v1/project/AuGenda/WatchConnectivityManager.swift:273>), [WatchSharedStateStore.swift:180](</Users/arthur/Development/AuGenda/local-artifacts/ensdev-audit-2026-10-07/input-v1/project/Shared/WatchSharedStateStore.swift:180>) in the immutable snapshot.

**Reasoning:** Capture while disconnected → switch the phone profile → reconnect → rejection removes the remaining queued payload, while the phone has not stored the task. Preserving the authority check is correct; discarding the person's work is the deviation. This is a deterministic source-path conclusion, not a claim that a physical-device incident was observed.

**Counterevidence:** Valid-event queue limits do refuse new actions instead of dropping old ones, and event IDs protect successful capture replay. Six Watch tests passed. Those protections do not address the rejected-capture path.

**Risk:** S2 moderate, conditionally affects people relying on wrist capture during interruption; blast radius is the affected queued capture; lost text may be unrecoverable. High confidence in source mechanism; real incidence UNKNOWN. Operational trigger: queued originating-profile event encounters a changed phone profile. Observed cause is rejection equated with deletion/acknowledgement; original design rationale UNKNOWN.

**Action:** Preserve rejected text in an origin-scoped recovery state and provide a bounded next action. Closure requires Class B restart/rejection/recovery tests, without applying the capture to an unauthorized profile. Physical transport remains separate Class A evidence for the declared Watch support claim.

### F-002 — Profile-scoped and global information paths conflict

**Expected:** Purpose-scoped context and information/action rights for actual represented people, including children/supporters; relationships and role names cannot silently expand authority. GR-1 Privacy/User Ownership/Human First; GR-3 Shared Records, Children and Supported Decision-Making, Information Review. CC-12.

**Observed:** Inbox lists all unprocessed captures without ownership filtering. Focus task selection/history and cognitive aggregation include records from all profiles. Personalization uses one global about-me/history store; its memory entry has no profile identity and its outgoing snapshot is reused with the active profile's context. Whole-product backup serializes the complete graph without a corresponding represented-person access check. In contrast, Home/Backlog/Watch paths apply profile filters. E-102/E-110.

**Source:** [InboxView.swift:18](</Users/arthur/Development/AuGenda/local-artifacts/ensdev-audit-2026-10-07/input-v1/project/AuGenda/InboxView.swift:18>), [FocusSessionHistoryView.swift:15](</Users/arthur/Development/AuGenda/local-artifacts/ensdev-audit-2026-10-07/input-v1/project/AuGenda/FocusSessionHistoryView.swift:15>), [FocusSessionView.swift:466](</Users/arthur/Development/AuGenda/local-artifacts/ensdev-audit-2026-10-07/input-v1/project/AuGenda/FocusSessionView.swift:466>), [CognitiveProfile.swift:15](</Users/arthur/Development/AuGenda/local-artifacts/ensdev-audit-2026-10-07/input-v1/project/AuGenda/CognitiveProfile.swift:15>), [AIPersonalization.swift:81](</Users/arthur/Development/AuGenda/local-artifacts/ensdev-audit-2026-10-07/input-v1/project/AuGenda/AIPersonalization.swift:81>)/[AIPersonalization.swift:272](</Users/arthur/Development/AuGenda/local-artifacts/ensdev-audit-2026-10-07/input-v1/project/AuGenda/AIPersonalization.swift:272>), [TaskBacklogView.swift:178](</Users/arthur/Development/AuGenda/local-artifacts/ensdev-audit-2026-10-07/input-v1/project/AuGenda/TaskBacklogView.swift:178>).

**Reasoning:** Changing a displayed profile does not consistently constrain the information being viewed, interpreted or sent as AI history. The failure concerns actual context boundaries and the product's separate-person/child use, not a demand to add accounts or a claim that profile switching is secure authentication. Specific off-device disclosure incidents and any external consent arrangements were not observed; those remain UNKNOWN.

**Counterevidence:** Coordinator overview, assignment restrictions, notification owner privacy and Home/Backlog filtering exist. They show useful partial controls but do not extend to the listed paths. Global preference customization alone is not proof all represented people authorized global disclosure.

**Risk:** S3 serious credible consequence when sensitive captures/health-related context from one person are exposed or included in another person's provider request; exposure is conditional on multi-person use and the affected paths. External copies can be hard to recall. High confidence in inspected boundary mismatch; actual authority arrangements/incident likelihood UNKNOWN. Observed cause is mixed global/per-profile state; organizational/design root cause UNKNOWN.

**Action:** Establish and enforce a consistent actual authority model across display, interpretation, AI memory and export. Class B verification covers synthetic separate-person allowed/denied paths, role/profile changes and disclosure/export. Authority interpretation requires Class C clarification where unresolved; neither a role label nor a disclaimer supplies missing consent.

### F-003 — AI enablement and revocation are not enforced across the request lifecycle

**Expected:** Explicit revocable delegation; pause/revocation handling for queued/in-flight/retry work; prevent not-yet-committed actions under revoked authority where cancellation is possible. GR-1 Human First/AI Is Opt-In; GR-3 AI Controls and Continuing Authorization After Change. CC-07.

**Observed:** Outbound policy checks versioned consent and local-only destination rules, but not the master `ai.enabled` flag. Application calls use unstructured Tasks without a retained cancellation handle. Settings changes update selection/UI state; the protected adapter checks policy before awaiting the provider and validates output afterward without a coordinated cancellation/current-authorization check. E-103.

**Source:** [AITaskEnricher.swift:726](</Users/arthur/Development/AuGenda/local-artifacts/ensdev-audit-2026-10-07/input-v1/project/AuGenda/AITaskEnricher.swift:726>)/[AITaskEnricher.swift:946](</Users/arthur/Development/AuGenda/local-artifacts/ensdev-audit-2026-10-07/input-v1/project/AuGenda/AITaskEnricher.swift:946>), [AIEnrichmentSettingsView.swift:131](</Users/arthur/Development/AuGenda/local-artifacts/ensdev-audit-2026-10-07/input-v1/project/AuGenda/AIEnrichmentSettingsView.swift:131>), [TaskDetailView.swift:466](</Users/arthur/Development/AuGenda/local-artifacts/ensdev-audit-2026-10-07/input-v1/project/AuGenda/TaskDetailView.swift:466>), [InboxView.swift:473](</Users/arthur/Development/AuGenda/local-artifacts/ensdev-audit-2026-10-07/input-v1/project/AuGenda/InboxView.swift:473>).

**Reasoning:** Hiding a button does not close the operation boundary: a queued initiation can reach a provider after the master flag changes, and the system has no specified coordinated handling for cancellable work already running. This finding does not demand recall of an already committed transmission or deletion of useful existing results when AI is disabled.

**Counterevidence:** Off-by-default UI, per-task exclusion, versioned provider receipts, destination-change consent and local-only enforcement are real protections. Those supported criteria remain PASS. The finding is the separate missing lifecycle limit, not absence of all consent controls.

**Risk:** S2 moderate conditional privacy/agency/cost effects for users disabling AI or changing destinations during operations; scope is affected requests. High confidence in boundary/control absence; real occurrence and exact provider cancellation behavior UNKNOWN. Design-history cause UNKNOWN.

**Action:** Define operation identity, current scope, cancellable/committed states and recovery; enforce them at the applicable boundaries. Class B fake-delayed-provider tests verify disable before initiation, in-flight cancellation, destination changes and no out-of-scope retries. Extra live-provider evidence is not required to establish the source finding.

### F-004 — Discarded AI proposals are omitted from usage accounting

**Expected:** Track provider requests/tokens/estimated cost and enforce the selected spending contract. GR-3 Resource and Cost Controls; PRD FR-6.2. CC-09.

**Observed:** TaskDetail receives a provider result and presents a preview; dismissing clears `pendingEnrichment`. Usage recording is a post-commit task-mutation effect, so dismissing a proposal or failing the task save does not record the known request. The cap reads this ledger. E-104.

**Source:** [TaskDetailView.swift:400](</Users/arthur/Development/AuGenda/local-artifacts/ensdev-audit-2026-10-07/input-v1/project/AuGenda/TaskDetailView.swift:400>)/[TaskDetailView.swift:492](</Users/arthur/Development/AuGenda/local-artifacts/ensdev-audit-2026-10-07/input-v1/project/AuGenda/TaskDetailView.swift:492>), [AIEnrichmentMutation.swift:38](</Users/arthur/Development/AuGenda/local-artifacts/ensdev-audit-2026-10-07/input-v1/project/AuGenda/AIEnrichmentMutation.swift:38>)/[AIEnrichmentMutation.swift:294](</Users/arthur/Development/AuGenda/local-artifacts/ensdev-audit-2026-10-07/input-v1/project/AuGenda/AIEnrichmentMutation.swift:294>), [AIUsageLedger.swift:167](</Users/arthur/Development/AuGenda/local-artifacts/ensdev-audit-2026-10-07/input-v1/project/AuGenda/AIUsageLedger.swift:167>).

**Reasoning:** Repeated generate → dismiss cycles produce requests while the recorded monthly totals remain unchanged. Whether an actual provider billed a particular account is not established; undercounting known returned request/token metadata is itself supported. Pricing is estimated and was not externally verified. UI zero means Unlimited and is a separate PRD feature-contract difference.

**Counterevidence:** Successful task-commit effects, corrupt-ledger fail-closed handling, persistence recovery and cap-at-recorded-threshold checks have passing tests. FailureAtomicity tests intentionally defer usage until task save; that protects task mutation but does not make request accounting complete.

**Risk:** S2 moderate potential underestimated usage/unexpected spending, especially for budget-constrained users; exposure is conditional on paid provider use and discarded/failed proposals. High confidence in code path; actual invoice/overrun/likelihood UNKNOWN. Observed cause is coupling usage truth to applied task persistence; design intent UNKNOWN.

**Action:** Account for the request event independently and idempotently; preserve privacy/deletion and honest estimate limits. Class B tests cover discard, cancel, failed save, repeated apply/retry, ledger failure and $0/finite/Unlimited semantics.

### F-005 — Applied AI task changes lack record-level action provenance

**Expected:** Trace what acted, what changed, applicable authorization and relevant rule/model version; preserve appropriate source/uncertainty and inspectable concise explanation without sensitive duplication. GR-3 AI Controls/Explanations; GR-5 evidence semantics. CC-08.

**Observed:** Application/cache paths save task/inbox fields and timestamps, then publish global usage/memory effects. The task/inbox models and usage entries do not link an applied change to its provider/model/authorization or preserve an inspectable field-change record. Validation/preview confidence is not retained as task-level source history. E-105.

**Source:** [AIEnrichmentMutation.swift:157](</Users/arthur/Development/AuGenda/local-artifacts/ensdev-audit-2026-10-07/input-v1/project/AuGenda/AIEnrichmentMutation.swift:157>), [AgendaTask.swift:14](</Users/arthur/Development/AuGenda/local-artifacts/ensdev-audit-2026-10-07/input-v1/project/AuGenda/AgendaTask.swift:14>), [InboxItem.swift:41](</Users/arthur/Development/AuGenda/local-artifacts/ensdev-audit-2026-10-07/input-v1/project/AuGenda/InboxItem.swift:41>), [AIUsageLedger.swift:24](</Users/arthur/Development/AuGenda/local-artifacts/ensdev-audit-2026-10-07/input-v1/project/AuGenda/AIUsageLedger.swift:24>) entry model.

**Reasoning:** A user later inspecting altered task metadata cannot reconstruct the required action trace from a generic monthly usage entry or current field values. An authorized Apply is not itself a durable provenance record. This does not require storing full prompts/private reasoning or treating all accepted user edits as uncertain forever.

**Counterevidence:** Preview, schema validation, provider/model usage metadata and safe rollback exist. They support their own control purposes; they do not link the action to the changed record.

**Risk:** S2 moderate correction/accountability loss for AI-enriched tasks and shared contexts; potential propagation into backups/interpretation. High confidence in inspected persistence representation; practical incidence/organizational root cause UNKNOWN.

**Action:** Define minimal purpose-bound action/change records with inspection/correction/deletion and explicit model-revision limits. Class B verifies traceability after restart/export, user corrections and deletion/retention behavior. A new stored model requires the repository's next schema/migration/fixture process.

### F-006 — Consequential setup and feature guidance is inaccurate

**Expected:** Update inaccurate affected behavior/interfaces/schema/user guidance and distinguish current claims from history. GR-3 Documentation and Continuity, Documented, Evidence for Product Claims. CC-28.

**Observed:** GETTING_STARTED names Xcode 16+, instructs adding font files, and tells the user to enable CloudKit by switching nonexistent `AppContainer.dev`/`.production` variants. Current production uses a local startup factory and explicit CloudKit `.none`. Developer documentation §3.10 says recurrence has no editor/generator/rules despite its own newer completion-driven section and current implemented/tested engine. Current recovery documentation does not explain the new whole-product backup contract adequately. E-106/E-110.

**Source:** [GETTING_STARTED.md:3](</Users/arthur/Development/AuGenda/local-artifacts/ensdev-audit-2026-10-07/input-v1/project/GETTING_STARTED.md:3>)/[GETTING_STARTED.md:19](</Users/arthur/Development/AuGenda/local-artifacts/ensdev-audit-2026-10-07/input-v1/project/GETTING_STARTED.md:19>), [DEVELOPER_DOCUMENTATION.md:549](</Users/arthur/Development/AuGenda/local-artifacts/ensdev-audit-2026-10-07/input-v1/project/DEVELOPER_DOCUMENTATION.md:549>), [AppContainer.swift:118](</Users/arthur/Development/AuGenda/local-artifacts/ensdev-audit-2026-10-07/input-v1/project/AuGenda/AppContainer.swift:118>), [TaskLifecycle.swift:10](</Users/arthur/Development/AuGenda/local-artifacts/ensdev-audit-2026-10-07/input-v1/project/AuGenda/TaskLifecycle.swift:10>).

**Counterevidence:** AGENTS, newer SPEC amendments and multiple PRD caution/status sections accurately separate goals and evidence. Dated older result counts are not treated as false merely because this audit collected newer results.

**Risk:** S2 moderate setup/recovery confusion and unsafe assumptions about sync/support; high confidence in direct contradictions. User impact/likelihood UNKNOWN. Observed cause is incompatible current guidance; authorship/change-process root cause UNKNOWN.

**Action:** Reconcile the current product baseline/docs, link authority and describe actual export/backup/privacy/time/version boundaries. Class B review verifies referenced APIs/instructions against the approved tree and replays relevant setup/recovery guidance. Do not rewrite historical audit conclusions.

### F-007 — Declared first-launch capacity-choice check fails locally

**Expected:** An empty `-ui-testing` store starts at the capacity choice and exposes the survival option. PRD US-1, SPEC/AGENTS first-launch posture, configured onboarding smoke; GR-3 Tested/Human Factors. E-114.

**Observed:** The selected iOS smoke did not find `capacity.title`. A bounded warm retry failed; a final run restored original scheme/test-plan bytes, removed the disposable-home override, retained the original UI assertion and also failed: **0 passed, 1 failed, exit 65** on iPhone 17 Pro Simulator/iOS 26.5 with Xcode 27.0. E-015/E-018. A separate controlled launch screenshot showed Home without the capacity sheet, E-019; it is corroboration, not an attachment from the failed assertion.

**Source:** [AuGendaUITests.swift:16](</Users/arthur/Development/AuGenda/local-artifacts/ensdev-audit-2026-10-07/input-v1/project/AuGendaUITests/AuGendaUITests.swift:16>), [AuGendaApp.swift:360](</Users/arthur/Development/AuGenda/local-artifacts/ensdev-audit-2026-10-07/input-v1/project/AuGenda/AuGendaApp.swift:360>), [HomeDashboardView.swift:452](</Users/arthur/Development/AuGenda/local-artifacts/ensdev-audit-2026-10-07/input-v1/project/AuGenda/HomeDashboardView.swift:452>).

**Reasoning:** Failure remains with the original source test configuration, so it is not explained solely by the audit's test-home setup. It establishes the specified outcome failure **in this configuration**. Root-level onboarding and child-level morning setup can both request sheets; that is a plausible contributing path, not a proven causal diagnosis. No physical-device/all-SDK failure or source crash is claimed.

**Counterevidence/conflict handling:** Mac/Watch tests and compilation pass. The first attempt stalled in diagnostic finalization and was interrupted; its runner exit is not used as an app-crash verdict. Successful original-source-plan execution would have changed this finding, but the reconciliation instead reproduced the failed assertion.

**Risk:** S2 moderate friction/exclusion at first use; scope is the checked clean-store launch. High confidence in observed outcome; mechanism and likelihood on other configurations UNKNOWN. Current display state does not establish an authorized replacement for the capacity flow.

**Action:** Diagnose the first-launch coordinator and validate clean store/preferences, original configuration and supported accommodation paths. Class B must repeat the defined first-launch scenario without weakening the assertion, plus a proportionate returning/low-capacity regression halo. No app repair was performed here.

## 6. Concern and material evidence gaps

| ID / state | Question and governing basis | Evidence / what could change | Required next verification |
| --- | --- | --- | --- |
| C-001 — CANDIDATE concern | Routine Artifact versus separately identifiable execution; retention of actual run information. GR-5 Settled Mappings; GR-3 documentation/ownership. | Blocks reuse one identity/current timestamps, reset checklist and remove bundles; E-107. Product-specific mapping/retention decision could establish a defensible representation or a confirmed semantic gap. No mandatory separate ORM table or indefinite history is invented. | **Class C:** reconcile product mapping/retention with settled Routine semantics. **Class A** scenario checks if the accepted mapping requires retained occurrences. FP-06 is a proposal until that decision. |
| EG-01 — material gap | Approved product baseline/adoption/gates, core-task classification and owner-absence/public-release operation. | Current files do not establish complete organizational record history. Could change CC-02/03/25 and actual approved feature/applicability scope. | **A** supply/inspect governing product records; **C** resolve conflicting authority when present. Absence does not establish never existed. |
| EG-02 — material gap | Proportionate security/privacy/threat/role/retention/incident/feedback and safety records. | Partial classification/disclosure/code exists; complete protection/recovery/affected-person records not supplied. Could change CC-13/14/15/25/29 readiness conclusions. | **A** inspect established records and relevant denied/recovery/retention scenarios. No universal external audit or certification. |
| EG-03 — material gap | Offline/AI-off full workflows, process-interrupted multi-store restore, late/mixed-version operations and consequential time semantics. | Source and exception/fixture tests pass subsets; no whole process-death/complete workflow evidence. Could change CC-04/18/19/30 operational determinations. | **A** named disposable interruption/time/offline scenarios against established criteria. Do not infer all persistence is unsafe from this unknown. |
| EG-04 — material gap | Selected accessibility, inclusion and complete low-capacity/device workflows. | System/tokens/preferences/source tests are not VoiceOver/alternative-navigation/contrast/user-outcome evidence. Could change CC-21–23/30 and PRD accommodation status. | **A** selected complete workflow/device checks and proportionate uncommon/combined-need scenarios. Voluntary people where feasible; no required survey/diagnosis collection. |
| EG-05 — material gap | Signed provisioning/paired Watch/App Group/widget/transport/consumer integration. | Unsigned compilation and simulator tests do not establish portal/signature/physical delivery. Could change PRD FR-4.4/7.1/7.2 and CC-19/31 support claims. | **A** applicable signed/paired configurations and specific transport/freshness/permission scenarios. No external calls were authorized in this execution. |
| EG-06 — material gap | External obligation/content-rights/environmental applicability and capable safety review where warranted. | Actual jurisdictions/contracts/activities/claims and applicability decisions are not supplied. Could change CC-24/29/32 criteria and release scope. | **A** facts/source applicability record; suitable interpretation when capability is insufficient. This audit does not invent a law, carbon target or certification. |
| EG-07 — material gap | Product-selected hardware performance/resource/recovery measurements. | PRD numerical targets exist; relevant hardware results do not. Could change CC-26 and those explicit PRD nonfunctional outcomes. | **A** named scenario/hardware measurements. Generic build size is not download/install evidence. |

These gaps are not manufactured from immaterial missing facts. Each is tied to the determination it could change. Supported source/test PASS and FAIL statements remain intact.

## 7. Domain coverage, achieved assurance and cross-domain synthesis

L3 risk-based source/criterion tracing was performed across the applicable domains; absence of operational evidence limits achieved assurance and the strength of runtime conclusions. There was no independent specialist/L4/L5 adversarial assurance pass. The review includes counterevidence and a proportionate halo outside the highest-risk paths: deterministic engines, migration/import validation, display/environment controls, notifications and build/package configuration.

| Universal domain | Coverage/result | Achieved assurance within scope |
| --- | --- | --- |
| U01 Intent & Purpose | Documented ND friction/purpose; actual broader benefit unknown. CC-01/03/23. | A2 documentary; actual impact UNKNOWN |
| U02 Requirements & Specification | Full FR-group mapping, explicit supersession, approval/status conflicts. F-006/EG-01. | A2 inspected criteria; formal adoption UNKNOWN |
| U03 Architecture & Design | Native/local schema, managers, common Watch contracts; global/profile and lifecycle gaps. F-001–05/C-001. | A2 source; operational integration limited |
| U04 Correctness & Fitness | 129 Mac/6 Watch tests, engines/import/migration, failed first-launch check. F-007. | A2 tested scenarios; universal fitness UNKNOWN |
| U05 Quality & Robustness | Rollback/failure fixtures, rejected capture path, interruption gaps. F-001/EG-03. | A2 specific paths; process/device resilience UNKNOWN |
| U06 Human Factors & Usability | Capacity/density/manual control source, failed onboarding, privacy/error/timeout considerations. | A1 wider usability; A2 specific test/source outcomes |
| U07 Accessibility & Inclusion | System controls and chosen target mismatch; no complete assistive-tech/combined-needs evidence. CC-21–23. | A1 wider outcomes; specific source sizing limit identified |
| U08 Security & Abuse Resistance | Keychain/import/output/consent protections; profile and revocation gaps. F-002/03. | A2 checked controls; whole security effectiveness UNKNOWN |
| U09 Maintainability & Operability | Compiler/static checks and restart material; inaccurate docs and incomplete operations/debt evidence. F-006/EG-01/02. | A2 check/doc facts; operation assurance limited |
| U10 Performance & Capacity | Coverage/build/package observations; hardware limits not measured. EG-07. | A1 indicative; specified performance UNKNOWN |
| U11 Testing & Verification | Executed methods/results, source tests versus real outcomes, failed test reconciliation. | A2 execution facts; full matrix UNKNOWN |
| U12 Lifecycle & Sustainability | Version/migration/backup, planned support/release/retirement limits. EG-02/05/06. | A2 fixture/serialization facts; lifecycle readiness UNKNOWN |
| U13 Governance & Decisions | Six-source authority/hashes, approved versus proposed work, missing adoption/authority records. | A2 supplied corpus facts; product governance operation UNKNOWN |

Conditional domains activated at proportionate depth: C01 safety consequences/applicability, C02 privacy, C03 external-obligation applicability (legal conclusions excluded), C04 accessibility engineering, C05 human factors, C06 information quality, C07 AI/automation, C08 ethics/affected people, C09 resilience, C10 interoperability, C11 dependencies, C12 paid-AI financial controls, C13 environmental applicability, C15 records, C16 observability and C17 provenance. C14 research/scientific validity had no established current contribution/research pathway; proposed insight benefit still requires honest product-claim evidence. No research collection was added.

Ecosystem examination concerned this product's phone/Watch/widget shared contracts, inherited controls, correlated outage/recovery and change propagation. Other EnsDev products and public ecosystem assurance were excluded.

Cross-domain conclusions:

- **Preservation versus authority:** rejecting a changed-profile mutation protects access; discarding its payload defeats continuity. Repair must satisfy both.
- **Privacy versus personalization:** individually useful context becomes a more sensitive or wrong-person mixture when profile boundaries are absent. A global AI toggle cannot stand in for every represented person's authority.
- **Failure atomicity versus cost truth:** deferring usage until task save helps mutation rollback but loses the independent fact of a provider request. Preserve task safety and account for requests separately.
- **Accessibility versus adaptive simplicity:** useful reduced surfaces/pins do not prove complete accommodated workflows. First-launch absence and fixed targets can defeat the intended low-friction entry.
- **Recovery versus deletion/consent:** full backups improve preservation but need actual export authority, retention/restoration meaning and renewed provider consent. Tests show consent receipts/credentials are excluded; this does not establish every interrupted recovery or external-copy deletion claim.
- **Documentation versus capability:** outdated CloudKit/recurrence guidance obscures real local backup and completion-driven recurrence. Correct the documentary contract before expanding scope.

## 8. Required verification and optional corroboration

Classes trace to existing requirements or material conflicts; recommendations are not converted into new mandatory criteria.

| Class | Purpose | Governing basis / what it must resolve |
| --- | --- | --- |
| A | Evaluate unresolved operational/record requirements | EG-01–EG-07 identify the criterion and determination affected. Collect only relevant authorized evidence for the chosen support/release claims. |
| B | Close confirmed findings after authorized remediation | F-001–F-007 define the required changed-path scenarios. Preserve original findings/date, verify effectiveness and regression halo, and retain evidence. No closure is claimed now. |
| C | Resolve material authority/semantic/evidence conflicts | Product baseline/rights/mapping where unresolved; C-001; contrary specification wording. iOS test-home versus original-plan conflict was examined and failure reproduced, E-018. |
| D | Optional extra confidence | Wider random fuzzing beyond established criteria, extra hardware beyond declared support, independent analysis where not required, or added robustness experiments. These do not gate supported verdicts or create new UNKNOWNs solely because they would be stronger. |

For an existing physical-device support/release criterion, necessary device evidence is Class A. For the already established source-path finding itself, demanding duplicate independent physical proof merely to strengthen confidence would be optional unless an applicable criterion/profile requires it.

## 9. Material conflicts and historical/current-state treatment

1. **PAF distribution/provenance:** declared intake files are absent; START-HERE/provenance claim excluded fixtures/expected answers while the ZIP contains them; one referenced source ZIP is absent and framework README says frozen candidate while convenience material describes validated release. Normative bytes present were read/pinned; excluded expected material was not used. Proceeded under the explicitly selected TXT workflow, available template and user freeze. No perfect source-release validation is claimed.
2. **Product statements:** explicit 2026-09-08 completion-driven recurrence update resolves the older launch-generation criterion for this assessment. The contradictory developer paragraph remains an inaccurate current claim. Broad back-deployment, five-versus-four density and zero-budget semantics require honest baseline alignment; source is evidence of implementation, not authority to silently amend a requirement.
3. **Formal approval/authority:** current PRD/guidance are selected assessment criteria; actual approved product scope, per-person sharing rights and organizational record completeness are not established merely by file presence. Leave those material gaps visible and seek Class C interpretation only where it affects a dependent determination.
4. **Onboarding evidence:** first isolated-home failure had stalled diagnostic finalization; warm bounded retry and original-plan run preserve the failed assertion. E-018 resolves the question of whether the audit-home configuration alone explains it. Causal mechanism and other configurations remain unknown; passing independent checks remain valid.

No prior audit verdict or grade was used to steer this result. Dated earlier build/test claims in supplied developer prose are REPORTED historical context, not newly verified current evidence. This snapshot and any future remediation/closure have separate dates/states; later changes must not erase the original findings.

## 10. Limitations and release/completion states

Source sampling, existing fixtures and local execution support the specifically bounded determinations above. They do not establish real-world incident frequency, every mutation path, fairness across populations, provider service behavior, exact current prices/terms, safe medical advice, applicable law, portal provisioning, distributed archives or operating effectiveness. No user data or live account evidence was collected. A lack of supplied evidence was never converted into proof of non-occurrence.

No blanket security, accessibility, offline, zero-data-loss, >80% coverage, Swift 6 strict-concurrency, global feature-parity or production-readiness claim is made. This is Swift 5 language mode with staged concurrency settings. Native Mac is separate from Catalyst. CloudKit is not implemented support. Custom fonts remain subject to the existing conditional asset/license/device gates.

Under the existing five gates: Secure has a supported access-control FAIL; Tested has the observed onboarding FAIL and unverified areas; Documented FAILS; the selected larger-target criterion is not implemented as specified and wider Accessible evidence remains unresolved; Maintainable has passing compiler/static subsets with broader unresolved evidence. **Done is not established. Releasable requires the authorized named-version/audience decision and appropriate gate evidence; this report grants neither that decision nor deployment authority.** No actual public-release breach is inferred from the absence of release evidence.

Work and evidence are preserved. The next useful action is a separately authorized bounded stage from the adoption plan, starting with capture preservation/profile authority and the first-launch failure, while preserving existing local/manual paths.

AUDITOR RESPONSE FROZEN
