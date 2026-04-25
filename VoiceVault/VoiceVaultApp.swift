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

    /// The SwiftData model container for `JournalEntry` persistence.
    /// Created once at app launch and shared with both SwiftUI and the DI layer.
    let sharedModelContainer: ModelContainer

    /// The centralized dependency injection container.
    /// Holds all service instances (audio, intelligence, storage).
    /// Swap `.production()` for `.preview()` to use mock services.
    @State private var environment: AppEnvironment

    init() {
        // 1. Build the SwiftData container
        let schema = Schema([JournalEntry.self])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false
        )

        let container: ModelContainer
        do {
            container = try ModelContainer(
                for: schema,
                configurations: [configuration]
            )
        } catch {
            fatalError("❌ Could not create ModelContainer: \(error)")
        }
        self.sharedModelContainer = container

        // 2. Wire the production environment with the real StorageService
        //    AppEnvironment.production(modelContainer:) is @MainActor and
        //    App.init() runs on the main thread, so this is safe.
        _environment = State(
            initialValue: AppEnvironment.production(modelContainer: container)
        )
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(environment)
        }
        .modelContainer(sharedModelContainer)
    }
}

