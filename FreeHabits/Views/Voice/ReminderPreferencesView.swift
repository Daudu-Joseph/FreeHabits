import SwiftUI
import SwiftData

struct ReminderPreferencesView: View {
    @AppStorage("reminderRepeatsEnabled") private var repeats = true
    @AppStorage("reminderRepeatMinutes") private var minutes = 15
    @AppStorage("reminderQuietEnabled") private var quiet = true
    @AppStorage("reminderQuietStart") private var start = 22
    @AppStorage("reminderQuietEnd") private var end = 8
    @AppStorage("reminderSpeakForeground") private var speaks = false
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Toggle("Repeat until logged", isOn: $repeats)
            if repeats {
                SelectMenu("Repeat every", selection: $minutes, options: [15, 30, 60, 120]) { "\($0) minutes" }.zIndex(30)
            }
            Toggle("Quiet hours", isOn: $quiet)
            if quiet {
                SelectMenu("Quiet from", selection: $start, options: Array(0..<24)) { String(format: "%02d:00", $0) }.zIndex(20)
                SelectMenu("Quiet until", selection: $end, options: Array(0..<24)) { String(format: "%02d:00", $0) }.zIndex(10)
                if start == end { Text("Matching hours turns quiet hours off.").font(.caption).foregroundStyle(.secondary) }
            }
            Toggle("Speak reminders while app is open", isOn: $speaks)
            Text("Set a reminder time in each habit. Done marks its whole goal complete. Snooze delays by your repeat interval. Skip silences today without awarding a completion. Reminders stop at midnight and resume on the next scheduled day.")
                .font(.caption).foregroundStyle(.secondary)
            Text("iOS controls delivery, sound, Focus and notification summaries. Up to 60 alerts are queued; open FreeHabits or use a notification action to refill the queue. Frequent reminders for many habits shorten how far ahead it lasts. Spoken reminders work only while the app is active.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// An in-app summary; this does not claim to be a WidgetKit Home Screen extension.
struct OverdueHabitsCard: View {
    @Query(sort: \Habit.sortOrder) private var habits: [Habit]
    @State private var revision = UUID()
    @State private var error: String?
    private var overdue: [Habit] {
        let _ = revision
        let seconds = Calendar.current.dateComponents([.hour, .minute], from: Date())
        let time = Double((seconds.hour ?? 0) * 3600 + (seconds.minute ?? 0) * 60)
        return habits.filter { habit in
            guard let due = habit.reminderTime, due <= time else { return false }
            return NotificationManager.shared.eligible(habit, on: Date()) && !NotificationManager.shared.isSnoozed(habit, on: Date())
        }
    }
    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { _ in
            if !overdue.isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    Label("Still to log", systemImage: "bell.badge.fill").font(.headline)
                    ForEach(overdue) { habit in
                        VStack(alignment: .leading, spacing: 8) {
                            Label(habit.name, systemImage: habit.icon).font(.subheadline.bold())
                            HStack {
                                Button("Done") { perform("DONE", habit) }
                                Button("Snooze") { perform("SNOOZE", habit) }
                                Button("Skip today") { perform("SKIP", habit) }
                            }.buttonStyle(.bordered).font(.caption)
                        }
                    }
                    if let error { Text(error).font(.caption).foregroundStyle(.red) }
                }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24))
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .habitReminderChanged)) { _ in revision = UUID() }
    }
    private func perform(_ action: String, _ habit: Habit) {
        Task { @MainActor in
            do { try await NotificationManager.shared.act(action, habit: habit, day: Date()); revision = UUID() }
            catch { self.error = "Couldn't save that action. Please try again." }
        }
    }
}
