//
//  NotificationManager.swift
//  FreeHabits
//
//  Created by Jonas Gunklach on 17.04.26.
//

import UserNotifications
import Foundation
import SwiftData

@MainActor
final class NotificationManager {
    static let shared = NotificationManager()
    private init() {}
    private var refreshGeneration = UUID()

    /// Replans up to seven days locally. iOS delivers these while the app is closed.
    /// Future evening checks use generic copy; only today's count can be known now.
    func refresh(habits: [Habit]) async {
        let generation = UUID()
        refreshGeneration = generation
        let center = UNUserNotificationCenter.current()
        let old = await center.pendingNotificationRequests()
        guard refreshGeneration == generation, !Task.isCancelled else { return }
        center.removePendingNotificationRequests(withIdentifiers: old.map(\.identifier).filter {
            $0.hasPrefix("habit_reminder_") || $0.hasPrefix("habit_plan_") || $0.hasPrefix("evening_plan_") || $0 == "evening_nudge"
        })
        let calendar = Calendar.current
        let now = Date()
        let today = calendar.startOfDay(for: now)
        var candidates: [(Date, UNMutableNotificationContent, String)] = []
        for offset in 0..<7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            let due = habits.filter { habit in
                guard !habit.isArchived, calendar.startOfDay(for: habit.createdAt) <= day,
                      habit.frequency.isDue(on: day), !habit.isPaused(on: day), !habit.isCompleted(on: day) else { return false }
                let completed = (habit.completions ?? []).filter { habit.isCompleted(on: $0.date) }.map(\.date)
                return !habit.frequency.isCompletedForWeek(completions: completed, relativeTo: day)
            }
            for habit in due {
                guard let time = habit.reminderTime,
                      let fire = calendar.date(bySettingHour: Int(time) / 3600, minute: Int(time) % 3600 / 60, second: 0, of: day), fire > now else { continue }
                let content = UNMutableNotificationContent()
                content.title = habit.name
                content.body = "Ready for a small step? Log your progress in FreeHabits."
                content.sound = .default
                candidates.append((fire, content, "habit_plan_"))
            }
            if UserDefaults.standard.object(forKey: "eveningCheckInEnabled") as? Bool != false,
               !due.isEmpty, let fire = calendar.date(bySettingHour: 20, minute: 0, second: 0, of: day), fire > now {
                let content = UNMutableNotificationContent()
                content.title = "Evening check-in"
                content.body = offset == 0 ? "\(due.count) \(due.count == 1 ? "habit" : "habits") left today. A small step still counts." : "Take a moment to check today's habits."
                content.sound = .default
                candidates.append((fire, content, "evening_plan_"))
            }
        }
        // Leave room under iOS's pending-notification limit.
        for (index, item) in candidates.sorted(by: { $0.0 < $1.0 }).prefix(60).enumerated() {
            guard refreshGeneration == generation, !Task.isCancelled else { return }
            let identifier = item.2 + generation.uuidString + "_\(index)"
            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: item.0)
            let request = UNNotificationRequest(identifier: identifier, content: item.1,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false))
            try? await center.add(request)
            if refreshGeneration != generation || Task.isCancelled {
                center.removePendingNotificationRequests(withIdentifiers: [identifier])
                return
            }
        }
    }

    // MARK: Permission

    func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    var isAuthorized: Bool {
        get async {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            return settings.authorizationStatus == .authorized
        }
    }

    // Existing editor/card entry points rebuild the same schedule as the root view.
    func scheduleReminder(for habit: Habit) { refreshFrom(habit) }
    func removeReminder(for habit: Habit) { refreshFrom(habit) }

    private func refreshFrom(_ habit: Habit) {
        guard let context = habit.modelContext,
              let habits = try? context.fetch(FetchDescriptor<Habit>()) else { return }
        Task { await refresh(habits: habits) }
    }

}
