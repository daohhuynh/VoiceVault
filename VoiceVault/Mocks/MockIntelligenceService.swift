//
//  MockIntelligenceService.swift
//  VoiceVault
//
//  Created by VoiceVault Team on 4/25/26.
//  Hackathon Day 1 — Mock: NLP Intelligence Pipeline
//

import Foundation

// MARK: - MockIntelligenceService

/// A mock implementation of `IntelligenceServiceProtocol` for previews and testing.
///
/// Performs lightweight keyword detection on the input transcript and returns
/// clinically realistic sentiment results without requiring the `NaturalLanguage`
/// framework.
///
/// **Owner:** Shared (scaffolding), maintained by Developer B.
final class MockIntelligenceService: IntelligenceServiceProtocol, @unchecked Sendable {

    // MARK: - Configuration

    /// Simulated processing delay in seconds. Set to 0 for instant results in tests.
    var simulatedDelay: TimeInterval = 0.5

    /// If set, the mock will throw this error instead of returning results.
    var simulatedError: IntelligenceError?

    // MARK: - Clinical Keyword Database

    /// A curated dictionary of medical/clinical keywords mapped to sentiment weight adjustments.
    /// Positive values indicate recovery/improvement language; negative values indicate distress.
    private let clinicalKeywords: [String: Double] = [
        // Positive indicators
        "improvement": 0.15,
        "better": 0.12,
        "progress": 0.14,
        "stable": 0.08,
        "optimistic": 0.18,
        "proud": 0.15,
        "consistency": 0.10,
        "recovery": 0.16,
        "calm": 0.12,
        "relaxed": 0.10,
        "energy": 0.08,
        "exercise": 0.10,
        "walk": 0.06,
        "meditation": 0.12,
        "sleep": 0.05,
        "healthy": 0.14,

        // Negative indicators
        "pain": -0.15,
        "headache": -0.12,
        "anxiety": -0.18,
        "panic": -0.22,
        "depression": -0.20,
        "depressive": -0.20,
        "hopeless": -0.25,
        "frustrated": -0.14,
        "irritable": -0.12,
        "nausea": -0.10,
        "insomnia": -0.16,
        "crisis": -0.24,
        "dark": -0.18,
        "fear": -0.15,
        "scared": -0.14,
        "overwhelm": -0.16,
        "cancelled": -0.08,
        "fatigue": -0.10,
        "exhausted": -0.12,

        // Neutral medical terms (included for keyword extraction, low weight)
        "medication": 0.0,
        "sertraline": 0.0,
        "ibuprofen": -0.02,
        "lisinopril": 0.0,
        "lorazepam": -0.05,
        "therapist": 0.02,
        "psychiatrist": 0.0,
        "appointment": 0.02,
        "blood pressure": 0.0,
        "heart rate": 0.0,
        "milligrams": 0.0,
        "sodium": 0.0,
    ]

    // MARK: - Protocol Conformance

    /// Analyzes the transcript using simple keyword matching to produce realistic results.
    ///
    /// The mock algorithm:
    /// 1. Scans the transcript (case-insensitive) for known clinical keywords.
    /// 2. Accumulates sentiment weight from matched keywords, normalized to [-1.0, 1.0].
    /// 3. Returns matched keywords sorted by absolute weight (most impactful first).
    /// 4. Generates a pseudo-random 128-dimensional vector seeded from the transcript hash.
    ///
    /// - Parameter transcript: The raw text to analyze.
    /// - Returns: A `SentimentResult` with score, keywords, and vector.
    /// - Throws: `IntelligenceError` if `simulatedError` is set or transcript is empty.
    func analyze(transcript: String) async throws -> SentimentResult {
        if let error = simulatedError {
            throw error
        }

        guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw IntelligenceError.emptyTranscript
        }

        // Simulate processing time
        if simulatedDelay > 0 {
            try await Task.sleep(for: .seconds(simulatedDelay))
        }

        let lowercased = transcript.lowercased()

        // Keyword extraction & sentiment accumulation
        var matchedKeywords: [(keyword: String, weight: Double)] = []
        var sentimentAccumulator: Double = 0.0

        for (keyword, weight) in clinicalKeywords {
            if lowercased.contains(keyword.lowercased()) {
                matchedKeywords.append((keyword, weight))
                sentimentAccumulator += weight
            }
        }

        // Normalize sentiment to [-1.0, 1.0]
        let normalizedScore = max(-1.0, min(1.0, sentimentAccumulator))

        // Sort keywords by absolute weight (most impactful first)
        let sortedKeywords = matchedKeywords
            .sorted { abs($0.weight) > abs($1.weight) }
            .map(\.keyword)

        // Generate a deterministic pseudo-random 128D vector from transcript content
        let vector = generateMockEmbedding(from: transcript, dimensions: 128)

        return SentimentResult(
            score: normalizedScore,
            keywords: sortedKeywords,
            vector: vector
        )
    }

    /// Computes cosine similarity between two vectors.
    ///
    /// This is a real mathematical implementation, not a mock — the algorithm
    /// is trivial and useful for testing the full pipeline.
    ///
    /// - Parameters:
    ///   - vectorA: First embedding vector.
    ///   - vectorB: Second embedding vector.
    /// - Returns: Cosine similarity in [-1.0, 1.0].
    /// - Throws: `IntelligenceError.analysisFailure` if dimensions don't match.
    func cosineSimilarity(between vectorA: [Double], and vectorB: [Double]) throws -> Double {
        guard vectorA.count == vectorB.count else {
            throw IntelligenceError.analysisFailure(
                underlying: "Vector dimension mismatch: \(vectorA.count) vs \(vectorB.count)"
            )
        }

        guard !vectorA.isEmpty else {
            throw IntelligenceError.analysisFailure(underlying: "Cannot compute similarity of empty vectors")
        }

        let dotProduct = zip(vectorA, vectorB).reduce(0.0) { $0 + $1.0 * $1.1 }
        let magnitudeA = sqrt(vectorA.reduce(0.0) { $0 + $1 * $1 })
        let magnitudeB = sqrt(vectorB.reduce(0.0) { $0 + $1 * $1 })

        guard magnitudeA > 0, magnitudeB > 0 else {
            return 0.0
        }

        return dotProduct / (magnitudeA * magnitudeB)
    }

    // MARK: - Private Helpers

    /// Generates a deterministic pseudo-random embedding vector from a string.
    ///
    /// Uses a simple hash-based seeding approach to produce consistent vectors
    /// for the same input, making tests reproducible.
    private func generateMockEmbedding(from text: String, dimensions: Int) -> [Double] {
        // Use the hash of the text as a seed for deterministic output
        var seed = abs(text.hashValue)
        return (0..<dimensions).map { i in
            seed = seed &* 6364136223846793005 &+ 1442695040888963407 &+ i
            // Normalize to [-1.0, 1.0] range
            return Double(seed % 2000) / 1000.0 - 1.0
        }
    }
}
