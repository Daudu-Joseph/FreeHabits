//
//  Habit.swift
//  FreeHabits
//
//  Created by Jonas Gunklach on 17.04.26.
//

import Foundation
import SwiftData
import SwiftUI

@Model
final class Habit {
    var name: String = ""
    var icon: String = "star.fill"
    var colorName: String = "blue"
    var createdAt: Date = Date.now
    /// Manual sort position; lower = higher in list.
    var sortOrder: Int = 0
    /// Non-nil when the habit is archived.
    var archivedAt: Date?
    /// JSON-encoded HabitFrequency. Stored as Data so SwiftData can persist it.
    var frequencyData: Data?
    /// Time-of-day offset in seconds from midnight for the daily reminder. nil = no reminder.
    var reminderTime: TimeInterval?
    /// HealthKit data type identifier for auto-tracking (e.g. "workout.running", "mindfulSession").
    /// nil means the habit is tracked manually only.
    var healthKitIdentifier: String?
    /// Optional additive fields keep older SwiftData records readable.
    var trackingKindRaw: String?
    var targetAmount: Double?
    var amountUnit: String?
    var category: String?
    var checklistItemsData: Data?
    var pausedRangesData: Data?

    @Relationship(deleteRule: .cascade, inverse: \HabitCompletion.habit)
    var completions: [HabitCompletion]?

    init(name: String, icon: String = "star.fill", colorName: String = "blue", sortOrder: Int = 0) {
        self.name = name
        self.icon = icon
        self.colorName = colorName
        self.createdAt = .now
        self.sortOrder = sortOrder
    }

    // MARK: Frequency helpers

    var frequency: HabitFrequency {
        get {
            guard let data = frequencyData,
                  let freq = try? JSONDecoder().decode(HabitFrequency.self, from: data)
            else { return .daily }
            return freq
        }
        set {
            frequencyData = try? JSONEncoder().encode(newValue)
        }
    }

    var isArchived: Bool { archivedAt != nil }

    enum TrackingKind: String, Codable, CaseIterable, Identifiable {
        case yesNo, amount, checklist, avoidance
        var id: String { rawValue }
        var title: String {
            switch self {
            case .yesNo: return "Simple"
            case .amount: return "Amount goal"
            case .checklist: return "Checklist"
            case .avoidance: return "Avoidance"
            }
        }
    }

    var trackingKind: TrackingKind {
        get { TrackingKind(rawValue: trackingKindRaw ?? "") ?? .yesNo }
        set { trackingKindRaw = newValue.rawValue }
    }

    var checklistItems: [String] {
        get { (try? JSONDecoder().decode([String].self, from: checklistItemsData ?? Data())) ?? [] }
        set { checklistItemsData = try? JSONEncoder().encode(newValue) }
    }

    var pausedRanges: [HabitPauseRange] {
        get { (try? JSONDecoder().decode([HabitPauseRange].self, from: pausedRangesData ?? Data())) ?? [] }
        set { pausedRangesData = try? JSONEncoder().encode(newValue) }
    }

    func isPaused(on date: Date, calendar: Calendar = .current) -> Bool {
        let day = calendar.startOfDay(for: date)
        return pausedRanges.contains {
            day >= calendar.startOfDay(for: $0.start) && day <= calendar.startOfDay(for: $0.end)
        }
    }

    var isCompletedToday: Bool {
        isCompleted(on: .now)
    }

    func isCompleted(on date: Date) -> Bool {
        let cal = Calendar.current
        let records = (completions ?? []).filter {
            cal.isDate($0.date, inSameDayAs: date) && $0.isRelapse != true && $0.isLogOnly != true
        }
        guard let record = records.first else { return false }
        if trackingKind == .amount, let targetAmount { return (record.amountValue ?? 0) >= targetAmount }
        if trackingKind == .checklist, !checklistItems.isEmpty {
            let done = record.checkedChecklistItems
            return checklistItems.allSatisfy { done.contains($0) }
        }
        return true
    }

    var isDueToday: Bool {
        frequency.isDue(on: .now) && !isPaused(on: .now)
    }

    var metrics: HabitMetrics {
        HabitMetrics(frequency: frequency, createdAt: createdAt, archivedAt: archivedAt,
                     completions: (completions ?? []).filter { $0.isRelapse != true && isCompleted(on: $0.date) }.map(\.date),
                     pausedRanges: pausedRanges)
    }

    var recentMetrics: HabitMetrics {
        let since = Calendar.current.date(byAdding: .day, value: -29, to: Calendar.current.startOfDay(for: .now))!
        return HabitMetrics(frequency: frequency, createdAt: createdAt, archivedAt: archivedAt,
                            completions: (completions ?? []).filter { $0.isRelapse != true && isCompleted(on: $0.date) }.map(\.date), since: since,
                            pausedRanges: pausedRanges)
    }
    var completionRate30Days: Double { recentMetrics.rate }
    var currentStreak: Int { metrics.current }
    var bestStreak: Int { metrics.best }
    var streakUnit: String { metrics.weekly ? "weeks" : "days" }

    var totalCompletions: Int {
        Set((completions ?? []).filter { isCompleted(on: $0.date) }.map { Calendar.current.startOfDay(for: $0.date) }).count
    }

    var habitColor: Color {
        Color.fromHabitColorName(colorName)
    }
}
