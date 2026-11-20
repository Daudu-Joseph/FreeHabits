import Foundation
import SwiftData
import WidgetKit

struct HabitWidgetItem: Codable, Identifiable {
    var id: String
    var name: String
    var icon: String
    var dueTime: TimeInterval
    var completed: Bool
    var snoozedUntil: Date?
    var amountProgress: String?
    var snoozeMinutes: Int
}
struct HabitWidgetSnapshot: Codable {
    var updatedAt: Date
    var day: Date
    var items: [HabitWidgetItem]
}
struct HabitWidgetAction: Codable, Identifiable {
    var id: UUID = UUID()
    var habitID: String
    var action: String
    var minutes: Int?
    var day: Date
}

@MainActor
enum HabitWidgetShared {
    static let group = "group.com.daudu.joseph.freehabits"
    static let snapshotKey = "habit-widget-snapshot-v1"
    static let actionsKey = "habit-widget-actions-v1"

    static func write(habits: [Habit]) {
        guard let defaults = UserDefaults(suiteName: group) else { return }
        let today = Calendar.current.startOfDay(for: .now)
        let items = habits.compactMap { habit -> HabitWidgetItem? in
            guard NotificationManager.shared.eligible(habit, on: today),
                  let reminderID = habit.reminderID else { return nil }
            let records = (habit.completions ?? []).filter { Calendar.current.isDate($0.date, inSameDayAs: today) }
            let snoozed = UserDefaults.standard.double(forKey: "reminder.\(reminderID).\(Int(today.timeIntervalSince1970)).snooze")
            let progress: String?
            if habit.trackingKind == .amount, let target = habit.targetAmount {
                let actual = records.reduce(0) { $0 + ($1.amountValue ?? 0) }
                progress = String(format: "%.0f / %.0f %@", actual, target, habit.amountUnit ?? "")
            } else { progress = nil }
            return HabitWidgetItem(id: reminderID, name: habit.name, icon: habit.icon,
                                   dueTime: habit.reminderTime ?? 86340, completed: false,
                                   snoozedUntil: snoozed > Date().timeIntervalSince1970 ? Date(timeIntervalSince1970: snoozed) : nil,
                                   amountProgress: progress,
                                   snoozeMinutes: max(15, UserDefaults.standard.integer(forKey: "reminderRepeatMinutes")))
        }.sorted { $0.dueTime < $1.dueTime }
        guard let data = try? JSONEncoder().encode(HabitWidgetSnapshot(updatedAt: .now, day: today, items: items)) else { return }
        defaults.set(data, forKey: snapshotKey)
        WidgetCenter.shared.reloadTimelines(ofKind: "FreeHabitsTodayWidget")
    }

    private static func pendingActions() -> [HabitWidgetAction] {
        guard let defaults = UserDefaults(suiteName: group),
              let data = defaults.data(forKey: actionsKey),
              let actions = try? JSONDecoder().decode([HabitWidgetAction].self, from: data) else { return [] }
        return actions
    }

    static func applyQueuedActions(habits: [Habit]) async {
        let actions = pendingActions()
        var retry: [HabitWidgetAction] = []
        for action in actions {
            guard let habit = habits.first(where: { $0.reminderID == action.habitID }) else {
                retry.append(action)
                continue
            }
            do {
                try await NotificationManager.shared.act(action.action, habit: habit, day: action.day, snoozeMinutes: action.minutes)
            } catch {
                retry.append(action)
            }
        }
        if let defaults = UserDefaults(suiteName: group) {
            if retry.isEmpty { defaults.removeObject(forKey: actionsKey) }
            else { defaults.set(try? JSONEncoder().encode(retry), forKey: actionsKey) }
        }
        write(habits: habits)
    }
}
