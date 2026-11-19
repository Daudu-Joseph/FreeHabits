import SwiftUI
import SwiftData

struct FreeHabitsRootView: View {
    var body: some View {
        TabView {
            ContentView().tabItem { Label("Today", systemImage: "checklist") }
            ProgressDashboard().tabItem { Label("Progress", systemImage: "chart.bar.xaxis") }
            NavigationStack { HabitDataView() }
                .tabItem { Label("Data", systemImage: "externaldrive") }
        }
        .tint(.purple)
    }
}

struct ProgressDashboard: View {
    @Query(sort: \Habit.sortOrder) private var habits: [Habit]
    @State private var selection: Date?
    @State private var selectedHabit: PersistentIdentifier?
    @State private var selectedChartRange = 3
    private let calendar = Calendar.current
    private var filtered: [Habit] {
        guard let selectedHabit else { return habits }
        return habits.filter { $0.persistentModelID == selectedHabit }
    }
    private var counts: [Date: Int] {
        var result: [Date: Int] = [:]
        for habit in filtered {
            for date in Set((habit.completions ?? []).filter { habit.isCompleted(on: $0.date) }.map { calendar.startOfDay(for: $0.date) }) where date <= Date() {
                result[date, default: 0] += 1
            }
        }
        return result
    }
    private var months: [Date] {
        let current = calendar.dateInterval(of: .month, for: Date())!.start
        return (-11...0).compactMap { calendar.date(byAdding: .month, value: $0, to: current) }
    }
    private func monthlyCount(_ month: Date) -> Int {
        guard let interval = calendar.dateInterval(of: .month, for: month) else { return 0 }
        return counts.filter { interval.contains($0.key) }.values.reduce(0, +)
    }
    private func chartSeries(_ label: String, dates: [Date], value: (Date) -> Int) -> ScrubChart<FloatingPointFormatStyle<Double>>.Series {
        .init(label: label, points: dates.map { date in
            .init(date: date, value: Double(value(date)))
        })
    }
    private var ranking: [Habit] {
        filtered.sorted { $0.totalCompletions > $1.totalCompletions }
    }
    private var consistency: Double {
        let done = filtered.reduce(0) { $0 + $1.recentMetrics.completed }
        let due = filtered.reduce(0) { $0 + $1.recentMetrics.expected }
        return due == 0 ? 0 : Double(done) / Double(due)
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Every small step adds up.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Picker("Habit", selection: $selectedHabit) {
                        Text("All habits").tag(Optional<PersistentIdentifier>.none)
                        ForEach(habits) { habit in
                            Text(habit.name).tag(Optional(habit.persistentModelID))
                        }
                    }
                    .pickerStyle(.menu)
                    if habits.isEmpty {
                        ContentUnavailableView("Your progress starts here", systemImage: "chart.xyaxis.line", description: Text("Add your first habit in Today. Your history will appear here as you check in."))
                    } else {
                        card("By habit") {
                            if counts.isEmpty {
                                Text("No completions yet").foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 170)
                            } else {
                                RingBreakdown<FloatingPointFormatStyle<Double>>(
                                    slices: ranking.filter { $0.totalCompletions > 0 }.map { habit in
                                        .init(label: habit.name, value: Double(habit.totalCompletions), color: habit.habitColor)
                                    },
                                    thickness: 34,
                                    tint: .purple,
                                    format: .number.precision(.fractionLength(0)),
                                    showsLegend: true,
                                    style: RingBreakdownStyle(
                                        blocks: [.purple, .blue, .teal, .pink, .orange, .indigo],
                                        rest: Color(.systemFill),
                                        ink: .primary,
                                        text: .primary,
                                        muted: .secondary
                                    )
                                )
                                .frame(minHeight: 250)
                                .accessibilityLabel("Habit completion breakdown")
                            }
                            Text("\(counts.values.reduce(0, +)) total completions")
                                .font(.headline).monospacedDigit()
                        }
                        card("Activity · past year") {
                            ActivityHeatmap(counts, weeks: 53, showsSummary: false, selection: $selection,
                                messages: .init(title: "Habit completions"), style: .init(accent: .purple))
                            if let selection {
                                Text("\(selection.formatted(date: .abbreviated, time: .omitted)): \(counts[selection, default: 0]) completions")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        card("Completions / month") {
                            if counts.isEmpty {
                                Text("Monthly activity will appear after your first check-in.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, minHeight: 160)
                            } else {
                                let today = calendar.startOfDay(for: Date())
                                let days = (0..<30).compactMap { calendar.date(byAdding: .day, value: $0 - 29, to: today) }
                                ScrubChart<FloatingPointFormatStyle<Double>>(
                                    series: [
                                        chartSeries("30D", dates: days) { counts[$0, default: 0] },
                                        chartSeries("3M", dates: Array(months.suffix(3)), value: monthlyCount),
                                        chartSeries("6M", dates: Array(months.suffix(6)), value: monthlyCount),
                                        chartSeries("1Y", dates: months, value: monthlyCount)
                                    ],
                                    mode: .line,
                                    tint: .purple,
                                    format: .number.precision(.fractionLength(0)),
                                    range: $selectedChartRange,
                                    style: ScrubChartStyle(
                                        line: .purple,
                                        accent: .purple,
                                        up: .green,
                                        down: .red,
                                        ink: .primary,
                                        muted: .secondary,
                                        band: .purple.opacity(0.12),
                                        ground: Color(.secondarySystemGroupedBackground)
                                    )
                                )
                                .frame(height: 300)
                                .accessibilityLabel("Monthly habit completions. Drag across the chart to inspect a month.")
                            }
                            Text("The current month is still in progress.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        card("Consistency · last 30 days") {
                            HStack(spacing: 20) {
                                ZStack {
                                    Circle().stroke(.purple.opacity(0.12), lineWidth: 12)
                                    Circle().trim(from: 0, to: consistency)
                                        .stroke(.purple, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                                        .rotationEffect(.degrees(-90))
                                    Text(consistency, format: .percent.precision(.fractionLength(0)))
                                        .font(.title2.bold()).monospacedDigit()
                                }.frame(width: 98, height: 98)
                                Text("Completed against scheduled goals. Weekly habits count toward their weekly target.")
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                        card("Ranking") {
                            ForEach(ranking) { habit in
                                HStack {
                                    Image(systemName: habit.icon).foregroundStyle(habit.habitColor)
                                    Text(habit.name).font(.subheadline).lineLimit(1)
                                    Spacer()
                                    Text("\(habit.totalCompletions)").monospacedDigit().font(.subheadline.bold())
                                }
                                ProgressView(value: Double(habit.totalCompletions), total: Double(max(1, ranking.first?.totalCompletions ?? 1)))
                                    .tint(habit.habitColor)
                            }
                        }
                    }
                }.padding(20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Progress")
        }
    }
    private func card<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title).font(.headline)
            content()
        }
        .padding(20).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24))
    }
}
