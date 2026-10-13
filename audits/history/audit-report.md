# AuGenda Broad-Spectrum Governance Audit Report

**Date:** 2026-07-20  
**Auditor:** Kimi (Agent `main`)  
**Scope:** Full AuGenda SwiftUI codebase (~35+ source files) against EnsDev Governance Prompt v1.0  
**Framework:** 5-Tier Governance (Constitution → Doctrine → Engineering → Ontology → User Context)  
**Instruction:** Read-only audit. No edits made. Report delivered as-is.

---

## Executive Summary

AuGenda is a sophisticated, neurodivergent-first productivity app built in Swift 6 with SwiftData, zero external dependencies, and deep ND-specific affordances. The codebase demonstrates strong architectural intent — a pure-logic Difficulty Engine, a density-aware UI layer, privacy-first AI defaults, and multi-profile household coordination. However, **there are material gaps between the codebase's current state and the EnsDev Governance framework**, particularly in the **Security threshold** (real OAuth credentials in source), **Testing threshold** (minimal test coverage), **Schema migration** (none — will crash on any property change), and **macOS target parity** (compile failures). The project is **not shippable to App Store** in its current state without addressing these blockers.

---

## Tier 1: Constitution — Foundational Values & Constraints

### 1.1 Founding Values ("The Core Mandate")

> *The user must never be ignored or contradicted. The user's word is final. The agent must always execute the user's instructions precisely.*

**Assessment: PASS — with note.**  
The codebase is entirely self-contained. No AI agent is embedded in the runtime. The architecture respects user autonomy: AI enrichment is **opt-in** (off by default), per-task `excludeFromAI` exists, and the density engine is purely deterministic. No "agentic" override of user decisions is present. The user is the sole authority within the app.

**Finding T1.1:** The `CognitiveStateSelector` presents the user with a direct capacity question ("I'm overwhelmed" → Survival mode) and does not override this choice. This is Constitution-aligned.

### 1.2 Semantic Discipline ("The Language of the System")

> *All terms are mapped to specific capabilities. Ambiguity is a failure mode. Discrepancies must be resolved through the Doctrine.*

**Assessment: MIXED.**  
The codebase has strong internal vocabulary: `frictionLevel`, `energyRequired`, `sensoryLoad`, `hyperfocusRisk`, `bodyDouble`, `densityMode`, `ndPriorityScore`. These are precise, ND-native terms. However, the **Ontology mapping** (Tier 4) has **unresolved forks**: `Relationship`, `FocusSession`, `CognitiveProfile`, and `Context` are defined in the prompt but have **no corresponding model or clear mapping** in the SwiftData schema. This is a semantic gap that Doctrine should resolve but has not yet.

### 1.3 Non-Interference ("The Prime Directive")

> *The agent must not override the user's goals. The agent must not seek efficiency or simplicity at the expense of user intent. The agent must not force the user into a single mode of operation.*

**Assessment: STRONG PASS.**  
The app is designed for **multi-modal operation**: text input, voice brain dump (`BrainDumpView` with `SFSpeechRecognizer`), visual density selectors, gesture-based completion, and Watch interaction. The `TaskBacklogView` offers four sort modes (`Manual`, `ND Priority`, `Due Date`, `Easiest First`). No mode is forced. The `DensityAdvisor` provides recommendations, not mandates — users can pin their own density.

**Finding T1.3:** The `ProfilePreferences.densityPinned` field allows the user to override the auto-calculated density. This is a direct implementation of Non-Interference.

### 1.4 Reliability ("The Bedrock")

> *The agent must be consistent and predictable. The agent must never lose user data or state. The agent must always handle errors gracefully.*

**Assessment: CRITICAL FAILURE — Data Loss Risk.**  
The `AppContainer` uses `AppContainer.dev` (local-only) in the production code path. The `production` container uses a placeholder CloudKit ID (`iCloud.com.augenda.AuGenda`) that is **not active** in the Apple Developer portal. Every launch with `.dev` that encounters a migration issue will start fresh with sample data. More critically: **there is no `VersionedSchema` or `MigrationPlan`**. If any `@Model` property is added, renamed, or removed, existing user installs will **crash on launch** with a SwiftData schema mismatch. This is a data-loss and reliability failure.

**Finding T1.4a:** No `MigrationPlan` defined. SwiftData schema version is implicit (= 1). Any model change = crash for existing users.

**Finding T1.4b:** `try? modelContext.save()` is used pervasively throughout the codebase (e.g., `HouseholdItemRow.complete()`, `TaskBacklogView.handleImportResult`, `AddTaskView.save()`). Errors are silently swallowed. If the save fails, the user has no feedback. This is not "graceful error handling" — it is silent failure.

**Finding T1.4c:** `importFeedback` exists for import/export, but core CRUD operations (task completion, profile creation) have no error surfacing.

### 1.5 Transparency ("The Window")

> *The agent must explain its reasoning when asked. The agent must make its internal state visible to the user. The agent must not hide important information.*

**Assessment: PARTIAL.**  
The UI is transparent about its logic: `ndPriorityScore` is visible, density is visible, energy levels are visible. The `DensityAdvisor` explains why it recommends a density. However, **AI enrichment is opaque** from the user's perspective. The `AITaskEnricher` protocol returns `TaskEnrichment` but there is no UI that shows the user *why* a particular AI suggestion was made. The `AIEnrichmentSettingsView` shows provider selection and API key entry, but not the reasoning behind any specific enrichment result. Also, **error transparency is weak**: the `try?` swallowing pattern means the user never sees why an operation failed.

---

## Tier 2: Doctrine — The Engine of Value

### 2.1 Contrast Requirements (The "No Generic" Rule)

> *Every feature, every message, every component must contrast with the generic alternative. The user must be able to tell why this is different.*

**Assessment: STRONG PASS.**  
This is AuGenda's greatest strength. The app is saturated with ND-specific affordances that contrast sharply with generic todo apps:

- **Friction dots** instead of priority flags (visual representation of initiation cost, not urgency).
- **Energy pip** system (1–5 scale) tied to task filtering.
- **Hyperfocus risk flag** — no generic app has this.
- **Body double flag** — unique to AuGenda.
- **Density mode** (Survival/Low/Functional/High) with progressive disclosure — generic apps don't have a "survival mode."
- **Brain dump** with voice input — designed for racing-thoughts moments.
- **Waiting on** field explicitly modeled (not just tags).
- **Coordinator/household** multi-profile view with per-profile energy and progress.
- **Watch sync** with low-friction task completion from wrist.
- **Strict privacy** default for notifications (redacts task titles from lock screen).

**Finding T2.1:** The `AgendaTaskCard` component uses `interestColor` and `FrictionDots` as primary UI elements. This is a clear, intentional contrast with generic task apps that would show only due dates and checkboxes.

### 2.2 Decomposition (The "Atomic Unit" Rule)

> *Every feature is composed of atomic units. The atomic unit is the smallest possible component that can deliver a specific value.*

**Assessment: PASS.**  
The codebase decomposes well:
- `DifficultyEngine.rank()` is a pure function — one atomic operation (six inputs → one 0–10 rank).
- `DensityAdvisor` is a separate, pure-logic struct from `DensityMode` (the enum).
- `ProfileDayCard` is a reusable component for household overview.
- `AgendaTaskCard` is a reusable component for the backlog.
- `EnergyPip`, `FrictionDots`, `InterestPips` are all separate, reusable micro-components.
- `KeychainStore` is a single-purpose wrapper for credential storage.
- `OAuthCoordinator` is generic PKCE logic, separate from `GoogleOAuth` (which is provider-specific).

**Finding T2.2:** The `TaskBacklogView` has three filter modes (All, For Now, Waiting) and four sort modes — each is a distinct atomic unit of user value. This is Doctrine-aligned decomposition.

### 2.3 System Safety (The "No Unsafe" Rule)

> *The system must never expose the user to unnecessary risk. The system must handle edge cases and failure modes. The system must be robust against unexpected input.*

**Assessment: CRITICAL FAILURE — Security & Edge Case Risks.**

**Finding T2.3a — CRITICAL: Real OAuth credential in source.**  
`GoogleOAuth.swift` contains a real, non-placeholder `clientID`: `416358058147-...`. This is a real Google OAuth client ID. It is also referenced in `Info.plist` (`CFBundleURLSchemes`). This credential is **hardcoded in the source code**, which means it is in version control and will be in the compiled binary. If this is a restricted client ID, it could be extracted. This is a **severe security failure** under the Security threshold.

**Finding T2.3b — API key storage is reasonable but not perfect.**  
`KeychainStore` uses `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` and stores per-provider API keys. This is good. However, there is **no biometric protection** (e.g., `kSecAccessControlBiometryCurrentSet`) for the AI provider keys. Given the user is hEDS/fatigue-prone and may hand their phone to others, this is a risk.

**Finding T2.3c — Brain dump voice input lacks interruption handling.**  
`BrainDumpView` uses `SFSpeechRecognizer` and `AVAudioEngine`. The `#if os(iOS)` block sets up the audio engine but there is no explicit error handling for `SFSpeechRecognizer` unavailability (e.g., the user denies microphone permission, or `SFSpeechRecognizer` returns `nil` for unsupported locales). The `voiceUnavailable` state exists but is only set via a button tap check, not on `onAppear`.

**Finding T2.3d — Import/Export accepts arbitrary file formats.**  
`TaskBacklogView` uses `.fileImporter` with allowed types `[.json, .commaSeparatedText, .plainText, .text]`. However, `TaskImporter.detectFormat` also claims to support `.yaml`, `.yml`, `.csv`, `.md`, `.markdown`, `.txt` — but the file importer does not allow `.yaml` or `.yml`. This is a mismatch that will confuse users. Also, the importer accepts duplicates and has no validation of imported data (e.g., a malicious JSON with extreme string lengths could cause memory issues or crashes).

**Finding T2.3e — `TaskExporter`/`TaskImporter` format handling is not robust.**  
`TaskTextFileDocument` is a simple `FileDocument` wrapper. There's no schema validation for imported JSON — no version field, no required field checking. A malformed import could create SwiftData models with invalid state (e.g., `frictionLevel` outside 1–5, `energyRequired` outside 1–3).

**Finding T2.3f — No rate limiting on AI enrichers.**  
The `AITaskEnricher` protocol and its 9 provider adapters have no rate-limiting or backoff mechanism. If the user accidentally triggers enrichment on a large batch of tasks (or if a future UI allows bulk enrichment), they could hit rate limits or incur unexpected costs. The `AIUsageLedger` tracks usage but does not enforce caps.

### 2.4 Feedback Loops (The "Continuous Improvement" Rule)

> *The system must learn from user interaction. The system must adapt to user preferences over time. The system must provide feedback on its own performance.*

**Assessment: MIXED.**  
The app has good feedback mechanisms:
- `ActivityLog.recordCompletion()` tracks completions (used for streaks).
- `CognitiveCheckInTracker` tracks recurring energy check-ins.
- `AIUsageLedger` tracks per-provider API usage (cost/usage awareness).
- `BlockManager` tracks block streaks.

However, there is **no explicit learning loop** for the density or difficulty recommendations. The `DifficultyEngine` is deterministic and static. The `DensityAdvisor` recommends based on `energyLevel` and `cognitiveLoad` but does not adjust its algorithm based on historical accuracy (e.g., "the user often overrides my Low recommendation to Survival — I should learn that"). The prompt asks the system to "learn from user interaction" — the app records data but does not act on it adaptively.

**Finding T2.4:** `ProfilePreferences` stores `densityPinned` but does not store a history of density overrides that could be used to train/adjust the advisor. The data is there (in `ActivityLog`, `CognitiveCheckInTracker`) but not wired into a feedback loop.

### 2.5 Progress Reporting (The "Always Show Your Work" Rule)

> *The system must report progress on long-running tasks. The system must not leave the user in a state of uncertainty.*

**Assessment: WEAK.**  
The app has **no progress reporting for async operations**. AI enrichment (which hits external APIs) has no loading state UI in the views audited. The `OAuthCoordinator` has no progress indicator during the `ASWebAuthenticationSession` flow. The `BlockManager` weather fetch is asynchronous but the UI does not show a loading state when weather is being fetched. The `WatchConnectivityManager` sync is silent — the user doesn't know if the Watch received the update.

**Finding T2.5:** `TaskBacklogView` shows an empty state when filtered tasks are empty, but there is no "loading" or "syncing" state for any network or async operation. This violates the Doctrine for users with ADHD who may be anxious about whether an action was received.

### 2.6 The Doctrine of Reliability (The "Never Fail" Rule)

> *The system must never fail in a way that leaves the user stranded. The system must always have a fallback. The system must degrade gracefully.*

**Assessment: FAIL — Graceful Degradation Missing.**

**Finding T2.6a:** CloudKit is a hard dependency in the schema but is not active. The fallback to `AppContainer.dev` is silent — the user does not know they are not getting sync. If they install on a second device, their data will not appear. There is no UI that says "iCloud sync is not configured."

**Finding T2.6b:** WeatherKit is referenced in `BlockManager` but if the user denies location permission, the app does not clearly explain what functionality is lost. The `WeatherKit` entitlement is not in the `.entitlements` file (the prompt mentions it but I did not see it in the file I read — this is a potential gap).

**Finding T2.6c:** If the AI provider's API key is invalid or expired, the enrichment will fail silently (the `AITaskEnricher` protocol does not enforce a specific error-handling UI pattern). The user will not know why enrichment is not working.

**Finding T2.6d:** The `aps-environment` is set to `development` in the entitlements file. This means push notifications will not work for TestFlight or App Store builds. The comment says Xcode auto-flips it, but manual signing must be verified — this is a known configuration risk that has caused many App Store rejections.

---

## Tier 3: Engineering Handbook — The Implementation Standard

### 3.1 Memory & Context Awareness (The "Never Forget" Rule)

> *The system must maintain context across operations. The system must remember user state. The system must not ask the user to repeat information.*

**Assessment: PASS.**  
The app maintains strong context:
- `ActiveProfileManager` persists the active profile ID in `UserDefaults`.
- `ProfilePreferences` stores per-profile settings (energy tracking, notification style, etc.).
- `UserPreferences` (SwiftData model) stores global preferences.
- `CognitiveCheckInTracker` stores check-in history.
- `ActivityLog` stores completion history.
- `WatchConnectivityManager` maintains session state.
- `InterruptionContext` records current activity context for session resumption.

However, `UserDefaults` is device-local and **not synced via CloudKit**. If the user switches devices, their active profile and preferences are reset. This is a context loss across devices.

**Finding T3.1:** `ActiveProfileManager` uses `UserDefaults` for `activeProfileID`. This should be stored in `NSUbiquitousKeyValueStore` or synced via CloudKit to maintain cross-device context.

### 3.2 Thought Steps & Reasoning (The "Show Your Work" Rule)

> *The system must reason through problems. The system must show its work. The system must not jump to conclusions.*

**Assessment: N/A for App Code.**  
This rule applies to the AI agent's behavior. Since AuGenda is an end-user app with no embedded reasoning agent, this rule does not directly apply to the codebase. However, the **app could show its reasoning** to the user: e.g., why a task was ranked with a specific `ndPriorityScore`. Currently, the score is visible but the reasoning ("high friction + low interest = low priority") is not explained.

### 3.3 Security & Data Handling (The "Never Leak" Rule)

> *The system must handle sensitive data carefully. The system must not leak user information. The system must respect privacy boundaries.*

**Assessment: MIXED — Strong intent, weak execution in places.**

**Strengths:**
- `strictPrivacy` defaults to `true` for notifications. Task titles are redacted from the lock screen. This is excellent.
- AI is off by default. `excludeFromAI` per-task. `KeychainStore` uses `AfterFirstUnlockThisDeviceOnly` (no iCloud sync of keys).
- Speech recognition is on-device (`SFSpeechRecognizer` on iOS uses local recognition unless explicitly configured otherwise; the app does not force server-based).
- Location is only used for WeatherKit and never stored or transmitted beyond Apple's service (per Info.plist description).
- No third-party analytics SDKs. No external dependencies at all.

**Weaknesses:**
- **Finding T3.3a — CRITICAL:** Hardcoded OAuth `clientID` in `GoogleOAuth.swift` (see T2.3a). This is a data leak risk.
- **Finding T3.3b:** The `Info.plist` contains the full reversed OAuth client ID in `CFBundleURLSchemes`. This is necessary for the callback, but combined with the hardcoded client ID, it makes credential rotation impossible without an app update.
- **Finding T3.3c:** `TaskExporter` exports task data in plain text (Markdown, JSON, CSV, YAML). There is no encryption option. If the user exports to iCloud Drive or shares the file, all their task data is in plaintext. This is a privacy boundary violation for sensitive tasks (e.g., medical appointments, therapy notes).
- **Finding T3.3d:** `AIUsageLedger` exists but does not log which tasks were enriched, only aggregate usage. While this is good for privacy, it means there is no audit trail if the user wants to review what data was sent to AI providers.
- **Finding T3.3e:** `NSMicrophoneUsageDescription` and `NSSpeechRecognitionUsageDescription` are present and clear (good). `NSLocationWhenInUseUsageDescription` is present and clear (good). However, there is **no `NSUserTrackingUsageDescription`** — if Apple ever requires this for App Store, it's missing. Not critical now but worth noting.

### 3.4 Code Language & Expression (The "Clear Code" Rule)

> *The system must express its reasoning clearly. The system must not use ambiguous or misleading language. The system must be precise.*

**Assessment: STRONG PASS.**  
The code is exceptionally well-commented and precise. Examples:

- `DifficultyEngine.swift`: "Six-axis projection to 0–10 rank. Stateless, deterministic, no SwiftData dependency. Unit-tested."
- `TaskBacklogView.swift`: "Brain dump — fast batch add for the racing-thoughts moment. Sits LEFT of the detailed-add button so it reads first; this is the lower-friction path and should be the easier reach."
- `NotificationManager.swift`: `strictPrivacy` defaults to true — "redacts task titles from lock screen."
- `DesignTokens.swift`: Extensive semantic naming (`appTextPrimary`, `appBackgroundSecondary`, `touchMinimum`).

The code expresses **intent** clearly, not just mechanics. This is a hallmark of well-governed engineering.

---

## Tier 4: Ontology — The Mapping of Reality

### 4.1 Ontology Concepts Defined in Governance

The prompt defines 11 core concepts: Observation, Artifact, Action, Outcome, Learning, Entity, State, Relationship, FocusSession, CognitiveProfile, Context.

### 4.2 Mapping to AuGenda Codebase

| Ontology Concept | AuGenda Model/Type | Mapping Quality | Notes |
|---|---|---|---|
| **Observation** | `InboxItem` | ✅ Strong | Inbox captures raw observations (brain dump, voice, quick add). Unprocessed. |
| **Artifact** | `Note` (missing) | ⚠️ Gap | There is no `Note` model. Notes are stored as `String` on `AgendaTask` and `AgendaItem`. This means notes are not first-class artifacts. |
| **Action** | `AgendaTask` | ✅ Strong | `AgendaTask` is the primary action unit. Has all action metadata: friction, energy, time, context, waitingOn. |
| **Outcome** | `isComplete`, `completedAt` | ✅ Strong | Completion is explicitly modeled with timestamp. `ActivityLog` tracks outcomes over time. |
| **Learning** | `CognitiveProfile` (partial) | ⚠️ Partial | `CognitiveProfile` is not a standalone model. `ProfilePreferences` stores preferences, and `CognitiveCheckInTracker` stores history, but there is no unified "learning" model that aggregates insights. |
| **Entity** | `Profile` | ✅ Strong | `Profile` represents the user entity. Multi-profile support means multiple entities. Coordinator role adds household entity concept. |
| **State** | `DensityMode`, `energyLevel`, `isComplete` | ✅ Strong | State is well-modeled. `DensityMode` is a four-state enum. Energy is a 1–5 scale. |
| **Relationship** | ❌ Missing | 🔴 Gap | There is no `Relationship` model. Tasks can be assigned to profiles (`assignedToProfileID`, `assignedByProfileID`), but there is no explicit relationship graph (e.g., "this task depends on that task," "this profile is a caregiver for that profile"). |
| **FocusSession** | ❌ Missing | 🔴 Gap | There is no `FocusSession` model. The app mentions "focus session" in the dashboard logic and notification categories, but there is no data model for tracking an actual focus session (start time, end time, interruptions, pomodoro count). |
| **CognitiveProfile** | `Profile` + `ProfilePreferences` | ⚠️ Partial | `Profile` has a `Neurotype` enum, but there is no dynamic `CognitiveProfile` that tracks how the user's cognitive state changes over time (e.g., "user is more accurate at self-reporting energy at 9am than 3pm"). |
| **Context** | `InterruptionContext` | ⚠️ Partial | `InterruptionContext` records the current activity label and item ID. This is a good start, but "Context" in the Ontology is broader — it includes environmental context (location, weather, time-of-day patterns), which is not fully captured. |

### 4.3 Unmapped Ontology Forks

**Finding T4.1:** `Relationship` is entirely unmapped. The prompt says "Represents a link between two entities." In AuGenda, this would be: task dependencies (task A blocked by task B), household relationships (parent → child profile), or bundle-to-task relationships. Currently, `waitingOn` is just a string, not a relationship to another task or entity.

**Finding T4.2:** `FocusSession` is entirely unmapped. The dashboard checks `focusSession != nil` in its primary action priority, but there is no `FocusSession` model. This means the focus session feature is **UI-only fantasy data** — it cannot persist or be tracked.

**Finding T4.3:** `CognitiveProfile` is fragmented. `ProfilePreferences` stores static preferences, and `CognitiveCheckInTracker` stores check-ins, but there is no model that combines these into a dynamic cognitive profile (e.g., "User X has an average energy of 2.3 on Mondays, and their friction baseline is 3.5").

**Recommendation:** Either add these models to the schema or explicitly deprecate them from the Ontology. The current state (referenced in UI but not in data) creates architectural drift.

---

## Tier 5: User Context — Arthur's Specific Needs

### 5.1 Arthur's Profile (from Governance Context)

- **Neurotype:** AuADHD (Autism + ADHD) — high masking, PDA-like demand avoidance, high EF variability
- **Physical:** hEDS (hypermobility), dysautonomia, chronic fatigue, chronic pain, 2–4h productive windows, medical fatigue
- **Context:** No professional ADHD support (undiagnosed until 33). Self-directed, inconsistent, needs strong scaffolding. Extreme disorientation. Needs relational transition support. Needs time-of-day adaptive support. Needs consistent daily structures.
- **Budget:** $0. No external developer. No third-party costs. No SaaS.
- **Risk:** Cannot handle sudden change. Must avoid burnout triggers. Must preserve existing cognitive load investment. Any crash or data loss = project abandonment risk.
- **Technical skill:** Capable but must be guided by Daimon.

### 5.2 Assessment Against User Context

**Finding T5.1 — Data Loss = Project Abandonment Risk.**  
The **lack of schema migration** and the **silent `try?` save pattern** means the app *will* eventually lose data or crash for Arthur. Given the governance explicitly states "any crash or data loss = project abandonment risk," this is a **Tier 5 violation**. The app must be made crash-proof and data-loss-proof before Arthur can rely on it.

**Finding T5.2 — No External Costs = Zero Budget.**  
The AI layer (9 providers) is off by default, which is good. However, if Arthur ever enables it, the API keys will incur costs. The app does not enforce a $0 budget cap. The `AIUsageLedger` tracks usage but does not block usage when costs are incurred. The `Ollama` provider is local-only (free), but the UI does not guide the user toward the free option. **Recommendation:** Add a "Local AI only (Ollama)" mode that hides all paid providers.

**Finding T5.3 — Fatigue & 2–4h Windows = Need for Stability.**  
The app is generally well-designed for fatigue: large touch targets, generous spacing, clear typography, minimal cognitive load. However, the **lack of a persistent FocusSession model** means the app cannot help Arthur track his 2–4h productive windows. The dashboard mentions focus sessions but cannot actually manage them. This is a critical missing feature for the stated user context.

**Finding T5.4 — No Professional Support = App Must Be the Scaffold.**  
The app is the scaffold. This is good — the design system is strong, the density modes are appropriate, and the household/coordinator view supports external scaffolding (if a partner is the coordinator). However, the **app does not have a "coach" or "guide" mode** that proactively helps Arthur when he is stuck. The governance mentions "virtual cognitive scaffolding" — the app provides structure but not active guidance. The AI enrichment could fill this gap, but it's currently a passive enrichment tool, not an active coach.

**Finding T5.5 — hEDS / Chronic Pain = Physical Interaction Design.**  
The app uses `Tokens.Spacing.touchMinimum` (44pt) and large tap targets. This is good for hEDS users who may have fine motor control issues. However, there is **no adjustable UI scale or text size override** beyond what the system provides. The app does not offer a "large mode" with bigger buttons and more spacing. This would be a valuable addition.

**Finding T5.6 — Disorientation = Need for Relational Transition Support.**  
The `InterruptionContext` records the current activity, but there is **no explicit "resume" flow** that brings the user back to where they were. The governance says "needs relational transition support" — the app should have a "You were working on X before you were interrupted. Resume?" prompt. This is not present.

**Finding T5.7 — Inconsistent = Need for Zero-Friction Daily Reset.**  
The `BlockManager` seeds default blocks and tasks, and the first-launch flow creates sample data. However, there is **no "daily reset" or "morning setup" wizard** that helps Arthur rebuild his agenda each day. The `TodayView` is static — it shows what's scheduled but does not help the user *plan* their day based on today's energy. This would be a high-value feature for an inconsistent user.

---

## Production Blockers — Cannot Ship Without These

| # | Blocker | Severity | File(s) | Fix Complexity |
|---|---|---|---|---|
| 1 | **Schema Migration Missing** | 🔴 Critical | `AppContainer.swift` | Medium — add `VersionedSchema` + `MigrationPlan` |
| 2 | **Real OAuth Client ID in Source** | 🔴 Critical | `GoogleOAuth.swift`, `Info.plist` | Low — move to env/build config, rotate credential |
| 3 | **macOS Compile Errors (UIColor)** | 🔴 Critical | `AuDHDComponents.swift` | Low — wrap in `#if os(iOS) / NSColor` |
| 4 | **CloudKit Not Active** | 🟠 High | `AppContainer.swift`, `.entitlements` | Medium — configure in Apple Developer portal |
| 5 | **`aps-environment` = development** | 🟠 High | `AuGenda.entitlements` | Low — change to `production` for archive |
| 6 | **Silent `try?` Save Failures** | 🟠 High | All view files | Medium — add error surfacing UI |
| 7 | **No Test Coverage for Managers/Views** | 🟠 High | `AuGendaTests/` | Medium — add UI/integration tests |
| 8 | **FocusSession Model Missing** | 🟡 Medium | Ontology / UI | Medium — add model + persistence |
| 9 | **Relationship Model Missing** | 🟡 Medium | Ontology / `AgendaTask` | Medium — add `relatedTaskID` or `TaskRelationship` |
| 10 | **No Progress UI for Async Ops** | 🟡 Medium | Views with network/AI | Low — add `ProgressView` overlays |
| 11 | **Export Data is Plaintext** | 🟡 Medium | `TaskExporter.swift` | Low — add encryption option or export warning |
| 12 | **No Daily Planning / Morning Setup Wizard** | 🟡 Medium | `TodayView.swift` | Medium — new feature |
| 13 | **No "Resume After Interruption" Flow** | 🟡 Medium | `InterruptionContext.swift` | Low — add prompt UI |
| 14 | **No Biometric Protection for API Keys** | 🟡 Medium | `KeychainStore.swift` | Low — add `kSecAccessControl` |
| 15 | **Font Files Missing** | 🟡 Medium | `DesignTokens.swift` / asset catalog | Low — add Atkinson + OpenDyslexic to bundle |

---

## Strengths — What AuGenda Does Exceptionally Well

1. **Zero External Dependencies.** The app has no SPM packages, no CocoaPods, no Carthage. This is a massive win for reliability, build reproducibility, and long-term maintenance. It aligns perfectly with Arthur's $0 budget and "no third-party costs" constraint.

2. **Deterministic Difficulty Engine.** `DifficultyEngine.rank()` is a pure, stateless, testable function. It is the architectural gold standard of the codebase. The six-axis model (friction, energy, sensory, social, initiation, interest) is uniquely AuGenda and deeply ND-informed.

3. **Privacy-by-Default Design.** `strictPrivacy` is `true`. Notifications redact task titles. AI is off. Speech is on-device. Location is only for WeatherKit. No analytics. This is a professional-grade privacy posture.

4. **Semantic Design Tokens.** `DesignTokens.swift` is comprehensive: colors, spacing, typography, borders, shadows, animation, layout, accessibility. The naming is semantic (`appTextPrimary`, not `gray900`), which supports theming and accessibility.

5. **Multi-Profile Household Architecture.** The `Profile` model with `role` (coordinator/self) and the `HouseholdOverviewView` is a genuinely advanced feature. Most todo apps are single-user. AuGenda is designed for households where one person may need to coordinate care for another.

6. **Watch Connectivity.** The `WatchSyncPayload` and bidirectional sync (iPhone → Watch, Watch → iPhone) is well-structured. The `#if canImport(WatchConnectivity)` conditional compilation is clean.

7. **Brain Dump with Voice.** The `BrainDumpView` is a well-designed low-EF feature. One thought per line, no decisions, large text surface, reassuring microcopy. The `SFSpeechRecognizer` integration is appropriate for the target user.

8. **First-Launch Flow.** The `RootView` with `FirstLaunchStep` is serial, no race conditions, and skips onboarding for Survival/Low users. This respects the user's current capacity state.

9. **Block System with Weather.** The `BlockManager` tying outdoor blocks to weather suggestions is an innovative, practical feature. It shows awareness of the user's real-world context.

10. **Comprehensive ND Vocabulary.** The app does not use generic terms. It uses ND-native language: friction, body double, hyperfocus risk, energy, density, survival mode. This is Contrast Doctrine at its finest.

---

## Recommendations — Prioritized Action Plan

### Phase 1: Safety & Security (Must Do Before Any TestFlight)

1. **Implement Schema Migration.** Add `VersionedSchema` and `MigrationPlan` to `AppContainer.swift`. Start with schema v1. Any future model change goes through v2 with a lightweight migration. This is non-negotiable.
2. **Remove Hardcoded OAuth Credential.** Move `clientID` to Xcode build settings / environment variable. Rotate the exposed Google OAuth client ID immediately (it is compromised by being in version control). Update `Info.plist` via build variable.
3. **Fix macOS Compile Errors.** Wrap all `UIColor` adaptive `Color` extensions in `AuDHDComponents.swift` with `#if os(iOS) / #else NSColor`. Verify the macOS target (Target 7) builds cleanly.
4. **Change `aps-environment` to `production`.** In `AuGenda.entitlements`, set `aps-environment` to `production`. Add a build-phase script that validates this for archive builds.
5. **Replace `try?` with Explicit Error Handling.** Add a small error banner/toast system. Replace all `try? modelContext.save()` with `do/catch` that surfaces the error. This is critical for data reliability.

### Phase 2: Reliability & Robustness (Before App Store)

6. **Add Integration Tests.** Expand `AuGendaTests` to cover `BlockManager`, `NotificationManager`, `WatchConnectivityManager`, and view flows (first launch, task add, completion). Use `SwiftData` in-memory container for test isolation.
7. **Add Loading States.** Add `ProgressView` or skeleton UI for: AI enrichment, OAuth flow, WeatherKit fetch, Watch sync.
8. **Add `FocusSession` Model.** Create a `FocusSession` SwiftData model with startTime, endTime, interruptions, targetTask. Wire it into the dashboard and add a "Start Focus" button. This is critical for Arthur's 2–4h window management.
9. **Add `Relationship` Model.** Add `TaskRelationship` with `sourceTaskID`, `targetTaskID`, `type` (blocks, follows, bundles). Replace `waitingOn` string with optional relationship link. This enables real dependency tracking.
10. **Add Export Encryption Option.** Add a toggle in export settings: "Encrypt with password" (use AES-256-GCM from `CryptoKit`). Default to encrypted for sensitive data.

### Phase 3: User Experience & ND Alignment (Ongoing)

11. **Add "Morning Setup" Wizard.** A daily modal that asks: "What's your energy today?" → "Which blocks do you want?" → "Here are your top 3 tasks." This is the "daily reset" scaffold Arthur needs.
12. **Add "Resume After Interruption" Prompt.** When the app returns from background and `InterruptionContext` has a recorded activity, show a gentle prompt: "You were working on [Task X]. Resume?" This is relational transition support.
13. **Add "Local AI Only" Mode.** A setting that hides all paid AI providers and shows only Ollama (with a guide to setting it up). Enforces the $0 budget.
14. **Add UI Scale Override.** A setting in `ProfilePreferences` for "Large UI" (bigger buttons, more spacing, larger text). This helps hEDS users with motor control.
15. **Add Task Dependency Visualization.** In `TaskDetailView`, show a "Blocked by" / "Blocks" section with linked tasks. This is the UI for the `Relationship` model.

### Phase 4: CloudKit & Sync (Post-Launch)

16. **Activate CloudKit.** Register `iCloud.com.augenda.AuGenda` in the Apple Developer portal. Switch `AppContainer` to use the production container. Test sync across devices. Migrate `UserDefaults` active profile to `NSUbiquitousKeyValueStore`.

---

## GAP Items — Areas Not Defined in Governance

The following are noted as **unresolved by the user** (the Governance Prompt mentions these are user-defined but no values were set):

| GAP Item | Status | Notes |
|---|---|---|
| **Security threshold** | ❌ Not defined | Defaulting to "reasonable professional standard." The OAuth credential exposure would fail any reasonable standard. |
| **Testing threshold** | ❌ Not defined | Defaulting to "reasonable professional standard." 3 test files is below standard. |
| **Accessibility threshold** | ❌ Not defined | Defaulting to "reasonable professional standard." The app is good (dynamic type, VoiceOver labels) but could be better (no UI scale override, no Reduce Motion consideration beyond system default). |
| **Maintainability threshold** | ❌ Not defined | Defaulting to "reasonable professional standard." Zero dependencies = high maintainability. But no schema migration = low maintainability. |

**Recommendation:** Arthur should define numeric or qualitative thresholds for these four items so that future audits can judge against explicit criteria rather than defaults.

---

## Conclusion

AuGenda is a **genuinely innovative and well-intentioned app** with a deep understanding of its neurodivergent users. The design system, the vocabulary, the privacy posture, and the zero-dependency architecture are all **best-in-class** for an indie ND app. However, it is **not yet production-ready** due to critical gaps in schema migration, credential security, error handling, and test coverage. The app is approximately **70% of the way to a shippable v1.0** but needs Phase 1 (Safety & Security) completed before any TestFlight or App Store submission.

The codebase shows strong alignment with the **Contrast Doctrine** and **Non-Interference** principles, but weak alignment with **Reliability** (due to silent failures and missing migrations) and **System Safety** (due to the exposed credential). The **Ontology** has unmapped forks that create architectural drift. The **User Context** (Arthur's specific needs) is well-served by the design but underserved by the missing FocusSession and Relationship models, and put at risk by the data-loss vulnerabilities.

**Overall Governance Grade: C+** — Strong intent and design, critical execution gaps in security and reliability. Fixable in 1–2 weeks of focused work.

---

*End of Report.*
