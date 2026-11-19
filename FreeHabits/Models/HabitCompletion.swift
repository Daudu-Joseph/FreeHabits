//
//  HabitCompletion.swift
//  FreeHabits
//
//  Created by Jonas Gunklach on 17.04.26.
//

import Foundation
import SwiftData

@Model
final class HabitCompletion {
    var date: Date = Date.now
    var habit: Habit?
    var amountValue: Double?
    var isRelapse: Bool?
    var isLogOnly: Bool?
    var checklistData: Data?
    var note: String?

    init(date: Date = .now) {
        self.date = date
    }

    var checkedChecklistItems: [String] {
        get { (try? JSONDecoder().decode([String].self, from: checklistData ?? Data())) ?? [] }
        set { checklistData = try? JSONEncoder().encode(newValue) }
    }
}
