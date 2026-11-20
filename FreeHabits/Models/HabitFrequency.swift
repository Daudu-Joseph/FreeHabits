//
//  HabitFrequency.swift
//  FreeHabits
//
//  Created by Jonas Gunklach on 17.04.26.
//

import Foundation

struct HabitPauseRange: Codable, Hashable {
    var start: Date
    var end: Date
}

/// Describes how often a habit should be performed.
enum HabitFrequency: Codable, Hashable {
    /// Every day.
    case daily
    /// Specific weekdays (1 = Sunday … 7 = Saturday, matching Calendar.weekday).
    case weekdays([Int])
    /// A fixed number of times per week (any days).
    case timesPerWeek(Int)

    // MARK: Codable

    private enum CodingKeys: String, CodingKey {
        case type, weekdays, count
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .daily:
            try c.encode("daily", forKey: .type)
        case .weekdays(let days):
            try c.encode("weekdays", forKey: .type)
            try c.encode(days, forKey: .weekdays)
        case .timesPerWeek(let n):
            try c.encode("timesPerWeek", forKey: .type)
            try c.encode(n, forKey: .count)
        }
    }

    nonisolated init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type_ = try c.decode(String.self, forKey: .type)
        switch type_ {
        case "weekdays":
            let days = try c.decode([Int].self, forKey: .weekdays)
            self = .weekdays(days)
        case "timesPerWeek":
            let n = try c.decode(Int.self, forKey: .count)
            self = .timesPerWeek(n)
        default:
            self = .daily
        }
    }

    // MARK: Helpers

    var displayName: String {
        switch self {
        case .daily:
            return "Every day"
        case .weekdays(let days):
            if days.sorted() == [2, 3, 4, 5, 6] { return "Weekdays" }
            if days.sorted() == [1, 7] { return "Weekends" }
            let syms = Calendar.current.shortWeekdaySymbols
            let names = days.sorted().compactMap { syms[safe: $0 - 1] }.joined(separator: ", ")
            return names
        case .timesPerWeek(let n):
            return "\(n)× per week"
        }
    }

    /// Returns true if the habit is due on the given date according to this frequency.
    func isDue(on date: Date, calendar: Calendar = .current) -> Bool {
        switch self {
        case .daily:
            return true
        case .weekdays(let days):
            let weekday = calendar.component(.weekday, from: date)
            return days.contains(weekday)
        case .timesPerWeek:
            // Always "due" — the count is evaluated at the week level
            return true
        }
    }

    /// For timesPerWeek: returns true if the habit has been completed enough times this week.
    func isCompletedForWeek(completions: [Date], relativeTo date: Date = .now) -> Bool {
        guard case .timesPerWeek(let target) = self else { return false }
        let cal = Calendar.current
        guard let weekInterval = cal.dateInterval(of: .weekOfYear, for: date) else { return false }
        let count = Set(completions.filter { weekInterval.contains($0) }.map { cal.startOfDay(for: $0) }).count
        return count >= target
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}


/// Pure calendar calculations shared by the app and its validation harness.
struct HabitMetrics {
    struct Period {
        let done: Int
        let target: Int
        let isOpen: Bool
    }
    let periods: [Period]
    let weekly: Bool

    init(frequency: HabitFrequency, createdAt: Date, archivedAt: Date?, completions: [Date], now: Date = .now, calendar: Calendar = .current, since: Date? = nil, pausedRanges: [HabitPauseRange] = []) {
        let today = calendar.startOfDay(for: now)
        let first = calendar.startOfDay(for: max(createdAt, since ?? createdAt))
        let last = min(today, calendar.startOfDay(for: archivedAt ?? now))
        let days = Set(completions.map { calendar.startOfDay(for: $0) }.filter { $0 >= first && $0 <= last })
        var result: [Period] = []
        if case .timesPerWeek(let target) = frequency {
            weekly = true
            var cursor = first
            while cursor <= last, let interval = calendar.dateInterval(of: .weekOfYear, for: cursor) {
                let count = days.filter { interval.contains($0) }.count
                let targetPerWeek = max(1, target)
                let pausedDays = (0..<7).compactMap { offset in
                    calendar.date(byAdding: .day, value: offset, to: interval.start)
                }.filter { day in
                    pausedRanges.contains { day >= calendar.startOfDay(for: $0.start) && day <= calendar.startOfDay(for: $0.end) }
                }.count
                let adjustedTarget = max(0, targetPerWeek - pausedDays)
                if adjustedTarget > 0 {
                    result.append(Period(done: min(count, adjustedTarget), target: adjustedTarget, isOpen: archivedAt == nil && interval.contains(now)))
                }
                cursor = interval.end
            }
        } else {
            weekly = false
            var cursor = first
            while cursor <= last {
                let paused = pausedRanges.contains {
                    cursor >= calendar.startOfDay(for: $0.start) && cursor <= calendar.startOfDay(for: $0.end)
                }
                if frequency.isDue(on: cursor, calendar: calendar) && !paused {
                    result.append(Period(done: days.contains(cursor) ? 1 : 0, target: 1, isOpen: archivedAt == nil && cursor == today))
                }
                guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
                cursor = next
            }
        }
        periods = result
    }

    var completed: Int { periods.reduce(0) { $0 + $1.done } }
    var expected: Int { periods.reduce(0) { $0 + $1.target } }
    var rate: Double { expected == 0 ? 0 : Double(completed) / Double(expected) }
    var current: Int {
        var count = 0
        for period in periods.reversed() {
            if period.done >= period.target { count += 1 }
            else if period.isOpen { continue }
            else { break }
        }
        return count
    }
    var best: Int {
        var run = 0
        var best = 0
        for period in periods {
            run = period.done >= period.target ? run + 1 : 0
            best = max(best, run)
        }
        return best
    }
}
