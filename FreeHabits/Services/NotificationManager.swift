import Foundation
import SwiftData
import UserNotifications
import AVFoundation

/// Local scheduling and actions never depend on an AI service or network access.
@MainActor
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()
    private var container: ModelContainer?
    private var refreshGeneration = UUID()
    private let speaker = AVSpeechSynthesizer()
    private override init() { super.init() }
    private let category = "HABIT_CHECK_IN"

    func configure(container: ModelContainer) {
        self.container = container
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.setNotificationCategories([UNNotificationCategory(identifier: category, actions: [
            UNNotificationAction(identifier: "DONE", title: "Done", options: [.authenticationRequired]),
            UNNotificationAction(identifier: "SNOOZE", title: "Snooze", options: []),
            UNNotificationAction(identifier: "SKIP", title: "Skip today", options: [.authenticationRequired])
        ], intentIdentifiers: [])])
    }

    private func stateKey(_ habit: Habit, _ day: Date, _ kind: String) -> String {
        "reminder.\(habit.reminderID ?? "unknown").\(Int(Calendar.current.startOfDay(for: day).timeIntervalSince1970)).\(kind)"
    }
    func isSkipped(_ habit: Habit, on day: Date) -> Bool {
        UserDefaults.standard.bool(forKey: stateKey(habit, day, "skip"))
    }
    func isSnoozed(_ habit: Habit, on day: Date) -> Bool {
        UserDefaults.standard.double(forKey: stateKey(habit, day, "snooze")) > Date().timeIntervalSince1970
    }
    private var interval: TimeInterval {
        let stored = UserDefaults.standard.integer(forKey: "reminderRepeatMinutes")
        return Double([15, 30, 60, 120].contains(stored) ? stored : 15) * 60
    }
    private func quiet(_ date: Date) -> Bool {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: "reminderQuietEnabled") as? Bool != false else { return false }
        let start = defaults.object(forKey: "reminderQuietStart") as? Int ?? 22
        let end = defaults.object(forKey: "reminderQuietEnd") as? Int ?? 8
        let hour = Calendar.current.component(.hour, from: date)
        if start == end { return false }
        return start < end ? hour >= start && hour < end : hour >= start || hour < end
    }
    func eligible(_ habit: Habit, on day: Date) -> Bool {
        let cal = Calendar.current
        guard !habit.isArchived, cal.startOfDay(for: habit.createdAt) <= cal.startOfDay(for: day),
              habit.frequency.isDue(on: day), !habit.isPaused(on: day),
              !habit.isCompleted(on: day), !isSkipped(habit, on: day) else { return false }
        let completed = (habit.completions ?? []).filter { habit.isCompleted(on: $0.date) }.map(\.date)
        return !habit.frequency.isCompletedForWeek(completions: completed, relativeTo: day)
    }

    /// iOS has a finite queue. Refill whenever the app opens or a notification action runs.
    func refresh(habits: [Habit]) async {
        let generation = UUID()
        refreshGeneration = generation
        var assigned = false
        for habit in habits where habit.reminderID == nil { habit.reminderID = UUID().uuidString; assigned = true }
        if assigned { try? habits.first?.modelContext?.save() }
        let center = UNUserNotificationCenter.current()
        let old = await center.pendingNotificationRequests()
        guard refreshGeneration == generation, !Task.isCancelled else { return }
        center.removePendingNotificationRequests(withIdentifiers: old.map(\.identifier).filter {
            $0.hasPrefix("habit_") || $0.hasPrefix("evening_")
        })
        let delivered = await center.deliveredNotifications()
        center.removeDeliveredNotifications(withIdentifiers: delivered.compactMap { note in
            guard let id = note.request.content.userInfo["habitID"] as? String,
                  let stamp = note.request.content.userInfo["day"] as? Double else { return nil }
            guard let habit = habits.first(where: { $0.reminderID == id }),
                  eligible(habit, on: Date(timeIntervalSince1970: stamp)) else { return note.request.identifier }
            return nil
        })
        let cal = Calendar.current
        let now = Date()
        let today = cal.startOfDay(for: now)
        var candidates: [(Date, UNMutableNotificationContent)] = []
        let repeats = UserDefaults.standard.object(forKey: "reminderRepeatsEnabled") as? Bool != false
        for offset in 0..<7 {
            guard let day = cal.date(byAdding: .day, value: offset, to: today),
                  let end = cal.date(byAdding: .day, value: 1, to: day) else { continue }
            let due = habits.filter { eligible($0, on: day) }
            for habit in due {
                guard let time = habit.reminderTime,
                      let scheduled = cal.date(bySettingHour: Int(time) / 3600, minute: Int(time) % 3600 / 60, second: 0, of: day) else { continue }
                let snoozed = UserDefaults.standard.double(forKey: stateKey(habit, day, "snooze"))
                let first = max(scheduled, Date(timeIntervalSince1970: snoozed))
                var fire = first
                if repeats && fire <= now {
                    fire = first.addingTimeInterval((floor(now.timeIntervalSince(first) / interval) + 1) * interval)
                }
                while fire < end {
                    if fire > now && !quiet(fire) {
                        let content = UNMutableNotificationContent()
                        content.title = habit.name
                        // Future notifications cannot know whether another device logged this habit.
                        content.body = fire == scheduled ? "Time for \(habit.name). Log your progress when you're ready." : "Still to log: \(habit.name). Done, snooze, or skip today?"
                        content.sound = .default
                        content.categoryIdentifier = category
                        content.threadIdentifier = "habit_\(habit.reminderID!)"
                        content.userInfo = ["habitID": habit.reminderID!, "day": day.timeIntervalSince1970]
                        candidates.append((fire, content))
                    }
                    if !repeats { break }
                    fire = fire.addingTimeInterval(interval)
                }
            }
            if UserDefaults.standard.object(forKey: "eveningCheckInEnabled") as? Bool != false,
               !due.isEmpty, let fire = cal.date(bySettingHour: 20, minute: 0, second: 0, of: day), fire > now, !quiet(fire) {
                let content = UNMutableNotificationContent()
                content.title = "Evening check-in"
                content.body = "Take a moment to check today's habits."
                content.sound = .default
                candidates.append((fire, content))
            }
        }
        for (index, item) in candidates.sorted(by: { $0.0 < $1.0 }).prefix(60).enumerated() {
            guard refreshGeneration == generation, !Task.isCancelled else { return }
            let id = "habit_plan_\(generation.uuidString)_\(index)"
            let components = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: item.0)
            try? await center.add(UNNotificationRequest(identifier: id, content: item.1,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)))
            if refreshGeneration != generation || Task.isCancelled {
                center.removePendingNotificationRequests(withIdentifiers: [id]); return
            }
        }
    }

    func act(_ action: String, habit: Habit, day: Date, snoozeMinutes: Int? = nil) async throws {
        guard Calendar.current.isDateInToday(day), eligible(habit, on: day) else { return }
        guard let context = habit.modelContext else { return }
        switch action {
        case "DONE":
            let record = (habit.completions ?? []).first { Calendar.current.isDate($0.date, inSameDayAs: day) && $0.isLogOnly != true } ?? HabitCompletion(date: day)
            if record.modelContext == nil { context.insert(record); record.habit = habit }
            record.isLogOnly = false
            record.isRelapse = false
            if habit.trackingKind == .amount { record.amountValue = max(record.amountValue ?? 0, habit.targetAmount ?? 1) }
            if habit.trackingKind == .checklist { record.checkedChecklistItems = habit.checklistItems }
            do { try context.save() } catch { context.rollback(); throw error }
        case "SNOOZE":
            UserDefaults.standard.set(Date().addingTimeInterval(Double(snoozeMinutes ?? Int(interval / 60)) * 60).timeIntervalSince1970,
                                      forKey: stateKey(habit, day, "snooze"))
        case "SKIP":
            // Skipping silences today; it does not award a completion or change the streak.
            UserDefaults.standard.set(true, forKey: stateKey(habit, day, "skip"))
        default: return
        }
        let delivered = await UNUserNotificationCenter.current().deliveredNotifications()
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: delivered.filter {
            ($0.request.content.userInfo["habitID"] as? String) == habit.reminderID
        }.map { $0.request.identifier })
        let all = try context.fetch(FetchDescriptor<Habit>())
        await refresh(habits: all)
        NotificationCenter.default.post(name: .habitReminderChanged, object: nil)
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        guard let id = info["habitID"] as? String, let stamp = info["day"] as? Double else { return }
        await handle(response.actionIdentifier, id: id, day: Date(timeIntervalSince1970: stamp))
    }
    private func handle(_ action: String, id: String, day: Date) async {
        guard ["DONE", "SNOOZE", "SKIP"].contains(action), let container else { return }
        let context = ModelContext(container)
        guard let habits = try? context.fetch(FetchDescriptor<Habit>()), let habit = habits.first(where: { $0.reminderID == id }) else { return }
        do { try await act(action, habit: habit, day: day) }
        catch {
            let content = UNMutableNotificationContent()
            content.title = "Check-in wasn't saved"
            content.body = "Open FreeHabits to log this habit."
            try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "action_error", content: content, trigger: nil))
        }
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        let title = notification.request.content.title
        await speakReminder(title)
        return [.banner, .list, .sound]
    }
    private func speakReminder(_ title: String) {
        guard UserDefaults.standard.bool(forKey: "reminderSpeakForeground"),
              !quiet(Date()), !AssistantSpeech.microphoneInUse, !AssistantSpeech.voicePlaybackInUse, !speaker.isSpeaking else { return }
        let utterance = AVSpeechUtterance(string: "Reminder. \(title). You can log it, snooze, or skip today.")
        speaker.speak(utterance)
    }
    func stopSpeaking() { speaker.stopSpeaking(at: .immediate) }
    func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }
    var isAuthorized: Bool {
        get async { await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .authorized }
    }
    func scheduleReminder(for habit: Habit) { refreshFrom(habit) }
    func removeReminder(for habit: Habit) { refreshFrom(habit) }
    private func refreshFrom(_ habit: Habit) {
        guard let context = habit.modelContext, let habits = try? context.fetch(FetchDescriptor<Habit>()) else { return }
        Task { await refresh(habits: habits) }
    }
}
extension Notification.Name {
    static let habitReminderChanged = Notification.Name("FreeHabits.habitReminderChanged")
}
