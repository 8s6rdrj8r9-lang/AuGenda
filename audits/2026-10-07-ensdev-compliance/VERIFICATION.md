# Verification record

Audit: **AUGENDA-ENSDEV-2026-10-07**. Methods were run after explicit freeze against a disposable execution copy of the accepted snapshot. Source/test/resource/build-setting bytes were unchanged; temporary launch-isolation settings and their reversal are recorded below. External research, live providers, production data and release signing were excluded.

## Actual results

| Record | Check | Configuration / actual result | Limit |
| --- | --- | --- | --- |
| E-011 | Main unit suite | Xcode 27.0 (27A266a), SDK 27.0, macOS 26.6.2 arm64: **129 passed, 0 failed, 0 skipped** | In-memory/temporary fixtures and test launch home; not every UI/real store/device path |
| E-012 | iOS Release build | Generic iOS, minimum 26.5, signing disabled: **exit 0** | Compilation/package facts; no signed archive/provisioning/device run |
| E-013 | Watch Release build-for-testing | Generic watchOS, minimum 26.5, signing disabled, testability enabled: **exit 0** | Includes Watch/widget/test products; not device transport or test execution |
| E-014 | Static checks/package/coverage | **21 checks passed**: plist/entitlement/privacy/project syntax, asset/test-plan JSON, shell syntax. No document/script/font files found in built selected packages. App coverage **9,521/43,841 = 21.72%** | Coverage exceeds 7% CI floor; >80% PRD goal remains aspirational. Selected payload omits obsolete task-prompt content; project configuration explicitly excludes that prompt, font README and script from target membership. No original distributed-package claim |
| E-015 | First onboarding attempt + warm retry | First assertion: expected `capacity.title` absent. Initial diagnostic/result collection stalled and audit-owned xcodebuild was interrupted; final runner exit 75. Bounded warm retry: **0 passed, 1 failed, exit 65** | Initial interrupted runner exit is not an app-crash finding; retry supplies a valid failed result. Both used test-home isolation |
| E-016 | Watch unit + launch smoke | Audit-created Apple Watch Series 11 46mm Simulator, watchOS 26.5: **6 passed, 0 failed, 0 skipped**, exit 0 | Five Swift Testing unit tests plus one UI launch test; no paired physical phone/App Group proof |
| E-017 | OAuth built-plist validator | **exit 0**, output: Google OAuth not configured; sign-in remains disabled | Correctly disabled optional sign-in; no actual OAuth success, provider registration or server evidence |
| E-018 | Original-source-plan onboarding reconciliation | Original main scheme/test-plan bytes restored, no CFFIXED_USER_HOME override, same Swift/tests/assertion, audit iPhone 17 Pro/iOS 26.5: **0 passed, 1 failed, exit 65** | Establishes the failed outcome in this configuration; platform/application causal mechanism still UNKNOWN |
| E-019 | Separate controlled local launch screenshot | Same installed Debug product launched with `-ui-testing`; Home visible without capacity sheet | Separate corroboration, not an attachment from the assertion; no claim of every launch/device |

Expected corrupted-store errors in Mac failure-path tests were not treated as app defects: the relevant assertions passed. Metadata extraction warnings did not turn successful builds into failures. Passing checks remain valid despite the distinct failed onboarding outcome.

## Test isolation and transformations

- Frozen sources: `local-artifacts/ensdev-audit-2026-10-07/input-v1/project/`, read-only, file-manifest hash in the freeze record.
- Execution copy: `local-artifacts/ensdev-audit-2026-10-07/verification/workspace/`. Only the initial main scheme/test plan received the existing `-ui-testing` argument and a disposable `CFFIXED_USER_HOME`; Foundation NSHomeDirectory/Application Support redirection was probed before execution. Mac tests used synthetic Keychain test accounts and disposable stores.
- The final iOS check restored original scheme/test-plan bytes. Its existing UI test itself sets `-ui-testing`. The audit-created simulator supplies its separate device data context; the disposable-home override was removed for this run. No assertion, Swift file, persistent model, test fixture or product build setting was repaired.
- Generic Release builds were not launched against user stores. No live-provider availability method or OAuth authorization was called.
- The first iOS runner was signalled only after its assertion failed and diagnostic output remained stalled for minutes. Original failure/log/result-finalization limits were retained. Two bounded follow-ups investigated a material execution conflict; there was no rerun-until-pass or weakened test.
- Audit-created simulator IDs and cleanup results are retained under verification. Original user simulators were not erased or shut down.

## Exact commands

The full argument arrays, working copy and per-check results/logs are in `commands.json` and the named `*-result.json` files in the verification directory. Mac runner environment adds only its verified disposable Foundation home; final source-plan iOS execution removes that override.

### mac-unit

```text
xcodebuild test -project AuGenda.xcodeproj -scheme AuGenda -destination platform=macOS -only-testing:AuGendaTests -parallel-testing-enabled NO -enableCodeCoverage YES -derivedDataPath "/Users/arthur/Development/AuGenda/local-artifacts/ensdev-audit-2026-10-07/verification/derived-mac" -resultBundlePath "/Users/arthur/Development/AuGenda/local-artifacts/ensdev-audit-2026-10-07/verification/mac-unit.xcresult" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
```

### ios-release

```text
xcodebuild build -project AuGenda.xcodeproj -scheme AuGenda -configuration Release -destination "generic/platform=iOS" -derivedDataPath "/Users/arthur/Development/AuGenda/local-artifacts/ensdev-audit-2026-10-07/verification/derived-ios" CODE_SIGNING_ALLOWED=NO
```

### watch-release

```text
xcodebuild build-for-testing -project AuGenda.xcodeproj -scheme "AuGendaWatch Watch App" -configuration Release -destination "generic/platform=watchOS" -derivedDataPath "/Users/arthur/Development/AuGenda/local-artifacts/ensdev-audit-2026-10-07/verification/derived-watch" CODE_SIGNING_ALLOWED=NO ENABLE_TESTABILITY=YES
```

### watch-smoke

```text
xcodebuild test -project AuGenda.xcodeproj -scheme "AuGendaWatch Watch App" -destination "platform=watchOS Simulator,id=D9CCB87D-4C0E-44B0-9D3E-5D66C2A2BC72" -parallel-testing-enabled NO "-only-testing:AuGendaWatch Watch AppTests" "-only-testing:AuGendaWatch Watch AppUITests/AuGendaWatch_Watch_AppUITests/testLaunchShowsCaptureSurface" -derivedDataPath "/Users/arthur/Development/AuGenda/local-artifacts/ensdev-audit-2026-10-07/verification/derived-watch-smoke" -resultBundlePath "/Users/arthur/Development/AuGenda/local-artifacts/ensdev-audit-2026-10-07/verification/watch-smoke.xcresult"
```

### ios-smoke-retry

```text
xcodebuild test -project AuGenda.xcodeproj -scheme AuGenda -destination "platform=iOS Simulator,id=C9E8F920-E670-4D2B-A7D7-C7411252645E" -parallel-testing-enabled NO "-only-testing:AuGendaUITests/AuGendaUITests/testCleanLaunchShowsCapacityChoice" -derivedDataPath "/Users/arthur/Development/AuGenda/local-artifacts/ensdev-audit-2026-10-07/verification/derived-ios-smoke" -resultBundlePath "/Users/arthur/Development/AuGenda/local-artifacts/ensdev-audit-2026-10-07/verification/ios-smoke-retry.xcresult" -collect-test-diagnostics never -test-timeouts-enabled YES -maximum-test-execution-time-allowance 90
```

### ios-source-plan

```text
xcodebuild test -project AuGenda.xcodeproj -scheme AuGenda -destination "platform=iOS Simulator,id=C9E8F920-E670-4D2B-A7D7-C7411252645E" -parallel-testing-enabled NO "-only-testing:AuGendaUITests/AuGendaUITests/testCleanLaunchShowsCapacityChoice" -derivedDataPath "/Users/arthur/Development/AuGenda/local-artifacts/ensdev-audit-2026-10-07/verification/derived-ios-smoke" -resultBundlePath "/Users/arthur/Development/AuGenda/local-artifacts/ensdev-audit-2026-10-07/verification/ios-source-plan.xcresult" -collect-test-diagnostics never -test-timeouts-enabled YES -maximum-test-execution-time-allowance 90
```

## Retained evidence and practical limits

Result bundles and full logs remain under the local verification directory. Structured summaries are retained beside them and copied into this report directory for inspection. Detailed uncompressed built payload sizes were observed only for the unsigned products: iOS 23,478,916 bytes including embedded content, Watch 6,454,517 bytes. These are not measured App Store download/install sizes and do not resolve the PRD's release-size criterion.

No measured iPhone 14 cold/warm launch, 1,000-task scrolling, 60-minute timer drift, memory/battery matrix, full assistive-technology/localization workflows, live AI/OAuth/WeatherKit, signed entitlements, physical Watch transport, production migration, public population or legal applicability evidence was collected. Each material unknown is tied to its requirement in the report; this list does not invalidate unrelated passing tests.

Portable structured summaries omit device identifiers; canonical result bundles and unredacted local summaries retain their original provenance. This is a redacted report view, not a different result.
