import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct HabitBackup: Codable {
    var version = 1
    var exportedAt = Date()
    var habits: [Entry]
    struct Entry: Codable {
        var name: String
        var icon: String
        var colorName: String
        var createdAt: Date
        var archivedAt: Date?
        var sortOrder: Int
        var frequency: HabitFrequency
        var reminderTime: Double?
        var healthKitIdentifier: String?
        var completions: [Date]
        var trackingKindRaw: String? = nil
        var targetAmount: Double? = nil
        var amountUnit: String? = nil
        var category: String? = nil
        var checklistItems: [String]? = nil
        var pausedRanges: [HabitPauseRange]? = nil
        var completionDetails: [CompletionEntry]? = nil
    }
    struct CompletionEntry: Codable {
        var date: Date
        var amountValue: Double? = nil
        var isRelapse: Bool? = nil
        var isLogOnly: Bool? = nil
        var checkedChecklistItems: [String]? = nil
        var note: String? = nil
    }
    @MainActor init(habits: [Habit]) {
        self.habits = habits.map {
            Entry(name: $0.name, icon: $0.icon, colorName: $0.colorName, createdAt: $0.createdAt,
                  archivedAt: $0.archivedAt, sortOrder: $0.sortOrder, frequency: $0.frequency,
                  reminderTime: $0.reminderTime, healthKitIdentifier: $0.healthKitIdentifier,
                  completions: ($0.completions ?? []).map(\.date), trackingKindRaw: $0.trackingKindRaw,
                  targetAmount: $0.targetAmount, amountUnit: $0.amountUnit, category: $0.category,
                  checklistItems: $0.checklistItems, pausedRanges: $0.pausedRanges,
                  completionDetails: ($0.completions ?? []).map {
                      CompletionEntry(date: $0.date, amountValue: $0.amountValue, isRelapse: $0.isRelapse,
                                      isLogOnly: $0.isLogOnly, checkedChecklistItems: $0.checkedChecklistItems, note: $0.note)
                  })
        }
    }
    static func decode(_ data: Data) throws -> Self {
        guard data.count <= 20_000_000 else { throw BackupError.invalid }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        // Validate frequency discriminators before the app's permissive legacy decoder.
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entries = root["habits"] as? [[String: Any]], entries.count <= 10_000 else { throw BackupError.invalid }
        for entry in entries {
            guard let frequency = entry["frequency"] as? [String: Any],
                  let type = frequency["type"] as? String,
                  ["daily", "weekdays", "timesPerWeek"].contains(type) else { throw BackupError.invalid }
        }
        let backup = try decoder.decode(Self.self, from: data)
        guard backup.version == 1 else { throw BackupError.version }
        for entry in backup.habits {
            guard !entry.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  entry.name.count <= 500, entry.icon.count <= 200, entry.colorName.count <= 100,
                  entry.completions.count <= 100_000,
                  entry.createdAt <= Date(), entry.completions.allSatisfy({ $0 <= Date() }),
                  entry.reminderTime.map({ $0 >= 0 && $0 < 86400 }) ?? true else { throw BackupError.invalid }
            switch entry.frequency {
            case .weekdays(let days):
                guard !days.isEmpty, Set(days).count == days.count, days.allSatisfy({ (1...7).contains($0) }) else { throw BackupError.invalid }
            case .timesPerWeek(let count): guard (1...7).contains(count) else { throw BackupError.invalid }
            case .daily: break
            }
        }
        return backup
    }
    @MainActor func restore(into context: ModelContext) throws {
        // A separate context makes a failed import rollback independent of pending UI edits.
        let transaction = ModelContext(context.container)
        transaction.autosaveEnabled = false
        let existing = try transaction.fetch(FetchDescriptor<Habit>())
        let base = (existing.map(\.sortOrder).max() ?? -1) + 1
        for (index, entry) in habits.sorted(by: { $0.sortOrder < $1.sortOrder }).enumerated() {
            let habit = Habit(name: entry.name, icon: entry.icon, colorName: entry.colorName, sortOrder: base + index)
            habit.createdAt = entry.createdAt
            habit.archivedAt = entry.archivedAt
            habit.frequency = entry.frequency
            habit.reminderTime = entry.reminderTime
            habit.healthKitIdentifier = entry.healthKitIdentifier
            habit.trackingKindRaw = entry.trackingKindRaw
            habit.targetAmount = entry.targetAmount
            habit.amountUnit = entry.amountUnit
            habit.category = entry.category
            habit.checklistItems = entry.checklistItems ?? []
            habit.pausedRanges = entry.pausedRanges ?? []
            transaction.insert(habit)
            let details = entry.completionDetails ?? []
            habit.completions = Set(entry.completions.map { Calendar.current.startOfDay(for: $0) }).sorted().map { day in
                let completion = HabitCompletion(date: day)
                if let detail = details.first(where: { Calendar.current.isDate($0.date, inSameDayAs: day) }) {
                    completion.amountValue = detail.amountValue
                    completion.isRelapse = detail.isRelapse
                    completion.isLogOnly = detail.isLogOnly
                    completion.checkedChecklistItems = detail.checkedChecklistItems ?? []
                    completion.note = detail.note
                }
                transaction.insert(completion)
                completion.habit = habit
                return completion
            }
        }
        do { try transaction.save() } catch { transaction.rollback(); throw error }
    }
    enum BackupError: LocalizedError {
        case invalid, version
        var errorDescription: String? {
            self == .version ? "This backup version is not supported." : "This file is not a valid FreeHabits backup."
        }
    }
}

struct HabitBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(backup: HabitBackup) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        data = try encoder.encode(backup)
    }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw HabitBackup.BackupError.invalid }
        self.data = data
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

struct HabitDataView: View {
    @Query(sort: \Habit.sortOrder) private var habits: [Habit]
    @Environment(\.modelContext) private var context
    @State private var document: HabitBackupDocument?
    @State private var exporting = false
    @State private var importing = false
    @State private var preview: HabitBackup?
    @State private var message: String?
    var body: some View {
        List {
            Section("Your history, in your hands") {
                Text("Save a complete copy of your habits and completion history to Files.")
                    .foregroundStyle(.secondary)
                Button("Export backup", systemImage: "square.and.arrow.up") {
                    do { document = try HabitBackupDocument(backup: HabitBackup(habits: habits)); exporting = true }
                    catch { message = error.localizedDescription }
                }
                Button("Restore from file", systemImage: "square.and.arrow.down") { importing = true }
            }
            if let backup = preview {
                Section("Review restore") {
                    LabeledContent("Habits", value: "\(backup.habits.count)")
                    LabeledContent("Completion records", value: "\(backup.habits.reduce(0) { $0 + $1.completions.count })")
                    Text("Imports as new copies, including archived habits. Importing the same file again creates additional copies. Existing habits stay in place.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button("Import these habits") {
                        do { try backup.restore(into: context); preview = nil; message = "Habits imported successfully." }
                        catch { message = error.localizedDescription }
                    }
                    Button("Cancel", role: .cancel) { preview = nil }
                }
            }
            Section {
                Text("Charts use Activity Heatmap by SwiftPieces, © 2026 Saivion Hayes, MIT + Commons Clause.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Backup & restore")
        .fileExporter(isPresented: $exporting, document: document, contentType: .json, defaultFilename: "FreeHabits-backup") { result in
            if case .failure(let error) = result { message = error.localizedDescription }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            do {
                let url = try result.get()
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= 20_000_000 else { throw HabitBackup.BackupError.invalid }
                preview = try HabitBackup.decode(Data(contentsOf: url))
            } catch { preview = nil; message = error.localizedDescription }
        }
        .alert("FreeHabits", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK") { message = nil }
        } message: { Text(message ?? "") }
    }
}
