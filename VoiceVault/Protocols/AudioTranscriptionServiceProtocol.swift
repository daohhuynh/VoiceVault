//
//  AudioTranscriptionServiceProtocol.swift
//  VoiceVault
//
//  Created by VoiceVault Team on 4/25/26.
//  Hackathon Day 1 — Service Contract: Audio → Text
//

import Foundation

// MARK: - AudioRecordingIntent

/// Describes the parameters for initiating an audio recording session.
///
/// Passed to `AudioTranscriptionServiceProtocol.transcribe(intent:)` to
/// configure the recording and recognition pipeline before starting.
struct AudioRecordingIntent: Sendable {

    /// The preferred locale for speech recognition (e.g., `en-US`, `es-MX`).
    /// Defaults to the device's current locale.
    let locale: Locale

    /// Whether to enable real-time partial results during recording.
    /// When `true`, the service may yield intermediate transcripts via a callback
    /// or AsyncSequence before returning the final result.
    let enablePartialResults: Bool

    /// Maximum recording duration in seconds. `nil` means unlimited (user-controlled stop).
    let maxDurationSeconds: Double?

    /// Creates a new recording intent with sensible defaults.
    ///
    /// - Parameters:
    ///   - locale: Speech recognition locale. Defaults to `.current`.
    ///   - enablePartialResults: Stream partial transcripts. Defaults to `true`.
    ///   - maxDurationSeconds: Optional time limit. Defaults to `nil` (unlimited).
    init(
        locale: Locale = .current,
        enablePartialResults: Bool = true,
        maxDurationSeconds: Double? = nil
    ) {
        self.locale = locale
        self.enablePartialResults = enablePartialResults
        self.maxDurationSeconds = maxDurationSeconds
    }
}

// MARK: - TranscriptionError

/// Errors that can occur during the audio capture and transcription pipeline.
enum TranscriptionError: Error, LocalizedError, Sendable {

    /// The user has not granted microphone access.
    case microphonePermissionDenied

    /// The user has not granted speech recognition permission.
    case speechRecognitionPermissionDenied

    /// On-device speech recognition is not available for the requested locale.
    case recognizerUnavailable(locale: Locale)

    /// The audio engine failed to start or encountered a hardware error.
    case audioEngineFailure(underlying: String)

    /// The recognition request was cancelled (e.g., user navigated away).
    case cancelled

    /// An unknown or unrecoverable error occurred.
    case unknown(underlying: String)

    var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            return "Microphone access is required. Please enable it in Settings."
        case .speechRecognitionPermissionDenied:
            return "Speech recognition access is required. Please enable it in Settings."
        case .recognizerUnavailable(let locale):
            return "Speech recognition is not available for \(locale.identifier)."
        case .audioEngineFailure(let msg):
            return "Audio engine error: \(msg)"
        case .cancelled:
            return "Transcription was cancelled."
        case .unknown(let msg):
            return "Transcription error: \(msg)"
        }
    }
}

// MARK: - AudioTranscriptionServiceProtocol

/// Defines the contract for the audio recording and on-device speech-to-text pipeline.
///
/// **Owner:** Developer A (Audio Module)
///
/// ## Responsibilities
/// - Request and verify microphone + speech recognition permissions.
/// - Configure and manage the `AVAudioEngine` + `SFSpeechRecognizer` pipeline.
/// - Return the finalized transcript as a plain `String`.
///
/// ## Implementation Notes
/// - The real implementation (`AudioTranscriptionService`) uses `AVFoundation`
///   and the `Speech` framework exclusively — no cloud APIs.
/// - All recognition MUST happen on-device (`requiresOnDeviceRecognition = true`).
/// - For streaming partial results, implementations may expose an `AsyncStream`
///   separately, but this protocol's primary method returns the final transcript.
///
/// ## Usage
/// ```swift
/// let service: AudioTranscriptionServiceProtocol = environment.audioService
/// let transcript = try await service.transcribe(intent: .init())
/// ```
protocol AudioTranscriptionServiceProtocol: Sendable {

    /// Starts a recording session, performs on-device speech recognition,
    /// and returns the finalized transcript.
    ///
    /// The method is long-running — it completes only when the user stops
    /// recording or `maxDurationSeconds` is reached.
    ///
    /// - Parameter intent: Configuration for the recording session.
    /// - Returns: The complete, finalized transcript as a `String`.
    /// - Throws: `TranscriptionError` if permissions are denied, the recognizer
    ///   is unavailable, or the audio engine encounters an error.
    func transcribe(intent: AudioRecordingIntent) async throws -> String

    /// Requests microphone and speech recognition permissions from the user.
    ///
    /// Call this early (e.g., on first launch) to avoid interrupting the
    /// recording flow with permission dialogs.
    ///
    /// - Returns: `true` if both permissions were granted, `false` otherwise.
    @discardableResult
    func requestPermissions() async -> Bool

    /// Stops any in-progress recording and recognition session.
    ///
    /// If no session is active, this method is a no-op.
    /// After calling stop, the `transcribe(intent:)` call that initiated
    /// the session will return with whatever transcript has been accumulated.
    func stopRecording() async
}
