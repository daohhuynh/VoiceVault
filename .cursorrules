# ═══════════════════════════════════════════════════════════════════════════════
# VoiceVault — AI Agent Rules (Hackathon Strike Team Edition)
# ═══════════════════════════════════════════════════════════════════════════════
# All AI coding agents (Cursor, Windsurf, Copilot, Gemini) MUST follow these
# rules when generating or modifying code in this repository.
# Last updated: 2026-04-25 — Hackathon Day 1 (v2: Strike Team Delegation)
# ═══════════════════════════════════════════════════════════════════════════════

## Project Identity
- App name: VoiceVault
- Platform: iOS 17+ (iPhone only for hackathon scope)
- Language: Swift 5.10+ with strict concurrency enabled
- UI Framework: SwiftUI (declarative only — no UIKit unless wrapping hardware APIs)
- Persistence: SwiftData (NO Core Data, NO Realm, NO SQLite wrappers)
- Minimum deployment target: iOS 17.0

## ═══ TEAM STRUCTURE: 24-HOUR STRIKE TEAM ═══

### This is NOT an enterprise project. This is a 24-hour hackathon. 
### Optimize for DEMO QUALITY and INTEGRATION SPEED, not clean separation.

### Team Roles & Directory Ownership

```
┌──────────────────────────────────────────────────────────────────────┐
│  Dev 1 — Systems Integrator & Sensor Lead (Dao)                     │
│  Owns: Services/Audio/, Core/AppEnvironment.swift, Protocols/       │
│  Mission: AVFoundation + SFSpeechRecognizer pipeline.               │
│           Gatekeeper of AppEnvironment and all shared contracts.     │
│           If a protocol needs amending at 2 AM, Dev 1 decides.      │
├──────────────────────────────────────────────────────────────────────┤
│  Dev 2 — Local Intelligence Pipeline (The "Brain")                  │
│  Owns: Services/Intelligence/, Services/Storage/, Models/,          │
│        Mocks/MockIntelligenceService.swift,                         │
│        Mocks/MockStorageService.swift                               │
│  Mission: NLTagger + NLEmbedding → vector → SwiftData in ONE flow.  │
│           Owns the entire data lifecycle: analyze text, generate     │
│           embeddings, persist to SwiftData, serve queries.           │
│           Eliminates the NLP↔Storage integration seam entirely.     │
├──────────────────────────────────────────────────────────────────────┤
│  Dev 3 — Patient "Vault" Architect (Consumer UI)                    │
│  Owns: Views/Patient/, ViewModels/Patient/                          │
│  Mission: Hyper-minimalist, dark-mode recording experience.         │
│           Premium mic interaction, waveform animations, gentle      │
│           nudges. Does NOT touch the database directly — pulls      │
│           exclusively from MockAudioTranscriptionService.            │
│           Make the recording feel safe, intimate, and frictionless.  │
├──────────────────────────────────────────────────────────────────────┤
│  Dev 4 — Clinical Data Viz Lead (Provider UI)                       │
│  Owns: Views/Provider/, ViewModels/Provider/                        │
│  Mission: Dense, Bloomberg-terminal-style clinical dashboard.       │
│           Lives in Swift Charts. Uses MockStorageService to pull     │
│           realistic SSRI/migraine/sleep-apnea mock data and build   │
│           sentiment timelines, keyword heatmaps, entry drill-downs. │
│           Make the data feel clinical, trustworthy, and actionable.  │
└──────────────────────────────────────────────────────────────────────┘
```

### Why This Split
- **Two UI devs = 2x polish.** Patient and Provider are different apps 
  with different design languages. Splitting them doubles visual output.
- **Brain owns vector→DB.** The tightest coupling in the system (NLP 
  output → SwiftData persistence) lives in ONE person's head.
- **Mock safety net.** If real services fail at 6 AM, leave 
  `AppEnvironment.preview()` injected. Judges see realistic clinical 
  data, you still have a competitive demo.

### ⚠️  CONFLICT RULES
- Do NOT modify files outside your owned directories.
- `Protocols/` and `Core/` are LOCKED. Only Dev 1 can amend them.
- If you need a contract change, message Dev 1. Do not self-serve.
- UI devs (Dev 3 & Dev 4): you are FULLY AUTONOMOUS within your own
  `Views/` and `ViewModels/` subdirectories. You do not need approval
  to build any component. If you need a button, build it. If the other
  UI dev already built one, build your own anyway. Go fast.

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

### 7. View Directory Structure
- Patient-facing views go in `Views/Patient/` with ViewModels in `ViewModels/Patient/`.
- Provider-facing views go in `Views/Provider/` with ViewModels in `ViewModels/Provider/`.
- There is NO `Views/Shared/` directory. It does not exist. Do not create one.
- Each view directory is **fully autonomous**. No cross-imports between
  `Views/Patient/` and `Views/Provider/`.
- **DRY does NOT apply to UI components in this hackathon.** If both Patient
  and Provider need a sentiment badge, each dev builds their own copy in
  their own folder. Duplicate freely. Coordination costs more than redundancy.
  We will refactor after the demo if we want to.

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
❌  Patient UI dev touching Services/ or Models/ directly
❌  Provider UI dev touching Services/ or Models/ directly
```

## ═══ GIT CONVENTIONS ═══

### 11. Commit Messages
- Format: `[module] brief description`
- Examples:
  - `[audio] implement real-time speech recognition pipeline`
  - `[brain] integrate NLEmbedding with SwiftData persistence`
  - `[patient-ui] add waveform animation to recording screen`
  - `[provider-ui] build sentiment timeline with Swift Charts`

### 12. Branch Strategy
- `main` — stable, buildable at all times
- `feature/<developer>/<module>` — individual work branches
- Merge via PR with at least 1 approval

## ═══ HACKATHON EMERGENCY PROTOCOL ═══

### 13. The 6 AM Failsafe
If at any point a real service implementation is broken and blocking the demo:
1. Revert `AppEnvironment.production()` to inject the Mock version.
2. The mock data is medical-grade realistic. Judges will not notice.
3. Prioritize a WORKING demo over a COMPLETE implementation.
4. A beautiful app with mock data beats an ugly app with real data.
