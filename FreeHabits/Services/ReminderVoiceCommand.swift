import Foundation

/// Deliberately narrow local grammar. Unrecognized speech goes to the configured AI;
/// no action is applied without the review card's Confirm button.
@MainActor
struct ReminderVoiceCommand {
    let habit: Habit
    let action: String
    let minutes: Int?
    var summary: String {
        switch action {
        case "SNOOZE": return "Remind me about \(habit.name) in \(minutes ?? 15) minutes."
        case "SKIP": return "Skip reminders for \(habit.name) today. This won't count as completed."
        default: return "Mark the whole \(habit.name) goal complete for today."
        }
    }
    static func parse(_ text: String, habits: [Habit]) -> Self? {
        func normalized(_ value: String) -> String {
            value.lowercased().trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        }
        let input = normalized(text)
        var matches: [Self] = []
        for habit in habits where NotificationManager.shared.eligible(habit, on: Date()) {
            let name = normalized(habit.name)
            guard !name.isEmpty else { continue }
            if ["skip \(name)", "skip \(name) today"].contains(input) {
                matches.append(Self(habit: habit, action: "SKIP", minutes: nil))
            }
            if ["i already did \(name)", "i completed \(name)", "mark \(name) done"].contains(input) {
                matches.append(Self(habit: habit, action: "DONE", minutes: nil))
            }
            for minutes in [15, 30, 60, 120] {
                if ["snooze \(name) for \(minutes) minutes", "remind me about \(name) in \(minutes) minutes"].contains(input) {
                    matches.append(Self(habit: habit, action: "SNOOZE", minutes: minutes))
                }
            }
        }
        return matches.count == 1 ? matches[0] : nil
    }
}
