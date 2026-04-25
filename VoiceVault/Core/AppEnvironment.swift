//
//  AppEnvironment.swift
//  VoiceVault
//
//  Created by VoiceVault Team on 4/25/26.
//  Hackathon Day 1 — Dependency Injection Container
//

import Foundation
import os
import SwiftData

// MARK: - AppEnvironment

/// The centralized dependency injection container for VoiceVault.
///
/// `AppEnvironment` is the single source of truth for all service instances
/// in the application. It holds protocol-typed references to every service,
/// allowing seamless swapping between real and mock implementations.
///
/// ## Design Rationale
/// - **No singletons.** Every service is instantiated and held by this container.
/// - **Protocol-typed properties** ensure consumers depend on abstractions, not
///   concrete implementations.
/// - **Factory methods** (`production()` and `preview()`) provide pre-configured
///   environments for different build contexts.
///
/// ## Usage in App Entry Point
/// ```swift
/// @main
/// struct VoiceVaultApp: App {
///     let container: ModelContainer
///     @State private var environment: AppEnvironment
///
///     init() {
///         let container = try! ModelContainer(for: JournalEntry.self)
///         self.container = container
///         _environment = State(initialValue: AppEnvironment.production(modelContainer: container))
///     }
///
///     var body: some Scene {
///         WindowGroup {
///             ContentView()
///                 .environment(environment)
///         }
///         .modelContainer(container)
///     }
/// }
/// ```
///
/// ## Usage in SwiftUI Previews
/// ```swift
/// #Preview {
///     SomeView()
///         .environment(AppEnvironment.preview())
/// }
/// ```
@Observable
final class AppEnvironment {

    // MARK: - Service Dependencies

    /// The audio recording and transcription pipeline.
    ///
    /// In production: `AudioTranscriptionService` (AVFoundation + Speech framework).
    /// In previews/tests: `MockAudioTranscriptionService` (instant dummy transcripts).
    let audioService: AudioTranscriptionServiceProtocol

    /// The on-device NLP intelligence pipeline.
    ///
    /// In production: `IntelligenceService` (NaturalLanguage framework).
    /// In previews/tests: `MockIntelligenceService` (instant mock sentiment results).
    let intelligenceService: IntelligenceServiceProtocol

    /// The SwiftData persistence layer for journal entries.
    ///
    /// In production: `StorageService` (SwiftData ModelContext).
    /// In previews/tests: `MockStorageService` (in-memory array).
    let storageService: StorageServiceProtocol

    /// The on-device empathetic response engine.
    ///
    /// In production: `EmpathyService` (Apple Foundation Models, Neural Engine).
    /// In previews/tests: `MockEmpathyService` (canned deterministic responses).
    let empathyService: EmpathyServiceProtocol

    /// The deterministic provider intake intelligence engine.
    ///
    /// In production: `IntakeService` (statistical aggregation over StorageService).
    /// In previews/tests: `MockIntakeService` (realistic sample data).
    let intakeService: IntakeServiceProtocol

    // MARK: - Logger

    /// Shared logger for application-wide diagnostics.
    /// Uses Apple's `os.Logger` for structured, performant logging.
    let logger: Logger

    // MARK: - Initializer

    /// Creates a new environment with the specified service implementations.
    ///
    /// This is the primary injection point. Each service parameter is
    /// protocol-typed, so any conforming implementation can be provided.
    ///
    /// - Parameters:
    ///   - audioService: The audio/transcription service to use.
    ///   - intelligenceService: The NLP intelligence service to use.
    ///   - storageService: The persistence service to use.
    ///   - empathyService: The empathetic response service to use.
    ///   - intakeService: The provider intake service to use.
    ///   - logger: The application logger. Defaults to the VoiceVault subsystem.
    init(
        audioService: AudioTranscriptionServiceProtocol,
        intelligenceService: IntelligenceServiceProtocol,
        storageService: StorageServiceProtocol,
        empathyService: EmpathyServiceProtocol,
        intakeService: IntakeServiceProtocol,
        logger: Logger = Logger(subsystem: "com.voicevault.app", category: "general")
    ) {
        self.audioService = audioService
        self.intelligenceService = intelligenceService
        self.storageService = storageService
        self.empathyService = empathyService
        self.intakeService = intakeService
        self.logger = logger
    }
}

// MARK: - Factory Methods

extension AppEnvironment {

    /// Creates a production environment with real service implementations.
    ///
    /// Call this in the `@main` App struct for release builds.
    /// Each real service uses native Apple frameworks (AVFoundation, Speech,
    /// NaturalLanguage, SwiftData) — no third-party dependencies.
    ///
    /// - Parameter modelContainer: The SwiftData `ModelContainer` from the app scene.
    ///   Its `mainContext` is injected into the `StorageService`.
    /// - Returns: An `AppEnvironment` configured with production services.
    @MainActor
    static func production(modelContainer: ModelContainer) -> AppEnvironment {
        let logger = Logger(subsystem: "com.voicevault.app", category: "production")
        logger.info("🔧 Initializing VoiceVault production environment — all services LIVE")

        let storage = StorageService(modelContext: modelContainer.mainContext)

        return AppEnvironment(
            audioService: AudioTranscriptionService(),
            intelligenceService: IntelligenceService(),
            storageService: storage,
            empathyService: EmpathyService(),
            intakeService: IntakeService(storageService: storage),
            logger: logger
        )
    }

    /// Creates a preview/testing environment with mock services.
    ///
    /// Use this in SwiftUI `#Preview` blocks and unit tests.
    /// All mock services return deterministic, medical-grade dummy data instantly.
    /// Does NOT require a `ModelContainer`.
    ///
    /// - Returns: An `AppEnvironment` configured with mock services.
    static func preview() -> AppEnvironment {
        return AppEnvironment(
            audioService: MockAudioTranscriptionService(),
            intelligenceService: MockIntelligenceService(),
            storageService: MockStorageService.withSampleData(),
            empathyService: MockEmpathyService(),
            intakeService: MockIntakeService(),
            logger: Logger(subsystem: "com.voicevault.app", category: "preview")
        )
    }
}
