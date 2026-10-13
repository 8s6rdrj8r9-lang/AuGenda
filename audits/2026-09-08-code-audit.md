# AuGenda code audit — 2026-09-08

**Remediation status:** All three findings below were addressed on 2026-09-08.
The finding descriptions and line references preserve the original audit snapshot.

Three actionable findings were identified in the current working tree. This was a targeted correctness and privacy review of task lifecycle/recurrence, notification scheduling, Watch synchronization, AI enrichment boundaries, and persistence/backup commands. Existing uncommitted changes were included. Application source was not modified.

## Findings

### P1 — One profile can expose another profile's notification content

**References:** `AuGenda/NotificationManager.swift:196–201, 315–343`; `AuGenda/ContentView.swift:896–904`.

Notification privacy is stored per profile, but `strictPrivacy` always reads the active profile. Changing that profile's notification privacy invokes `reconcilePendingAgendaNotifications`, which fetches every incomplete future agenda item without filtering ownership. It then schedules all of them using the active profile's preferences.

**Trigger:** Profile A keeps private notification previews enabled and owns a future item with sensitive notes. Switch to profile B and disable private previews. The refresh schedules A's item using B's setting, including A's title and notes in the notification. A's preference remains enabled but no longer protects that content.

**Suggested fix:** Resolve notification privacy and style from each item's owner, with a conservative fallback for unassigned records. If notifications should only cover the active profile, enforce that scope and reconcile on profile changes. Add a two-profile regression test proving one profile cannot unredact another's content.

**Evidence:** Static call-path verification; notification delivery was not exercised on a device.

### P2 — Completing a generated recurring occurrence early can terminate the series

**References:** `AuGenda/TaskLifecycle.swift:396–411, 562–585`.

Generated occurrences calculate the next date from the original series anchor and the completion timestamp. They do not require the calculated date to be later than the current occurrence. Completing an occurrence before its scheduled time can therefore calculate that same occurrence's date. The existing-occurrence lookup returns the task being completed, and no successor is created. Both backlog tasks and agenda items use this pattern.

**Trigger:** Complete a September 1 daily task to generate September 2 at 09:00. Complete the generated task on September 2 at 08:00. The next-date calculation returns September 2 at 09:00 again; the existing record is then completed, leaving no September 3 occurrence.

**Suggested fix:** Retain the original anchor for cadence/month-end behavior, but advance beyond both the completion timestamp and the current occurrence date. Add early-completion tests for both model types, including a generated monthly occurrence.

**Evidence:** Ran the actual `RecurrenceCalendar` source in a standalone Swift probe. The generated date and next date on early completion were both `2026-09-02 09:00:00 +0000`. Static inspection confirms the lookup returns the current record. Existing series tests complete occurrences after their scheduled time and do not cover this case.

### P2 — Notification refresh silently cancels outstanding snoozes

**References:** `AuGenda/NotificationManager.swift:315–343, 376–389`; `AuGenda/ContentView.swift:904`; `AuGenda/TaskBacklogView.swift:237`.

Reconciliation removes all pending agenda-category notifications, including snooze reminders. It rebuilds reminders only for items whose original scheduled date is still in the future, and calls ordinary scheduling without honoring `snoozedUntil`.

**Trigger:** Snooze an overdue item for ten minutes, then change private notification previews. Reconciliation cancels the snooze and excludes the item because its original scheduled time has passed. No reminder replaces it. Restoring a backup with a future snooze on an overdue item has the same omission. For originally future items, refresh can instead restore the original reminder time and interrupt the snooze.

**Suggested fix:** Include incomplete items with future snooze deadlines and prioritize `scheduleSnooze` over ordinary scheduling when rebuilding notifications. Test both an overdue snoozed item and an originally future item.

**Evidence:** Static verification of cancellation, selection, and reconstruction paths; notification delivery was not exercised on a device.

## Validation and limits

- Passed the main macOS unit suite using `xcodebuild test -project AuGenda.xcodeproj -scheme AuGenda -destination 'platform=macOS' -only-testing:AuGendaTests -derivedDataPath build/audit-derived CODE_SIGNING_ALLOWED=NO`.
- The first sandboxed attempt failed because Xcode's SwiftData macro compiler could not operate. The permitted rerun outside the sandbox succeeded.
- Result bundle: `build/audit-derived/Logs/Test/Test-AuGenda-2026.09.08_09-29-07--0600.xcresult`.
- Ran a standalone recurrence calendar probe; no production source or existing tests were changed.
- Did not run iOS/watchOS builds, UI tests, device notification delivery, live WatchConnectivity delivery, or real AI provider requests. Passing unit tests does not disprove the uncovered edge cases above.
- Repository guidance is stale: `AGENTS.md` says recurrence is unimplemented, while the current lifecycle code implements it. Future reviews should use the current code as evidence of behavior.


## Remediation verification — 2026-09-08

- Agenda reminder planning now resolves the owner's privacy and style. Missing
  or unassigned owners use redacted content and minimal reminders. Direct snooze
  scheduling uses that same policy.
- Notification reconciliation includes incomplete overdue items, and reminder
  planning preserves snooze deadlines instead of restoring the original schedule.
- Both recurrence services advance beyond the current occurrence as well as the
  completion time while retaining the original cadence anchor.
- Added regression tests for two-profile privacy/style isolation, fallback,
  overdue/future snoozes, completed/expired snoozes, and early daily/monthly
  completion with idempotent replays for both task model types.
- The full main macOS unit suite passed after these changes. Result bundle:
  `build/audit-derived/Logs/Test/Test-AuGenda-2026.09.08_09-39-33--0600.xcresult`.
- Updated SPEC, PRD, developer documentation, and stale recurrence guidance.
  Device notification delivery and iOS/watchOS validation remain untested here.
