//
//  JournalEntry.swift
//  VoiceVault
//
//  Created by VoiceVault Team on 4/25/26.
//  Hackathon Day 1 — Core Schema
//

import Foundation
import SwiftData

// MARK: - JournalEntry

/// The primary persistence model representing a single voice journal recording.
///
/// Each entry captures the full lifecycle of a voice note:
/// 1. Raw audio is recorded and transcribed on-device via `Speech` framework.
/// 2. The transcript is analyzed locally via `NaturalLanguage` for sentiment and keywords.
/// 3. A vector embedding is computed for semantic similarity search.
///
/// This model is intentionally decoupled from any UI or service logic.
/// All business operations on entries go through `StorageServiceProtocol`.
@Model
final class JournalEntry {

    // MARK: - Identity

    /// Stable, globally unique identifier for this entry.
    /// Automatically generated on creation; used for cross-referencing and sync.
    @Attribute(.unique)
    var id: UUID

    /// The exact date and time the recording was initiated by the user.
    var timestamp: Date

    // MARK: - Transcription

    /// The verbatim, unprocessed transcript produced by on-device speech recognition.
    ///
    /// This is the raw output from `SFSpeechRecognizer` with no post-processing.
    /// May contain filler words, false starts, and recognition artifacts.
    /// An empty string indicates transcription has not yet completed or failed.
    var rawTranscript: String

    // MARK: - Sentiment Analysis

    /// A normalized sentiment polarity score in the range `[-1.0, 1.0]`.
    ///
    /// - `-1.0` indicates extremely negative sentiment (distress, crisis language).
    /// - `0.0` indicates neutral or mixed sentiment.
    /// - `+1.0` indicates extremely positive sentiment (optimism, recovery language).
    ///
    /// Computed locally via `NLTagger` with the `.sentimentScore` tag scheme.
    var sentimentScore: Double

    // MARK: - Keyword Extraction

    /// An ordered array of clinically relevant keywords extracted from the transcript.
    ///
    /// Keywords are extracted via `NLTagger` using `.nameType` and `.lexicalClass` schemes,
    /// filtered to retain nouns, medical terms, and emotional descriptors.
    /// Ordered by relevance/frequency descending.
    ///
    /// Example: `["sleep", "anxiety", "medication", "headache", "improvement"]`
    var extractedKeywords: [String]

    // MARK: - Vector Embedding

    /// A dense vector representation of the transcript for semantic similarity search.
    ///
    /// Generated via `NLEmbedding.wordEmbedding(for: .english)` or a custom
    /// on-device model. The dimensionality depends on the embedding model used
    /// (typically 128 or 512 floats).
    ///
    /// Used for finding semantically similar past entries (e.g., "show me entries
    /// where the patient discussed sleep problems").
    ///
    /// Stored as `[Double]` for SwiftData compatibility. Empty array if embedding
    /// has not been computed.
    var vectorEmbedding: [Double]

    // MARK: - Metadata

    /// Duration of the original audio recording in seconds.
    /// Zero if not yet determined.
    var audioDurationSeconds: Double

    /// Optional filepath or identifier for the raw audio data if retained.
    ///
    /// Audio blobs are stored externally via `@Attribute(.externalStorage)` on
    /// a companion model if needed. This field holds only a reference string.
    var audioReferenceKey: String?

    // MARK: - Lifecycle

    /// Indicates whether the entry has been fully processed (transcribed + analyzed).
    /// UI can use this to show a processing spinner or partial state.
    var isFullyProcessed: Bool

    // MARK: - Initializer

    /// Creates a new journal entry with all required fields.
    ///
    /// - Parameters:
    ///   - id: Unique identifier. Defaults to a new UUID.
    ///   - timestamp: When the recording was initiated. Defaults to now.
    ///   - rawTranscript: The speech-to-text output. Defaults to empty.
    ///   - sentimentScore: Sentiment polarity in [-1.0, 1.0]. Defaults to 0.
    ///   - extractedKeywords: Relevant keywords. Defaults to empty.
    ///   - vectorEmbedding: Dense embedding vector. Defaults to empty.
    ///   - audioDurationSeconds: Recording length in seconds. Defaults to 0.
    ///   - audioReferenceKey: Optional reference to stored audio blob.
    ///   - isFullyProcessed: Whether NLP pipeline has completed. Defaults to false.
    init(
        id: UUID = UUID(),
        timestamp: Date = .now,
        rawTranscript: String = "",
        sentimentScore: Double = 0.0,
        extractedKeywords: [String] = [],
        vectorEmbedding: [Double] = [],
        audioDurationSeconds: Double = 0.0,
        audioReferenceKey: String? = nil,
        isFullyProcessed: Bool = false
    ) {
        self.id = id
        self.timestamp = timestamp
        self.rawTranscript = rawTranscript
        self.sentimentScore = sentimentScore
        self.extractedKeywords = extractedKeywords
        self.vectorEmbedding = vectorEmbedding
        self.audioDurationSeconds = audioDurationSeconds
        self.audioReferenceKey = audioReferenceKey
        self.isFullyProcessed = isFullyProcessed
    }
}

// MARK: - Convenience Extensions

extension JournalEntry {

    /// Human-readable sentiment label derived from the numeric score.
    ///
    /// Thresholds are calibrated for clinical relevance:
    /// - **Negative** (< -0.25): May indicate distress — flag for review.
    /// - **Neutral** (-0.25...0.25): Baseline emotional state.
    /// - **Positive** (> 0.25): Indicates improvement or positive coping.
    var sentimentLabel: String {
        switch sentimentScore {
        case ..<(-0.25):
            return "Negative"
        case -0.25...0.25:
            return "Neutral"
        default:
            return "Positive"
        }
    }

    /// A truncated preview of the transcript suitable for list cells.
    /// Returns the first 120 characters followed by ellipsis if longer.
    var transcriptPreview: String {
        if rawTranscript.count <= 120 {
            return rawTranscript
        }
        return String(rawTranscript.prefix(120)) + "…"
    }
}
