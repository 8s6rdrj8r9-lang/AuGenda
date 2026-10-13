# Implementation Prompt: AuGenda macOS 27 Modernization
**Target:** macOS 27.0.1 (Golden Gate) & iOS 27  
**Architecture:** Apple Silicon (ARM64) Exclusive | Swift 6.4 | SwiftUI + SwiftData  
**Governance:** EnsDev Doctrine (Offline-first, Cognitive scaffolding, Augmentation over automation)

---

## Objective
Modernize **AuGenda** to target macOS 27 / iOS 27 with:
1. **Default AI:** Apple Foundation Model (`FoundationModels`) on-device as the default provider (`.appleFoundation`).
2. **Siri AI Delegation:** Native `AppIntents` integration allowing Siri AI and Spotlight to delegate capture, task retrieval, and enrichment actions.
3. **ChatGPT Backup:** Automatic/opt-in fallback to ChatGPT (OpenAI) when on-device models encounter guardrail false positives or device resource constraints.
4. **macOS 27 Features 1–6 Integration:**
   - **Feature 1 (AI & Delegation):** On-device foundation models default, Siri AI delegation intents, ChatGPT backup fallback.
   - **Feature 2 (SwiftData Modernization):** Native enum predicates, sectioned queries, and background observers.
   - **Feature 3 (SwiftUI 6+ Performance & Layout):** Adaptive density, toolbar overflow resilience (`toolbarOverflowMenu`, `visibilityPriority`), and Liquid Glass styling.
   - **Feature 4 (Apple Silicon Optimization):** Pure ARM64 targeting, zero x86 legacy overhead, optimized Neural Engine throughput.
   - **Feature 5 (Privacy & Transparency):** Zero cloud egress default, 0-cost token ledger tracking, explicit fallback consent.
   - **Feature 6 (Cognitive Scaffolding & Accessibility):** Sensory load tracking, focus mode integration, non-judgmental executive function support.

---

## Detailed Requirements & Implementation Steps

### 1. Default AI Provider & Fallback Engine
- In `AITaskEnricher.swift`:
  - Ensure `AIProvider.appleFoundation` is recognized as the default provider for new setups and release targets.
  - Implement fallback execution in `AIEnricherRegistry` or a coordinator: when `appleFoundation` throws an on-device error (`onDeviceGuardrailTripped`, `onDeviceModelUnavailable`, `onDeviceModelFailed`), and the user has enabled cloud backup with ChatGPT (`.openai`), smoothly execute fallback enrichment while recording appropriate token ledger and privacy disclosures.
- In `AIEnrichmentSettingsView.swift`:
  - Default `activeProviderRaw` to `AIProvider.appleFoundation.rawValue`.
  - Add settings toggle and controls for "ChatGPT Backup Fallback" with clear privacy disclosures.
- In `AppDefaultsKeys.swift`:
  - Add keys: `ai.backupProvider`, `ai.enableBackupFallback`.

### 2. Siri AI Delegation via App Intents
- Create `AuGenda/AuGendaAppIntents.swift`:
  - `CaptureBrainDumpIntent`: Allows Siri to capture thoughts directly into AuGenda's Brain Dump / Inbox.
  - `EnrichTaskIntent`: Siri-triggered task structuring via on-device Foundation Model.
  - `GetTopFocusTaskIntent`: Siri retrieval of current priority/low-friction task based on energy capacity.
  - Register with `AppShortcutsProvider` so macOS 27 Spotlight and Siri AI recognize spoken and typed intents.

### 3. SwiftData & SwiftUI Enhancements
- Support enum predicates in task query definitions, leveraging SwiftData's native enum filtering.
- Ensure toolbar and navigation elements utilize macOS 27 adaptive layout controls.

### 4. Verification
- Verify Swift syntax and clean compilation on Apple Silicon `arm64-apple-macosx27.0`.
