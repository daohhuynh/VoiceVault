# VoiceVault (iOS Engine)

**Airgapped NLP Audio Pipeline via Strict Actor-Model Concurrency.**

VoiceVault is an iOS-native edge-compute audio transcription and sentiment analysis engine. Engineered to operate entirely offline, the system enforces a strict zero-network privacy moat via Apple's native machine learning frameworks. The architecture utilizes modern Swift Concurrency to isolate mutable hardware state and guarantee thread-safe execution across the high-frequency audio DSP pipeline.

Designed as a barebones data-ingestion tier, UI rendering is heavily deprioritized in favor of rigorous memory safety, Automatic Reference Counting (ARC) optimization, and hardware-sympathetic execution.

---

### Concurrency & Thread Boundaries

The architecture strictly deprecates legacy Grand Central Dispatch (GCD) structures (`DispatchQueue`, `OperationQueue`) in favor of modern Swift Concurrency, ensuring compile-time safety across thread boundaries.

* **Actor-Model State Isolation:** Mutable hardware instances—specifically `AVAudioEngine` and `SFSpeechRecognizer`—are entirely encapsulated within a `private actor AudioEngine`. This creates an absolute data-race safety guarantee during high-frequency asynchronous audio buffer callbacks without the overhead of manual `NSLock` or mutex implementations.
* **Deterministic UI Pinning:** Context switches for state mutations are rigorously controlled. All transcript updates and database synchronizations are pinned back to the main thread via `@MainActor` decorators and `await MainActor.run`, ensuring UI consistency without blocking the audio processing thread.

### Audio Pipeline & DSP Ingress

The audio pipeline utilizes native hardware-accelerated enclosures rather than raw pointer manipulation, optimizing for system stability during continuous transcription.

* **Hardware-Native Formatting:** The system dynamically queries and adopts the iOS device's native hardware format via `inputNode.outputFormat(forBus: 0)` (typically 32-bit floating-point linear PCM), avoiding computationally expensive software format conversions.
* **Buffer Ingestion:** Audio is captured using an `AVAudioEngine` tap block initialized with a discrete 1024-frame buffer size. These `AVAudioPCMBuffer` payloads are appended synchronously into an `SFSpeechAudioBufferRecognitionRequest` for continuous streaming analysis.

### Memory Architecture & ARC Optimization

Because Swift relies on Automatic Reference Counting (ARC) rather than a background Garbage Collector, the architecture enforces strict memory hygiene to prevent heap leaks during indefinite recording sessions.

* **Retain Cycle Prevention:** Escaping closures within the audio taps and asynchronous timeout mechanisms (`Task.sleep`) strictly enforce `[weak self]` capture semantics. This guarantees that background tasks yield memory references immediately upon cancellation or completion.
* **Reference-Type Data Models:** Driven by the underlying `SwiftData` ORM, the core database entities are implemented as `final class` reference types decorated with `@Model`, managing persistence states via Swift's macro-generated metadata.
* **Synchronous Context Saves:** Due to the `ModelContext` being bound to the SwiftUI environment, background context batching is bypassed. Instead, the architecture forces all database `upsert` and `save()` operations onto the main thread via `MainActor.run` to ensure transactional integrity.

### Edge Inference & The Privacy Moat

To satisfy the requirements of a zero-network, airgapped environment, all machine learning inference is routed through local hardware accelerators.

* **On-Device Hardware Enforcement:** Cloud fallback is explicitly banned via the compiler directive `request.requiresOnDeviceRecognition = true`. This forces all acoustic model evaluations to execute locally, utilizing the Apple Neural Engine (ANE) to preserve battery life and data privacy.
* **Semantic Analysis:** Sentence-level similarity and sentiment extraction bypass heavy third-party frameworks (e.g., CoreML) in favor of Apple's highly optimized `NaturalLanguage` framework. The engine calculates vector similarities using `NLEmbedding.sentenceEmbedding` and extracts lexical tokens via `NLTagger`.

### Tech Stack

| Layer | Technology | Purpose |
| :--- | :--- | :--- |
| **Core Architecture** | Swift 5.9+ (Actors, async/await) | Data-race prevention and thread management. |
| **DSP / Audio I/O** | `AVFoundation` | 1024-frame microphone buffer ingestion. |
| **Inference & NLP** | `Speech`, `NaturalLanguage` | Airgapped transcription and vector embeddings. |
| **Persistence** | `SwiftData` (`@Model`) | Main-thread synchronized B-Tree storage. |

### Build Instructions

The project requires Xcode 15+ and an iOS 17.0+ deployment target due to the reliance on `SwiftData` and modern Swift macros.

1. Open `VoiceVault.xcodeproj` in Xcode.
2. Select a physical iOS device (Microphone APIs and On-Device Speech Recognition will fail on the Simulator).
3. Ensure your App ID has the `NSSpeechRecognitionUsageDescription` and `NSMicrophoneUsageDescription` entitlements configured in the `Info.plist`.
4. Build and Run (`Cmd + R`).