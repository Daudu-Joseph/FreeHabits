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

- `git diff --check` passed for the tracked changes.
- The Windows Swift parser could not start `swift-frontend` (`permission denied`), so this is not a syntax check.
- `xcodebuild` is not installed on this Windows machine. No Apple-platform build, simulator preview, IPA or device install was produced for this follow-up.
- No tests were run for this follow-up. SwiftData migration and behavior still need an Apple-platform build and runtime review.

## Still open

- Richer recurrence schedules beyond existing daily, weekday and times-per-week options.
- Interactive notification actions and a WidgetKit extension.
- Native Apple-platform build, SwiftData migration validation, and visual review on an iPhone simulator/device.

The current changes have not been built or run on an Apple platform. Stored model properties require migration validation before this update is relied on with existing data.
