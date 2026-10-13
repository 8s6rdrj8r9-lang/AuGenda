# AuGenda — Feature Spec

> Scope: the beta launch spec — capture→inbox→review pipeline, AI-enrichment
> layer, six-axis difficulty model, configurable capacity check-ins, and the
> Gemini OAuth login path. Living document — keep in sync with the code.
>
> Last updated: 2026-09-12

AuGenda is an iOS/macOS agenda app for AuDHD brains. Everything below is built
around the same posture: **calm, glanceable, opt-in, no demands, no surprises.**

---

## 1. Brain dump → Inbox pipeline

### 1.1 Overview

The core capture loop: brain dump → inbox (unprocessed) → mandatory review →
AgendaTask. Nothing auto-files. The user always confirms.

### 1.2 Capture (`BrainDumpView`)

- **Entry points:** pencil button in the HomeDashboard toolbar; existing "Brain
  dump" button in the TaskBacklogView.
- **Input:** multi-line TextEditor (one thought per line). Each line becomes
  one `InboxItem`.
- **Voice (iOS):** "Dictate" button uses `SFSpeechRecognizer` with
  `requiresOnDeviceRecognition = true` — audio never leaves the device. Appends
  transcribed text to the editor as a new line on completion. Degrades silently
  if the user denies speech permission.
- **Submit:** "Send to inbox" → each non-empty line creates an `InboxItem`
  with `state = .unprocessed`. Nothing becomes a task yet.

### 1.3 Inbox banner (HomeDashboard)

- `InboxReadyBanner` appears above the Primary Action Zone when there are
  unprocessed items and density is not `.survival` (survival mode shows nothing
  extra).
- Badge dot on the brain dump toolbar button when the inbox is non-empty.
- Tapping the banner opens `InboxView` as a sheet.

### 1.4 Review (`InboxView` + `InboxItemReviewSheet`)

- `InboxView` lists all `.unprocessed` items with timestamps and source icons.
- Tapping an item opens `InboxItemReviewSheet`.
- **Fields:** title (pre-filled from AI suggestion or raw capture), friction,
  energy, initiation cost, context tag. Difficulty band preview computed live.
- **AI enrichment:** if AI is enabled and a provider is set, "Suggest structure"
  sends the raw capture text to the active provider and fills in the fields for
  review. User sees every suggestion before it's applied.
- **Confirm:** "Add to tasks" creates an `AgendaTask` from the reviewed fields,
  sets `InboxItem.state = .organized`, links via `resolvedTaskID`.
- **Discard:** "Discard" sets `state = .archived` — item is gone from the review
  queue.
- Swipe-to-delete on the list also archives.

### 1.5 `InboxItem` model

Stored in SwiftData; CloudKit-compatible (all properties have defaults or are optional).

| Field | Type | Notes |
|---|---|---|
| `clientID` | UUID | identity |
| `rawCapture` | String | verbatim capture text |
| `sourceRaw` | String | `textCapture` or `voiceCapture` |
| `stateRaw` | String | `unprocessed`, `organized`, `archived` |
| `aiSuggested*` | Int?/String? | AI-filled per-field, stored for re-entry |
| `resolvedTaskID` | UUID? | set when organized → AgendaTask |
| `assignedToProfileID` | UUID? | inherited from active profile at capture time |

---

## 2. Task editing

Existing tasks are fully editable — not just brain-dump → refine, but any field
at any time.

- **Entry point:** `TaskDetailView` → pencil button (top bar) → `showEdit` sheet.
- **Implementation:** the editor reuses `AddTaskView`, passed an `editingTask:`
  parameter, so the create and edit paths share one form (single source of truth
  for validation and field layout).
- All task metadata is editable: title, description, the six difficulty axes,
  time estimate, context tag, best-time-of-day, and the per-task `excludeFromAI`
  opt-out.

---

## 2. AI enrichment

### 2.1 Posture (unchanged from the original spec)

- **OFF by default.** Nothing leaves the device until the user has enabled AI,
  picked a provider, and either tapped **Enrich** or turned on auto-enrich
  (itself off by default).
- **API keys live in the Keychain** (`KeychainStore`), never `@AppStorage`,
  never iCloud-synced.
- **Per-task opt-out** via `excludeFromAI: Bool`.
- Each cloud provider's first enable shows a disclosure of what is sent to whom;
  DeepSeek adds a PRC-jurisdiction warning.

### 2.2 Enrich an *existing* task

Enrichment is available on any already-made task, not only at creation.

- **Gate** (`TaskDetailView.canEnrich`): `aiEnabled && showEnrichButtons &&
  !task.excludeFromAI && activeProvider != nil`.
- **Default Engine:** `apple-foundation` (Apple Foundation Models, on-device). Zero cloud egress, 0-cost token accounting, private by default.
- **ChatGPT Backup:** If `apple-foundation` is unavailable or trips safety filters, and user has enabled backup fallback, automatically route to `openai` (ChatGPT) with user confirmation.
- **Siri AI Delegation:** Exposes `CaptureBrainDumpIntent`, `EnrichTaskIntent`, and `GetTopFocusTaskIntent` to Siri AI and macOS 27 Spotlight.
- **Flow:** "Enrich with AI" (sparkles) → `runEnrichment()` → `pendingEnrichment`
  → **`EnrichmentPreviewSheet`** (user reviews the proposal) → `applyEnrichment()`
  writes the fields onto the task. The user always previews before anything is
  applied — enrichment never silently overwrites.
- **Failure** surfaces as a calm "Enrichment failed" alert with a short,
  mapped message (see §2.4) — never a raw error dump.

### 2.3 Provider matrix

Single source of truth: the `AIProvider` enum. The settings picker and the
`AIEnrichmentManager` adapter lookup both walk it.

| Provider | `rawValue` | Privacy tier | API key | Default model | Default / Role |
|---|---|---|---|---|---|
| Apple (on device) | `apple-foundation` | On device | no | `apple-foundation-3b` | **Default Primary** |
| ChatGPT (OpenAI) | `openai` | Cloud | yes | `gpt-4o` | **Backup Fallback** |
| Claude (Anthropic) | `claude` | Cloud | yes | `claude-sonnet-4-5` | Optional |
| Gemini (Google) | `gemini` | Cloud | yes¹ | `gemini-2.5-flash` | Optional |
| DeepSeek | `deepseek` | Cloud | yes | `deepseek-chat` | Optional |
| Mistral (EU) | `mistral` | Cloud | yes | `mistral-large-latest` | Optional |
| Ollama (self-hosted) | `ollama` | Self-hosted | no | `llama3.1:8b` | Optional |
| Perplexity | `perplexity` | Cloud | yes | `sonar-pro` | Advanced |
| Grok (xAI) | `grok` | Cloud | yes | `grok-3` | Advanced |

¹ Gemini accepts **either** an API key **or** Google OAuth sign-in (see §3).

Privacy tiers (`PrivacyTier`): `onDevice` (Apple), `selfHosted` (Ollama),
`cloud` (everything else) — surfaced as a chip beside each provider. Advanced
providers (Perplexity, Grok) hide behind an "Advanced providers" disclosure.

Each adapter conforms to `AITaskEnricher` (`isAvailable()` + `enrich(context:)`)
and returns a shared `TaskEnrichment`. Token usage is recorded in
`AIUsageLedger`; on-device runs report 0 tokens (no cost, ever).


### 2.4 Error handling

`AIEnricherError` maps every failure to a short, actionable, blame-free message.
Apple Foundation Models failures specifically are translated (never dumped):

- `onDeviceModelUnavailable` — model assets not ready (the common Simulator
  case; nested `ModelManagerError 1026`). Suggests a real device or a cloud
  provider.
- `onDeviceGuardrailTripped` — Apple's safety classifier blocked the task
  (often a false positive). Suggests rephrasing or a cloud provider.
- `onDeviceModelFailed` — generic on-device failure.

Mapping matches on **stable nested-error markers** (`ModelManager`,
`SensitiveContentAnalysisML`) rather than `GenerationError` enum cases, which
have moved across SDK seeds. Model-availability is checked before guardrail,
because a Simulator asset failure surfaces *through* the guardrail subsystem.

> Note: Apple Foundation Models is effectively **unavailable in the iOS
> Simulator**. Use a real device with Apple Intelligence, or a cloud provider,
> to exercise a successful on-device-style enrichment.

---

## 3. Gemini OAuth login path

Gemini can authenticate with a Google account instead of a pasted API key.

- **`OAuthCoordinator`** — generic OAuth 2.0 Authorization Code + **PKCE** flow
  via `ASWebAuthenticationSession`. No third-party SDK. Handles PKCE
  verifier/challenge, `state` validation, code→token exchange, refresh, and
  Keychain token storage (account `oauth-{provider}`, separate from API keys).
- **`GoogleOAuth`** — Google-specific config: auth/token endpoints, the
  `https://www.googleapis.com/auth/generative-language` scope, and
  `access_type=offline` + `prompt=consent` for refresh tokens.
- **Client type: iOS** (no client secret — public client). The reversed-DNS
  scheme is registered in `Info.plist` under `CFBundleURLTypes`; the redirect
  URI is `{REVERSED_CLIENT_ID}:/oauth2redirect`. One iOS client covers both the
  iOS and macOS builds (both use `ASWebAuthenticationSession` + the custom
  scheme). The "Desktop app" client type (with a secret + loopback redirect) is
  deliberately **not** used — secrets can't be kept in a shipped client.
- **`AIEnricher_Gemini`** prefers the OAuth Bearer token and falls back to the
  Keychain API key. `isAvailable()` is true if signed in **or** a key exists.
- **Settings** (`AIEnrichmentSettingsView`): a "Sign in with Google" section
  above the API-key field for Gemini, with signed-in status and sign-out. The
  button is disabled (with a banner) until a real client ID is configured.

**Operational caveats:** in OAuth-consent "Testing" mode, only listed test
users can sign in and refresh tokens expire ~weekly; users see an "unverified
app" screen until the app is verified. If `generateContent` returns 401/403 over
OAuth (sign-in OK, generation not), add an `x-goog-user-project` header.

---

## 4. Six-axis difficulty model

`DifficultyEngine` — pure, stateless projection of six task attributes into a
single **0–10 rank**, then onto the `DensityMode` filter ceiling. ND brains
don't experience difficulty as one number; one-to-five stars collapse
independent dimensions.

| Axis | Range | Meaning |
|---|---|---|
| friction | 1–4 | execution effort |
| energy | 1–4 | running cost |
| sensoryLoad | 0–3 | environmental load (noise/light/crowd) |
| socialLoad | 0–3 | synchronous-communication weight |
| initiationCost | 0–3 | first-step / dread weight |
| interest | 1–5 | intrinsic engagement (absorbs difficulty) |

Rank → **`DifficultyBand`**: `trivial` (<3), `easy` (3–4), `moderate` (5–6),
`hard` (7–8), `demanding` (9–10). Bands carry a label + plain-language
description and drive dashboard labelling and `DensityMode` filtering.

The AI enrichment layer auto-fills these six axes (plus title cleanup,
sub-tasks, time estimate, context, best-time-of-day). Per-profile axis
weighting (e.g. autism profiles weighting sensory heavier) is a noted v2.

---

## 5. Configurable capacity check-ins ("Are you overwhelmed?")

The `CognitiveStateSelector` ("how are you / I'm overwhelmed") can recur on a
schedule the user controls.

### 5.1 Frequency (`CognitiveCheckInFrequency`)

- `never` — **default**. Nothing prompts until the user opts in.
- `daily` — once per period (see 5.2).
- `everyAppLaunch` — on every cold launch.
- `everyForeground` — every return to foreground.

Persisted + gated by `CognitiveCheckInTracker`. `shouldPrompt(scenePhase:)`
encodes the rules; `record()` is written whenever a check-in is completed
(`CognitiveStateSelector.apply()`), so `daily` throttles correctly. A cold
launch counts as a foreground, so the launch check defers to
`shouldPrompt(.active)` and covers all four modes.

### 5.2 Daily sub-mode (`dailyUsesRollingWindow`, only meaningful for `daily`)

- **false (default)** — *first use of the day*: re-asks the first time the app
  is opened each calendar day (resets at midnight).
- **true** — *24-hour rolling window*: re-asks only once a full 24h has elapsed
  since the last check-in (11pm → 11pm next night).

Exposed as a Settings toggle ("Space check-ins 24h apart") that only appears
when `daily` is selected.

### 5.3 Where the choice is offered

Default is `never`, so the user is offered the choice exactly once:

- **During onboarding** — the onboarding tour's final card embeds the
  `CheckInFrequencyChooser`. Completing onboarding marks the choice "offered".
- **On a later launch** — users who declared overwhelm on first launch **skip**
  onboarding, so they never see that card. For them (and any pre-feature user),
  the standalone **`CheckInPreferenceStep`** first-launch sheet surfaces the
  same choice on the next launch, gated by `onboardingCompleted &&
  !checkInPreferenceOffered`.

Settings → Profile → Energy & Executive Function always exposes the picker for
later changes.

---

## 6. File map

| Area | Files |
|---|---|
| Enrichment core | `AITaskEnricher.swift`, `AIPersonalization.swift`, `AIUsageLedger.swift`, `KeychainStore.swift` |
| Provider adapters | `AIEnricher_AppleFoundation.swift`, `AIEnricher_Claude.swift`, `AIEnricher_OpenAI.swift`, `AIEnricher_Gemini.swift`, `AIEnricher_DeepSeek.swift`, `AIEnricher_Mistral.swift`, `AIEnricher_Ollama.swift`, `AIEnricher_Perplexity.swift`, `AIEnricher_Grok.swift`, `AIEnricher_OpenAICompatible.swift` |
| OAuth | `OAuthCoordinator.swift`, `GoogleOAuth.swift` |
| Difficulty | `DifficultyEngine.swift` |
| Check-ins | `CognitiveStateSelector.swift` (frequency, tracker, chooser, step), `OnboardingView.swift`, `AuGendaApp.swift` (first-launch routing), `ProfileViews.swift` (settings) |
| Task detail/edit/enrich | `TaskDetailView.swift`, `AddTaskView` (shared create/edit form) |
| Settings UI | `AIEnrichmentSettingsView.swift` |
| Config | `Info.plist` (`CFBundleURLTypes` for the OAuth callback) |


## Agenda reminder and recurrence guarantees (2026-09-08)

- Agenda reminders follow the assigned owner's notification privacy and style,
  regardless of the active household profile. Unassigned or unavailable owners
  receive private previews and minimal reminders.
- Refreshing notification privacy or restoring a backup preserves outstanding
  snooze deadlines, including for overdue items. Snoozes replace the original
  schedule; expired snoozes do not reinstate it.
- Completing daily, weekday, weekly, or monthly recurring tasks creates the next
  occurrence after both the completion time and current occurrence date. Early
  completion must not stop the series. Monthly dates retain the original day
  preference, clamped for shorter months. Generation is completion-driven.

### Mac local store isolation (2026-09-12)

New native Mac stores use `Application Support/ensdev.AuGenda/AuGenda.store`
with CloudKit explicitly disabled. Before using that location, startup checks
an existing legacy `Application Support/default.store` using read-only model
metadata. Recognized AuGenda stores continue at their existing path; unrelated
apps' stores are left untouched. Unreadable legacy metadata still produces the
recovery surface rather than silently creating an empty account. Existing
dedicated stores take precedence. iOS store placement is unchanged.
