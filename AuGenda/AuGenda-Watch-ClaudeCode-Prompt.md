# Claude Code — AuGenda Watch: single-push build

## Context

You're working in the **AuGenda** repository — a native iOS + macOS SwiftUI app (SwiftData + CloudKit) built for AuDHD users. This run adds the **watchOS app + complications**.

Two documents govern this work and override your own defaults:

1. `AuGenda-Watch-Spec.md` — the watch design + architecture spec (in the repo root). **Read it fully first.**
2. The AuGenda master project instructions — design philosophy, semantic token rules, accessibility-as-the-design-system.

Where the spec or master instructions conflict with your instinct, **they win.**

**Cardinal rule:** AuGenda already has a semantic token system, environment-driven adaptive rendering, and SwiftData models. **Reuse them. Do not invent a parallel system.** If something is genuinely missing, *extend the existing one* — never fork it, never hardcode.

---

## Goal of this push

In a single autonomous run, produce a **compiling, runnable, offline-first watchOS app + complication scaffold** that implements the core of the spec.

Win condition: it boots in the watch simulator and shows real local/mock data **with no iPhone paired**. Prioritize that over completeness. Stub anything that can't be finished and tag it clearly. Getting me past the blank page is the goal — I read, prune, and extend from there.

---

## Step 0 — Inventory before you build (do this first, then report)

Before writing any code, read the codebase and report a short inventory:

1. **Token system** — spacing, typography, color, density, motion, elevation. Exact type/enum names and structure.
2. **Adaptive environment values** — likely `\.cognitiveState`, `\.densityMode`, `\.reduceStimulus`, `\.attentionMode` or equivalents. Report the *actual* names.
3. **SwiftData models** — tasks, routines, focus sessions, cognitive-state — and how the `ModelContainer` / CloudKit container is currently configured.
4. **Target structure** — is there already a watchOS app or widget-extension target? Is this a raw `.xcodeproj`, or a generator (XcodeGen / Tuist / SPM)?
5. **Patterns** — skim one or two existing iOS views for the established component, styling, and accessibility conventions.

Then proceed using the **real names you found**, not the ones guessed above.

---

## What to build (mapped to the spec)

- **Shared code strategy** — make the token system, environment values, and SwiftData models available to the watch app *and* the widget extension via shared target membership / a shared framework or package. The widget extension needs an **App Group** to read the SwiftData store.
- **`NowView`** — single-column, Digital-Crown-scrollable: NOW (top, largest, one primary action) → NEXT (quiet) → CAPTURE (dictation/Scribble/Siri button). Layout is stable across every visit (spatial memory).
- **Recovery card** — injected at the top of the stack when an interruption is detected (focus session paused, backgrounded mid-task, long gap): "Welcome back — you were on X, next step Y."
- **Complications (WidgetKit)** — `accessoryRectangular` (the flagship Now/Next anchor), `accessoryCircular` / `accessoryCorner` (state glyph + semantic tint), `accessoryInline` (single line). Driven by a `TimelineProvider` with **sparse** entries — pre-render the near future, refresh on meaningful change, **never poll**. Provide a calm redacted/placeholder state.
- **Smart Stack** — make the rectangular widget Smart-Stack-eligible with basic relevance so the right thing surfaces contextually.
- **`WatchConnectivityManager`** — `WCSession` for live state (focus-session timer, immediate NEXT changes). Define the message shape for the Ollama relay and the *send* side, but **no model call on the watch** (it can't reach Ollama — that lives on the iPhone side, out of scope here).
- **Offline-first data** — own CloudKit-backed `ModelContainer` on the watch so the orientation anchor works with no phone, no network, no Mac. AI features are async garnish that degrade instantly to local data.
- **Haptics** — modern SwiftUI haptics (e.g. `.sensoryFeedback`) or `WKInterfaceDevice` haptics, mapped to the spec's gentle semantics: soft single tap for transition nudges, small success on completion (not celebratory), escalation reserved only for user-set time-critical alarms. Quiet states soften/suppress.
- **Always-On Display** — NOW (or the complication) stays legible while dimmed: current task text, decolored, reduced update cadence, no animation.
- **Accessibility** — Dynamic Type reflow (no clipping), VoiceOver labels with *cognitive meaning* ("current task, manageable" — never "green dot"), Reduce Motion → crossfades, and the **primary-action hand-gesture shortcut** so Double Tap triggers the NOW view's primary action.
- **Styling** — token-driven throughout. True-black backgrounds, muted semantic palette as **accent tint only** (ring / leading bar / dot), color never the sole carrier of meaning.

---

## Chosen defaults (decided — do not re-litigate)

- **Own SwiftData + CloudKit store on the watch** (true offline), not a WatchConnectivity snapshot.
- **AI "suggest next" is a stub this push** (deferred to v2). Build the WCSession plumbing + message shape; no Ollama call on the watch.
- **Double Tap → primary action** via the primary-action hand-gesture shortcut.
- **NEXT surfaces 1 item** in Functional mode; the Crown reveals a 2nd.

---

## Hard constraints

- No hardcoded spacing / color / typography. Reuse tokens; extend the system if needed.
- Wrap all watch-specific APIs in `#if os(watchOS)`. **Do not break the existing iOS / macOS targets** or change shared code's behavior on those platforms.
- Offline-first must hold: the app runs and shows useful data with no phone connected.
- **No destructive actions on the watch** — no delete, no irreversible operations. Gentle, reversible actions only (defer / not-now / snooze).
- Gentle haptics only; respect quiet / Bedtime states.
- Calm by construction: no aggressive animation, no full-screen color washes, no urgency red.

---

## Out of scope this push

Full task editing · deletion · analytics / history · automation config · planning surfaces · the actual Ollama relay logic (stub it) · notification-server work. Keep to the **watch UI + local data + connectivity scaffold**.

---

## The target-creation wrinkle (your one sanctioned stop point)

Creating a new watchOS app + widget-extension target by hand-editing `project.pbxproj` is error-prone and can corrupt the project.

- If a generator (XcodeGen / Tuist) is present, add the targets there declaratively.
- If it's a raw `.xcodeproj` and the surgery looks risky, **stop and ask me to create the empty watchOS App + Widget Extension target shells in Xcode**, then continue filling them in. Do not gamble on the project file.

Either way, ensure the watch app and widget extension share the models + tokens and that the widget has the App Group needed to read the SwiftData store.

---

## Verify & report

- Build the watch scheme (`xcodebuild`, or name the scheme to run). **It must compile.**
- Then summarize:
  - what's built and runnable,
  - what's stubbed (consistent `// TODO(watch v2):` tag),
  - what needs a decision from me,
  - a short, ranked "next push" list.

---

## Working style

- Work autonomously end-to-end; pause only at the target-shell juncture above.
- Keep changes coherent and reviewable — I read and prune code, so favor legible, lightly-commented seams over heavy abstraction.
- Don't gold-plate. A compiling skeleton with clear TODOs beats a half-built relay.
