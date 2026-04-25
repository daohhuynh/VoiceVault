//
//  AudioTranscriptionService.swift
//  VoiceVault
//
//  Owner: Dev 1 — Systems Integrator & Sensor Lead (Dao)
//  Hackathon Day 1 — Production Audio Pipeline
//
//  Captures live microphone audio via AVAudioEngine and performs real-time,
//  on-device speech recognition using SFSpeechRecognizer. All processing
//  stays on the device — no data leaves the phone.
//

import AVFoundation
import Foundation
import Observation
import os
import Speech

// MARK: - AudioTranscriptionService

/// Production implementation of `AudioTranscriptionServiceProtocol`.
///
/// Manages an `AVAudioEngine` ↔ `SFSpeechRecognizer` pipeline to capture live
/// microphone input and stream on-device transcription results. All speech
/// recognition is performed locally via Apple's Neural Engine to guarantee
/// data privacy.
///
/// ## Architecture
/// The service delegates all mutable, hardware-bound state to a private
/// `AudioEngine` actor, ensuring thread-safe access to `AVAudioEngine`,
/// `SFSpeechRecognitionTask`, and the recognition request. The outer
/// `@Observable` class exposes a `currentTranscript` property that SwiftUI
/// views can bind to for real-time updates.
///
/// ## Concurrency
/// - `transcribe(intent:)` suspends until the user calls `stopRecording()`
///   or `maxDurationSeconds` elapses.
/// - Partial results are continuously pushed to `currentTranscript` on the
///   main actor so the UI updates in real time.
/// - Audio buffer callbacks are bridged into structured concurrency via
///   `AsyncStream` + continuation.
///
/// ## Usage
/// ```swift
/// let service = AudioTranscriptionService()
/// let transcript = try await service.transcribe(intent: .init())
/// ```
@Observable
final class AudioTranscriptionService: AudioTranscriptionServiceProtocol, @unchecked Sendable {

    // MARK: - Observable State

    /// The continuously updating transcript text. Views can observe this
    /// property to display real-time speech-to-text results.
    @ObservationIgnored
    private(set) var currentTranscript: String = ""

    // MARK: - Private State

    /// The internal actor that owns all hardware and recognition resources.
    @ObservationIgnored
    private let engine = AudioEngine()

    /// Logger scoped to the audio subsystem.
    @ObservationIgnored
    private let logger = Logger(subsystem: "com.voicevault.app", category: "audio")

    // MARK: - Protocol Conformance

    /// Starts a recording session, performs on-device speech recognition,
    /// and returns the finalized transcript.
    ///
    /// This method is long-running — it suspends until `stopRecording()` is
    /// called or `intent.maxDurationSeconds` elapses. While suspended,
    /// `currentTranscript` is updated in real time with partial results
    /// (if `intent.enablePartialResults` is `true`).
    ///
    /// - Parameter intent: Configuration for the recording session.
    /// - Returns: The complete, finalized transcript as a `String`.
    /// - Throws: `TranscriptionError` if permissions are denied, the recognizer
    ///   is unavailable, or the audio engine encounters a hardware error.
    func transcribe(intent: AudioRecordingIntent) async throws -> String {
        logger.info("▶️ transcribe(intent:) called — locale: \(intent.locale.identifier)")

        // 1. Verify permissions
        let granted = await requestPermissions()
        guard granted else {
            // Determine which permission was denied for a precise error
            let micStatus = AVAudioApplication.shared.recordPermission
            if micStatus != .granted {
                logger.error("❌ Microphone permission denied")
                throw TranscriptionError.microphonePermissionDenied
            }
            logger.error("❌ Speech recognition permission denied")
            throw TranscriptionError.speechRecognitionPermissionDenied
        }

        // 2. Validate recognizer availability for the requested locale
        guard let recognizer = SFSpeechRecognizer(locale: intent.locale),
              recognizer.isAvailable else {
            logger.error("❌ Recognizer unavailable for locale: \(intent.locale.identifier)")
            throw TranscriptionError.recognizerUnavailable(locale: intent.locale)
        }

        // 3. Enforce on-device recognition for privacy
        guard recognizer.supportsOnDeviceRecognition else {
            logger.error("❌ On-device recognition not supported for locale: \(intent.locale.identifier)")
            throw TranscriptionError.recognizerUnavailable(locale: intent.locale)
        }

        // 4. Reset observable state
        await MainActor.run {
            self.currentTranscript = ""
        }

        // 5. Start the engine and stream results
        logger.info("🎙️ Starting audio engine and recognition…")
        let transcript: String
        do {
            transcript = try await engine.startSession(
                recognizer: recognizer,
                intent: intent,
                onPartialResult: { [weak self] partialText in
                    guard let self else { return }
                    Task { @MainActor in
                        self.currentTranscript = partialText
                    }
                }
            )
        } catch let error as TranscriptionError {
            logger.error("❌ Transcription failed: \(error.localizedDescription)")
            throw error
        } catch {
            logger.error("❌ Unexpected error: \(error.localizedDescription)")
            throw TranscriptionError.unknown(underlying: error.localizedDescription)
        }

        // 6. Finalize
        await MainActor.run {
            self.currentTranscript = transcript
        }
        logger.info("✅ Transcription complete — \(transcript.count) characters")
        return transcript
    }

    /// Requests microphone and speech recognition permissions from the user.
    ///
    /// Safe to call multiple times — subsequent calls return the cached
    /// authorization status without re-prompting.
    ///
    /// - Returns: `true` if both microphone and speech recognition access are granted.
    @discardableResult
    func requestPermissions() async -> Bool {
        let micGranted = await requestMicrophonePermission()
        let speechGranted = await requestSpeechPermission()
        logger.info("🔐 Permissions — mic: \(micGranted), speech: \(speechGranted)")
        return micGranted && speechGranted
    }

    /// Stops any in-progress recording and recognition session.
    ///
    /// The pending `transcribe(intent:)` call will return with whatever
    /// transcript has been accumulated so far. If no session is active,
    /// this method is a no-op.
    func stopRecording() async {
        logger.info("⏹️ stopRecording() called")
        await engine.stopSession()
    }

    // MARK: - Private Helpers

    /// Requests microphone access using the modern async API.
    ///
    /// - Returns: `true` if the user has granted microphone permission.
    private func requestMicrophonePermission() async -> Bool {
        let currentStatus = AVAudioApplication.shared.recordPermission
        switch currentStatus {
        case .granted:
            return true
        case .denied:
            return false
        case .undetermined:
            return await withCheckedContinuation { continuation in
                AVAudioApplication.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        @unknown default:
            return false
        }
    }

    /// Requests speech recognition authorization using the modern async API.
    ///
    /// - Returns: `true` if the user has granted speech recognition permission.
    private func requestSpeechPermission() async -> Bool {
        let currentStatus = SFSpeechRecognizer.authorizationStatus()
        switch currentStatus {
        case .authorized:
            return true
        case .denied, .restricted:
            return false
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status == .authorized)
                }
            }
        @unknown default:
            return false
        }
    }
}

// MARK: - AudioEngine (Private Actor)

/// An isolated actor that owns the `AVAudioEngine`, `SFSpeechRecognitionTask`,
/// and `SFSpeechAudioBufferRecognitionRequest` lifecycle.
///
/// By encapsulating all mutable hardware state inside an actor, we guarantee
/// data-race freedom without resorting to locks or `@unchecked Sendable`.
private actor AudioEngine {

    // MARK: - Properties

    /// The core audio engine that captures microphone input.
    private var audioEngine: AVAudioEngine?

    /// The active recognition request being fed audio buffers.
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?

    /// The active recognition task returned by the speech recognizer.
    private var recognitionTask: SFSpeechRecognitionTask?

    /// Logger scoped to the audio engine internals.
    private let logger = Logger(subsystem: "com.voicevault.app", category: "audio-engine")

    // MARK: - Session Lifecycle

    /// Configures the audio session, installs a tap on the microphone input node,
    /// starts the audio engine, and begins streaming recognition results.
    ///
    /// This method suspends until `stopSession()` is called or the optional
    /// `maxDurationSeconds` timer fires. The final transcript is returned.
    ///
    /// - Parameters:
    ///   - recognizer: A validated `SFSpeechRecognizer` for the target locale.
    ///   - intent: The recording configuration.
    ///   - onPartialResult: A closure called on each partial transcript update.
    /// - Returns: The finalized transcript string.
    /// - Throws: `TranscriptionError` on audio engine or recognition failures.
    func startSession(
        recognizer: SFSpeechRecognizer,
        intent: AudioRecordingIntent,
        onPartialResult: @Sendable @escaping (String) -> Void
    ) async throws -> String {

        // Tear down any previous session
        cleanupResources()

        // 1. Configure AVAudioSession
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
            logger.info("🔊 Audio session configured — category: record, mode: measurement")
        } catch {
            logger.error("❌ Audio session setup failed: \(error.localizedDescription)")
            throw TranscriptionError.audioEngineFailure(underlying: error.localizedDescription)
        }

        // 2. Create the audio engine and recognition request
        let engine = AVAudioEngine()
        self.audioEngine = engine

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = intent.enablePartialResults
        self.recognitionRequest = request
        // --- THE SIMULATOR BYPASS ---
        #if targetEnvironment(simulator)
        // The simulator doesn't have the offline models, so we allow cloud processing just for testing
        request.requiresOnDeviceRecognition = false
        #else
        // On a physical device, strictly enforce the privacy moat
        request.requiresOnDeviceRecognition = true
        #endif

        // 3. Install a tap on the input node to feed audio buffers into the request
        let inputNode = engine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        guard recordingFormat.sampleRate > 0, recordingFormat.channelCount > 0 else {
            logger.error("❌ Invalid audio format — sampleRate or channelCount is 0")
            throw TranscriptionError.audioEngineFailure(
                underlying: "Invalid audio input format (sampleRate=\(recordingFormat.sampleRate), channels=\(recordingFormat.channelCount))"
            )
        }

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            request.append(buffer)
        }

        // 4. Start the audio engine
        do {
            engine.prepare()
            try engine.start()
            logger.info("🎙️ Audio engine started — sampleRate: \(recordingFormat.sampleRate)")
        } catch {
            logger.error("❌ Audio engine failed to start: \(error.localizedDescription)")
            cleanupResources()
            throw TranscriptionError.audioEngineFailure(underlying: error.localizedDescription)
        }

        // 5. Launch a timeout task if maxDurationSeconds is configured.
        //    This must start BEFORE we block on the continuation so it can
        //    asynchronously call stopSession() while recognition is in flight.
        var timeoutTask: Task<Void, Never>?
        if let maxDuration = intent.maxDurationSeconds {
            timeoutTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(maxDuration))
                guard !Task.isCancelled else { return }
                await self?.stopSession()
            }
        }

        // 6. Bridge SFSpeechRecognitionTask delegate callbacks into structured concurrency
        let transcript: String
        do {
            transcript = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in

                var hasResumed = false
                var accumulatedTranscript = ""

                self.recognitionTask = recognizer.recognitionTask(with: request) { result, error in

                    if let result {
                        accumulatedTranscript = result.bestTranscription.formattedString
                        onPartialResult(accumulatedTranscript)

                        if result.isFinal {
                            guard !hasResumed else { return }
                            hasResumed = true
                            continuation.resume(returning: accumulatedTranscript)
                        }
                    }

                    if let error {
                        // The task may fire an error after being cancelled — don't
                        // double-resume the continuation in that case.
                        guard !hasResumed else { return }
                        hasResumed = true

                        let nsError = error as NSError
                        // Error code 1 / 216 = recognition was cancelled by us (stopRecording).
                        // In that case, return whatever we have instead of throwing.
                        if nsError.domain == "kAFAssistantErrorDomain" && (nsError.code == 1 || nsError.code == 216) {
                            continuation.resume(returning: accumulatedTranscript)
                        } else {
                            continuation.resume(throwing: TranscriptionError.unknown(underlying: error.localizedDescription))
                        }
                    }
                }
            }
        } catch {
            timeoutTask?.cancel()
            throw error
        }

        // 7. Cancel the timeout task now that recognition completed normally
        timeoutTask?.cancel()
        return transcript
    }

    /// Stops the active recording session and tears down all resources.
    ///
    /// After this call, the continuation in `startSession` will be resumed
    /// with the accumulated transcript.
    func stopSession() {
        logger.info("⏹️ Stopping audio engine and recognition task")
        recognitionRequest?.endAudio()
        recognitionTask?.finish()
        cleanupResources()
    }

    // MARK: - Cleanup

    /// Tears down the audio engine, removes the input tap, and deactivates
    /// the audio session. Safe to call multiple times.
    private func cleanupResources() {
        if let engine = audioEngine, engine.isRunning {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        audioEngine = nil
        recognitionRequest = nil
        recognitionTask = nil

        // Best-effort deactivation — don't throw if it fails
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        logger.debug("🧹 Audio resources cleaned up")
    }
}
