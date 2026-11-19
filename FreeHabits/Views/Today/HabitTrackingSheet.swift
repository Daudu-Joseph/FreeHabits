import SwiftUI
import SwiftData

/// Daily log editor shared by amount, checklist, avoidance, and day-note flows.
struct HabitTrackingSheet: View {
    @Bindable var habit: Habit
    var date: Date
    var noteOnly = false
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var amountText = "1"
    @State private var note = ""
    @State private var checked = Set<String>()

    private var existing: HabitCompletion? {
        let sameDay = (habit.completions ?? []).filter { Calendar.current.isDate($0.date, inSameDayAs: date) }
        if noteOnly { return sameDay.first(where: { $0.note != nil }) ?? sameDay.first(where: { $0.isLogOnly != true }) }
        return sameDay.first(where: { $0.isLogOnly != true })
    }
    private var currentAmount: Double { existing?.amountValue ?? 0 }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label(habit.name, systemImage: habit.icon)
                    Text(date.formatted(date: .complete, time: .omitted))
                        .font(.caption).foregroundStyle(.secondary)
                }
                if habit.trackingKind == .amount {
                    Section("Progress") {
                        LabeledContent("Current", value: "\(currentAmount.formatted()) \(habit.amountUnit ?? "")")
                        LabeledContent("Goal", value: "\((habit.targetAmount ?? 1).formatted()) \(habit.amountUnit ?? "")")
                        HStack {
                            TextField("Add amount", text: $amountText).keyboardType(.decimalPad)
                            Text(habit.amountUnit ?? "").foregroundStyle(.secondary)
                        }
                    }
                }
                if habit.trackingKind == .checklist {
                    Section("Steps") {
                        if habit.checklistItems.isEmpty { Text("Edit this habit to add checklist steps.").foregroundStyle(.secondary) }
                        ForEach(habit.checklistItems, id: \.self) { item in
                            Button {
                                if checked.contains(item) { checked.remove(item) } else { checked.insert(item) }
                            } label: {
                                Label(item, systemImage: checked.contains(item) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(.primary)
                            }
                        }
                    }
                }
                if habit.trackingKind == .avoidance && !noteOnly {
                    Section("Today") {
                        Button("Stayed on track", systemImage: "checkmark.circle.fill") { save(relapse: false) }.tint(.green)
                        Button("Log a relapse", systemImage: "arrow.counterclockwise.circle") { save(relapse: true) }.tint(.orange)
                    }
                }
                Section("Note") {
                    TextField("Add a note for this day", text: $note, axis: .vertical).lineLimit(3...8)
                }
            }
            .navigationTitle("Daily log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                if noteOnly || habit.trackingKind != .avoidance {
                    ToolbarItem(placement: .confirmationAction) { Button("Save") { save() } }
                }
            }
            .onAppear {
                note = existing?.note ?? ""
                checked = Set(existing?.checkedChecklistItems ?? [])
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func save(relapse: Bool = false) {
        let record: HabitCompletion
        if let existing { record = existing }
        else {
            record = HabitCompletion(date: Calendar.current.startOfDay(for: date))
            record.isLogOnly = noteOnly
            context.insert(record)
            if habit.completions == nil { habit.completions = [] }
            habit.completions?.append(record)
        }
        record.note = note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : note
        if !noteOnly && habit.trackingKind == .amount {
            record.amountValue = max(0, currentAmount + (Double(amountText) ?? 0))
        } else if !noteOnly && habit.trackingKind == .checklist {
            record.checkedChecklistItems = Array(checked)
        } else if !noteOnly && habit.trackingKind == .avoidance {
            record.isRelapse = relapse
        }
        dismiss()
    }
}
