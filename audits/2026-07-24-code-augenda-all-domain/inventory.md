# AuGenda All-Domain Audit — File and Domain Inventory

- **Audit ID:** `2026-07-24-code-augenda-all-domain`
- **Snapshot:** branch `active-dev`, commit `d7f059e`, including the uncommitted working tree as observed before remediation
- **Purpose:** demonstrate that every in-scope production, test, configuration, asset, and documentation path was assigned to an audit domain

## Production Swift — Main App

### AI, privacy, authentication, and secrets

```text
AuGenda/AIEnricher_AppleFoundation.swift
AuGenda/AIEnricher_Claude.swift
AuGenda/AIEnricher_DeepSeek.swift
AuGenda/AIEnricher_Gemini.swift
AuGenda/AIEnricher_Grok.swift
AuGenda/AIEnricher_Mistral.swift
AuGenda/AIEnricher_Ollama.swift
AuGenda/AIEnricher_OpenAI.swift
AuGenda/AIEnricher_OpenAICompatible.swift
AuGenda/AIEnricher_Perplexity.swift
AuGenda/AIEnrichmentSettingsView.swift
AuGenda/AIPersonalization.swift
AuGenda/AITaskEnricher.swift
AuGenda/AIUsageLedger.swift
AuGenda/GoogleOAuth.swift
AuGenda/KeychainStore.swift
AuGenda/OAuthCoordinator.swift
```

### Persistence, migration, import/export, and domain models

```text
AuGenda/AgendaItem.swift
AuGenda/AgendaTask.swift
AuGenda/AppContainer.swift
AuGenda/AppDefaultsKeys.swift
AuGenda/BlockModels.swift
AuGenda/CognitiveProfile.swift
AuGenda/DifficultyEngine.swift
AuGenda/FocusSession.swift
AuGenda/InboxItem.swift
AuGenda/Note.swift
AuGenda/ProfileModels.swift
AuGenda/TaskImportExport.swift
AuGenda/TaskRelationship.swift
```

### App shell, workflows, UI, and accessibility

```text
AuGenda/AddNoteSheet.swift
AuGenda/AuDHDComponents.swift
AuGenda/AuDHDLayout.swift
AuGenda/AuDHDNDComponents.swift
AuGenda/AuDHDProgressComponents.swift
AuGenda/AuGendaApp.swift
AuGenda/BlockView.swift
AuGenda/CognitiveStateSelector.swift
AuGenda/ContentView.swift
AuGenda/DesignTokens.swift
AuGenda/ErrorBanner.swift
AuGenda/FocusSessionHistoryView.swift
AuGenda/FocusSessionView.swift
AuGenda/HomeDashboardView.swift
AuGenda/HouseholdView.swift
AuGenda/InboxView.swift
AuGenda/InterruptionPickerSheet.swift
AuGenda/MorningSetupView.swift
AuGenda/OnboardingView.swift
AuGenda/ProfileViews.swift
AuGenda/SmartSuggestView.swift
AuGenda/TaskBacklogView.swift
AuGenda/TaskDetailView.swift
```

### Platform services, notifications, and cross-device integration

```text
AuGenda/NotificationManager.swift
AuGenda/WatchConnectivityManager.swift
```

The four groups above assign all 55 main-app Swift files present at the baseline.

## Production Swift — Watch App

Assigned to Watch UI, data parity, persistence, accessibility, offline behavior, and WatchConnectivity:

```text
AuGendaWatch Watch App/AgendaItem.swift
AuGendaWatch Watch App/AgendaTask.swift
AuGendaWatch Watch App/AuGendaWatchApp.swift
AuGendaWatch Watch App/NowView.swift
AuGendaWatch Watch App/ProfileModels.swift
AuGendaWatch Watch App/WatchAppContainer.swift
AuGendaWatch Watch App/WatchSessionClient.swift
AuGendaWatch Watch App/WatchTokens.swift
```

## Production Swift — Widget/Complication Extension

Assigned to extension persistence, App Groups/signing, timelines, intents, privacy, and visual accessibility:

```text
AuGendaWatchWidgets/AgendaItem.swift
AuGendaWatchWidgets/AgendaTask.swift
AuGendaWatchWidgets/AppIntent.swift
AuGendaWatchWidgets/AuGendaWatchWidgets.swift
AuGendaWatchWidgets/AuGendaWatchWidgetsBundle.swift
AuGendaWatchWidgets/AuGendaWatchWidgetsControl.swift
AuGendaWatchWidgets/ProfileModels.swift
AuGendaWatchWidgets/WatchAppContainer.swift
AuGendaWatchWidgets/WatchTokens.swift
```

## Test Swift

### Main unit and migration tests

```text
AuGendaTests/AppDefaultsKeysTests.swift
AuGendaTests/AuGendaTests.swift
AuGendaTests/DifficultyEngineTests.swift
AuGendaTests/FocusSessionTests.swift
AuGendaTests/KeychainStoreTests.swift
AuGendaTests/MigrationTests.swift
AuGendaTests/NotificationManagerTests.swift
AuGendaTests/StateEngineTests.swift
AuGendaTests/TaskImportExportTests.swift
AuGendaTests/TaskRelationshipTests.swift
```

### Main UI tests

```text
AuGendaUITests/AuGendaUITests.swift
AuGendaUITests/AuGendaUITestsLaunchTests.swift
```

### Watch unit and UI tests

```text
AuGendaWatch Watch AppTests/AuGendaWatch_Watch_AppTests.swift
AuGendaWatch Watch AppUITests/AuGendaWatch_Watch_AppUITests.swift
AuGendaWatch Watch AppUITests/AuGendaWatch_Watch_AppUITestsLaunchTests.swift
```

These paths were assigned to coverage quality, assertion quality, migration realism, negative paths, UI automation, accessibility automation, and paired-device verification.

## Xcode Project, Workspace, and Schemes

Assigned to target membership, build settings, deployment targets, signing/capabilities, resources, archive behavior, scheme isolation, and reproducibility:

```text
.gitignore
AuGenda.xcodeproj/project.pbxproj
AuGenda.xcodeproj/project.xcworkspace/contents.xcworkspacedata
AuGenda.xcodeproj/xcshareddata/xcschemes/AuGenda.xcscheme
AuGenda.xcodeproj/xcshareddata/xcschemes/AuGendaWatch Watch App.xcscheme
AuGenda.xcodeproj/xcshareddata/xcschemes/AuGendaWatchWidgetsExtension.xcscheme
AuGenda.xcodeproj/xcuserdata/arthur.xcuserdatad/xcschemes/xcschememanagement.plist
```

The tracked `xcuserdata` path was additionally assigned to working-tree/repository hygiene.

## Plists, Entitlements, Privacy Manifests, and Scripts

Assigned to runtime declarations, privacy accuracy, OAuth callbacks, local-network/ATS requirements, export compliance, capabilities, and release gates:

```text
AuGenda/AuGenda.entitlements
AuGenda/Info.plist
AuGenda/PrivacyInfo.xcprivacy
AuGenda/Scripts/validate-oauth.sh
AuGendaWatch Watch App/PrivacyInfo.xcprivacy
AuGendaWatchWidgets/Info.plist
AuGendaWatchWidgets/PrivacyInfo.xcprivacy
```

## Assets and Bundled Resources

Every file beneath the following baseline paths was inspected by manifest review, file-signature checks, Xcode build output, or built-bundle inspection and assigned to asset correctness, accessibility, privacy, packaging, or app-icon validation:

```text
AuGenda/Assets.xcassets/**
AuGenda/Fonts/**
AuGendaWatch Watch App/Assets.xcassets/**
AuGendaWatchWidgets/Assets.xcassets/**
```

This includes the three files presented as fonts, all main/Watch/widget catalog `Contents.json` files, every icon PNG, color-set manifests, and the backup app-icon catalog. Deleted-but-tracked widget app-icon files visible in the working tree were included in the project/resource review.

The following non-code resources were also assigned to packaging and documentation truthfulness:

```text
AuGenda/AuGenda-Watch-ClaudeCode-Prompt.md
AuGenda/Fonts/README.md
```

## Product and Developer Documentation

Assigned to requirements traceability, current-state truthfulness, compatibility, privacy/accessibility claims, test claims, release status, and internal-resource packaging:

```text
DESIGN_SYSTEM_USAGE.md
DEVELOPER_DOCUMENTATION.md
GETTING_STARTED.md
KIMI-CODE-PROMPT.md
PRD-GAP-FIX-PROMPT.md
PRD-compliance-audit.md
PRD.md
SPEC.md
audit-report.md
audit-report-v2.md
audit-report-v3.md
audit-report-v4.md
audit-report-v5.md
audit-report-v6.md
```

`audit-report-v5.md` and `audit-report-v6.md` were untracked at the baseline; they were still in scope because the audit explicitly included the current working tree.

## Unrelated Working-Tree Material

The following untracked paths were assigned only to hygiene/coupling review. A repository-wide reference search found no runtime or Xcode-project coupling to them:

```text
resonator-audit-report.md
resonator-ble-data-transfer.md
resonator-core-hrs.md
resonator-design-review.md
resonator-pass5-ensdev-audit.md
resonator-pogo-vs-qi.md
resonator-production-audit-pass1.md
resonator-production-audit-pass2.md
resonator-production-audit-pass3.md
resonator-production-audit-pass4.md
resonator-production-audit-pass5.md
resonator-production-audit-unified.md
resonator-sensor-options.md
```

## Audit Outputs

The audit’s own files are evidence artifacts, not product runtime inputs:

```text
audits/2026-07-24-code-augenda-all-domain/scope.md
audits/2026-07-24-code-augenda-all-domain/inventory.md
audits/2026-07-24-code-augenda-all-domain/findings.md
audits/2026-07-24-code-augenda-all-domain/remediation.md
audits/2026-07-24-code-augenda-all-domain/verification.md
audits/2026-07-24-code-augenda-all-domain/risk-register.md
```

## Exclusions

Generated DerivedData, simulator state, `.git` object storage, build products outside the repository, and operating-system/Xcode internals were excluded as implementation inputs. They were used only as verification evidence where explicitly recorded in `verification.md`.
