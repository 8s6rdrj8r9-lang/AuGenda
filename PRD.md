# AuGenda — Product Requirements Document (PRD)

**Version:** 1.1
**Date:** 2026-10-15
**Product Owner:** Arthur (AuDHD, hEDS, chronic fatigue)  
**Developer:** ensdev (indie, zero-budget)  
**Classification:** Internal — Daimon Workspace  
**Project Root:** `/Users/arthur/Development/AuGenda`

---

## How to Read This PRD

Sections 2–12 are the **normative product requirements and intended user
experience**. They describe what AuGenda should do; they are not assertions
that every acceptance criterion is implemented, tested, released, or available
on every configured platform.

Sections 13–14 and §16.1 record **implementation and verification status**.
Only dated build/test/device evidence may be treated as verified. A source file,
target, entitlement, checkmark, or prior audit grade is not release evidence by
itself.

### Implementation update — 2026-09-08

Completion-driven daily, weekday, weekly, and monthly recurrence is implemented;
launch-time generation, biweekly, and custom rules remain outside that subset.
Early completion must advance beyond the current occurrence while preserving
monthly cadence and replay idempotency. Agenda notification privacy and style
follow the assigned owner, with private/minimal fallback for unavailable or
unassigned owners. Reminder refresh must preserve snooze deadlines for both
future and overdue items. These updates supersede the older recurrence status
in the dated snapshot below; they do not establish device or release validation.

## 1. Executive Summary

AuGenda is an **indie productivity app built for neurodivergent humans** — specifically those with AuADHD (Autism + ADHD), dyslexia, dyspraxia, PDA, and comorbid physical conditions. It is a native SwiftUI app for iOS, iPad, and macOS with a companion Watch app. Unlike generic todo apps, AuGenda is designed around **friction, energy, sensory load, and initiation cost** rather than urgency and deadlines.

The app has zero external dependencies, no subscription costs, no analytics, and privacy-by-default architecture. It is built for a single user with extreme constraints: no budget, no professional support, 2–4 hour productive windows, chronic fatigue, and zero tolerance for data loss or sudden UI changes.

**Current implementation snapshot (2026-07-24):** active development and
remediation; not declared shipped or production-ready. The working tree
contains a file-backed local-only SwiftData app, native Watch and Watch widget
targets, optional AI integrations, schema migrations, and an expanded unit-test
suite. Recurrence fields are retained for portability, but no recurrence engine
or recurring-instance UI is implemented. The current tree passes 85 macOS unit
tests plus unsigned generic iOS and Watch Release build lanes. It is not a
release candidate: a full signed matrix, paired-device Watch/App Group QA,
accessibility/device QA, provider credentials, archive validation, and
performance/size measurement remain exit gates.

---

## 2. Product Vision & Mission

### 2.1 Vision Statement

> *A productivity system that understands the ND brain before the user has to explain themselves.*

### 2.1 Mission Statement

AuGenda exists to provide **virtual cognitive scaffolding** for neurodivergent adults who cannot access professional support. It is the app Arthur wishes he had at 15, 25, and 33. It does not try to make the user "more productive." It tries to make the user's existing energy sufficient for the day.

### 2.3 Core Principles

1. **Zero friction first.** The app must be usable during a "Survival mode" day when the user has zero executive function.
2. **Privacy by default.** No data leaves the device unless explicitly requested. AI is opt-in. Notifications redact task titles from the lock screen.
3. **No judgment.** The app never tells the user they "should" do more. It adapts to their capacity, not the other way around.
4. **Data is sacred.** Zero data loss tolerance. Schema migrations are mandatory. Saves are verified. Errors are surfaced, not swallowed.
5. **$0 budget compatible.** Core functionality must work without spending money on AI, cloud, or third-party services.
6. **Multi-profile.** A single household can have multiple profiles (e.g., parent + child, or self + partner as coordinator).
7. **Cross-platform.** iPhone, iPad, Mac, and Watch. The current implementation
   is local-only on the main app and uses a phone-authored Watch snapshot
   contract; CloudKit remains a future product direction.

---

## 3. Target User Persona

### 3.1 Primary Persona: Arthur ("The Masked AuDHD Adult")

- **Age:** 33  
- **Neurotype:** AuADHD (Autism + ADHD), high masking, PDA-like demand avoidance, high EF variability  
- **Physical:** hEDS (hypermobility), dysautonomia, chronic fatigue, chronic pain  
- **Productive windows:** 2–4 hours/day, unpredictable timing  
- **Professional support:** None (undiagnosed until 33)  
- **Budget:** $0. No external developer. No SaaS. No third-party costs.  
- **Risk tolerance:** Zero. Any crash or data loss = project abandonment.  
- **Cognitive load:** Cannot handle sudden UI changes. Needs relational transition support. Needs time-of-day adaptive support. Needs consistent daily structures.  
- **Technical skill:** Capable of coding but needs Daimon guidance.  
- **Pain points with existing tools:**
  - Todo apps assume consistent energy and willpower.
  - Calendar apps don't understand that "3pm meeting" might be impossible if energy is 1/5 at 3pm.
  - Pomodoro apps don't account for hyperfocus or physical pain interrupts.
  - No app understands "I can do this task but only if someone else is in the room (body double)."
  - No app has a "survival mode" that hides everything except the absolute minimum.

### 3.2 Secondary Persona: The Coordinator (Partner/Caregiver)

- A partner, parent, or caregiver who manages tasks for someone else with AuDHD.
- Uses the "coordinator" role in the household view.
- Needs to assign tasks, check energy levels, and see progress without being intrusive.
- Needs the app to be simple enough that they don't need training to use it.

### 3.3 Tertiary Persona: The Dyslexic User

- Needs dyslexia-friendly typography. The current build uses system Dynamic
  Type only; approved custom-font options remain an unmet requirement.
- Needs generous spacing and large touch targets.
- Needs minimal text density and no ALL CAPS.
- Needs clear visual hierarchy with color and shape, not just text size.

---

## 4. Problem Statement

### 4.1 The Generic Productivity Problem

> *Existing todo apps are designed for neurotypical executive function. They assume the user can reliably estimate time, prioritize by urgency, and initiate tasks on demand. These assumptions are false for ~15-20% of the population.*

### 4.2 Specific Pain Points

| Pain Point | Neurotypical App Behavior | AuGenda Behavior |
|-----------|---------------------------|------------------|
| **Energy variability** | Tasks have fixed due dates | Tasks have energy requirements and friction levels |
| **Initiation cost** | Tasks are sorted by deadline | Tasks are sorted by "easiest to start" (low friction + high interest) |
| **Hyperfocus** | No awareness of focus state | Detects hyperfocus risk and warns the user |
| **Sensory overload** | Dense UI with many notifications | Progressive disclosure — show less when energy is low |
| **Task switching** | No support for transitions | Records interruption context and offers resume prompts |
| **Body doubling** | Not a concept | Tasks can flag "needs body double" and household view shows who is available |
| **Inconsistent routines** | Daily habits are assumed | Blocks are suggested based on energy, not forced |
| **Physical pain/fatigue** | No awareness | Weather-aware outdoor blocks, energy check-ins, recovery prompts |
| **Data loss anxiety** | Silent sync failures | Explicit error banners, no `try?` saves, schema migrations |
| **Cost** | Freemium with subscriptions | Free core, zero-cost local AI option, no analytics |

---

## 5. Solution Overview

### 5.1 The AuGenda System

AuGenda is built around **six dimensions of task difficulty** rather than a single priority score:

1. **Friction** (1–4): How hard is it to *start* this task? (1 = easy, 4 = wall)
2. **Energy** (1–4): How much energy does this task consume? (1 = minimal, 4 = draining)
3. **Sensory Load** (0–3): How much environmental sensory input is involved?
4. **Social Load** (0–3): How much synchronous communication is involved?
5. **Initiation Cost** (0–3): How much first-step paralysis or dread is involved?
6. **Interest** (1–5): How intrinsically interesting is this task? (hyperfocus fuel)

These six dimensions are fed into a **deterministic Difficulty Engine** that produces a 0–10 rank. This rank is used to sort tasks by "easiest to start" rather than "most urgent."

### 5.2 The Five Density Modes

The UI adapts to the user's current cognitive capacity through four density modes:

| Mode | Energy Level | UI Behavior | Primary Content |
|------|-------------|-------------|-----------------|
| **Survival** | 1/5 | Only the most critical task. No lists. One button. | Top priority + lowest friction task |
| **Low** | 2/5 | Minimal list. No details. Large buttons. | 3–5 most actionable tasks |
| **Functional** | 3/5 | Standard view. Full lists. Normal density. | All tasks for the day, sorted by actionability |
| **High** | 4–5/5 | Full detail. All features. Analytics. | Everything + focus session + history + suggestions |

Density is auto-calculated from energy level but can be manually overridden (pinned).

### 5.3 Key Features

| Feature | Description | User Value |
|---------|-------------|------------|
| **Brain Dump** | Voice or text rapid capture of racing thoughts, one per line | Low-EF task entry without decisions |
| **Focus Session** | Pomodoro-style timer with hyperfocus guard and interruption tracking | Protects 2–4h windows from self-interruption |
| **Morning Setup** | Daily wizard suggesting blocks and tasks based on energy | Rebuilds the day when EF is inconsistent |
| **Block System** | Time-blocked routines (startup, wind-down, outdoor) with weather awareness | Reduces decision fatigue about "what to do next" |
| **Household View** | Multi-profile coordination with energy visibility and task assignment | Enables body doubling and caregiver support |
| **Smart Suggest** | AI-free task ranking using the six-axis difficulty engine | Surfaces the most actionable task without AI |
| **Inbox** | Unscheduled task capture with quick-add | Prevents task loss during low-EF moments |
| **Backlog** | Full task list with filtering, sorting, and import/export | Long-term task management with ND-native sorting |
| **Resume Prompt** | "You were working on X" notification when returning to the app | Relational transition support |
| **Interruption Tracking** | Record why you got interrupted during a focus session | Pattern recognition for future planning |
| **Note Model** | First-class notes attached to tasks | Artifact capture (Ontology) |
| **Task Relationships** | Dependencies: "This task blocks that task" | Realistic planning with blocked-by awareness |
| **AI Enrichment** | Optional AI task breakdown (Claude, OpenAI, Ollama, etc.) | Off by default; local AI free mode available |
| **Watch Companion** | Quick task completion, energy update, focus session status | Low-friction interaction from wrist |
| **Export/Import** | JSON, CSV, Markdown, YAML, and plain text task-list portability with optional AES-256-GCM encryption | A portable copy of active tasks; not a full-app backup |
| **Accessibility** | System Dynamic Type today; VoiceOver, touch targets, motion reduction, and future verified font options | Full ND accessibility stack after device validation |

---

## 6. Feature Requirements

### 6.1 Core Domain: Task Management

#### FR-1.1: Task Model (AgendaTask)
**Priority:** Must  
**Description:** Every task must have the six-axis difficulty dimensions plus interest, time, and context.  
**Acceptance Criteria:**
- AC-1.1.1: Task has `frictionLevel` (1–4), `energyRequired` (1–4), `sensoryLoad` (0–3), `socialLoad` (0–3), `initiationCost` (0–3), `interestLevel` (1–5)
- AC-1.1.2: Task has `estimatedMinutes` (Int) and `totalEstimatedMinutes` (sum of subtask estimates)
- AC-1.1.3: Task has `ndPriorityScore` computed as `priority * 3.0 + interest * 1.5 - friction * 1.0 - energy * 0.5`
- AC-1.1.4: Task has `contextTag` (String) for environmental filtering (home, work, outdoors, etc.)
- AC-1.1.5: Task has `waitingOn` (String) for external dependencies
- AC-1.1.6: Task has `hyperfocusRisk` (Bool) for tasks that may trigger extended focus
- AC-1.1.7: Task has `bodyDouble` (Bool) for tasks requiring presence of another person
- AC-1.1.8: Task has `excludeFromAI` (Bool) for privacy-sensitive tasks
- AC-1.1.9: Task has `assignedToProfileID` and `assignedByProfileID` for household coordination
- AC-1.1.10: Task has `isComplete`, `isAbandoned`, `completedAt`, `abandonedAt` for lifecycle tracking

#### FR-1.2: Task Relationships (TaskRelationship)
**Priority:** Must  
**Description:** Tasks can have structured dependencies.  
**Acceptance Criteria:**
- AC-1.2.1: Relationship types: `blocks`, `follows`, `bundles`, `related`
- AC-1.2.2: `blocks` and `follows` prevent the target task from being marked actionable until the source is complete
- AC-1.2.3: Relationships are queryable from both directions ("blocks" and "blocked by")
- AC-1.2.4: Relationships are shown in `TaskDetailView`

#### FR-1.3: Subtasks (TaskStep)
**Priority:** Must  
**Description:** Tasks can be broken into steps with individual time estimates.  
**Acceptance Criteria:**
- AC-1.3.1: Each step has `title`, `estimatedMinutes`, `isComplete`, `sortOrder`
- AC-1.3.2: Step completion updates the parent task's `totalEstimatedMinutes`
- AC-1.3.3: Steps are visible in `TaskDetailView`

#### FR-1.4: Notes (Note)
**Priority:** Must  
**Description:** First-class notes can be attached to tasks.  
**Acceptance Criteria:**
- AC-1.4.1: Note has `title`, `body`, `tags`, `relatedTaskID`, `relatedItemID`
- AC-1.4.2: Notes are queryable from `TaskDetailView` via `relatedTaskID`
- AC-1.4.3: Notes are included in the schema migration plan

#### FR-1.5: Task Import/Export
**Priority:** Must  
**Description:** Tasks can be exported and imported in multiple formats with optional encryption.  
**Acceptance Criteria:**
- AC-1.5.1: Export formats: JSON, CSV, Markdown, YAML, plain text
- AC-1.5.2: Optional AES-256-GCM encryption using a versioned
  PBKDF2-HMAC-SHA256 password envelope (210,000 iterations); legacy SHA-256
  envelopes remain readable for migration
- AC-1.5.3: Import selects format from a supported file extension and strictly
  validates the selected format before mutation
- AC-1.5.4: Import accepts JSON, CSV, Markdown, YAML, plain text
- AC-1.5.5: Encrypted imports decrypt with password before parsing
- AC-1.5.6: Import prevents duplicates (by `clientID`)
- AC-1.5.7: Error banner shown on import failure

#### FR-1.6: Difficulty Engine
**Priority:** Must  
**Description:** Pure, deterministic six-axis difficulty ranking.  
**Acceptance Criteria:**
- AC-1.6.1: `DifficultyEngine.rank(friction, energy, sensory, social, initiation, interest)` returns 0–10 Int
- AC-1.6.2: Formula: `friction*2.0 + energy*1.5 + sensory*1.0 + social*1.0 + initiation*2.0 - (interest-1)*1.0`, clamped to 0–30, divided by 3, rounded
- AC-1.6.3: Stateless, no SwiftData dependency, unit-tested
- AC-1.6.4: Used by `SmartSuggestView` and `TaskBacklogView` "For Now" filter

### 6.2 Scheduling Domain: Agenda Items

#### FR-2.1: Agenda Items (AgendaItem)
**Priority:** Must  
**Description:** Scheduled tasks with time and recurrence.  
**Acceptance Criteria:**
- AC-2.1.1: `AgendaItem` has `scheduledDate`, `frictionLevel`, `energyRequired`, `contextTag`, `priority`, `recurrenceRule`
- AC-2.1.2: `recurrenceRule` supports: `none`, `daily`, `weekly`, `weekdays`
- AC-2.1.3: Recurrence engine generates instances idempotently (no duplicates for the same day)
- AC-2.1.4: Recurrence engine runs on app launch
- AC-2.1.5: Future: monthly, biweekly, custom recurrence

#### FR-2.2: Notifications
**Priority:** Must  
**Description:** ND-tuned notification system with per-profile styles.  
**Acceptance Criteria:**
- AC-2.2.1: Four notification categories: `AGENDA_ITEM`, `FOCUS_SESSION`, `HYPERFOCUS_WARNING`, `LOW_EF_NUDGE`
- AC-2.2.2: Per-profile notification styles: `standard` (all alerts), `predictable` (no overdue), `minimal` (at-time only)
- AC-2.2.3: `strictPrivacy` defaults to `true` — redacts task titles from lock screen
- AC-2.2.4: Notification actions: Done, Snooze (5/15/30 min), End Session, Start Focus, Dismiss
- AC-2.2.5: Notification IDs follow `{UUID}-{advance|attime|overdue|snooze}` pattern for cancellation

#### FR-2.3: Morning Setup Wizard (MorningSetupView)
**Priority:** Should  
**Description:** Daily planning modal that gates on first launch of each day.  
**Acceptance Criteria:**
- AC-2.3.1: Shows on first app launch of each day (checked via `UserDefaults` date)
- AC-2.3.2: Step 1: Energy picker (1–4)
- AC-2.3.3: Step 2: Suggested blocks based on energy and scheduled items
- AC-2.3.4: Step 3: Top 3 tasks sorted by `ndPriorityScore`
- AC-2.3.5: "Save today's capacity" persists energy to the active profile;
  suggested tasks and blocks are review-only and are not scheduled automatically
- AC-2.3.6: Can be dismissed and won't show again until tomorrow
- AC-2.3.7: Survival/Low energy users see fewer suggestions

### 6.3 Focus Domain: Focus Sessions

#### FR-3.1: Focus Session Model (FocusSession)
**Priority:** Must  
**Description:** Persistent focus session tracking with interruption logging.  
**Acceptance Criteria:**
- AC-3.1.1: `FocusSession` has `startTime`, `endTime`, `plannedDurationMinutes`, `actualDurationMinutes`, `taskID`, `taskTitle`, `state`, `interruptionCount`, `interruptionTimestamps`, `interruptionReasons`
- AC-3.1.2: States: `idle`, `active`, `paused`, `completed`, `abandoned`
- AC-3.1.3: `isOverdue` computed from `plannedDurationMinutes` vs elapsed time
- AC-3.1.4: `recordInterruption(reason:)` increments count and logs timestamp + reason
- AC-3.1.5: Persisted to SwiftData, queryable by profile

#### FR-3.2: Focus Session View (FocusSessionView)
**Priority:** Must  
**Description:** Timer UI with task selection and interruption tracking.  
**Acceptance Criteria:**
- AC-3.2.1: Shows selected task title and planned duration
- AC-3.2.2: Pomodoro-style countdown timer
- AC-3.2.3: "I got interrupted" button with quick-reason picker (Notification, Phone call, Lost track, Physical discomfort, Other)
- AC-3.2.4: Suggested duration from `CognitiveProfile.suggestedFocusLength()` based on historical data
- AC-3.2.5: Link to `FocusSessionHistoryView`

#### FR-3.3: Focus Session History (FocusSessionHistoryView)
**Priority:** Should  
**Description:** List of past focus sessions with analytics.  
**Acceptance Criteria:**
- AC-3.3.1: Lists all completed/abandoned sessions sorted by startTime descending
- AC-3.3.2: Shows planned vs actual duration, completion status, interruption count, reasons
- AC-3.3.3: Accessible from Settings or FocusSessionView

#### FR-3.4: Cognitive Profile (CognitiveProfile)
**Priority:** Should  
**Description:** Lightweight insight aggregator from historical data.  
**Acceptance Criteria:**
- AC-3.4.1: `typicalWindowLengthMinutes()` returns median of completed sessions in last 30 days
- AC-3.4.2: `suggestedFocusLength(energyLevel:)` scales typical window by energy/3.0
- AC-3.4.3: Wired into `FocusSessionView` for duration suggestion
- AC-3.4.4: Future: energy-by-hour patterns, completion accuracy, friction override patterns

### 6.4 Block Domain: Time Blocks

#### FR-4.1: Block Model (Block)
**Priority:** Must  
**Description:** Time-blocked routines with completion tracking.  
**Acceptance Criteria:**
- AC-4.1.1: Block types: `startup`, `windDown`, `deepWork`, `admin`, `outdoor`, `social`, `recovery`, `custom`
- AC-4.1.2: Each block has `currentStreak`, `lastCompletedDate`, `weatherCheckEnabled`
- AC-4.1.3: Outdoor blocks trigger WeatherKit fetch when activated
- AC-4.1.4: `shouldAutoSurface` returns true for incomplete startup blocks not completed today

#### FR-4.2: Block Tasks (BlockTask)
**Priority:** Must  
**Description:** Tasks within a block.  
**Acceptance Criteria:**
- AC-4.2.1: BlockTask has `title`, `isComplete`, `isOptional`
- AC-4.2.2: Block completion resets all block tasks to incomplete for the next run (blocks are repeatable routines)
- AC-4.2.3: Optional block tasks don't block block completion

#### FR-4.3: Bundle System (BundleTemplate, AttachedBundle)
**Priority:** Must  
**Description:** Reusable task bundles that can be attached to blocks.  
**Acceptance Criteria:**
- AC-4.3.1: `BundleTemplate` defines reusable bundles (e.g., "Morning Routine")
- AC-4.3.2: `BundleTemplateItem` defines items within a template
- AC-4.3.3: `AttachedBundle` is an instance of a template attached to a specific block run
- AC-4.3.4: `autoPromptBlockTypes` determines which block types auto-suggest bundles

#### FR-4.4: Weather Integration (BlockManager)
**Priority:** Should  
**Description:** Outdoor blocks get weather suggestions.  
**Acceptance Criteria:**
- AC-4.4.1: `BlockManager` fetches weather via `WeatherService.shared` when outdoor block activated
- AC-4.4.2: Location requested at `kCLLocationAccuracyKilometer` only when needed
- AC-4.4.3: Weather data suggests whether to proceed with outdoor block
- AC-4.4.4: Requires `com.apple.developer.weatherkit` entitlement and `NSLocationWhenInUseUsageDescription`
- AC-4.4.5: Graceful degradation if weather unavailable (no crash, no weather suggestions)

### 6.5 Profile Domain: User Identity

#### FR-5.1: Profile Model (Profile)
**Priority:** Must  
**Description:** Multi-profile support with neurotypes and roles.  
**Acceptance Criteria:**
- AC-5.1.1: Profile has `name`, `role` (coordinator/self), `neurotypes` (ADHD, autism, PDA, dyslexia, dyspraxia, neurotypical)
- AC-5.1.2: Avatar support: `avatarImageData` (PNG/JPEG) or `avatarColorHex`
- AC-5.1.3: Multiple profiles per household
- AC-5.1.4: Active profile persisted in `UserDefaults` (not CloudKit-synced)

#### FR-5.2: Profile Preferences (ProfilePreferences)
**Priority:** Must  
**Description:** Per-profile settings with ND-specific options.  
**Acceptance Criteria:**
- AC-5.2.1: `currentEnergyLevel` (1–4) with default 3
- AC-5.2.2: `densityMode` (survival/low/functional/high) with auto-calculation from energy
- AC-5.2.3: `densityPinned` — manual override of auto-calculated density
- AC-5.2.4: `hyperfocusGuard` (Bool) — enables extra warnings during focus sessions
- AC-5.2.5: `notificationStyle` (standard/predictable/minimal)
- AC-5.2.6: `strictPrivacy` (Bool) — defaults to true, redacts notification content
- AC-5.2.7: `taskLanguageStyle` (formal/casual/playful) — affects task text tone
- AC-5.2.8: `appFont` supports system typography and, when authoritative
  licensed assets plus device QA are available, approved custom legibility
  fonts
- AC-5.2.9: `largeTouchTargets` (Bool) — increases minimum touch size
- AC-5.2.10: `focusSessionMinutes` (Int) — default session length
- AC-5.2.11: `uiScale` (Double) — 1.0, 1.25, 1.5 for UI scaling
- AC-5.2.12: `showCheckInNudges` (Bool) — periodic energy check-in reminders
- AC-5.2.13: `lowStimulationMode` (Bool) — reduces animation and visual noise
- AC-5.2.14: `reduceMotion` (Bool) — respects system setting but can be overridden

**Implementation status (2026-07-24):** only the system `AppFont` option is
presented. It resolves semantic SwiftUI text styles through Dynamic Type. The
former custom font artifacts and `UIAppFonts` registration were removed because
they were not valid font binaries. `uiScale`, large-touch-target, and other
stored preference fields must not be treated as user-facing completed features
unless the corresponding setting and rendering behavior are both verified.

#### FR-5.3: Household View (HouseholdView)
**Priority:** Must  
**Description:** Multi-profile coordination dashboard.  
**Acceptance Criteria:**
- AC-5.3.1: Shows all profiles with current energy level, completion status, and assigned tasks
- AC-5.3.2: Coordinator can assign tasks to other profiles
- AC-5.3.3: Shows body double availability
- AC-5.3.4: Profile day cards with progress indicators

#### FR-5.4: UI Scale Override
**Priority:** Should  
**Description:** Adjustable UI size for motor accessibility.  
**Acceptance Criteria:**
- AC-5.4.1: Settings picker: Normal (1.0), Large (1.25), Extra Large (1.5)
- AC-5.4.2: `uiScale` environment value injected at app root
- AC-5.4.3: `AuDHDButton`, `AuDHDCard`, `OptionCard` scale padding and frame heights
- AC-5.4.4: Future: typography scaling, full view scaling

**Implementation status (2026-07-24):** this remains a requirement. The
unsupported custom scale control is not currently exposed; device text size and
accessibility display settings are the supported scaling path.

### 6.6 AI Domain: Foundation Models & Siri AI Delegation (macOS 27 / iOS 27)

#### FR-6.1: AI Provider System (AITaskEnricher)
**Priority:** Must  
**Description:** Pluggable AI provider architecture with Apple Foundation Model (`appleFoundation`) as the default engine on macOS 27 / iOS 27, accompanied by an opt-in ChatGPT (`openai`) backup fallback.  
**Acceptance Criteria:**
- AC-6.1.1: Protocol `AITaskEnricher` with `enrich(task:context:)` method.
- AC-6.1.2: Providers: `appleFoundation` (Default, on-device), `openai` (ChatGPT Backup), `claude`, `gemini`, `deepseek`, `mistral`, `ollama`, `perplexity`, `grok`.
- AC-6.1.3: Default provider is `appleFoundation` with 0-token cost and strict on-device data isolation.
- AC-6.1.4: Per-task `excludeFromAI` opt-out guarantees complete bypass.
- AC-6.1.5: API keys for cloud providers stored securely in Keychain (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`).
- AC-6.1.6: ChatGPT Backup Fallback: If `appleFoundation` is unavailable or trips safety guardrails, user-authorized fallback seamlessly routes to ChatGPT (`openai`) while honoring the token ledger.

#### FR-6.2: Siri AI Delegation (App Intents)
**Priority:** Must  
**Description:** Native App Intents integration for Siri AI and macOS 27 Spotlight task delegation.  
**Acceptance Criteria:**
- AC-6.2.1: `CaptureBrainDumpIntent` exposes fast voice capture to Siri and Spotlight.
- AC-6.2.2: `EnrichTaskIntent` delegates task restructuring directly to Siri AI using on-device foundation models.
- AC-6.2.3: `GetTopFocusTaskIntent` enables Siri to retrieve the current low-friction, high-priority task matching current user capacity.
- AC-6.2.4: Conforms to `AppShortcutsProvider` for immediate zero-setup voice discovery.

#### FR-6.3: AI Usage Ledger & Budget Controls
**Priority:** Should  
**Description:** Tracks API usage, enforces cost caps, and records zero-cost metrics for local runs.  
**Acceptance Criteria:**
- AC-6.3.1: Tracks per-provider token count, cost, and request count per month (on-device Foundation runs record 0 tokens / $0).
- AC-6.3.2: `maxMonthlyCostUSD` with picker ($0/$5/$10/$20/$50).
- AC-6.3.3: `canEnrich()` returns false when monthly cap reached.
- AC-6.3.4: Enforced at all enrichment entry points with `ErrorBanner` feedback.
- AC-6.3.5: Usage visible in `AIEnrichmentSettingsView`.

#### FR-6.4: macOS 27 / iOS 27 Architecture & Platform Alignment (Features 1–6)
**Priority:** Must  
**Description:** Full alignment with the macOS 27 Golden Gate system capabilities.  
**Acceptance Criteria:**
- AC-6.4.1 (Feature 1 - AI & Delegation): On-device Foundation Models default, Siri AI delegation via App Intents, and ChatGPT backup.
- AC-6.4.2 (Feature 2 - SwiftData Modernization): SwiftData enum predicates for domain models and sectioned query support for time/energy grouping.
- AC-6.4.3 (Feature 3 - SwiftUI Performance): Adaptive density views with toolbar overflow resilience (`toolbarOverflowMenu`, `visibilityPriority`).
- AC-6.4.4 (Feature 4 - Apple Silicon Exclusivity): Pure ARM64 compilation, utilizing unified memory architecture for zero-latency local model execution.
- AC-6.4.5 (Feature 5 - Privacy Boundaries): Strict offline-first operation by default, with clear disclosures for cloud fallback.
- AC-6.4.6 (Feature 6 - Cognitive Scaffolding): Integration of sensory load, energy tracking, and focus filters without judgmental reminders.

### 6.7 Watch Domain: Companion App

#### FR-7.1: Watch Sync (WatchConnectivityManager)
**Priority:** Should  
**Description:** Bidirectional iPhone ↔ Watch sync.  
**Acceptance Criteria:**
- AC-7.1.1: A versioned `WatchSnapshot` includes active-profile-scoped agenda
  and backlog summaries, energy/density, focus state, pending/low-friction
  counts, and `pendingRecovery`
- AC-7.1.2: iPhone sends snapshot on: scene active/background, task complete, snooze, energy change
- AC-7.1.3: Watch sends: task completed, task snoozed, energy update, sync request
- AC-7.1.4: Full snapshots use `updateApplicationContext` with `sendMessage` as
  a reachable latency optimization; Watch mutations use a durable outbox,
  `transferUserInfo`, event IDs, and phone acknowledgements
- AC-7.1.5: Graceful degradation when Watch is unreachable
- AC-7.1.6: Watch app and widget share the latest snapshot and pending-action
  overlay through App Group `group.ensdev.AuGenda.watch`

**Implementation status (2026-07-24):** the shared source contract, entitlements,
freshness checks, profile scoping, and outbox tests exist. Developer Portal
provisioning, signed-entitlement inspection, paired physical iPhone/Watch
delivery, offline retry, complication reload, and stale-title redaction are not
yet release-verified.

#### FR-7.2: Watch App (NowView)
**Priority:** Should  
**Description:** Watch display of current state and quick actions.  
**Acceptance Criteria:**
- AC-7.2.1: Shows next task title and time
- AC-7.2.2: Shows current energy level
- AC-7.2.3: Shows focus session status (active/inactive)
- AC-7.2.4: Quick actions: complete task, snooze, update energy, request sync
- AC-7.2.5: Recovery card shows when `pendingRecovery` is true

### 6.8 UX Domain: Accessibility & Design

#### FR-8.1: Design System (DesignTokens)
**Priority:** Must  
**Description:** Comprehensive semantic design system.  
**Acceptance Criteria:**
- AC-8.1.1: `Tokens.Color` — semantic colors: `warning`, `success`, `info`, `danger`, `primary`, `secondary`, `accent`, `background`, `surface`, `textPrimary`, `textSecondary`, `textMuted`, `border`, `overlay`
- AC-8.1.2: `Tokens.Spacing` — 2, 4, 8, 12, 16, 20, 24, 32, 40, 48, 64, 80px scale
- AC-8.1.3: `Tokens.Typography` — h1-h6, body, caption, label, button, with sizes
- AC-8.1.4: `Tokens.Border` — radius scale (4, 8, 12, 16, 20, 24px)
- AC-8.1.5: `Tokens.Shadow` — elevation levels (0–4)
- AC-8.1.6: `Tokens.Animation` — duration scale (fast/normal/slow), easing curves
- AC-8.1.7: `Tokens.Layout` — breakpoints, max content width, grid columns
- AC-8.1.8: `AppColor` palette — 12+ semantic colors with light/dark variants
- AC-8.1.9: Environment values include `reduceMotion`,
  `lowStimulationMode`, `uiScale`, and adaptive `densityMode`; text sizing uses
  system Dynamic Type rather than a competing custom multiplier

#### FR-8.2: Reusable Components (AuDHDComponents)
**Priority:** Must  
**Description:** ND-optimized UI components.  
**Acceptance Criteria:**
- AC-8.2.1: `AuDHDCard` — card with consistent padding, border, shadow, optional badge
- AC-8.2.2: `AuDHDButton` — button with minimum 44pt touch target, clear visual state
- AC-8.2.3: `AuDHDInput` — text input with clear label, validation, and error state
- AC-8.2.4: `OptionCard` — selectable card with radio/check behavior
- AC-8.2.5: `StatusAlert` — non-blocking inline alert (not modal)
- AC-8.2.6: `ProgressIndicator`, `ProgressRing`, `ProgressSummary` — visual progress
- AC-8.2.7: `EnergyCheckInCard` — energy self-report prompt
- AC-8.2.8: `EnergyDots` — visual energy representation (1–4 dots)
- AC-8.2.9: `FrictionDots` — visual friction representation (1–4 dots)
- AC-8.2.10: `HyperfocusWarning` — modal warning during focus sessions
- AC-8.2.11: `TaskCard` — task display card with all ND metadata
- AC-8.2.12: `SkeletonLoader` — loading placeholder for async content

#### FR-8.3: Accessibility
**Priority:** Must  
**Description:** Full accessibility stack.  
**Acceptance Criteria:**
- AC-8.3.1: Dynamic Type support throughout
- AC-8.3.2: VoiceOver labels on all interactive elements
- AC-8.3.3: Dyslexia-friendly typography uses system Dynamic Type until
  authoritative licensed custom fonts, correct bundle registration, and a full
  accessibility/device test matrix are available
- AC-8.3.4: Minimum 44pt touch targets (60pt when `largeTouchTargets` enabled)
- AC-8.3.5: Reduce Motion support via environment value and system setting
- AC-8.3.6: High contrast and color-blind safe palette
- AC-8.3.7: ErrorBanner with VoiceOver announcement
- AC-8.3.8: Resume banner with VoiceOver announcement

**Implementation status (2026-07-24):** semantic Dynamic Type and multiple
accessibility labels/touch-target fixes are present in source. Full VoiceOver,
Switch Control, Dynamic Type, Reduce Motion, Increase Contrast, localization,
contrast, and physical-device coverage remains an exit gate; “full
accessibility stack” is not a verified current-state claim.

#### FR-8.4: Density-Driven UI
**Priority:** Must  
**Description:** UI adapts to cognitive capacity.  
**Acceptance Criteria:**
- AC-8.4.1: Survival mode (energy 1): single task, no lists, one primary button, minimal text
- AC-8.4.2: Low mode (energy 2): 3–5 tasks, no details, large buttons, summary only
- AC-8.4.3: Functional mode (energy 3): full lists, normal density, all features accessible
- AC-8.4.4: High mode (energy 4–5): full detail, analytics, history, suggestions, all settings
- AC-8.4.5: Density auto-calculated from energy but manually overridable (pinned)

### 6.9 Context Domain: Interruptions & Transitions

#### FR-9.1: Interruption Context (InterruptionContext)
**Priority:** Must  
**Description:** Records what the user was doing before an interruption.  
**Acceptance Criteria:**
- AC-9.1.1: `recordActivity(itemID:contextLabel:)` stores activity label, item ID, and timestamp in `UserDefaults`
- AC-9.1.2: `currentActivity()` returns the activity if within 15 minutes
- AC-9.1.3: `clear()` removes recorded activity
- AC-9.1.4: Used by WatchConnectivityManager to send `pendingRecovery` to Watch

#### FR-9.2: Resume Banner
**Priority:** Must  
**Description:** Gentle prompt to resume previous activity when returning to app.  
**Acceptance Criteria:**
- AC-9.2.1: Shows when app returns from background and `InterruptionContext.currentActivity()` is within 15 minutes
- AC-9.2.2: Displays: "You were working on [label]. Resume?"
- AC-9.2.3: Resume button and dismiss button
- AC-9.2.4: Auto-dismisses after 10 seconds
- AC-9.2.5: VoiceOver accessible with labels and hints

#### FR-9.3: Brain Dump (BrainDumpView)
**Priority:** Must  
**Description:** Low-EF rapid task capture.  
**Acceptance Criteria:**
- AC-9.3.1: Text input area — one thought per line, no decisions required
- AC-9.3.2: Voice input via `SFSpeechRecognizer` (on-device, iOS only)
- AC-9.3.3: Each line becomes an unscheduled `InboxItem` on save
- AC-9.3.4: `SFSpeechRecognizer.isAvailable` check on appear and in button action
- AC-9.3.5: Error banner if voice input unavailable

### 6.10 Error Handling Domain

#### FR-10.1: Error Banner (ErrorBanner)
**Priority:** Must  
**Description:** Non-blocking error surfacing for all async operations.  
**Acceptance Criteria:**
- AC-10.1.1: Appears at top of screen, auto-dismisses after 3 seconds
- AC-10.1.2: Shows error message with warning icon and dismiss button
- AC-10.1.3: Animated entry/exit (move + opacity)
- AC-10.1.4: VoiceOver accessible with `accessibilityLabel` and `accessibilityHint`
- AC-10.1.5: Used by all `modelContext.save()` failures
- AC-10.1.6: Used by import failures, AI enrichment failures, and watch sync failures

#### FR-10.2: Save Error Handling
**Priority:** Must  
**Description:** All persistent saves must be explicit and error-surfaced.  
**Acceptance Criteria:**
- AC-10.2.1: Zero `try? modelContext.save()` in app-layer code
- AC-10.2.2: All saves use `do { try modelContext.save() } catch { ErrorBannerController.shared.show(...) }`
- AC-10.2.3: `try?` is acceptable in Watch code (no UI for error display)
- AC-10.2.4: `try?` in I/O paths (fetch, decode, parse) must log via `logger.error()` or `logger.warning()`

---

## 7. User Stories

### US-1: First Launch
**As a** new user with AuDHD and low energy  
**I want** to set up the app without being overwhelmed  
**So that** I can start using it today without abandoning it

**Acceptance Criteria:**
- App detects first launch and shows `CognitiveStateSelector`
- Step 1: Pick current energy level (1–4) with visual energy dots
- Step 2: Optional profile setup (name, neurotypes, role)
- Step 3: Optional onboarding (can be skipped)
- Survival/Low energy users skip onboarding entirely
- All settings have sensible defaults
- No account creation required
- No internet connection required

### US-2: Daily Morning Setup
**As a** user with inconsistent routines  
**I want** the app to help me build my day based on today's energy  
**So that** I don't have to decide what to do from scratch every morning

**Acceptance Criteria:**
- App shows morning setup wizard on first launch of each day
- Wizard suggests blocks based on energy and scheduled items
- Wizard suggests top 3 tasks by actionability
- I can dismiss it and it won't show again until tomorrow
- "Save today's capacity" persists my selected energy without changing tasks
  or blocks

### US-3: During a Focus Session
**As a** user prone to hyperfocus and interruptions  
**I want** a protected timer with gentle warnings and interruption logging  
**So that** I can complete my 2–4 hour productive window without losing track of time

**Acceptance Criteria:**
- I select a task and start a focus session
- Timer counts down with visual progress
- At 75% elapsed, a hyperfocus warning appears (if enabled)
- At planned end, a notification prompts me to stop
- If I get interrupted, I tap "I got interrupted" and pick a reason
- Interruptions are logged for later review
- Session history shows patterns over time
- Suggested duration adapts based on my historical data

### US-4: Low Energy Day (Survival Mode)
**As a** user in survival mode (energy 1/5)  
**I want** the app to show only the absolute minimum  
**So that** I don't feel overwhelmed by a long task list I can't act on

**Acceptance Criteria:**
- App detects survival mode from energy level or manual pin
- Shows only one task — the most critical and lowest-friction task
- Large buttons, minimal text, no lists
- I can still access the full app if needed (not locked out)
- Energy check-in prompt is gentle, not demanding

### US-5: Household Coordination
**As a** partner/caregiver of someone with AuDHD  
**I want** to see their energy level and assigned tasks  
**So that** I can support them without being intrusive

**Acceptance Criteria:**
- Household view shows all profiles with energy levels
- I can assign tasks to my partner's profile
- I can see which tasks need a body double
- I can see their completion progress
- Notifications respect their privacy settings (task titles redacted)

### US-6: Brain Dump During Overwhelm
**As a** user with racing thoughts and low EF  
**I want** to dump all my thoughts quickly without organizing them  
**So that** I don't lose ideas and can process them later when I have capacity

**Acceptance Criteria:**
- Brain dump button is accessible from any screen
- One line per thought, no categorization required
- Voice input works when I can't type
- Each line becomes an unscheduled inbox item
- I can review and organize inbox items later

### US-7: Data Privacy and Control
**As a** user with privacy concerns and a $0 budget  
**I want** to know my data stays on my device unless I explicitly choose otherwise  
**So that** I don't worry about surveillance, costs, or data loss

**Acceptance Criteria:**
- All core data is local-only by default
- AI enrichment is off by default and opt-in
- API keys are stored in Keychain with biometric protection when available
- "Local AI only" mode hides all paid providers
- Export is encrypted with AES-256-GCM when password is provided
- Notifications redact task titles from lock screen by default
- No analytics, no tracking, no third-party SDKs

### US-8: Task Dependencies
**As a** user with complex projects  
**I want** to mark tasks as blocked by other tasks  
**So that** I don't see tasks I can't start yet

**Acceptance Criteria:**
- I can create a "blocks" or "follows" relationship between two tasks
- The blocked task shows "Blocked by [Task X]" in detail view
- The blocking task shows "Blocks [Task Y]" in detail view
- Blocked tasks are visually distinguished in the backlog
- Future: filter out blocked tasks from "For Now" view

---

## 8. Technical Architecture

### 8.1 Stack

| Layer | Technology | Rationale |
|-------|-----------|-----------|
| UI | SwiftUI | Declarative, reactive, native accessibility; currently Swift 5 language mode with staged concurrency settings |
| Data | SwiftData | Native Apple framework, `@Query` macro, no external dependencies |
| Persistence | File-backed local SwiftData store | Local-only, migration-versioned, no network required |
| Future sync | CloudKit (not implemented) | Product direction requiring a separate merge, migration, recovery, entitlement, and multi-device program |
| Notifications | UNUserNotificationCenter | Native, reliable, per-profile customization |
| Location | CoreLocation | On-demand, only for outdoor blocks, `kCLLocationAccuracyKilometer` |
| Weather | WeatherKit | On-device, privacy-preserving, no API key |
| Speech | SFSpeechRecognizer | Native dictation path; runtime on-device/network behavior must be verified and disclosed |
| Crypto | CryptoKit | AES-256-GCM for export encryption, no external crypto library |
| Keychain | Security framework | Secret storage; accessibility and access-control behavior verified per credential flow |
| Watch | WatchConnectivity + shared versioned contract | Full phone snapshots, durable Watch mutation outbox, acknowledgements, App Group-backed Watch/widget presentation |
| AI | AITaskEnricher protocol | Pluggable, 9 providers, off by default |

### 8.2 Architecture Pattern

**No MVVM.** Views use `@Query` directly. Managers are `@MainActor` singletons. `ModelContext` is injected after container initialization.

```
AuGendaApp (@main)
└── WindowGroup
    └── RootView (injects modelContext into managers)
        └── ContentView (tab/sidebar shell)
            ├── TodayView (@Query AgendaItem)
            ├── TaskBacklogView (@Query AgendaTask)
            ├── BlockView (@Query Block)
            ├── HouseholdView (@Query Profile)
            ├── SmartSuggestView (@Query AgendaTask)
            └── FocusSessionView (@Query FocusSession)
```

### 8.3 Data Model

**17 SwiftData models** in the main local schema:

| Domain | Models |
|--------|--------|
| Scheduling | `AgendaItem`, `SubTask` |
| Task | `AgendaTask`, `TaskStep` |
| Block | `Block`, `BlockTask`, `BundleTemplate`, `BundleTemplateItem`, `AttachedBundle`, `AttachedBundleItem` |
| Profile | `Profile`, `ProfilePreferences` |
| Focus | `FocusSession` |
| Relationship | `TaskRelationship` |
| Note | `Note` |
| Legacy | `UserPreferences` (deprecated) |
| Inbox | `InboxItem` |

**Schema versioning:** `VersionedSchema` v1 and v2 with `MigrationPlan`. Lightweight migration between versions.

The main `ModelConfiguration` is file-backed and does not set
`cloudKitDatabase`. CloudKit-compatible model shapes and comments are not
evidence that cloud sync is active.

### 8.4 Singleton Managers

| Manager | Responsibility | Threading |
|---------|---------------|-----------|
| `NotificationManager` | Notification scheduling, focus session state | `@MainActor` + `nonisolated objectWillChange` |
| `BlockManager` | Block activation, weather fetch, location | `@MainActor` + `nonisolated objectWillChange` |
| `ActiveProfileManager` | Profile selection, preferences exposure | `@MainActor` + `nonisolated objectWillChange` |
| `WatchConnectivityManager` | Watch sync, bidirectional messaging | `@MainActor` + `nonisolated objectWillChange` |

### 8.5 Design System

| File | Contents |
|------|----------|
| `DesignTokens.swift` | Color, spacing, typography, border, shadow, animation, layout, accessibility |
| `AuDHDComponents.swift` | Cards, buttons, inputs, option cards, alerts, adaptive colors |
| `AuDHDProgressComponents.swift` | Progress indicators, energy check-in, skeleton loader |
| `AuDHDLayout.swift` | Screen containers, sections, navigation, tabs, sidebar, empty states |
| `AuDHDNDComponents.swift` | Interruption context, task cards, energy dots, hyperfocus warnings |

### 8.6 Security Architecture

| Layer | Implementation |
|-------|---------------|
| API keys | Keychain; exact accessibility/access-control behavior must be verified per flow and device state |
| OAuth tokens | Separate Keychain service + PKCE verifier; expiry/refresh and provider registration remain release gates |
| Export encryption | AES-256-GCM with versioned PBKDF2-HMAC-SHA256 password derivation (210,000 iterations); legacy SHA-256 envelopes are import-only |
| Notifications | `strictPrivacy` default true — redacts content from lock screen |
| Local data | SQLite with SwiftData, no custom encryption at rest (Apple-encrypted on device) |
| Cloud data | None in the current production configuration; CloudKit is future scope |
| Analytics | None — zero external SDKs |
| Build validation | OAuth validation script exists; release gating must invoke it and validate effective build settings |

---

## 9. Non-Functional Requirements

### 9.1 Performance

- **Cold launch:** < 2 seconds on iPhone 14
- **Warm launch:** < 1 second
- **Task list scroll:** 60fps with 1000+ tasks
- **Focus session timer:** No drift > 1 second over 60 minutes
- **Brain dump voice input:** < 500ms from tap to recording start

### 9.2 Reliability

- **Data loss:** Zero tolerance. All saves are explicit `do/catch`. Schema migrations are mandatory.
- **Crash:** Zero tolerance for production crashes. `fatalError` eliminated from app-layer code.
- **Offline:** Core functionality works entirely offline. AI enrichment requires network (except Apple Foundation + Ollama).
- **Future sync:** Any future CloudKit feature must be optional, user-controlled,
  failure-atomic, and unable to delete local data on sync failure.

These are release requirements, not measured current-state guarantees. Persistence
failure handling, destructive flows, migration fixtures, and every mutation path
must pass the release matrix before “zero data loss” is asserted.

### 9.3 Accessibility

- **WCAG 2.1 AA equivalent:** Color contrast, touch targets, text scaling, motion reduction
- **Dynamic Type:** All text scales with system settings
- **VoiceOver:** All interactive elements have labels and hints
- **Dyslexia support:** System Dynamic Type now; verified, licensed custom
  legibility fonts remain future scope
- **Motor accessibility:** At least 44pt targets and compatibility with system
  accessibility sizing; custom 60pt/UI-scale modes remain requirements until
  fully wired and verified
- **Cognitive accessibility:** Progressive disclosure, consistent patterns, no sudden changes

Every item above is a target. No 100% accessibility claim is accepted without
the VoiceOver, Switch Control, Dynamic Type, motion, contrast, localization, and
physical-device evidence defined in §16.1.

### 9.4 Compatibility

**Product compatibility goal:** iOS/iPadOS 17+, macOS 14+, watchOS 10+, subject
to an explicit back-deployment implementation and test program.

**Currently configured minimums (2026-07-24):**

- **iOS/iPadOS:** 26.5
- **macOS:** 26.3
- **watchOS:** 26.5

The project therefore does not currently meet the broader compatibility goal.
No device-family support claim (for example iPhone 12, iPad Air 4, or Watch
Series 7) is verified until the deployment target is compatible and the device
matrix passes.

### 9.5 Battery & Resource

- **Location:** Only requested when outdoor block is activated, `kCLLocationAccuracyKilometer` (low power)
- **WeatherKit:** Only one fetch per outdoor block activation
- **Background:** No main-app background mode is currently declared; local
  notifications are delivered by the system and Watch transport behavior must
  be validated under suspension/background conditions
- **AI:** No persistent AI connections. One-shot API calls only when user explicitly triggers enrichment.
- **Watch:** Bounded full snapshots and event mutations; no continuous polling

---

## 10. Security & Privacy Requirements

### 10.1 Data Classification

| Data Type | Classification | Storage |
|-----------|---------------|---------|
| Tasks, agenda items, notes | Private | Local file-backed SwiftData store |
| Profile info, preferences | Private | Local file-backed SwiftData store |
| API keys (AI providers) | Secret | Keychain; access-control behavior depends on the configured credential flow |
| OAuth tokens | Secret | Keychain (separate service) |
| Export files | Confidential | User-controlled (encrypted when password set) |
| AI usage ledger | Private | Local file |
| Speech transcripts | Private | Apple speech-recognition path; on-device/network behavior must be verified and disclosed |
| Location | Sensitive | Requested on demand and provided to Apple WeatherKit for the requested forecast; not persisted by AuGenda |

### 10.2 Privacy Requirements

- **No third-party analytics:** Zero external SDKs for tracking or analytics.
- **No data monetization:** No ads, no data sales, no user profiling for commercial purposes.
- **AI opt-in:** AI enrichment is off by default. Per-task opt-out available.
- **Notification privacy:** `strictPrivacy` defaults to true. Task titles never appear on lock screen.
- **Export control:** User can export their own data. No automatic cloud backup without explicit opt-in.
- **OAuth release configuration:** valid provider-issued client settings and
  callback schemes must replace placeholders before shipping.

### 10.3 Compliance

- **GDPR:** User is data controller (local data). Export/erase functionality available.
- **Apple privacy release gate:** reconcile `Info.plist`, privacy manifests, and
  the App Store privacy questionnaire against all enabled behavior and signed
  targets. The current source declares no tracking; that declaration still
  requires release review.
- **App Store positioning goal:** no restricted content, gambling, or medical
  claims; final category and metadata require App Review/legal validation.

---

## 11. AI Strategy

### 11.1 Philosophy

AI in AuGenda is **optional enrichment, not core functionality**. The app works perfectly without AI. AI is a convenience layer for users who want task breakdown suggestions, context-aware tips, or language style adjustments.

### 11.2 Provider Architecture

| Provider | Type | Cost | Privacy |
|----------|------|------|---------|
| **appleFoundation** | On-device | Free | Highest (local) |
| **ollama** | Self-hosted | Free | Highest (local) |
| **claude** | API | Paid | High (Anthropic) |
| **openai** | API | Paid | Medium (OpenAI) |
| **gemini** | API | Paid | Medium (Google) |
| **deepseek** | API | Paid | Disabled pending a live release smoke test |
| **mistral** | API | Paid | Medium (Mistral) |
| **perplexity** | API | Paid | Medium (Perplexity) |
| **grok** | API | Paid | Medium (xAI) |

### 11.3 Enrichment Use Cases

- **Task breakdown:** "Break this task into 3–5 sub-steps"
- **Context suggestions:** "You might need these items for this task"
- **Language style adjustment:** Formal → casual → playful tone
- **Time estimation:** "Based on similar tasks, this might take 45 minutes"
- **Hyperfocus risk assessment:** "This task has high interest — consider a shorter focus session"

### 11.4 Cost Control

- Monthly budget picker: $0 (free/local only), $5, $10, $20, $50
- `canEnrich()` gate enforced at all entry points
- Usage tracked per provider, per month
- `AIUsageLedger` shows remaining budget in settings

---

## 12. Multi-Platform Support

This section defines the intended product surface. Configured targets and
source branches do not establish feature parity; each platform still requires
the dated release matrix in §16.1.

### 12.1 iPhone (Primary)

- Full feature set
- Tab-based navigation
- Bottom sheet for brain dump
- WatchConnectivity host
- Camera for avatar photos (ContactsUI)

### 12.2 iPad

- Full feature set
- Sidebar navigation (larger screen)
- Split-view support for task detail
- Multi-window support (future)

### 12.3 Mac (Designed for iPad)

- Full feature set
- Sidebar navigation
- Keyboard shortcuts (⌘1–⌘5 for tabs)
- Menu bar integration
- No camera avatar (file picker instead)

### 12.4 Apple Watch (Companion)

- Phone is the durable task source of truth
- Receives versioned, active-profile-scoped full snapshots through
  WatchConnectivity
- Persists the latest presentation snapshot and mutation outbox in the Watch
  App Group shared with the widget
- Shows agenda/backlog context, energy, density, focus, and recovery state
- Queues complete, snooze, energy, and capture mutations until the phone
  acknowledges them
- Widget/complication reads the same fresh presentation snapshot

**Verification boundary:** the source contract and test seams exist, but App
Group provisioning, paired-device transport, offline convergence, complication
refresh, freshness redaction, and cross-profile isolation remain physical-device
release gates.

---

## 13. Roadmap

### 13.1 v1.0 — Active Release Candidate (Not Shipped)

The working tree contains implementation for the following areas, but this list
is an inventory rather than a completion claim:

- Core task/agenda/backlog flows and deterministic difficulty ranking
- Focus sessions and interruption tracking
- Blocks, multi-profile household, brain dump, and smart suggestions
- Export/import, encrypted export envelopes, and v1-to-v2 schema migration
- Optional AI-provider architecture and privacy/cost controls
- Watch app, shared snapshot/outbox contract, and Watch widget
- Semantic system Dynamic Type and accessibility remediation

Release status remains **not verified**. Required gates include the full current
build/test matrix, migration and mutation failure-path coverage, signed Release
archives, OAuth/provider configuration, WeatherKit/App Group provisioning,
paired-device Watch QA, privacy review, accessibility/device QA, and measured
performance/size.

### 13.2 v1.1 — Next Sprint

- [x] Task dependency filtering in "For Now" view (hide blocked tasks)
- [ ] Full note search and independent note list
- [ ] Deep adaptive CognitiveProfile (energy-by-hour, completion accuracy)
- [ ] Credentialed integration tests for AI enrichers and OAuth; paired-device
      integration tests for Watch sync
- [ ] Implement and verify the recurrence engine (daily, weekly, weekdays,
      monthly, biweekly, and future custom rules)
- [ ] App Store submission after the release gates above; CloudKit is not a v1
      prerequisite unless separately implemented

### 13.3 v1.2 — Medium Term

- [ ] iPhone/iPad Home Screen and Lock Screen widgets; the current widget target
      is Watch-only
- [ ] Shortcuts app integration (Siri)
- [ ] Time tracking per task (actual vs estimated)
- [ ] Energy pattern visualization (charts)
- [ ] Shared blocks (household coordination)
- [ ] Custom block types
- [ ] Bulk task operations (multi-select, batch assign)

### 13.4 v2.0 — Long Term

- [ ] Full CloudKit sync (multi-device)
- [ ] Collaborative households (real-time sync)
- [ ] Medication/reminder integration
- [ ] Sleep tracking correlation (HealthKit)
- [ ] Advanced analytics dashboard
- [ ] Custom difficulty dimensions (user-defined axes)
- [ ] Community block templates (shareable routines)

---

## 14. Success Metrics

### 14.1 Technical Metrics

| Metric | Target | Latest verified evidence |
|--------|--------|---------|
| Production line coverage | >80% | 7.5475% (2,942 / 38,980 lines) on the 2026-07-24 post-remediation macOS unit result |
| Production crashes | 0 | Not measurable before release without a defined reporting process |
| Data loss incidents | 0 | No release population; failure-path verification still in progress |
| Build time | <30s | Current tree not measured under a controlled configuration |
| Release install/download size | <50MB | Not measured; a prior Debug bundle is not release-size evidence |
| Memory usage | <100MB | Current tree not measured on the supported device matrix |

### 14.2 User Metrics (Post-Launch)

| Metric | Target |
|--------|--------|
| Day 1 retention | >60% |
| Day 7 retention | >30% |
| Day 30 retention | >15% |
| Daily active users (DAU) | >50% of install base |
| Focus session completion rate | >70% |
| Energy check-in frequency | >3x/week |
| Brain dump usage | >1x/week |
| Task completion rate | >50% |
| App Store rating | >4.5 stars |
| Support tickets | <1 per 100 users |

### 14.3 Accessibility Metrics

| Metric | Target |
|--------|--------|
| VoiceOver compatibility | 100% of interactive elements |
| Dynamic Type support | 100% of text elements |
| Touch target compliance | 100% ≥44pt |
| Reduce Motion support | 100% of animations |
| System Dynamic Type | 100% of user-visible text |
| Custom dyslexia-font option | Future: 100% only after asset/license/bundle/device verification |

These are targets. None is recorded as a current 100% pass without the dated
manual and automated evidence in §16.1.

---

## 15. Glossary

| Term | Definition |
|------|------------|
| **AuADHD** | Autism + ADHD comorbidity |
| **Body double** | A person whose presence helps another person focus and complete tasks |
| **Density mode** | UI complexity level: Survival, Low, Functional, High |
| **Difficulty Engine** | Six-axis deterministic ranking algorithm (friction, energy, sensory, social, initiation, interest) |
| **EF** | Executive Function — the cognitive skills that control and regulate behavior |
| **Friction** | How hard it is to start a task (1–4) |
| **hEDS** | Hypermobile Ehlers-Danlos Syndrome — a connective tissue disorder |
| **Hyperfocus** | Intense, sustained concentration that can last hours and disrupt schedules |
| **Initiation cost** | The "warming up" required before a task can be started (0–3) |
| **ND** | Neurodivergent — brains that function differently from the societal standard |
| **ndPriorityScore** | AuGenda's actionability ranking: higher = more worth doing right now |
| **PDA** | Pathological Demand Avoidance — a profile where demands trigger anxiety and resistance |
| **Sensory load** | How much sensory input a task generates (0–3) |
| **Social load** | How much social interaction a task requires (0–3) |
| **Survival mode** | The lowest energy state where only the absolute minimum is shown |

---

## 16. Appendices

### 16.1 Dated Verification and Audit Evidence

The current authoritative audit set is:
`audits/2026-07-24-code-augenda-all-domain/`. Its baseline verification was
captured before the remediation edits now in the working tree.

**Verified on 2026-07-24 for that pre-remediation snapshot:**

- macOS main unit suite: **46 passed, 0 failed, 0 skipped**;
- production line coverage in that macOS result:
  **4,161 / 35,484 lines (11.7264%)**;
- unsigned iOS Simulator unit suite: **43 passed, 3 failed**, with all three
  failures caused by unsigned Keychain entitlement errors;
- focused signed iOS Keychain rerun: **5 passed, 0 failed**;
- Watch/widget code compiled as dependencies of the signed main scheme; the
  standalone Watch flow was blocked by unavailable CoreSimulator services.

The test suite and production code have changed since that baseline. Therefore
these counts are **historical evidence, not current-tree pass or coverage
claims**.

**Verified on 2026-07-24 for the post-remediation working tree:**

- macOS main unit suite: **85 passed, 0 failed, 0 skipped**;
- production line coverage in that result:
  **2,942 / 38,980 lines (7.5475%)** for `AuGenda.app`;
- unsigned generic iOS Release build succeeded, including embedded Watch and
  widget dependencies;
- unsigned generic watchOS Release `build-for-testing` succeeded with
  testability enabled for the test product;
- Release package inspection found none of the former prompt, README, script,
  or invalid-font resources;
- Swift parse, plist/entitlement/privacy-manifest, workflow YAML, project-file,
  shell syntax, asset JSON, diff whitespace, and targeted secret checks passed.

**Still unverified as of 2026-07-24:**

- simulator and physical-device UI journeys across iPhone, iPad, Mac, and
  Watch, including the Watch unit/UI runners;
- signed Release archives, effective entitlements, validation/notarization,
  release install/download size, memory, and performance;
- paired physical iPhone/Watch behavior and App Group provisioning;
- full VoiceOver, Switch Control, Dynamic Type, Reduce Motion, Increase
  Contrast, localization, and physical-device accessibility;
- release Google OAuth, WeatherKit, Ollama, and external AI credentials;
- App Store privacy questionnaire and final legal/release review.

Historical grade-labelled audit reports may be useful provenance, but their
grades and “production-ready” wording are not current release evidence.

### 16.2 Remediation Prompt

- `KIMI-CODE-PROMPT.md` — Full phased remediation plan for Kimi Code execution

### 16.3 Developer Documentation

- `DEVELOPER_DOCUMENTATION.md` — Build setup, architecture, quirks, pre-ship checklist
- `GETTING_STARTED.md` — Developer onboarding guide

### 16.4 Build Commands

```bash
# iOS Simulator build
cd /Users/arthur/Development/AuGenda
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project AuGenda.xcodeproj -scheme AuGenda \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build

# macOS build
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project AuGenda.xcodeproj -scheme AuGenda \
  -destination 'platform=macOS' build

# Run main unit tests
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project AuGenda.xcodeproj -scheme AuGenda \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:AuGendaTests test

# Validate OAuth placeholder
bash AuGenda/Scripts/validate-oauth.sh
```

---

*End of PRD.*
*Document maintained by the Daimon workspace agent.*
*Last updated: 2026-07-24*

### Mac local store isolation (2026-09-12)

New native Mac stores use `Application Support/ensdev.AuGenda/AuGenda.store`
with CloudKit explicitly disabled. Before using that location, startup checks
an existing legacy `Application Support/default.store` using read-only model
metadata. Recognized AuGenda stores continue at their existing path; unrelated
apps' stores are left untouched. Unreadable legacy metadata still produces the
recovery surface rather than silently creating an empty account. Existing
dedicated stores take precedence. iOS store placement is unchanged.


## UI clarity update — 2026-10-15

- Inbox has a labeled, profile-scoped pending count in the sidebar and Tasks toolbar. Inbox has Close; capture review has Back to Inbox separately from Discard.
- Today uses the same title as navigation, labels its scheduled list “Scheduled today,” and calls the near-term empty state “Nothing coming up soon.” Scheduled AgendaItem records and the AgendaTask list remain separate; Tasks explains where scheduled items live. No persistence migration is involved.
- Blocks is the consistent section name on Today. Energy matching uses “Matches energy,” priority ranking uses “Suggested order,” and sorting uses a menu to reduce competing controls.
- New tasks start with a title and optional-details toggle; editing opens details. Hidden fields retain their existing defaults and values. Review labels collapsed difficulty Optional, or Suggested when AI suggestions exist; expanded scores are estimates.
- Focus duration can be adjusted locally for the session (5–480 minutes), including accepting the historical suggestion, without changing profile defaults. Settings explains the Today layout in user-facing terms and distinguishes AI setup needed from enabled with a provider.
- Validation (2026-10-15): [GitHub CI run 38787188369](https://github.com/8s6rdrj8r9-lang/AuGenda/actions/runs/38787188369) passed for commit `5f7f935a2d6f5dc2d0e26f4938ac62a35205f881`: macOS unit tests, 20.36% app line coverage (7% floor), iOS onboarding UI smoke test, iOS Release build, Watch app/test/widget build, six Watch unit tests, Watch launch UI smoke test, and package-content validation. Swift syntax and whitespace checks also passed locally. The changed screens still need a visual walkthrough; these automated checks do not establish usability or accessibility compliance. The installed local app has not been replaced.
