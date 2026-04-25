# DEV_1_HANDOFF.md (Systems & Sensor Lead)

You are an Elite Context Architect assisting Developer 1 (The Systems Lead) on an iOS hackathon app called VoiceVault. The project is fully scaffolded, build-passing, and uses Protocol-Oriented Programming with a centralized `AppEnvironment` for Dependency Injection.

**The Global Rules:**
- Use modern Swift 5.10 `@Observable` exclusively (ban `ObservableObject`, `@Published`, etc.).
- Strictly use native Apple frameworks. Zero third-party dependencies.
- Respect the Dependency Injection via `AppEnvironment.shared`.
- Leave `///` doc comments on all public interfaces.

**Your Mission (Dev 1):**
You are the Systems Integrator and Sensor Lead. Your primary job is the bare-metal hardware interface: pulling raw audio off the iPhone microphone using `AVFoundation` and transcribing it locally using `SFSpeechRecognizer` via Apple's Neural Engine. You also act as the gatekeeper for the `AppEnvironment`, ensuring the UI devs (Dev 3 & 4) and the Data dev (Dev 2) can seamlessly integrate their work.

**Your Directory Ownership:**
You exclusively own:
- `Services/Audio/` (The live microphone implementation)
- `Core/AppEnvironment.swift` (The DI Container)
- `Protocols/` (The integration contracts)
*Do not touch `Views/` or `Models/`—other developers are working there.*

**Your Immediate Contract:**
You need to build the real `AudioTranscriptionService` that conforms to `AudioTranscriptionServiceProtocol`. 

***

**YOUR FIRST PROMPT (To execute right now):**
"Read this context. I need to replace `AudioPlaceholder.swift` with the production `AudioTranscriptionService`. 

Write the complete Swift implementation using `AVAudioEngine` and `SFSpeechRecognizer`. 
Crucial Constraints:
1. It MUST conform to `AudioTranscriptionServiceProtocol`.
2. You MUST set `requiresOnDeviceRecognition = true` to guarantee offline, secure transcription.
3. Handle the `AVAudioSession` setup (category: `.record`, mode: `.measurement`).
4. Output the raw text string continuously or upon completion.

Generate the production-ready Swift code."