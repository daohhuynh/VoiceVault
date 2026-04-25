# ═══════════════════════════════════════════════════════════════════════════════
# VoiceVault — AI Agent Rules
# ═══════════════════════════════════════════════════════════════════════════════
# All AI coding agents (Cursor, Windsurf, Copilot, Gemini) MUST follow these
# rules when generating or modifying code in this repository.
# Last updated: 2026-04-25 — Hackathon Day 1
# ═══════════════════════════════════════════════════════════════════════════════

## Project Identity
- App name: VoiceVault
- Platform: iOS 17+ (iPhone only for hackathon scope)
- Language: Swift 5.10+ with strict concurrency enabled
- UI Framework: SwiftUI (declarative only — no UIKit unless wrapping hardware APIs)
- Persistence: SwiftData (NO Core Data, NO Realm, NO SQLite wrappers)
- Minimum deployment target: iOS 17.0

## ═══ ARCHITECTURE MANDATES ═══

### 1. Observable Pattern — @Observable ONLY
- USE the modern `@Observable` macro from the Observation framework for ALL
  view models and observable state holders.
- DO NOT use legacy `ObservableObject`, `@Published`, `@StateObject`, or
  `@ObservedObject`. These are BANNED in this codebase.
- View models MUST be annotated with `@Observable` and injected via
  `@State` in the owning view or passed as a dependency.
- Example:
  ```swift
  @Observable
  final class RecordingViewModel {
      var isRecording = false
      var transcript: String = ""
  }
  ```

### 2. Protocol-Oriented Programming (POP)
- Every service boundary MUST be defined as a Swift `protocol` FIRST.
- Concrete implementations live in separate files from their protocols.
- Protocols MUST live in the `Protocols/` directory.
- Concrete services MUST live in the `Services/` directory.
- Mock implementations MUST live in the `Mocks/` directory.
- Never call a concrete service directly from a ViewModel — always go
  through the protocol abstraction.

### 3. Dependency Injection
- All service dependencies MUST be injected, never instantiated inline.
- Use the `AppEnvironment` container (defined in `Core/AppEnvironment.swift`)
  as the single source of truth for wiring dependencies.
- ViewModels receive protocol-typed dependencies through their initializer.
- SwiftUI views obtain ViewModels via `@State` or from `@Environment`.
- Example:
  ```swift
  @Observable
  final class JournalViewModel {
      private let storage: StorageServiceProtocol
      private let intelligence: IntelligenceServiceProtocol

      init(storage: StorageServiceProtocol, intelligence: IntelligenceServiceProtocol) {
          self.storage = storage
          self.intelligence = intelligence
      }
  }
  ```

### 4. Zero Third-Party Dependencies
- DO NOT add any Swift Package Manager dependencies unless the team lead
  explicitly approves it in a PR comment.
- Prefer native Apple frameworks at all times:
  - Audio capture → `AVFoundation`
  - Speech-to-text → `Speech` (SFSpeechRecognizer)
  - NLP / Sentiment → `NaturalLanguage` (NLTagger, NLEmbedding)
  - Persistence → `SwiftData`
  - Networking (if needed) → `URLSession`
  - Charts → `Charts` framework
- If you believe a third-party package is truly necessary, leave a
  `// DEPENDENCY_REQUEST: <package> — <reason>` comment and do NOT add it.

## ═══ CONCURRENCY RULES ═══

### 5. Swift Concurrency
- Use structured concurrency (`async/await`, `TaskGroup`) for ALL
  asynchronous work. No Combine, no DispatchQueue, no completion handlers.
- Service protocol methods that perform I/O MUST be declared `async throws`.
- Mark actors and sendable types appropriately to satisfy strict concurrency.
- Audio streaming callbacks from AVFoundation may use a continuation bridge
  (`withCheckedThrowingContinuation`) when wrapping delegate APIs.

## ═══ FILE & CODE ORGANIZATION ═══

### 6. File Naming Conventions
- One public type per file. The filename MUST match the type name.
  - `JournalEntry.swift` contains `@Model final class JournalEntry`
  - `AudioTranscriptionServiceProtocol.swift` contains that protocol
- Extensions go in `TypeName+ExtensionPurpose.swift`
  - e.g., `Date+Formatting.swift`

### 7. Directory Ownership (Conflict Avoidance)
- Each developer owns specific directories. Do NOT modify files outside
  your assigned directory without explicit coordination:
  ```
  Developer A (Audio):    Services/Audio/, Mocks/MockAudioService.swift
  Developer B (NLP):      Services/Intelligence/, Mocks/MockIntelligenceService.swift
  Developer C (Storage):  Services/Storage/, Mocks/MockStorageService.swift, Models/
  Developer D (UI/UX):    Views/, ViewModels/
  ```
- Shared contracts in `Protocols/` and `Core/` are LOCKED after initial
  scaffolding. Changes require team consensus.

### 8. Documentation Requirements
- ALL public protocols, methods, and properties MUST have a `///` doc comment
  explaining purpose, parameters, return values, and thrown errors.
- Use `// MARK: -` sections to organize files longer than 50 lines.
- Leave a `// TODO: [owner]` comment for any incomplete implementation.

## ═══ SWIFTDATA RULES ═══

### 9. Schema Discipline
- All `@Model` classes live in `Models/` and NOTHING else.
- Models MUST NOT import SwiftUI. They are pure data.
- Models MUST NOT contain business logic — that belongs in services.
- Use `@Attribute(.unique)` for natural keys.
- Use `@Attribute(.externalStorage)` for large blobs (audio files).
- Schema migrations MUST be handled via `VersionedSchema`.

## ═══ TESTING ═══

### 10. Testability
- Every service protocol MUST have a corresponding Mock in `Mocks/`.
- Mocks MUST return deterministic, realistic data — not empty strings or 0s.
- Unit tests go in `VoiceVaultTests/` and use the Mock implementations.
- Test file naming: `TypeNameTests.swift`

## ═══ PROHIBITED PATTERNS ═══

The following patterns are BANNED and must NEVER appear in this codebase:

```
❌  ObservableObject, @Published, @StateObject, @ObservedObject
❌  import Combine (except for bridging legacy APIs, which requires a comment)
❌  DispatchQueue.main.async (use @MainActor instead)
❌  Singleton pattern (use DI via AppEnvironment)
❌  Force unwrapping (!) in production code (allowed in tests and previews)
❌  Any third-party SPM package without explicit approval
❌  print() for logging (use os.Logger)
❌  Massive view files > 200 lines (decompose into subviews)
```

## ═══ GIT CONVENTIONS ═══

### 11. Commit Messages
- Format: `[module] brief description`
- Examples:
  - `[audio] implement real-time speech recognition pipeline`
  - `[models] add vector embedding field to JournalEntry`
  - `[mocks] add realistic medical sentiment data`

### 12. Branch Strategy
- `main` — stable, buildable at all times
- `feature/<developer>/<module>` — individual work branches
- Merge via PR with at least 1 approval
