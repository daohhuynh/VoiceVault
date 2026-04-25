//
//  SentimentResult.swift
//  VoiceVault
//
//  Created by VoiceVault Team on 4/25/26.
//  Hackathon Day 1 — Shared Value Types
//

import Foundation

// MARK: - SentimentResult

/// A value type encapsulating the complete output of the on-device NLP pipeline.
///
/// Returned by `IntelligenceServiceProtocol.analyze(transcript:)` after
/// processing a raw transcript through sentiment analysis, keyword extraction,
/// and vector embedding generation.
///
/// This struct is intentionally a plain value type (not a `@Model`) so it can
/// be freely passed between services without persistence coupling.
struct SentimentResult: Sendable, Equatable, Codable {

    /// A normalized sentiment polarity score in the range `[-1.0, 1.0]`.
    ///
    /// - `-1.0` → extremely negative (crisis language, distress indicators)
    /// - `0.0`  → neutral or mixed emotional valence
    /// - `+1.0` → extremely positive (recovery language, optimistic outlook)
    let score: Double

    /// Clinically relevant keywords extracted from the transcript.
    ///
    /// Ordered by relevance descending. Typically includes:
    /// - Medical terms (symptoms, conditions, medications)
    /// - Emotional descriptors (anxious, hopeful, frustrated)
    /// - Behavioral markers (sleep, appetite, exercise)
    ///
    /// Example: `["insomnia", "anxiety", "melatonin", "improvement", "fatigue"]`
    let keywords: [String]

    /// Dense vector embedding of the transcript for semantic similarity search.
    ///
    /// Dimensionality depends on the embedding model (typically 128 or 512).
    /// Used to find semantically related past entries via cosine similarity.
    let vector: [Double]
}

// MARK: - SentimentResult Convenience

extension SentimentResult {

    /// An empty/default result representing unprocessed or failed analysis.
    static let empty = SentimentResult(score: 0.0, keywords: [], vector: [])

    /// Human-readable sentiment label for quick clinical triage.
    var label: String {
        switch score {
        case ..<(-0.25):
            return "Negative"
        case -0.25...0.25:
            return "Neutral"
        default:
            return "Positive"
        }
    }
}
