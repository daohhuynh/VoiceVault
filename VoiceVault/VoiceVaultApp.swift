//
//  VoiceVaultApp.swift
//  VoiceVault
//
//  Created by Dao Huynh on 4/25/26.
//

import SwiftUI
import SwiftData

@main
struct VoiceVaultApp: App {

    /// The centralized dependency injection container.
    /// Holds all service instances (audio, intelligence, storage).
    /// Swap `.production()` for `.preview()` to use mock services.
    @State private var environment = AppEnvironment.production()

    /// The SwiftData model container for `JournalEntry` persistence.
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            JournalEntry.self,
        ])
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false
        )

        do {
            return try ModelContainer(
                for: schema,
                configurations: [modelConfiguration]
            )
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(environment)
        }
        .modelContainer(sharedModelContainer)
    }
}
