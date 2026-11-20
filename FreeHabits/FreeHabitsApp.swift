//
//  FreeHabitsApp.swift
//  FreeHabits
//
//  Created by Jonas Gunklach on 17.04.26.
//

import SwiftUI
import SwiftData

@main
struct FreeHabitsApp: App {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var sharedModelContainer: ModelContainer = {
#if FREE_PERSONAL_INSTALL
        let config = ModelConfiguration(cloudKitDatabase: .none)
#else
        let config = ModelConfiguration(cloudKitDatabase: .private("iCloud.de.jonasgunklach.FreeHabits"))
#endif
        do {
            return try ModelContainer(for: Habit.self, HabitCompletion.self, configurations: config)
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            Group {
            if hasCompletedOnboarding {
                FreeHabitsRootView()
            } else {
                OnboardingView(hasCompletedOnboarding: $hasCompletedOnboarding)
            }
            }
            .task { NotificationManager.shared.configure(container: sharedModelContainer) }
        }
        .modelContainer(sharedModelContainer)
    }
}
