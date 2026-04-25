//
//  IntelligenceServiceProtocol.swift
//  VoiceVault
//
//  Created by VoiceVault Team on 4/25/26.
//  Hackathon Day 1 — Service Contract: Text → Intelligence
//

import Foundation

// MARK: - IntelligenceError

/// Errors that can occur during on-device NLP analysis.
enum IntelligenceError: Error, LocalizedError, Sendable {

    /// The provided transcript was empty or contained only whitespace.
    case emptyTranscript

    /// The NLTagger could not determine the language of the transcript.
    case languageDetectionFailed

    /// The embedding model is not available for the detected language.
    case embeddingModelUnavailable(language: String)

    /// An internal NLP framework error occurred.
    case analysisFailure(underlying: String)

    var errorDescription: String? {
        switch self {
        case .emptyTranscript:
            return "Cannot analyze an empty transcript."
        case .languageDetectionFailed:
            return "Unable to detect the language of the transcript."
        case .embeddingModelUnavailable(let lang):
            return "Word embedding model is not available for language: \(lang)."
        case .analysisFailure(let msg):
            return "NLP analysis failed: \(msg)"
        }
    }
}

// MARK: - IntelligenceServiceProtocol

/// Defines the contract for the on-device NLP intelligence pipeline.
///
/// **Owner:** Developer B (NLP/Intelligence Module)
///
/// ## Responsibilities
/// - Accept a raw transcript string from the audio pipeline.
/// - Perform sentiment analysis via `NLTagger` (`.sentimentScore` scheme).
/// - Extract clinically relevant keywords via `NLTagger` (`.nameType`, `.lexicalClass`).
/// - Generate a vector embedding via `NLEmbedding` for semantic search.
/// - Return all results packaged in a `SentimentResult` value type.
///
/// ## Implementation Notes
/// - ALL processing MUST happen on-device. No network calls.
/// - The real implementation (`IntelligenceService`) uses Apple's `NaturalLanguage`
///   framework exclusively.
/// - Keyword extraction should prioritize medical/clinical vocabulary when present.
/// - The vector embedding dimensionality should match `NLEmbedding.wordEmbedding(for:)`
///   output (typically 512 for English).
///
/// ## Usage
/// ```swift
/// let service: IntelligenceServiceProtocol = environment.intelligenceService
/// let result = try await service.analyze(transcript: "I've been sleeping better...")
/// print(result.score)     // 0.65
/// print(result.keywords)  // ["sleep", "improvement", "better"]
/// ```
protocol IntelligenceServiceProtocol: Sendable {

    /// Analyzes a transcript and returns sentiment, keywords, and vector embedding.
    ///
    /// This is the primary entry point for the NLP pipeline. The method performs
    /// three distinct analyses and aggregates them into a single result:
    ///
    /// 1. **Sentiment scoring** — Normalized polarity in [-1.0, 1.0].
    /// 2. **Keyword extraction** — Ordered list of clinically relevant terms.
    /// 3. **Vector embedding** — Dense float array for semantic similarity.
    ///
    /// - Parameter transcript: The raw text to analyze. Must not be empty.
    /// - Returns: A `SentimentResult` containing score, keywords, and vector.
    /// - Throws: `IntelligenceError` if the transcript is empty, language detection
    ///   fails, or the embedding model is unavailable.
    func analyze(transcript: String) async throws -> SentimentResult

    /// Computes the cosine similarity between two vector embeddings.
    ///
    /// Useful for finding semantically similar journal entries without
    /// re-running the full NLP pipeline.
    ///
    /// - Parameters:
    ///   - vectorA: First embedding vector.
    ///   - vectorB: Second embedding vector.
    /// - Returns: Cosine similarity in the range `[-1.0, 1.0]`, where 1.0
    ///   indicates identical semantic meaning.
    /// - Throws: `IntelligenceError.analysisFailure` if vectors have mismatched dimensions.
    func cosineSimilarity(between vectorA: [Double], and vectorB: [Double]) throws -> Double
}
