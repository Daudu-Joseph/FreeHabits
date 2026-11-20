import AppIntents
import SwiftUI
import WidgetKit

private let freeHabitsGroup = "group.com.daudu.joseph.freehabits"
private let snapshotKey = "habit-widget-snapshot-v1"
private let actionsKey = "habit-widget-actions-v1"

struct WidgetHabit: Codable, Identifiable {
    var id: String
    var name: String
    var icon: String
    var dueTime: TimeInterval
    var completed: Bool
    var snoozedUntil: Date?
    var amountProgress: String?
    var snoozeMinutes: Int
}
struct WidgetSnapshot: Codable {
    var updatedAt: Date
    var day: Date
    var items: [WidgetHabit]
}
struct QueuedAction: Codable {
    var id = UUID()
    var habitID: String
    var action: String
    var minutes: Int?
    var day: Date
}

struct FreeHabitsWidgetEntry: TimelineEntry {
    var date: Date
    var snapshot: WidgetSnapshot?
}

struct FreeHabitsWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> FreeHabitsWidgetEntry { .init(date: .now, snapshot: nil) }
    func getSnapshot(in context: Context, completion: @escaping (FreeHabitsWidgetEntry) -> Void) {
        completion(.init(date: .now, snapshot: readSnapshot()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<FreeHabitsWidgetEntry>) -> Void) {
        let entry = FreeHabitsWidgetEntry(date: .now, snapshot: readSnapshot())
        completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(15 * 60))))
    }
    private func readSnapshot() -> WidgetSnapshot? {
        guard let defaults = UserDefaults(suiteName: freeHabitsGroup),
              let data = defaults.data(forKey: snapshotKey) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }
}

struct WidgetHabitActionIntent: AppIntent {
    static var title: LocalizedStringResource = "Update habit reminder"
    static var openAppWhenRun = false
    @Parameter(title: "Habit ID") var habitID: String
    @Parameter(title: "Action") var action: String
    @Parameter(title: "Minutes") var minutes: Int
    init() { habitID = ""; action = ""; minutes = 15 }
    init(habitID: String, action: String, minutes: Int = 15) {
        self.habitID = habitID; self.action = action; self.minutes = minutes
    }
    func perform() async throws -> some IntentResult {
        guard let defaults = UserDefaults(suiteName: freeHabitsGroup) else { return .result() }
        if let data = defaults.data(forKey: actionsKey),
           var actions = try? JSONDecoder().decode([QueuedAction].self, from: data) {
            actions.append(QueuedAction(habitID: habitID, action: action, minutes: minutes, day: .now))
            defaults.set(try? JSONEncoder().encode(actions), forKey: actionsKey)
        } else {
            let actions = [QueuedAction(habitID: habitID, action: action, minutes: minutes, day: .now)]
            defaults.set(try? JSONEncoder().encode(actions), forKey: actionsKey)
        }
        if let data = defaults.data(forKey: snapshotKey), var snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data) {
            if action == "DONE" || action == "SKIP" { snapshot.items.removeAll { $0.id == habitID } }
            if action == "SNOOZE", let index = snapshot.items.firstIndex(where: { $0.id == habitID }) {
                snapshot.items[index].snoozedUntil = Date().addingTimeInterval(Double(minutes) * 60)
            }
            defaults.set(try? JSONEncoder().encode(snapshot), forKey: snapshotKey)
        }
        WidgetCenter.shared.reloadTimelines(ofKind: "FreeHabitsTodayWidget")
        return .result()
    }
}

struct FreeHabitsTodayWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: FreeHabitsWidgetEntry
    private var items: [WidgetHabit] { Array((entry.snapshot?.items ?? []).prefix(family == .systemLarge ? 2 : 1)) }
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    if family == .systemLarge {
                        Text("FREEHABITS").font(.caption2.weight(.bold)).tracking(1.2).foregroundStyle(.secondary)
                    }
                    Text(items.isEmpty ? "You're all caught up" : "Still to log")
                        .font(.headline.weight(.bold)).lineLimit(1)
                }
                Spacer(minLength: 2)
                Text("\(items.count)").font(.title2.weight(.bold).monospacedDigit()).foregroundStyle(.purple)
            }
            if items.isEmpty {
                Label(entry.snapshot == nil ? "Open FreeHabits to sync today" : "Nothing due right now", systemImage: "checkmark.circle.fill")
                    .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(items) { item in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Image(systemName: item.icon).font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.purple).frame(width: 20)
                            TaskRow(item.name, status: .constant(.open), due: dueLabel(item), tint: .purple)
                                .frame(height: 72).allowsHitTesting(false)
                        }
                        HStack(spacing: 7) {
                            Button(intent: WidgetHabitActionIntent(habitID: item.id, action: "DONE")) {
                                Label("Done", systemImage: "checkmark").labelStyle(.titleAndIcon)
                            }
                            Button(intent: WidgetHabitActionIntent(habitID: item.id, action: "SNOOZE", minutes: item.snoozeMinutes)) {
                                Label("Snooze", systemImage: "clock").labelStyle(.titleAndIcon)
                            }
                            Button(intent: WidgetHabitActionIntent(habitID: item.id, action: "SKIP")) {
                                Label("Skip", systemImage: "forward.end").labelStyle(.titleAndIcon)
                            }
                        }.font(.system(size: 10, weight: .semibold)).tint(.purple)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .containerBackground(Color(.systemGroupedBackground), for: .widget)
    }
    private func dueLabel(_ item: WidgetHabit) -> String {
        let progress = item.amountProgress.map { " · \($0)" } ?? ""
        if let snooze = item.snoozedUntil, snooze > .now { return "Snoozed · " + snooze.formatted(date: .omitted, time: .shortened) + progress }
        let time = Calendar.current.startOfDay(for: entry.date).addingTimeInterval(item.dueTime)
        return (time <= .now ? "Overdue · " : "Today · ") + time.formatted(date: .omitted, time: .shortened) + progress
    }
}

@main
struct FreeHabitsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "FreeHabitsTodayWidget", provider: FreeHabitsWidgetProvider()) { entry in
            FreeHabitsTodayWidgetView(entry: entry)
        }
        .configurationDisplayName("FreeHabits Today")
        .description("See habits still to log and take a quick action.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}
