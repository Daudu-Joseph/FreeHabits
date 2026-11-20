# FreeHabits improvement status

Implemented 2026-11-19 in the original `FreeHabits` SwiftUI project.

## Implemented

- Today, Progress and Data tabs, with adaptive system light/dark surfaces and purple progress accents.
- Progress: completion distribution, 53-week activity heatmap with day selection, monthly totals, schedule-based 30-day consistency and habit ranking. Includes archived history and a per-habit filter. Empty history shows an empty state, not example activity.
- SwiftPieces `ActivityHeatmap` 1.3.0 source and license included. Earlier dashboard cards/charts were custom SwiftUI and Apple Charts.
- JSON backup export through Files, schema/version validation, restore preview and explicit import. Imports are new copies, including archives; repeating an import duplicates habits. No existing habit is deleted or overwritten. Reminder preferences are retained; notification permission remains controlled by iOS.
- Daily/scheduled-day streak calculations skip rest days; weekly goals count completed weeks. An unfinished current day/week preserves the preceding streak until that period ends.
- Rates exclude days before creation and after archival. Weekly rates count distinct completed days against weekly quotas, capped at the quota. A partial week in the 30-day window retains its full weekly goal; this is goal progress, not a prorated daily rate. Current schedule is applied retrospectively because the original model stores no schedule-change history.
- Detail stats show actual completed/expected counts and distinguish weekly streak units.

## First-stage validation snapshot

- Swift compiler parse against the existing iOS SDK: passed, all application Swift source.
- Native Windows compiled calendar harness: passed seven scenarios (scheduled rest, missed scheduled day, creation/duplicate handling, open weekly goal, missed week, future entries, empty history).
- `git diff --check`: passed.
- Full iOS typecheck: attempted with the existing Windows Swift/Darwin SDK; interrupted after several minutes without diagnostics or completion. This is NOT a successful typecheck or build.
- No IPA produced, no device install, and no visual/device validation performed. Files import/export, SwiftData transaction behavior and chart layouts still require an Apple-platform build and runtime check before relying on the update.

Those checks describe the first-stage source snapshot only. The follow-up below changes stored model properties and must be validated separately before use with existing data.

## Follow-up implementation

- Added optional SwiftData fields for tracking kind, amount target/unit, category, checklist definitions, pause ranges and per-day amount, relapse, checklist, note and note-only data. Existing fields and completion records are retained; an Apple-platform migration check is still required.
- Added amount-goal, checklist and avoidance selection to habit creation/editing, plus category and a one-range pause editor.
- Added a daily log sheet to specialized habit cards and day notes from the detail calendar. Note-only rows do not count as completions. Amount goals complete only when the target is reached; checklists complete when every item is checked; relapse entries are excluded from completed streak days.
- Pause days are omitted from due-day metrics, and weekly targets are reduced for paused days. Progress and calendar views now count only records that satisfy the selected tracking goal.
- Extended backup export/restore to retain the new habit fields and per-day log details while allowing older backups to omit them.
- Added a 25-minute focus timer launched from habit detail. The follow-up replaces its custom ring/controls with SwiftPieces `TimerDial`, allows one-minute additions while paused, and does not persist sessions or auto-complete the habit.
- Added category labels to habit detail and list views.
- Added SwiftPieces `DateStrip` to navigate dates in both Today layouts, with future dates disabled.
- Replaced the custom monthly Apple Chart with SwiftPieces `ScrubChart`, with 30-day, 3-month, 6-month and 1-year ranges and no fabricated empty-history data.
- Replaced the custom completion donut with SwiftPieces `RingBreakdown`, retaining the actual per-habit completion counts and colors.
- Replaced the two pause-date controls with SwiftPieces `DateRangePicker`.
- Added exact component versions, registry source links and usage notes to `FreeHabits/Components/SwiftPieces/PROVENANCE.md`.

## Follow-up verification

- GitHub Actions run #9 succeeded on the hosted Mac runner: https://github.com/Daudu-Joseph/FreeHabits/actions/runs/44626487873 (2m 11s). Source commit: `299b39f`, branch `codex/free-personal-install` in `Daudu-Joseph/FreeHabits`. Uploaded the changed source through the signed-in GitHub browser; the local dirty checkout was preserved.
- Downloaded artifact digest matched GitHub's SHA-256: `dbbf5ddd2decef6efbaac328ac1031dbc44e58fed21b054bfe47ffbe23882b88`.
- Extracted IPA: `C:\Users\acer\Desktop\TASK\FreeHabits-install\FreeHabits-improved-build9.ipa`, 1,613,070 bytes; SHA-256 `8d87b57670f56affa63ccfb220f190347fde16388e22f2ee91d113a3fc4328e3`.
- IPA ZIP integrity passed; metadata confirms `com.daudu.joseph.freehabits`, version/build `1.0 / 1`, minimum iOS `18.0`, and zero embedded Watch entries.
- `git diff --check` passed for the tracked changes.
- The Windows Swift parser could not start `swift-frontend` (`permission denied`), so this is not a syntax check.
- `xcodebuild` is not installed on this Windows machine; the successful archive and IPA above were produced by GitHub's hosted Mac runner.
- No tests were run for this follow-up. SwiftData migration and behavior still need an Apple-platform build and runtime review.

## Still open

- Richer recurrence schedules beyond existing daily, weekday and times-per-week options.
- Interactive notification actions and a WidgetKit extension.
- Device installation, SwiftData migration validation, and visual review on an iPhone simulator/device.

The current changes compiled and archived successfully on an Apple platform. They have not been installed or run on the user's iPhone. Stored model properties still require migration validation with existing data.

## Voice and repeat-reminder update - 2026-11-20

Implemented in source:
- SwiftPieces ThoughtOrb 1.2.0 Swift source and Metal shader, with its morphing status pill and palettes for listening, thinking, speaking and review. Decorative animation does not represent microphone amplitude.
- Locally scheduled habit reminders repeat at 15, 30, 60 or 120 minutes until completed, snoozed or skipped for that calendar day. A stable optional reminder identity keeps notification actions attached to the right habit.
- Notification actions: Done completes the whole goal; Snooze uses the configured interval; Skip silences today without awarding a completion. Actions for past days are ignored. Note-only records are preserved.
- Quiet hours default to 22:00-08:00. Reminders do not bypass iOS Focus, silent mode or notification permissions. Spoken reminders are optional and run only while the app is active, without interrupting orb recording or playback.
- Overdue cards in Today and Voice. This is an in-app card, not a WidgetKit Home Screen extension.
- Local voice commands, with explicit confirmation: "mark Gym done", "I already did Gym", "skip Gym today", "snooze Gym for 30 minutes", "remind me about Gym in 30 minutes". Commands require a unique exact habit name; supported snooze intervals are 15/30/60/120. Other requests use NVIDIA and its configured key/model.
- The notification queue is capped at 60 and populated from the next seven days. This is NOT a promise of seven-day coverage: frequent alerts or many habits can exhaust the queue much sooner. Opening the app or using an action refills it. No background AI polling or unlimited closed-app alarm loop is claimed.

Still open: iPhone runtime validation of notification delivery/actions, microphone, spoken reminders, NVIDIA access, SwiftData migration, and the Home Screen widget update below. Existing completed build #11 predates Thought Orb and repeat reminders.

### Update build evidence

- Final source commit: b8cf13407a478b43465f8a738560e79bfe87d9dd (the initial Thought Orb/reminder commit is cdc8696fef48f688fa8164acae941a7b355512df).
- GitHub Actions build #13 succeeded (1m 47s): https://github.com/Daudu-Joseph/FreeHabits/actions/runs/44754690445 . The archive compiled the SwiftUI, notification delegate and Metal sources. No test suite was run.
- Downloaded artifact ZIP SHA-256 matches GitHub: d69cb4945487968b247df26e5783730b847eb3658ca00171d126ec6548cec740.
- IPA retained at C:\Users\acer\Desktop\TASK\FreeHabits-install\FreeHabits-voice-reminders-build13.ipa, 1,922,515 bytes; SHA-256 dbfd404ec3f54b77cb90e72184637e048784727d4d55c1a39f7c4c0dec499e0e.
- Package integrity passed. Metadata confirms com.daudu.joseph.freehabits, 1.0 / 1, iOS 18.0 minimum, microphone/speech permission descriptions, default.metallib, no Watch entries and no app extensions.
- Install instructions: FreeHabits-install/INSTALL-voice-reminders-build13.md. Runtime behavior and existing-data migration are unverified on iPhone. No NVIDIA key or authenticated provider request was used during this update.

## Home Screen widget update - 2026-11-20

- Added a WidgetKit extension with medium and large Today widgets for habits that are due and not yet logged. Rows use the SwiftPieces `TaskRow` 2.2.0 source; WidgetKit supplies the extension, and App Intents supply Done, Snooze and Skip buttons.
- The app publishes a compact snapshot through an App Group container. The widget displays the last snapshot and system-managed timeline refreshes; iOS does not promise immediate or continuous widget refresh.
- Widget button taps queue the action and update the displayed snapshot. FreeHabits applies queued actions to its SwiftData records when the app next becomes active, then rebuilds the widget snapshot. The widget does not open the app or write the SwiftData store directly.
- Snooze uses the app's selected repeat interval. Amount habits include current progress. Local notifications remain responsible for timely reminders; a widget does not speak.
- The free-personal-account IPA workflow must be built and installed to verify that AltServer provisions both the WidgetKit extension and App Group entitlement. Widget availability in the iPhone gallery, button behavior, App Group signing, and existing-data migration remain unverified until device installation.
