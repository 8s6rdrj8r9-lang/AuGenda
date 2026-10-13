# AuGenda Governance Audit Report v2 — Post-Remediation Deep-Dive

**Date:** 2026-07-20 (post-remediation)  
**Auditor:** Kimi (Agent `main`)  
**Scope:** Full AuGenda SwiftUI codebase (43 `.swift` files, ~20,130 lines) against EnsDev Governance Prompt + KIMI-CODE-PROMPT remediation deliverables  
**Framework:** 5-Tier Governance (Constitution → Doctrine → Engineering → Ontology → User Context)  
**Instruction:** Read-only audit. No edits made. Cross-referenced every claim to source lines. Files read in chunks; all claims traceable to line numbers.

---

## Executive Summary

**Overall Grade: B — Significant improvement from C+, but not yet A-grade.**

The remediation addressed **all 5 Phase 1 critical blockers** (security, schema migration, macOS compile, entitlements, error handling) and **delivered all 14 Phase 2–4 deliverables** (new models, ErrorBanner, InterruptionContext resume flow, Local AI mode, tests). However, **several gaps remain** that prevent an A-grade:

- **Dead code:** `CognitiveProfile` is created but never invoked. It sits in the codebase as architectural drift.
- **Partial error handling:** `try?` still pervades fetch operations, AI adapters, JSON decoding, and Watch-layer saves — the remediation only fixed the *app-layer* `modelContext.save()` calls, leaving ~45 `try?` occurrences across the codebase.
- **Missing font bundle:** `AtkinsonHyperlegible` and `OpenDyslexic` are referenced in code (`ProfileModels.swift:137–139`) but not in `Info.plist` or the asset catalog. Dyslexia-friendly font choices are silently ignored.
- **No export encryption:** Task exports remain plaintext across all 5 formats (Markdown, JSON, CSV, YAML, plain text).
- **No biometric protection:** `KeychainStore` still uses `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` (`KeychainStore.swift:85, 99`) without `kSecAccessControlBiometryCurrentSet`.
- **Watch recovery context stubbed:** `NowView.shouldShowRecovery` is hardcoded to `false` (`NowView.swift:102`).
- **Accessibility gaps:** `ErrorBanner` and `RootView` resume banner lack VoiceOver labels.
- **Test coverage shallow:** 28 tests total (up from ~3 in v1), but critical managers (`NotificationManager`, `BlockManager`, `WatchConnectivityManager`, `ActiveProfileManager`) remain completely untested.

**Key deltas from v1 audit:**

| v1 Finding | v1 Severity | v2 Status | Delta |
|---|---|---|---|
| Schema migration missing | 🔴 Critical | **FIXED** | `AuGendaMigrationPlan` with v1→v2 lightweight migration (`AppContainer.swift:28–64`) |
| Real OAuth clientID in source | 🔴 Critical | **FIXED** | Placeholder + `ProcessInfo.environment` fallback (`GoogleOAuth.swift:41–42`) |
| macOS compile errors (UIColor) | 🔴 Critical | **FIXED** | `NSColor(name:nil, dynamicProvider:)` with raw RGB values (`AuDHDComponents.swift:394–442`) |
| `aps-environment` = development | 🟠 High | **FIXED** | Changed to `production` (`AuGenda.entitlements:9–11`) |
| Silent `try?` save failures | 🟠 High | **PARTIALLY FIXED** | App-layer saves now use `ErrorBanner` (~40 `do/catch` save paths added); fetches/decodes still silent |
| `FocusSession` model missing | 🟡 Medium | **FIXED** | New `FocusSession.swift` + `NotificationManager` persists sessions (`NotificationManager.swift:304–315, 389–406`) |
| `Relationship` model missing | 🟡 Medium | **FIXED** | New `TaskRelationship.swift` + `TaskDetailView` shows sections (`TaskDetailView.swift:181–222`) |
| No progress UI for async ops | 🟡 Medium | **PARTIALLY FIXED** | AI enrichment shows `ProgressView` (`AIEnrichmentSettingsView.swift:288`, `InboxView.swift:280`); OAuth/WeatherKit still lack progress |
| Export plaintext | 🟡 Medium | **NOT FIXED** | Still plaintext (`TaskImportExport.swift:140–298`) |
| No resume-after-interruption | 🟡 Medium | **FIXED** | `RootView` resume banner wired to `InterruptionContext` (`AuGendaApp.swift:208–218`) |
| No "Local AI only" mode | 🟡 Medium | **FIXED** | `AIEnrichmentSettingsView.localOnlyMode` filters paid providers (`AIEnrichmentSettingsView.swift:40, 62–68`) |
| No biometric key protection | 🟡 Medium | **NOT FIXED** | Still `AfterFirstUnlockThisDeviceOnly` (`KeychainStore.swift:85`) |
| Font files missing | 🟡 Medium | **NOT FIXED** | No `UIAppFonts` in `Info.plist` |
| CloudKit not active | 🟠 High | **NOT FIXED** | Still `AppContainer.dev` active; `cloudKitContainerID` still placeholder |
| No daily planning wizard | 🟡 Medium | **NOT FIXED** | No morning setup flow |

---

## Tier 1: Constitution — Foundational Values & Constraints

### 1.1 Founding Values ("The Core Mandate")
**Assessment: PASS — unchanged.**
- AI enrichment remains opt-in, off by default (`AIEnrichmentSettingsView.swift:23: aiEnabled: Bool = false`).
- `excludeFromAI` per-task exists (`AddAgendaItemView.swift:1310` toggle).
- No agentic override of user decisions. The user is the sole authority.

### 1.2 Semantic Discipline ("The Language of the System")
**Assessment: IMPROVED — mostly resolved, one dead fork.**
- `FocusSession` and `TaskRelationship` are now fully mapped to SwiftData models and wired into UI.
- `CognitiveProfile` exists (`CognitiveProfile.swift:10–31`) but is **dead code** — zero call sites in the entire codebase. The Ontology mapping has a fork: `CognitiveProfile` is defined but not invoked. Either wire it into `FocusSessionView` to suggest session length based on historical data, or remove it from the Ontology and delete the file.
- `Artifact` (Note model) remains a gap. Notes are still stored as `String` properties on `AgendaTask` and `AgendaItem`. No first-class `Note` entity with UUID, timestamps, or relationships.

### 1.3 Non-Interference ("The Prime Directive")
**Assessment: STRONG PASS — unchanged.**
- Multi-modal operation preserved: text input, voice brain dump (`BrainDumpView`), visual density selectors, gesture-based completion, Watch interaction.
- `DensityAdvisor` remains advisory-only (`HomeDashboardView.swift:265–278`). The user can apply or dismiss suggestions.
- `ProfilePreferences.densityPinned` allows explicit override (`ProfileModels.swift:362–371`).

### 1.4 Reliability ("The Bedrock")
**Assessment: CRITICAL IMPROVEMENT, with residual risk.**

**Fixed since v1:**
- `AuGendaMigrationPlan` exists with `VersionedSchema` v1 and v2 (`AppContainer.swift:28–64`).
- `AppContainer.dev` now uses `do/try/catch` with fallback to `makeTestContainer()` (`AppContainer.swift:108–116`).
- `makeTestContainer()` also uses the migration plan (`AppContainer.swift:127`).
- `AppContainer.production` still uses `fatalError` on failure (`AppContainer.swift:88`) — this is acceptable because it is the last-resort bootstrap container and the comment block at line 7–26 explicitly warns it must be replaced before shipping.

**Still present:**
- The **erase-all-data** path (`ContentView.swift:1010–1023`) uses `try?` for every model deletion. If a deletion fails (e.g., a foreign key constraint violation), the app continues to the next model. A partially-erased database could leave orphaned relationships or corrupt SwiftData graph state. The outer `do/try/catch` at line 1024 only catches the final `save()`, not the individual `delete()` calls. This is a data integrity risk in the most destructive operation the app offers.
- `try?` fetch patterns remain pervasive (~15 occurrences). Fetch failures are less destructive than save failures, but they can cause silent data loss: a task may disappear from a view because the fetch failed, not because it was deleted. Examples:
  - `ContentView.swift:170` and `194`: `guard let item = (try? modelContext.fetch(descriptor))?.first else { return }` — if fetch fails, the notification action is silently dropped.
  - `ProfileModels.swift:446` and `456`: `try? ctx.fetch(descriptor)` — if the profile fetch fails, `activeProfile` becomes nil and the app shows empty states.
  - `TaskRelationship.swift:79` and `89`: `try? context.fetch(descriptor)` — if relationship fetch fails, the task appears unblocked when it is actually blocked.

### 1.5 Transparency ("The Window")
**Assessment: IMPROVED, with accessibility gaps.**
- `ErrorBanner` is present at the root of every view (`ContentView.swift:74`). It overlays at `zIndex: 100` and auto-dismisses after 3 seconds (`ErrorBanner.swift:21–24`).
- **However:** `ErrorBanner` has **no accessibility label** (`ErrorBanner.swift:33–67`). The `Image(systemName: "exclamationmark.triangle.fill")` and `Text(message)` are not wrapped in `.accessibilityLabel`. A VoiceOver user would hear the raw message text but not the warning icon semantics. The dismiss button (`Image(systemName: "xmark")`) also lacks `.accessibilityLabel`. This is a transparency gap for screen-reader users — they may not understand that an error occurred or how to dismiss it.
- AI enrichment reasoning is still opaque. The `EnrichmentPreviewSheet` (`TaskDetailView.swift:497–593`) shows *what* changed but not *why* the AI suggested it. There is no "AI reasoning" field visible to the user.
- The `resumePrompt` overlay in `RootView` (`AuGendaApp.swift:136–181`) shows the last activity label but does not explain *why* the app is showing it ("Because you were away for 15+ minutes"). The banner also lacks VoiceOver labels on the "Resume" and dismiss buttons.

---

## Tier 2: Doctrine — The Engine of Value

### 2.1 Contrast Requirements ("No Generic")
**Assessment: STRONG PASS — unchanged.**
- ND-specific affordances remain intact: friction dots, energy pips, hyperfocus risk flag, body double flag, density modes, brain dump with voice input, "waiting on" field, multi-profile household, Watch sync, strict privacy defaults.
- New `FocusSession` model adds focus-session tracking — a feature no generic todo app has.
- New `TaskRelationship` model adds dependency tracking — also unique.

### 2.2 Decomposition ("Atomic Unit")
**Assessment: PASS — unchanged.**
- New models follow the same atomic pattern: `FocusSession` is a single-purpose model for focus sessions. `TaskRelationship` is a single-purpose model for task dependencies.
- `ErrorBanner` is a single-purpose, reusable component.
- `InterruptionContext` is a single-purpose enum for session tracking.

### 2.3 System Safety ("No Unsafe")
**Assessment: MAJOR IMPROVEMENT, with residual gaps.**

**Fixed since v1:**
- **T2.3a — CRITICAL:** Hardcoded OAuth `clientID` is **fully removed**. `GoogleOAuth.swift:41–42` uses `ProcessInfo.processInfo.environment["AUGENDA_GOOGLE_CLIENT_ID"]` with a fallback to `"YOUR_CLIENT_ID_HERE.apps.googleusercontent.com"`. `Info.plist:51` uses `YOUR_CLIENT_ID_REVERSED`. The `isConfigured` check (`GoogleOAuth.swift:59–62`) correctly detects the placeholder and disables the Sign-In button.
- `OAuthCoordinator` PKCE implementation is sound (`OAuthCoordinator.swift:170–225`):
  - Verifier generated with `SecRandomCopyBytes` (`OAuthCoordinator.swift:365–367`).
  - Challenge is SHA256 of verifier (`OAuthCoordinator.swift:370–373`).
  - State is a random UUID (`OAuthCoordinator.swift:174`).
  - State is validated on callback (`OAuthCoordinator.swift:207–211`).
  - Token refresh uses `refresh_token` and updates stored tokens (`OAuthCoordinator.swift:228–264`).
  - Token storage uses `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` (`OAuthCoordinator.swift:141`).
- `KeychainStore` uses `AfterFirstUnlockThisDeviceOnly` (`KeychainStore.swift:85, 99`).

**Still present:**
- **T2.3b — Biometric protection:** No `kSecAccessControlBiometryCurrentSet` or `kSecAccessControlBiometryCurrentSet` is applied to API keys or OAuth tokens. Given Arthur's hEDS/fatigue context and potential for handing the phone to partners/children, this is a residual risk. The fix is simple: add `kSecAccessControlBiometryCurrentSet` to the `queryAdd` dictionary in `KeychainStore.set()` and `OAuthCoordinator.writeTokens()`, falling back to `AfterFirstUnlockThisDeviceOnly` if biometry is unavailable.
- **T2.3c — Brain dump voice input:** `BrainDumpView` (in `TaskBacklogView.swift:961–1206`) still lacks explicit `SFSpeechRecognizer` availability check on `onAppear`. The `voiceUnavailable` state (`TaskBacklogView.swift:980`) is only set via button tap (`TaskBacklogView.swift:1146`), not on initial load. The `#if os(iOS)` block sets up `AVAudioEngine` but does not guard against `SFSpeechRecognizer(locale: .autoupdatingCurrent)` returning `nil` for unsupported locales. If the user's locale is unsupported, tapping the microphone button will crash or fail silently.
- **T2.3d — Import/Export format mismatch:** `TaskBacklogView.swift:313` allows `.json, .commaSeparatedText, .plainText, .text` in `.fileImporter`. However, `TaskImporter.detectFormat` (`TaskImportExport.swift:305–315`) supports `.yaml` and `.yml`. If a user exports to YAML (which the exporter supports) and later tries to re-import, they cannot select the `.yaml` file because the file picker doesn't allow it. This is a UI gate mismatch that will confuse users.
- **T2.3e — Import validation:** No schema version check in `TaskImporter`. The `version: 1` field is written in YAML/JSON exports (`TaskImportExport.swift:172`) but never validated on import. A v2 export with new fields would be silently ignored by a v1 parser. Also, no maximum file size check — a malicious 100MB JSON import could cause memory pressure.
- **T2.3f — No rate limiting on AI:** Still no rate-limiting or cost cap. The `AIUsageLedger` tracks usage (`AIUsageLedger.swift:166`) but does not enforce caps. The `AIEnrichmentSettingsView` shows "Tokens this month" and "Estimated cost" (`AIEnrichmentSettingsView.swift:429–452`) but offers no way to set a hard limit.
- **T2.3g — Ollama host warning is advisory, not a block:** `AIEnrichmentSettingsView.swift:312–330` warns about plain HTTP outside the local network but does not prevent the user from saving the host. A non-technical user might not understand the warning and proceed anyway.

### 2.4 Feedback Loops ("Continuous Improvement")
**Assessment: IMPROVED — new models but no adaptive loop.**
- `CognitiveProfile.swift` was created as a lightweight aggregator (`CognitiveProfile.swift:10–31`). It has `typicalWindowLengthMinutes(in:)` and `suggestedFocusLength(in:energyLevel:)`.
- **However:** `CognitiveProfile` is **never called** anywhere in the codebase. It is dead code. The `FocusSessionView` (`FocusSessionView.swift:36`) uses `profileManager.activePreferences?.focusSessionMinutes ?? 25` — not `CognitiveProfile.suggestedFocusLength`.
- `DensityAdvisor` still does not learn from historical override accuracy. `ActivityLog` (`AuDHDNDComponents.swift:53–93`) records snoozes/completions but no adaptive tuning occurs. The advisor rules are static (`DesignTokens.swift:416–466`).
- `AIUsageLedger` records usage but does not feed back into behavior (e.g., "You used $5 last month — consider switching to Ollama").

### 2.5 Progress Reporting ("Always Show Your Work")
**Assessment: IMPROVED.**
- AI enrichment now shows `ProgressView` in `AIEnrichmentSettingsView.swift:288` (test button) and `InboxView.swift:280` (suggest structure button).
- `BlockManager.isLoadingWeather` (`BlockView.swift:30`) is published, but `BlockListView` does not show a progress indicator during weather fetch. `BlockDetailView` shows `ProgressView` when `isLoadingWeather` is true (`BlockView.swift:680`), but the list view does not.
- OAuth flow has no progress indicator. The `ASWebAuthenticationSession` is a system UI, but the app could show a "Signing in…" overlay while waiting for the callback.
- Watch sync has no progress indicator. The user doesn't know if the Watch received the update.
- `TaskExporter` / `TaskImporter` have no progress UI for large files. A 1000-task export could take several seconds with no feedback.

### 2.6 The Doctrine of Reliability ("Never Fail")
**Assessment: IMPROVED.**
- `aps-environment` is now `production` (`AuGenda.entitlements:9–11`).
- `AppContainer.dev` gracefully falls back to `makeTestContainer()` (`AppContainer.swift:108–116`).
- `NotificationManager` now persists `FocusSession` to SwiftData (`NotificationManager.swift:304–315` and `389–406`).
- **Still missing:** CloudKit is still inactive (`AppContainer.swift:26`). No UI explains this to the user. `UserDefaults` active profile is still not synced across devices (`ProfileModels.swift:523–528`).
- **Still missing:** If the AI provider's API key is invalid or expired, enrichment fails silently in some paths. The `InboxView.runEnrich()` (`InboxView.swift:463–495`) shows errors in the UI, but `AddAgendaItemView.runEnrich()` (`ContentView.swift:1417–1464`) shows errors in `enrichState`. However, bulk enrichment (if it existed) would have no error surfacing.
- **Still missing:** `WeatherKit` fetch in `BlockManager` (`BlockView.swift:189–205`) has `do/catch` but the error is only logged via `os.log`, not shown to the user. If the user denies location permission, the weather suggestions simply don't appear with no explanation.

---

## Tier 3: Engineering Handbook — The Implementation Standard

### 3.1 Memory & Context Awareness ("Never Forget")
**Assessment: PASS.**
- `InterruptionContext` is now properly wired in `RootView` (`AuGendaApp.swift:208–218`). When the app returns to `.active`, it checks `InterruptionContext.currentActivity()` and shows the resume banner if the interruption was within 15 minutes.
- `InterruptionContext.recordActivity(contextLabel:)` is called in:
  - `HomeDashboardView.onAppear` (`HomeDashboardView.swift:441`)
  - `TaskBacklogView.onAppear` (`TaskBacklogView.swift:340`)
  - `TaskBacklogView` task tap (`TaskBacklogView.swift:434–437`)
  - `AuDHDNDComponents.swift` task expand (`AuDHDNDComponents.swift:490–494`)
- **Still missing:** `ActiveProfileManager` uses `UserDefaults` for `activeProfileIDKey` (`ProfileModels.swift:431, 523–528`). No cross-device sync. If Arthur switches from iPhone to iPad, the active profile resets. This is a context-loss risk. Recommendation: migrate to `NSUbiquitousKeyValueStore` or sync via CloudKit.
- **Still missing:** `CognitiveCheckInTracker` uses `UserDefaults` for frequency and last check-in (`CognitiveStateSelector.swift:61–124`). Not synced across devices.
- **Still missing:** `ActivityLog` uses `UserDefaults` for snoozes/completions (`AuDHDNDComponents.swift:53–93`). Not synced across devices. The density advisor is therefore device-local.

### 3.2 Thought Steps & Reasoning ("Show Your Work")
**Assessment: N/A for app code.**
- The app does not contain an embedded reasoning agent. However, it could show its reasoning to the user: e.g., why a task was ranked with a specific `ndPriorityScore`. Currently, the score is visible but the reasoning is not explained.

### 3.3 Security & Data Handling ("Never Leak")
**Assessment: IMPROVED, with residual gaps.**

**Fixed since v1:**
- OAuth `clientID` is no longer hardcoded.
- `Info.plist` no longer contains the reversed client ID.
- `ErrorBanner` surfaces save failures (~40 app-layer save paths now use `do/catch` + `ErrorBanner`).
- `InterruptionContext` no longer stores plaintext task titles in `UserDefaults`. The legacy `lastItemTitle` key is cleared aggressively (`AuDHDNDComponents.swift:170`).

**Still present:**
- **Export plaintext:** `TaskExporter` exports all task data in plaintext (Markdown, JSON, CSV, YAML). No encryption option. `TaskTextFileDocument` writes raw UTF-8 (`TaskImportExport.swift:560–562`). If Arthur exports medical appointments or therapy notes to iCloud Drive or shares the file, all task data is exposed. This is a privacy boundary violation for sensitive tasks.
- **KeychainStore:** No biometric protection. `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` means the key is accessible after first unlock without biometrics. If Arthur hands the phone to a partner or child, the API key is readable by anyone with device access. The fix: add `kSecAccessControlBiometryCurrentSet` to the `queryAdd` dictionary.
- **No `NSUserTrackingUsageDescription`:** Still missing, though not critical for App Store today. Apple may require it in the future.
- `AIUsageLedger` still does not log which specific tasks were enriched — only aggregate tokens/cost. While this is good for privacy, it means there is no audit trail if the user wants to review what data was sent to AI providers.
- `PersonalizationStore` writes `memory.json` to Application Support (`AIPersonalization.swift:196–222`). The file uses `completeFileProtectionUntilFirstUserAuthentication`, which is good, but there is no additional app-level encryption. If the device is unlocked, the file is readable.
- `AIUsageLedger` writes `ai-usage-ledger.json` with the same file protection. Contains provider names and token counts — part of the user's behavioral profile.

### 3.4 Code Language & Expression ("Clear Code")
**Assessment: STRONG PASS.**
- The codebase remains exceptionally well-commented. New files follow the same precise documentation style.
- `CognitiveProfile.swift` is a stub — `energyByHour()` returns `[:]` with a comment "Stub for now — returns empty dict." This is honest but incomplete. Either implement it or remove it.
- `WatchSessionClient` has clear TODOs for v2 features (`WatchSessionClient.swift:50–54, 143–144, 246`). These are acceptable for a planned feature.
- `NowView` has a clear TODO for watch recovery context (`NowView.swift:100–102`).
- No `TODO` or `FIXME` comments in the core app logic (only in watch stubs and `CognitiveProfile` stub).

---

## Tier 4: Ontology — The Mapping of Reality

### 4.1 Ontology Concepts Revisited (Detailed)

| Ontology Concept | AuGenda Model/Type | v1 Status | v2 Status | Source Lines | Notes |
|---|---|---|---|---|---|
| **Observation** | `InboxItem` | ✅ Strong | ✅ Strong | `InboxItem.swift:1–81` | Unchanged. Brain dumps, voice captures, quick adds. |
| **Artifact** | `Note` (string on `AgendaTask`) | ⚠️ Gap | ⚠️ Gap | `AgendaTask.swift:185` | Still no first-class `Note` model. Notes are strings on tasks/items. |
| **Action** | `AgendaTask` | ✅ Strong | ✅ Strong | `AgendaTask.swift:1–185` | Six-axis difficulty model, friction, energy, context. |
| **Outcome** | `isComplete`, `completedAt` | ✅ Strong | ✅ Strong | `AgendaTask.swift:170–171` | Completion tracked with timestamp. `ActivityLog` records outcomes. |
| **Learning** | `CognitiveProfile` | ⚠️ Partial | ⚠️ **Dead code** | `CognitiveProfile.swift:10–31` | Exists but **never invoked**. No adaptive loop. |
| **Entity** | `Profile` | ✅ Strong | ✅ Strong | `ProfileModels.swift:195–272` | Multi-profile household with roles, neurotypes, avatar. |
| **State** | `DensityMode`, `energyLevel` | ✅ Strong | ✅ Strong | `DesignTokens.swift:313–401` | Four-state enum with auto-derivation from energy. |
| **Relationship** | `TaskRelationship` | 🔴 Gap | ✅ **Fixed** | `TaskRelationship.swift:36–68` | New model with `blocks`, `follows`, `bundles`, `related`. |
| **FocusSession** | `FocusSession` | 🔴 Gap | ✅ **Fixed** | `FocusSession.swift:18–75` | New model with start/end, interruptions, completion state. |
| **CognitiveProfile** | `Profile` + `ProfilePreferences` | ⚠️ Partial | ⚠️ **Dead code** | `CognitiveProfile.swift:10–31` | Fragmented. No unified dynamic profile. |
| **Context** | `InterruptionContext` | ⚠️ Partial | ✅ **Fixed** | `AuDHDNDComponents.swift:100–215` | Now records activity in views and supports resume banner. |

### 4.2 Unmapped Forks (Updated)

**Finding T4.1 (v2):** `CognitiveProfile` is the only remaining unmapped Ontology fork. It is defined as a pure logic enum (`CognitiveProfile.swift:10–31`) but has **zero call sites** in the entire codebase. The `FocusSessionView` (`FocusSessionView.swift:36`) uses `profileManager.activePreferences?.focusSessionMinutes ?? 25` instead of `CognitiveProfile.suggestedFocusLength(in:energyLevel:)`. Either:
- Wire it into `FocusSessionView` to adapt session length based on historical completed focus sessions, OR
- Remove `CognitiveProfile` from the Ontology and delete the file to prevent architectural drift.

**Finding T4.2 (v2):** `Artifact` (Note model) is still missing. Notes remain as `String` properties on `AgendaTask` (`AgendaTask.swift:185`) and `AgendaItem`. No first-class note entity with its own UUID, timestamps, tags, or relationships. This means notes cannot be searched independently, linked to multiple tasks, or have their own metadata (e.g., "therapy note from March 15"). Recommendation: add a `Note` SwiftData model with `clientID`, `title`, `body`, `createdAt`, `updatedAt`, `relatedTaskID`, and `tags`.

**Finding T4.3 (v2):** `FocusSession` is now properly mapped, but the UI does not show historical focus sessions. The `FocusSession` model persists sessions (`FocusSession.swift:18–75`), but there is no "Focus History" view where the user can see past sessions, their completion rate, average duration, or patterns by time-of-day. The data is being collected but not surfaced for user insight.

---

## Tier 5: User Context — Arthur's Specific Needs

### 5.1 Arthur's Profile (recap)
- AuADHD, hEDS, chronic fatigue, 2–4h productive windows, $0 budget, extreme disorientation, no professional support, cannot handle data loss or crashes.

### 5.2 Assessment Against User Context (Detailed)

**Finding T5.1 — Data Loss = Project Abandonment Risk:**
- **IMPROVED:** Schema migration exists (`AppContainer.swift:28–64`). `try?` save pattern is largely replaced in the app layer (~40 `do/catch` + `ErrorBanner` paths added).
- **STILL AT RISK:** The erase-all-data path (`ContentView.swift:1010–1023`) uses `try?` for every model deletion. If a deletion fails, the app continues to the next model. A partially-erased database could leave orphaned relationships or corrupt state. The final `save()` at line 1024 would then fail on an inconsistent graph. For Arthur, a partially-erased database that crashes on launch = project abandonment risk.
- **STILL AT RISK:** `AppContainer.production` uses `fatalError` (`AppContainer.swift:88`). If Arthur ever accidentally switches to `.production` (e.g., via a build setting mistake), the app will crash on launch if CloudKit is not active. The `dev` container has a fallback, but `production` does not.
- **STILL AT RISK:** `makeTestContainer()` uses `fatalError` (`AppContainer.swift:129`). If the in-memory test container fails to create (e.g., due to a model validation error), the app crashes. This is a last-resort fallback but still a crash point.

**Finding T5.2 — $0 Budget = Zero Costs:**
- **FIXED:** "Local AI only" mode is implemented (`AIEnrichmentSettingsView.swift:40, 62–68`). When enabled (`localOnlyMode: Bool`), only `appleFoundation` and `ollama` are visible in the provider list. The `onChange(of: localOnlyMode)` at line 114 clears the active provider if it's a paid one. This enforces Arthur's $0 budget constraint.
- **STILL AT RISK:** There is no **cost cap** or **usage hard limit** on paid providers. The `AIUsageLedger` tracks usage (`AIUsageLedger.swift:166`) but does not block. If Arthur accidentally enables a paid provider and runs enrichment on a large batch of tasks, he could incur costs. The `AIUsageLedger` should have a `maxMonthlyCostUSD` setting that blocks enrichment when exceeded.
- **STILL AT RISK:** The `Ollama` host warning (`AIEnrichmentSettingsView.swift:312–330`) is excellent — it warns about plain HTTP outside the local network. However, the warning is advisory, not a block. A non-technical user might save an insecure host anyway.

**Finding T5.3 — Fatigue & 2–4h Windows = Need for Stability:**
- **IMPROVED:** `FocusSession` is now persistent (`FocusSession.swift:18–75`). `FocusSessionView` exists with a visual countdown ring (`FocusSessionView.swift:229–276`).
- **STILL AT RISK:** `CognitiveProfile.suggestedFocusLength(in:energyLevel:)` is dead code. The app does not adapt session length based on historical data. Arthur must manually set `focusSessionMinutes` in settings (`ProfilePreferences.swift:296`). The app could suggest "Your last 5 sessions averaged 22 minutes. Suggest 20 minutes today?" but does not.
- **STILL AT RISK:** The `FocusSession` model does not track **interruptions** in detail. It has `interruptionCount` (`FocusSession.swift:34`) but no timestamps or reasons for interruptions. For ADHD users, understanding *when* and *why* they get interrupted is key to managing their windows. The model should store interruption timestamps and optional reason strings.

**Finding T5.4 — No Professional Support = App Must Be Scaffold:**
- **IMPROVED:** Resume-after-interruption flow is now wired (`AuGendaApp.swift:208–218`). The `resumePrompt` banner shows the last activity label and offers a "Resume" button.
- **STILL AT RISK:** The banner is **not** accessible to VoiceOver. The `Resume` button (`AuGendaApp.swift:146–155`) and `xmark` dismiss button (`AuGendaApp.swift:157–165`) have no `.accessibilityLabel`. A VoiceOver user would hear "Button" for both, with no context.
- **STILL AT RISK:** The `DensityAdvisor` suggests capacity changes but does not explain *why* in a way that helps Arthur learn his patterns. For example: "You've snoozed 3 tasks recently. Try Low capacity?" is good, but "You've snoozed 3 tasks in the last 15 minutes. Your average snooze rate is 1 per hour. Try Low capacity?" would be more scaffold-like.
- **STILL AT RISK:** No "coach" or "guide" mode. The app provides structure but not active guidance when Arthur is stuck. The AI enrichment could fill this gap, but it's currently a passive enrichment tool, not an active coach.

**Finding T5.5 — hEDS / Chronic Pain = Physical Interaction Design:**
- **STILL AT RISK:** `AppFont` supports `atkinson` and `openDyslexic` (`ProfileModels.swift:103–142`), but the **font files are not in the bundle** and **`Info.plist` has no `UIAppFonts` entry**. If the user selects these fonts in `ProfileSettingsView` (`ProfileViews.swift:896–913`), `Font.custom("AtkinsonHyperlegible-Regular", size: 16, relativeTo: style)` (`ProfileModels.swift:137`) silently falls back to the system font. The user has no feedback that their dyslexia-friendly font choice is being ignored. This is a silent failure for a user with dyslexia.
- **STILL AT RISK:** No adjustable UI scale or text size override beyond system Dynamic Type. The `Tokens.Typography` sizes are fixed multipliers (`DesignTokens.swift:86–121`) with no user-adjustable scale factor. For hEDS users with fine motor control issues, a "Large UI" mode (bigger buttons, more spacing, larger text) would be valuable. The app respects system Dynamic Type but does not offer an additional override.
- **STILL AT RISK:** `Tokens.Spacing.touchMinimum` is 44pt (`DesignTokens.swift:81`), which meets iOS guidelines. However, some hEDS users may need 56pt or larger. No override exists.

**Finding T5.6 — Disorientation = Need for Relational Transition Support:**
- **FIXED:** `InterruptionContext.recordActivity(contextLabel:)` is called in multiple views:
  - `HomeDashboardView.onAppear` (`HomeDashboardView.swift:441`)
  - `TaskBacklogView.onAppear` (`TaskBacklogView.swift:340`)
  - `TaskBacklogView` task tap (`TaskBacklogView.swift:434–437`)
  - `AuDHDNDComponents.swift` task expand (`AuDHDNDComponents.swift:490–494`)
- The resume banner shows in `RootView` (`AuGendaApp.swift:136–181`) with the activity label and a "Resume" button. It auto-dismisses after 10 seconds (`AuGendaApp.swift:213–217`).
- **STILL AT RISK:** The watch `NowView` has `shouldShowRecovery` hardcoded to `false` (`NowView.swift:96–103`). The comment says "TODO(watch v2): wire InterruptionContext.shouldShowRecovery through to the watch." The watch does not get the resume prompt. For a user who relies on the watch for quick task completion, this is a missing transition support on the secondary device.
- **STILL AT RISK:** The `InterruptionRecoveryPrompt` component (`AuDHDNDComponents.swift:236–344`) exists but is not used in `RootView`. The `RootView` uses its own inline resume banner (`AuGendaApp.swift:136–181`) instead of the reusable `InterruptionRecoveryPrompt`. This means the full-screen recovery overlay (with "Resume where I left off", "Help me figure out what to do", "Start fresh") is not shown. The inline banner is less supportive for a disoriented user.

**Finding T5.7 — Inconsistent = Need for Zero-Friction Daily Reset:**
- **STILL AT RISK:** No "Morning Setup" wizard. The `TodayView` / `HomeDashboardView` shows existing tasks but does not help the user plan their day based on today's energy. The `DensityAdvisor` suggests capacity changes but does not help build an agenda.
- **STILL AT RISK:** The `BlockManager` seeds default blocks on first launch (`BlockView.swift:286–332`), but there is no daily "reset blocks" flow. For an inconsistent user, yesterday's incomplete blocks may not be relevant today. The app should offer a "Rebuild today's blocks" option based on current energy and scheduled items.
- **STILL AT RISK:** No "end-of-day review" flow. The app records completions (`ActivityLog`) but does not surface insights like "You completed 3 tasks today, 2 were low friction. Tomorrow, try starting with a low-friction task."

---

## Deep File Analysis

### Metrics for Every App-Layer File

| File | Lines | `try?` count | `do/catch` save count | `TODO`/`FIXME`/`HACK` | `fatalError` | Force unwrap (`!`) | Force cast (`as!`) | `DispatchQueue.main.async` without `[weak self]` |
|---|---|---|---|---|---|---|---|---|
| `AppContainer.swift` | 246 | 0 | 0 | 0 | 2 (l.88, 129) | 0 | 0 | 0 |
| `GoogleOAuth.swift` | 94 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| `ErrorBanner.swift` | 68 | 1 (l.21: sleep) | 0 | 0 | 0 | 0 | 0 | 0 |
| `FocusSession.swift` | 84 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| `TaskRelationship.swift` | 91 | 2 (l.79, 89: fetch) | 0 | 0 | 0 | 0 | 0 | 0 |
| `CognitiveProfile.swift` | 32 | 1 (l.19: fetch) | 0 | 1 (stub comment) | 0 | 0 | 0 | 0 |
| `AIEnrichmentSettingsView.swift` | 741 | 0 | 2 (saveKey, removeKey) | 0 | 0 | 0 | 0 | 0 |
| `KeychainStore.swift` | 145 | 1 (l.127: get) | 0 | 0 | 0 | 0 | 0 | 0 |
| `OAuthCoordinator.swift` | 432 | 3 (l.123, 253, 314: decode) | 0 | 0 | 0 | 0 | 0 | 0 |
| `NotificationManager.swift` | 574 | 1 (l.398: fetch) | 2 (l.312, 402: save) | 0 | 0 | 0 | 0 | 1 (l.518: has `[weak self]`) |
| `TaskDetailView.swift` | 850 | 2 (l.478, 487: fetch) | 3 (l.172, 428, 453: save) | 0 | 0 | 0 | 0 | 2 (l.440, 445: `asyncAfter` without `[weak self]`) |
| `AuGendaApp.swift` / `RootView` | 363 | 1 (l.214: sleep) | 0 | 0 | 0 | 0 | 0 | 2 (l.202, 333, 355: `asyncAfter` without `[weak self]`) |
| `ContentView.swift` | 1715 | 15 (l.170, 194, 1010–1023: fetch/delete; l.1034: keychain) | 8 (various save) | 0 | 0 | 0 | 0 | 3 (l.360, 1695: `asyncAfter` without `[weak self]`) |
| `HomeDashboardView.swift` | 1556 | 0 | 7 (various save) | 0 | 0 | 0 | 0 | 0 |
| `DesignTokens.swift` | 467 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| `AuDHDComponents.swift` | 502 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| `AuDHDNDComponents.swift` | 1467 | 2 (l.154, 158: fetch) | 2 (l.590, 605: save) | 0 | 0 | 0 | 0 | 1 (l.1146: `async` without `[weak self]`) |
| `ProfileModels.swift` | 543 | 3 (l.446, 456, 475: fetch) | 1 (l.493: save) | 0 | 0 | 0 | 0 | 0 |
| `ProfileViews.swift` | 1260 | 1 (l.715: fetch) | 3 (l.751, 1124, 1200: save) | 0 | 0 | 0 | 0 | 0 |
| `BlockView.swift` | 972 | 2 (l.159, 290: fetch) | 5 (l.63, 103, 124, 330, 784: save) | 0 | 0 | 0 | 0 | 0 |
| `CognitiveStateSelector.swift` | 464 | 0 | 1 (l.330: save) | 0 | 0 | 0 | 0 | 0 |
| `InboxView.swift` | 523 | 0 | 3 (l.47, 446, 456: save) | 0 | 0 | 0 | 0 | 0 |
| `TaskBacklogView.swift` | 1206 | 2 (l.159: data read; l.1202: audio) | 2 (l.954, 1136: save) | 0 | 0 | 0 | 0 | 3 (l.1146, 1176, 1183: `async` without `[weak self]`) |
| `TaskImportExport.swift` | 563 | 4 (l.160, 333, 337: encode/decode; l.561: write) | 0 | 0 | 0 | 0 | 0 | 0 |
| `WatchConnectivityManager.swift` | 328 | 7 (l.100, 101, 173, 183, 242, 246, 263: encode/fetch/save) | 0 | 0 | 0 | 0 | 0 | 0 |
| `SmartSuggestView.swift` | 265 | 0 | 0 | 0 | 0 | 0 | 0 | 1 (l.110: `asyncAfter` without `[weak self]`) |
| `FocusSessionView.swift` | 411 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| `HouseholdView.swift` | 297 | 0 | 1 (l.255: save) | 0 | 0 | 0 | 0 | 0 |
| **TOTAL** | **~20,130** | **~45** | **~40** | **1** | **2** | **0** | **0** | **~13** |

### Key Observations from Metrics

1. **No force unwraps (`!`) or force casts (`as!`) anywhere in the app layer.** This is excellent and reflects strong engineering discipline. The remediation did not introduce any new force unwraps.
2. **`fatalError` is only in `AppContainer.swift`** (production container at line 88, test container at line 129). Both are last-resort bootstrap failures. Acceptable for a container that cannot recover.
3. **`try?` is still widespread:** ~45 occurrences. The remediation only targeted `modelContext.save()` in the app layer (~40 saves fixed). It did not touch:
   - Fetch operations (`try? context.fetch(...)`) — 15+ occurrences. These are less destructive but can cause silent data disappearance.
   - JSON encode/decode in AI adapters (`try? JSONDecoder().decode(...)`) — 6+ occurrences across `AIEnricher_Claude.swift:142`, `AIEnricher_Gemini.swift:172`, `AIEnricher_OpenAICompatible.swift:162`, `OAuthCoordinator.swift:123, 253, 314`.
   - Watch-layer saves (`try? context.save()`) — 2 occurrences in `WatchConnectivityManager.swift:246, 263`. The remediation prompt explicitly said "Do not change `try?` in Watch code" — this was followed but leaves the Watch layer with silent failures.
   - `TaskImportExport` encode/decode — 4 occurrences. A failed export encode returns `"{}"` or empty string with no user feedback.
   - `AVAudioSession` teardown — 1 occurrence in `TaskBacklogView.swift:1202`.
4. **`DispatchQueue.main.async` without `[weak self]`:** 13 occurrences, mostly in `asyncAfter` for animation timing. These are generally safe because the closures are short-lived and don't capture `self` strongly in a way that causes retain cycles (they're one-shot timers). However:
   - `TaskBacklogView.swift:1146` and `TaskBacklogView.swift:1176` use `DispatchQueue.main.async` for voice recording state machine. If the view is dismissed while recording is active, these closures could capture `self` and prevent deallocation until recording stops.
   - `NotificationManager.swift:518` uses `[weak self]` correctly.
5. **`TODO`/`FIXME`/`HACK` comments:** Only 1 in the app layer (`CognitiveProfile.swift:13` — "Stub for now"). The watch layer has several TODOs for v2 features, which are acceptable for planned work.

---

## Test Coverage Matrix

### Test Files (6 total)

| File | Tests | Framework | Coverage | Quality |
|---|---|---|---|---|
| `AuGendaTests.swift` | 1 placeholder | Swift Testing | None — empty example test | N/A |
| `DifficultyEngineTests.swift` | 8 tests | Swift Testing | `DifficultyEngine.rank()`, `DifficultyBand`, `DensityMode.maxDifficultyRank`, `AgendaTask.passes(densityFilter:)` | Strong — exact-value regression locks |
| `StateEngineTests.swift` | 7 tests | Swift Testing | `DensityAdvisor.suggestion()`, `ProfilePreferences.effectiveDensity`, `DensityMode.representativeEnergyLevel` | Strong — deterministic pure-logic tests |
| `TaskImportExportTests.swift` | 6 tests | Swift Testing | `TaskExporter` YAML/JSON round-trip, `TaskImporter` clamping, empty input safety | Strong — round-trip and edge cases |
| `FocusSessionTests.swift` | 3 tests | XCTest | `FocusSession` creation, completion, overdue | Shallow — property accessors only, no persistence |
| `TaskRelationshipTests.swift` | 3 tests | XCTest | `TaskRelationship` creation, type round-trip, `isBlocking` | Shallow — property accessors only, no persistence |

**Total: 28 tests** (up from ~3 in v1). This is a **material improvement** but still far below professional standard for an app of this complexity (~20,130 lines, 43 files, 6 managers).

### Coverage Gaps (Untested Managers/Systems)

| Manager/System | Tested? | Notes | Risk |
|---|---|---|---|
| `NotificationManager` | ❌ No | Focus session persistence, notification scheduling, action handlers, snooze | **High** — Core feature, no tests |
| `BlockManager` | ❌ No | Weather fetch, bundle attachment, streak tracking, location delegate | **High** — Core feature, no tests |
| `WatchConnectivityManager` | ❌ No | Payload building, message routing, WCSessionDelegate | **High** — Cross-device sync, no tests |
| `ActiveProfileManager` | ❌ No | Profile switching, seeding, UserDefaults persistence | **High** — Core state, no tests |
| `AIEnricherRegistry` + 9 adapters | ❌ No | All provider adapters untested | **Medium** — Network-dependent, mockable |
| `OAuthCoordinator` | ❌ No | PKCE flow, token refresh, Keychain read/write | **High** — Security-critical, no tests |
| `KeychainStore` | ❌ No | Get/set/remove error paths | **Medium** — Security-critical, mockable |
| `InterruptionContext` | ❌ No | Record/clear/gap description logic | **Medium** — User context feature |
| `CognitiveCheckInTracker` | ❌ No | Frequency logic, stale detection | **Low** — Simple logic |
| `ActivityLog` | ❌ No | Snooze/completion counting | **Low** — Simple logic |
| `EnergyCheckInTracker` | ❌ No | Stale threshold logic | **Low** — Simple logic |
| `TaskImporter` (Markdown/CSV) | ⚠️ Partial | Only YAML and JSON tested; Markdown/CSV/plaintext parsers have no tests | **Medium** — Parser risk |
| `AppContainer` / migration | ❌ No | `AuGendaMigrationPlan` untested | **High** — Data safety-critical |
| `ErrorBannerController` | ❌ No | Show/dismiss/auto-dismiss timing | **Low** — UI component |
| `PersonalizationStore` | ❌ No | Memory JSON read/write, snapshot | **Medium** — Data safety |
| `AIUsageLedger` | ❌ No | File read/write, cost calculation | **Medium** — Data safety |
| `ContentView` / `HomeDashboardView` | ❌ No | No UI/integration tests | **High** — Main user flows |
| `FocusSessionView` | ❌ No | Timer logic, break transitions | **Medium** — Core feature |
| `TaskDetailView` | ❌ No | Relationship fetch, enrichment apply | **Medium** — Core feature |

### Test Verdict

The new `FocusSessionTests` and `TaskRelationshipTests` are correct but shallow — they test property accessors and computed properties, not persistence or integration with `NotificationManager`. No test verifies that `FocusSession` actually appears in SwiftData after `NotificationManager.startFocusSession()` is called. No test verifies that `TaskRelationship` affects `isBlocked` behavior in `TaskDetailView`.

**Recommendation:** Add integration tests that:
1. Create an `AgendaTask`, start a focus session via `NotificationManager`, verify a `FocusSession` record exists in SwiftData.
2. Create two `AgendaTask`s, link them with `TaskRelationship(blocks)`, verify the target task's `isBlocked` property reflects the relationship.
3. Test `AppContainer` migration by creating a v1 database, inserting data, then opening with v2 schema and confirming data preservation.
4. Mock `URLSession` and test at least one AI adapter (`AIEnricher_Ollama` is local-only and most testable).

---

## Security Re-scan

### Hardcoded Secrets Audit (Line-by-Line)

| File | Line | Pattern | Status | Notes |
|---|---|---|---|---|
| `GoogleOAuth.swift` | 41–42 | `clientID = ProcessInfo...environment["AUGENDA_GOOGLE_CLIENT_ID"] ?? "YOUR_CLIENT_ID_HERE..."` | ✅ PLACEHOLDER | No secret. Falls back to placeholder. |
| `GoogleOAuth.swift` | 46–49 | `redirectURI = reversed clientID` | ✅ PLACEHOLDER | Derived from placeholder when not configured. |
| `Info.plist` | 51 | `YOUR_CLIENT_ID_REVERSED` | ✅ PLACEHOLDER | No secret. |
| `AppContainer.swift` | 26 | `cloudKitContainerID = "iCloud.com.augenda.AuGenda"` | ⚠️ PLACEHOLDER | Not a secret, but inactive. Will cause silent CloudKit failure. |
| All `.swift` files | — | API keys, tokens | ✅ None found | Thorough grep across all files. |
| `AIEnricher_*.swift` | — | Hardcoded endpoints | ✅ All configurable | URLs come from `OAuthCoordinator` or `AIEnrichmentSettingsView`. |
| `TaskImportExport.swift` | — | Encryption keys | ⚠️ None | No encryption keys because no encryption is implemented. |
| `KeychainStore.swift` | 32 | `service = "com.augenda.AuGenda.aiprovider"` | ✅ Not a secret | Service identifier, not a credential. |
| `OAuthCoordinator.swift` | 94 | `keychainAccount = "oauth-\(provider.rawValue)"` | ✅ Not a secret | Account identifier, not a credential. |
| `OAuthCoordinator.swift` | 115 | `service = "com.augenda.AuGenda.oauth"` | ✅ Not a secret | Service identifier. |

**Verdict:** No hardcoded secrets remain in source. The OAuth credential exposure from v1 (Finding T2.3a) is fully remediated. The `GoogleOAuth.swift` implementation now follows iOS security best practices: no client secret (iOS OAuth clients don't have one), placeholder clientID, environment variable override for builds.

### Credential Exposure (Updated)

| Surface | Risk | Status | Details |
|---|---|---|---|
| OAuth tokens in Keychain | `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` | ⚠️ No biometric lock | Accessible after first unlock. No `kSecAccessControlBiometryCurrentSet`. |
| API keys in Keychain | Same as above | ⚠️ Same | Same risk for all 9 provider API keys. |
| Export files | Plaintext on disk | 🔴 No encryption | All 5 formats export task titles, notes, metadata in plaintext. |
| AI personalization memory | JSON file with `completeFileProtectionUntilFirstUserAuthentication` | ⚠️ Encrypted at rest | Protected by Apple's file encryption, but no app-level encryption. |
| `UserDefaults` activity log | Plaintext timestamps | ⚠️ No sensitive content | Only timestamps, no task titles or content. |
| `UserDefaults` interruption context | UUIDs + context labels | ⚠️ No plaintext titles | Legacy `lastItemTitle` key is cleared aggressively. |
| `UserDefaults` energy check-in | Timestamp + energy level | ⚠️ Minimal | Behavioral data, not sensitive content. |
| `UserDefaults` AI config | Provider, host, model | ⚠️ Minimal | No API keys (those are in Keychain). |

### Plaintext Data Surfaces (Detailed)

1. **Task Export (All Formats):**
   - **JSON** (`TaskImportExport.swift:156–163`): Exports `TaskExportPayload` with all task fields. No encryption. Pretty-printed with `.sortedKeys`.
   - **YAML** (`TaskImportExport.swift:170–196`): Hand-rolled YAML. All fields including `notes` are quoted but unencrypted. Sensitive notes (e.g., "therapy session about trauma") are exposed.
   - **CSV** (`TaskImportExport.swift:209–245`): Comma-separated values. No encryption. Notes with commas are escaped but still plaintext.
   - **Markdown** (`TaskImportExport.swift:253–291`): GFM checklist format. Titles and metadata trailers are plaintext. Notes are indented blockquotes.
   - **Plain text** (`TaskImportExport.swift:295–297`): Titles only. Still plaintext.
   - **Risk:** If Arthur exports to iCloud Drive or shares via AirDrop, all task data is exposed to anyone with access to the file. Medical appointments, therapy notes, medication regimens, and personal context tags are all in plaintext.
   - **Mitigation recommendation:** Add `CryptoKit` AES-256-GCM encryption with a user-provided password. Use `CryptoKit` (already available on iOS 13+ / macOS 10.15+). Add a toggle: "Encrypt with password." When enabled, wrap the exported payload in an encrypted envelope before writing to `FileWrapper`.

2. **AI Personalization Memory (`AIPersonalization.swift:196–222`):**
   - Writes `memory.json` to Application Support.
   - Uses `completeFileProtectionUntilFirstUserAuthentication` — good.
   - Content: task titles, difficulty bands, enrichment timestamps. Not highly sensitive but part of the user's behavioral profile.
   - No app-level encryption. If the device is unlocked, the file is readable by any app with file system access.

3. **AI Usage Ledger (`AIUsageLedger.swift:138–164`):**
   - Writes `ai-usage-ledger.json` with same file protection.
   - Contains provider names, token counts, cost estimates. Behavioral profile data.

---

## Remaining Production Blockers

| # | Blocker | Severity | File(s) | Fix Complexity | Status vs v1 | Line Refs |
|---|---|---|---|---|---|---|
| 1 | **Schema Migration Missing** | 🔴 Critical | `AppContainer.swift` | Medium | **FIXED** | `AppContainer.swift:28–64` |
| 2 | **Real OAuth Client ID in Source** | 🔴 Critical | `GoogleOAuth.swift`, `Info.plist` | Low | **FIXED** | `GoogleOAuth.swift:41–42`, `Info.plist:51` |
| 3 | **macOS Compile Errors (UIColor)** | 🔴 Critical | `AuDHDComponents.swift` | Low | **FIXED** | `AuDHDComponents.swift:394–442` |
| 4 | **CloudKit Not Active** | 🟠 High | `AppContainer.swift`, `.entitlements` | Medium | Unchanged | `AppContainer.swift:26` |
| 5 | **`aps-environment` = development** | 🟠 High | `AuGenda.entitlements` | Low | **FIXED** | `AuGenda.entitlements:9–11` |
| 6 | **Silent `try?` Save Failures** | 🟠 High | App-layer views | Medium | **PARTIALLY FIXED** | ~40 saves fixed; ~45 `try?` remain |
| 7 | **No Test Coverage for Managers/Views** | 🟠 High | `AuGendaTests/` | Medium | **IMPROVED** | 28 tests total (was ~3) |
| 8 | **FocusSession Model Missing** | 🟡 Medium | Ontology / UI | Medium | **FIXED** | `FocusSession.swift:18–75` |
| 9 | **Relationship Model Missing** | 🟡 Medium | Ontology / `AgendaTask` | Medium | **FIXED** | `TaskRelationship.swift:36–68` |
| 10 | **No Progress UI for Async Ops** | 🟡 Medium | Views with network/AI | Low | **PARTIALLY FIXED** | AI has `ProgressView`; Weather/OAuth lack it |
| 11 | **Export Data is Plaintext** | 🟡 Medium | `TaskExporter.swift` | Low | **NOT FIXED** | `TaskImportExport.swift:140–298` |
| 12 | **No Daily Planning / Morning Setup Wizard** | 🟡 Medium | `TodayView.swift` | Medium | Unchanged | — |
| 13 | **No "Resume After Interruption" Flow** | 🟡 Medium | `InterruptionContext.swift` | Low | **FIXED** | `AuGendaApp.swift:208–218` |
| 14 | **No Biometric Protection for API Keys** | 🟡 Medium | `KeychainStore.swift` | Low | **NOT FIXED** | `KeychainStore.swift:85` |
| 15 | **Font Files Missing** | 🟡 Medium | `DesignTokens.swift` / asset catalog | Low | **NOT FIXED** | `Info.plist` has no `UIAppFonts` |
| 16 | **CognitiveProfile is dead code** | 🟡 Medium | `CognitiveProfile.swift` | Low | **NEW** | `CognitiveProfile.swift:10–31` (zero call sites) |
| 17 | **Watch resume context stubbed** | 🟡 Medium | `NowView.swift` | Low | **NEW** | `NowView.swift:96–103` (`&& false`) |
| 18 | **ErrorBanner lacks VoiceOver label** | 🟡 Medium | `ErrorBanner.swift` | Low | **NEW** | `ErrorBanner.swift:33–67` |
| 19 | **RootView resume banner lacks VoiceOver** | 🟡 Medium | `RootView.swift` | Low | **NEW** | `AuGendaApp.swift:146–165` |
| 20 | **Erase-all-data uses `try?` deletes** | 🟡 Medium | `ContentView.swift` | Low | **NEW** | `ContentView.swift:1010–1023` |
| 21 | **File importer does not allow YAML** | 🟡 Medium | `TaskBacklogView.swift` | Low | **NEW** | `TaskBacklogView.swift:313` |
| 22 | **Brain dump lacks speech availability check** | 🟡 Medium | `TaskBacklogView.swift` | Low | **NEW** | `TaskBacklogView.swift:980–985` |
| 23 | **No cost cap on AI usage** | 🟡 Medium | `AIUsageLedger.swift` | Medium | Unchanged | `AIUsageLedger.swift:166` |
| 24 | **ActiveProfile not synced across devices** | 🟡 Medium | `ProfileModels.swift` | Medium | Unchanged | `ProfileModels.swift:523–528` |
| 25 | **No first-class Note model** | 🟡 Medium | Ontology | Medium | Unchanged | `AgendaTask.swift:185` |

---

## Recommendations for v2 (Path to A-Grade)

### Phase 1: Fix Remediation Gaps (Must Do Before TestFlight)

1. **Wire `CognitiveProfile` or remove it.** Either call `CognitiveProfile.suggestedFocusLength()` from `FocusSessionView` to adapt session duration based on historical completed sessions, or remove `CognitiveProfile` from the Ontology and delete the file. Dead code is architectural drift that confuses future maintainers.
2. **Fix `ErrorBanner` accessibility.** Add `.accessibilityLabel("Error: \(message)")` to the banner content and `.accessibilityLabel("Dismiss error")` to the xmark button so VoiceOver users know an error occurred and how to dismiss it.
3. **Fix `RootView` resume banner accessibility.** Add `.accessibilityLabel("Resume")` to the Resume button and `.accessibilityLabel("Dismiss resume prompt")` to the xmark button.
4. **Fix erase-all-data `try?` deletes.** Wrap the deletion loop in `do/try/catch` and abort the erase if any model fails to delete, surfacing the error via `ErrorBanner`. Do not proceed to the next model if a delete fails — partial erasure is worse than no erasure.
5. **Add `UIAppFonts` to `Info.plist`.** Register `AtkinsonHyperlegible-Regular.ttf`, `AtkinsonHyperlegible-Bold.ttf`, and `OpenDyslexic-Regular.otf`. Bundle the font files in the app target. Add a fallback alert if `Font.custom` fails to load (e.g., check if the font name is loadable and show "Font not available — using system font" if not).
6. **Add YAML to `.fileImporter` allowed types.** `TaskBacklogView.swift:313` should include `.yaml` or define a custom UTType so users can import YAML exports. The parser already supports YAML (`TaskImportExport.swift:305–315`); the UI gate is the only mismatch.
7. **Fix `AppContainer.production` fallback.** If `production` fails to create, fall back to `dev` instead of `fatalError`. The current `fatalError` is a crash risk for Arthur if the CloudKit container is not yet active.

### Phase 2: Reliability & Robustness (Before App Store)

8. **Add export encryption option.** Use `CryptoKit` (AES-256-GCM) to encrypt exports with a user-provided password. Add a toggle in the export UI: "Encrypt with password." Default to encrypted for builds where the user has entered any sensitive tasks. The `CryptoKit` import is already available (used in `OAuthCoordinator.swift` via `CC_SHA256`).
9. **Add biometric Keychain protection.** Add `kSecAccessControlBiometryCurrentSet` to `KeychainStore.set()` for API keys and OAuth tokens. Fall back to `AfterFirstUnlockThisDeviceOnly` if biometry is unavailable, but prefer it when available. This is a one-line addition to the `queryAdd` dictionary.
10. **Fix Brain Dump speech availability check.** In `BrainDumpView.onAppear`, check `SFSpeechRecognizer(locale: .autoupdatingCurrent)?.isAvailable` and set `voiceUnavailable` accordingly. If unavailable, disable the microphone button with an explanation: "Voice input is not available on this device."
11. **Add Watch `InterruptionContext` flow.** Wire `InterruptionContext.shouldShowRecovery` through `WatchConnectivityManager` so `NowView` can show the recovery card. Remove the `&& false` stub in `NowView.swift:102`.
12. **Add tests for `NotificationManager` focus session persistence.** Verify that `startFocusSession()` creates a `FocusSession` record in SwiftData and `endFocusSession()` marks it completed. This is critical because the `FocusSession` model is new and its persistence path is untested.
13. **Add tests for `AppContainer` migration.** Create a v1 database (by temporarily removing new models from the schema), populate it with sample data, then open with v2 schema and confirm data is preserved and new models are queryable. This verifies the `AuGendaMigrationPlan` actually works.
14. **Add tests for `KeychainStore`.** Test get/set/remove with error simulation. Use a mock `SecItem` wrapper or test against the real Keychain in a test container.
15. **Add tests for `OAuthCoordinator`.** Mock `URLSession` and test PKCE flow: authorize URL generation, callback parsing, token exchange, refresh. Mock `ASWebAuthenticationSession` if possible, or test the URL-building and token-decoding logic in isolation.

### Phase 3: User Experience & ND Alignment (Ongoing)

16. **Add "Morning Setup" Wizard.** A daily modal that asks: "What's your energy today?" → "Which blocks do you want?" → "Here are your top 3 tasks." This is the daily-reset scaffold Arthur needs. Use the existing `CognitiveStateSelector` and `BlockListView` components.
17. **Add UI scale override.** A `ProfilePreferences` setting for "Large UI" (bigger buttons, more spacing, larger text). This helps hEDS users with motor control issues. Scale `Tokens.Spacing.touchMinimum` and `Tokens.Typography` sizes by a user-selected factor (e.g., 1.0x, 1.25x, 1.5x).
18. **Add cost cap to AI usage.** A `maxMonthlyCostUSD` setting in `AIUsageLedger`. When `thisMonthCostUSD >= cap`, block all enrichment calls and show a banner: "AI usage paused — monthly cap reached." This enforces Arthur's $0 budget even if he accidentally enables a paid provider.
19. **Add first-class `Note` model.** Create a `Note` SwiftData model with `clientID`, `title`, `body`, `createdAt`, `updatedAt`, `relatedTaskID`. Replace `AgendaTask.notes` string with a relationship to `Note` records. This closes the `Artifact` Ontology gap and enables note search, linking, and metadata.
20. **Add focus session history view.** The `FocusSession` model persists sessions but there is no UI to view them. Add a "Focus History" section in Settings or the Focus tab that shows past sessions, completion rate, average duration, and patterns by time-of-day. This helps Arthur understand his 2–4h windows.
21. **Add interruption detail to `FocusSession`.** The model has `interruptionCount` but no timestamps or reasons. Add `interruptionTimestamps: [Date]` and `interruptionReasons: [String]` to help Arthur understand *when* and *why* he gets interrupted.

### Phase 4: CloudKit & Sync (Post-Launch)

22. **Activate CloudKit.** Register `iCloud.ensdev.AuGenda` in Apple Developer portal. Switch `AppContainer` to `.production`. Test sync across devices.
23. **Migrate `UserDefaults` active profile to `NSUbiquitousKeyValueStore`.** Store `activeProfileID` in `NSUbiquitousKeyValueStore` so it syncs across devices. This prevents context loss when Arthur switches from iPhone to iPad.
24. **Migrate `ActivityLog` and `CognitiveCheckInTracker` to CloudKit.** Store activity logs and check-in history in a lightweight CloudKit record so the `DensityAdvisor` has cross-device data.

---

## Conclusion

The remediation was **genuinely effective** — it delivered all 14 promised deliverables, fixed the 3 critical blockers (OAuth credential, schema migration, macOS compile), and elevated the codebase from C+ to B. The app is now **much closer to TestFlight-ready** than it was in v1. However, **it is not yet A-grade** because:

- Dead code (`CognitiveProfile`) creates architectural drift that will confuse future maintainers.
- Accessibility gaps in `ErrorBanner` and `RootView` violate the "no user left behind" principle — VoiceOver users cannot fully perceive errors or resume prompts.
- Missing font bundle means dyslexia-friendly font choices (`atkinson`, `openDyslexic`) are silently ignored, failing users with dyslexia who selected those fonts in settings.
- Plaintext export is a privacy boundary violation for sensitive medical, therapy, or personal task data.
- No biometric Keychain protection is a security gap for a user who may hand their phone to partners, children, or caregivers.
- The test suite, while improved from 3 to 28 tests, still lacks coverage for the most critical managers (`NotificationManager`, `BlockManager`, `WatchConnectivityManager`, `ActiveProfileManager`). The new `FocusSessionTests` and `TaskRelationshipTests` are shallow property tests, not integration tests.
- The erase-all-data path uses `try?` for deletions, risking partial erasure and database corruption.
- The watch resume context is stubbed (`NowView.swift:102`), leaving the secondary device without transition support.

**Fixing Phase 1 items (7 recommendations) would bring the grade to B+.**  
**Fixing Phase 1 + Phase 2 items (15 recommendations) would bring the grade to A−.**  
**Completing all 4 phases (24 recommendations) would achieve a solid A.**

The codebase continues to demonstrate **best-in-class ND-specific design intent**. The remediation respected that intent while addressing the critical execution gaps. The remaining work is incremental, not structural — a testament to the strong architectural foundation laid in the original build.

---

*End of Report v2.*
