# Audit Scope: Code — AuGenda All-Domain

- **Audit ID:** 2026-07-24-code-augenda-all-domain
- **Type:** Code, with supporting configuration and documentation
- **Target:** The complete AuGenda repository at the current `active-dev` working tree, including uncommitted changes
- **Triggered By:** On-demand
- **Standards:** Project PRD and SPEC; EnsDev Audit System v1.1 reusable code-audit flow; applicable Swift and Apple platform guidance; Apple privacy and security requirements; Apple Human Interface Guidelines; WCAG accessibility requirements; mobile application security practices
- **Out of Scope:** Implementing remediation without later approval; production account data; unverifiable external-provider internals; medical or legal validation of product content
- **Capacity:** Full
- **Context:** Prior audit and remediation work exists, but every conclusion and line location must be independently revalidated against the current working tree
- **Auditor:** Human + Codex
- **Neutral:** Codex (facilitator mode)
- **Date:** 2026-07-24

## Included Targets

- Main AuGenda app
- AuGenda Watch app
- AuGenda Watch widgets
- Unit and UI test targets
- Xcode project, schemes, build settings, entitlements, privacy manifests, scripts, and assets
- PRD, SPEC, getting-started, developer, design-system, and compliance documentation
- Tracked and untracked repository state for hygiene, accidental coupling, sensitive-data, and release-readiness risks

## Audit Domains

- Architecture and dependency boundaries
- Functional correctness and state management
- SwiftData persistence, schema evolution, and migrations
- Import/export parsing, validation, and data integrity
- Security, privacy, authentication, OAuth, Keychain, and erase semantics
- AI provider integrations, data handling, usage accounting, and failure behavior
- Networking, transport security, and external-service boundaries
- Concurrency, performance, memory, energy, and resource use
- Accessibility, Dynamic Type, keyboard access, VoiceOver semantics, and UX consistency
- Notifications, focus sessions, scheduling, task relationships, and cognitive-state behavior
- WatchConnectivity, Watch app, widgets, and cross-target model parity
- Error handling, recovery, observability, and user-facing failure states
- Test quality, coverage, determinism, and negative-path validation
- Build configuration, signing, entitlements, privacy declarations, scripts, and release readiness
- Maintainability, duplication, dead code, documentation accuracy, PRD/SPEC compliance, and repository hygiene

## Boundaries

The audit is read-only except for generated audit artifacts and normal build/test outputs. Existing tracked and untracked changes will not be overwritten. Findings require direct evidence from source, configuration, documentation, build output, tests, or controlled reproduction. Unobservable real-device behavior is recorded as an explicit verification gap rather than assumed to pass.

Untracked Resonator material is assessed for repository hygiene and accidental project coupling. It is not treated as AuGenda runtime code unless the build, source, or project documentation references it.

## Success Criteria

- Every relevant source, test, configuration, script, asset manifest, and support document is inventoried and assigned to an audit domain.
- Every applicable scheme and target is built or its failure is captured with reproducible evidence.
- Applicable automated tests are run, with failures and coverage gaps documented.
- Findings identify exact files, symbols, and current line numbers wherever possible.
- Suspected defects are reproduced or clearly labeled as static risks requiring a specific verification step.
- Cross-domain duplicates are consolidated under one owning finding.
- Findings are severity-ranked, with a concise highest-risk summary and an exhaustive remainder.
- Remediation includes concrete actions, fallbacks, ownership, due dates calibrated for Full capacity, and verification methods.
