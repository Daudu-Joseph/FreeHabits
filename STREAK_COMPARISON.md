# FreeHabits improvement plan

Reviewed 2026-11-19. FreeHabits findings come from the local Swift source, not a new device inspection. Streak findings are advertised features in its current [official README](https://github.com/InlitX/streak#features); they were not independently tested. Streak currently lists iOS as in progress.

## Existing foundation

FreeHabits already implements one-tap completion, grid/list layouts, past-day navigation and logging, daily/specific-weekday/weekly-target schedules, current/best streaks, totals, a completion-rate ring, monthly history, reminders, archiving, reorder, dark mode and confetti. Source also contains Apple Health integration; its operation in the installed personal build is unverified. The installed package excludes the Watch companion. Personal builds explicitly disable CloudKit.

## Feature gaps

| Area | FreeHabits source today | Streak advertises | Proposed priority |
| --- | --- | --- | --- |
| Data portability | No backup or restore UI/service found | File backup/restore, automatic backups, imports | First |
| Progress visualization | Month calendar, last-seven-days strip, per-habit numbers | Year activity grid, monthly totals, streak charts, overall insights | First |
| Habit types | Binary daily completion | Amount goals, avoidance/relapses, checklists | Second |
| Scheduling | Daily, specific weekdays, times/week | Also times/month and every N days | Second |
| Pauses | Archive/unarchive only | Vacation pause | Second |
| Daily context | Date and completion record only | Notes and photos | Second; notes before photos |
| Organization | Manual order; preset icons/colors | Categories, emoji, covers | Second; categories first |
| Notifications | Reminder plus evening nudge | Completion/snooze/amount actions | Third |
| Home widgets | No WidgetKit target found | Multiple interactive widget types | Third; needs iOS implementation |
| Focus | No timer/session model found | Timer, Pomodoro, sound, session history | Later |
| Sharing | No progress export found | Shareable progress image | Later |
| Personalization | Grid/list, palette, system appearance | Multiple designs, backgrounds, icons | Later |
| Privacy lock | No app lock found | PIN/biometric lock | Optional |
| Tasks | No task/project system found | Tasks/projects/tags | Optional; avoid expanding scope initially |

## Correctness work before new features

- `Models/Habit.swift`: current and best streaks require adjacent calendar days. They ignore scheduled rest days and weekly targets. Define daily, scheduled-day and weekly-target streak units explicitly before changing the calculation.
- `Models/Habit.swift`: the 30-day rate includes dates before `createdAt`; weekly targets are treated as daily obligations.
- `Views/HabitDetail/HabitDetailView.swift`: the rate subtitle estimates completed days by multiplying the rate by 30. That is inaccurate for scheduled habits and new habits. Show actual completed/due counts.
- `ContentView.swift`: daily completed count and due count use different filters; historical views also need creation/archive boundaries considered.
- `Models/AppMigrationPlan.swift`: no active migration plan. Introduce and validate a data-preservation strategy before adding persistent model fields. Never solve a schema issue by resetting the installed store.

## Delivery order

1. Correct streak/rate calculations and add versioned JSON export/restore with validation and a restore preview.
2. Add a year heatmap and an overall progress screen, using existing completion records first.
3. Add amount goals, notes, richer schedules and pause history with a deliberate SwiftData migration.
4. Add notification actions and evaluate iOS widgets against the existing personal signing workflow.
5. Consider focus sessions and deeper appearance changes after the core tracker is reliable.

Remain native SwiftUI. Implement behavior for FreeHabits using its existing SwiftData store. Streak is a Flutter project, so its UI source cannot be pasted into this app. Any source reuse requires a separate review of its license and additional terms.

This comparison changes no application code. No new build, installation, device operation or automated test was performed.
