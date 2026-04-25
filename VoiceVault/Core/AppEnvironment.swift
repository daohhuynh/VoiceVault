//
//  AppEnvironment.swift
//  VoiceVault
//
//  Created by VoiceVault Team on 4/25/26.
//  Hackathon Day 1 — Dependency Injection Container
//

import Foundation
import os

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
///     @State private var environment = AppEnvironment.production()
///
///     var body: some Scene {
///         WindowGroup {
///             ContentView()
///                 .environment(environment)
///         }
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
    ///   - logger: The application logger. Defaults to the VoiceVault subsystem.
    init(
        audioService: AudioTranscriptionServiceProtocol,
        intelligenceService: IntelligenceServiceProtocol,
        storageService: StorageServiceProtocol,
        logger: Logger = Logger(subsystem: "com.voicevault.app", category: "general")
    ) {
        self.audioService = audioService
        self.intelligenceService = intelligenceService
        self.storageService = storageService
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
    /// - Returns: An `AppEnvironment` configured with production services.
    static func production() -> AppEnvironment {
        // TODO: [team] Replace mocks with real implementations as they become available.
        // During initial parallel development, all services start as mocks so the
        // UI team (Developer D) can build against realistic data immediately.
        let logger = Logger(subsystem: "com.voicevault.app", category: "production")
        logger.info("🔧 Initializing VoiceVault production environment")

        return AppEnvironment(
            audioService: AudioTranscriptionService(),
            intelligenceService: MockIntelligenceService(),
            storageService: MockStorageService(),
            logger: logger
        )
    }

    /// Creates a preview/testing environment with mock services.
    ///
    /// Use this in SwiftUI `#Preview` blocks and unit tests.
    /// All mock services return deterministic, medical-grade dummy data instantly.
    ///
    /// - Returns: An `AppEnvironment` configured with mock services.
    static func preview() -> AppEnvironment {
        return AppEnvironment(
            audioService: AudioTranscriptionService(),
            intelligenceService: MockIntelligenceService(),
            storageService: MockStorageService.withSampleData(),
            logger: Logger(subsystem: "com.voicevault.app", category: "preview")
        )
    }
}
