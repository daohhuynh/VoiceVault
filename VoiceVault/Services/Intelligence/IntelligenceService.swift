//
//  IntelligenceService.swift
//  VoiceVault
//
//  Owner: Dev 2 — Local Intelligence Pipeline (The "Brain")
//  Hackathon Day 1 — Production NLP Service
//
//  Performs on-device NLP analysis using Apple's NaturalLanguage framework.
//  Three-stage pipeline: Keyword Extraction → Sentiment Scoring → Vector Embedding.
//  All processing stays on the device — no data leaves the phone.
//

import Foundation
import NaturalLanguage
import Observation
import os

// MARK: - IntelligenceService

/// Production implementation of `IntelligenceServiceProtocol`.
///
/// Uses Apple's `NaturalLanguage` framework to perform a three-stage NLP
/// pipeline entirely on-device:
///
/// 1. **Keyword Extraction** — `NLTagger` with `.lexicalClass` scheme identifies
///    nouns and adjectives, then ranks them by frequency. The top 10 most
///    relevant terms are returned.
/// 2. **Sentiment Analysis** — `NLTagger` with `.sentimentScore` scheme evaluates
///    the full transcript and returns a normalized polarity in `[-1.0, 1.0]`.
/// 3. **Vector Embedding** — `NLEmbedding.sentenceEmbedding(for:)` converts
///    the entire transcript into a dense `[Double]` array for semantic search.
///
/// ## Privacy
/// All NLP models run on the local Neural Engine / CPU. Zero network calls.
///
/// ## Error Handling
/// If any NLP model fails to load (rare on iOS 17+), the service throws
/// descriptive `IntelligenceError` cases so callers can degrade gracefully
/// (e.g., fall back to `MockIntelligenceService` via `AppEnvironment`).
///
/// ## Concurrency
/// The class is `@Observable` for SwiftUI compatibility and `@unchecked Sendable`
/// to satisfy the `IntelligenceServiceProtocol: Sendable` requirement.
/// All mutable state is internal and accessed only within `async` methods.
@Observable
final class IntelligenceService: IntelligenceServiceProtocol, @unchecked Sendable {

    // MARK: - Private Properties

    /// Logger scoped to the intelligence subsystem for structured diagnostics.
    @ObservationIgnored
    private let logger = Logger(subsystem: "com.voicevault.app", category: "intelligence")

    /// The maximum number of keywords to extract from a transcript.
    /// Keeps results focused and clinically useful.
    @ObservationIgnored
    private let maxKeywordCount = 10

    /// Minimum word length to consider for keyword extraction.
    /// Filters out articles, prepositions, and other noise.
    @ObservationIgnored
    private let minimumWordLength = 3

    // MARK: - Lexical Classes for Keywords

    /// The set of `NLTag` lexical classes considered meaningful for keyword extraction.
    /// Nouns capture clinical entities (symptoms, medications, body parts).
    /// Adjectives capture qualitative descriptors (severe, mild, chronic).
    @ObservationIgnored
    private let relevantLexicalClasses: Set<NLTag> = [
        .noun,
        .adjective
    ]

    // MARK: - Protocol Conformance

    /// Analyzes a transcript and returns sentiment, keywords, and vector embedding.
    ///
    /// Executes the full three-stage NLP pipeline:
    /// 1. Validates the input and detects language.
    /// 2. Extracts keywords via `NLTagger` (`.lexicalClass` scheme).
    /// 3. Computes sentiment via `NLTagger` (`.sentimentScore` scheme).
    /// 4. Generates a vector embedding via `NLEmbedding.sentenceEmbedding(for:)`.
    ///
    /// - Parameter transcript: The raw text to analyze. Must not be empty.
    /// - Returns: A `SentimentResult` containing score, keywords, and vector.
    /// - Throws: `IntelligenceError` if the transcript is empty, language detection
    ///   fails, or the embedding model is unavailable.
    func analyze(transcript: String) async throws -> SentimentResult {
        logger.info("🧠 analyze() called — input length: \(transcript.count) characters")

        // 1. Validate input
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            logger.error("❌ Empty transcript provided")
            throw IntelligenceError.emptyTranscript
        }

        // 2. Detect language
        let language = try detectLanguage(in: trimmed)
        logger.info("🌐 Detected language: \(language.rawValue)")

        // 3. Extract keywords (nouns + adjectives, ranked by frequency)
        let keywords = extractKeywords(from: trimmed)
        logger.info("🔑 Extracted \(keywords.count) keywords: \(keywords.joined(separator: ", "))")

        // 4. Compute sentiment score
        let sentimentScore = computeSentiment(for: trimmed)
        logger.info("💭 Sentiment score: \(sentimentScore)")

        // 5. Generate vector embedding
        let vector = try generateEmbedding(for: trimmed, language: language)
        logger.info("📐 Generated embedding vector — dimensions: \(vector.count)")

        // 6. Package and return
        let result = SentimentResult(
            score: sentimentScore,
            keywords: keywords,
            vector: vector
        )

        logger.info("✅ Analysis complete — score: \(result.score), keywords: \(result.keywords.count), vector dims: \(result.vector.count)")
        return result
    }

    /// Computes the cosine similarity between two vector embeddings.
    ///
    /// Uses the standard dot-product / magnitude formula. Useful for finding
    /// semantically similar journal entries without re-running the full NLP pipeline.
    ///
    /// - Parameters:
    ///   - vectorA: First embedding vector.
    ///   - vectorB: Second embedding vector.
    /// - Returns: Cosine similarity in `[-1.0, 1.0]`, where 1.0 indicates
    ///   identical semantic meaning.
    /// - Throws: `IntelligenceError.analysisFailure` if vectors have mismatched dimensions.
    func cosineSimilarity(between vectorA: [Double], and vectorB: [Double]) throws -> Double {
        guard vectorA.count == vectorB.count else {
            throw IntelligenceError.analysisFailure(
                underlying: "Vector dimension mismatch: \(vectorA.count) vs \(vectorB.count)"
            )
        }

        guard !vectorA.isEmpty else {
            throw IntelligenceError.analysisFailure(
                underlying: "Cannot compute similarity of empty vectors"
            )
        }

        let dotProduct = zip(vectorA, vectorB).reduce(0.0) { $0 + $1.0 * $1.1 }
        let magnitudeA = sqrt(vectorA.reduce(0.0) { $0 + $1 * $1 })
        let magnitudeB = sqrt(vectorB.reduce(0.0) { $0 + $1 * $1 })

        guard magnitudeA > 0, magnitudeB > 0 else {
            return 0.0
        }

        return dotProduct / (magnitudeA * magnitudeB)
    }

    // MARK: - Private: Language Detection

    /// Detects the dominant language of the transcript using `NLLanguageRecognizer`.
    ///
    /// - Parameter text: The input text to analyze.
    /// - Returns: The detected `NLLanguage`.
    /// - Throws: `IntelligenceError.languageDetectionFailed` if the recognizer
    ///   cannot determine the language.
    private func detectLanguage(in text: String) throws -> NLLanguage {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)

        guard let dominantLanguage = recognizer.dominantLanguage else {
            logger.error("❌ Language detection failed — no dominant language found")
            throw IntelligenceError.languageDetectionFailed
        }

        return dominantLanguage
    }

    // MARK: - Private: Keyword Extraction

    /// Extracts the most relevant keywords (nouns and adjectives) from the transcript.
    ///
    /// Uses `NLTagger` with the `.lexicalClass` scheme to identify parts of speech,
    /// then filters for nouns and adjectives. Keywords are ranked by frequency of
    /// occurrence (most frequent first) and limited to `maxKeywordCount`.
    ///
    /// Words shorter than `minimumWordLength` are discarded to eliminate noise
    /// (articles, prepositions, conjunctions).
    ///
    /// - Parameter text: The input text to analyze.
    /// - Returns: An array of keyword strings, ordered by frequency descending.
    ///   Returns an empty array if the tagger produces no results.
    private func extractKeywords(from text: String) -> [String] {
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = text

        var frequencyMap: [String: Int] = [:]
        let range = text.startIndex..<text.endIndex

        tagger.enumerateTags(
            in: range,
            unit: .word,
            scheme: .lexicalClass,
            options: [.omitPunctuation, .omitWhitespace, .omitOther]
        ) { tag, tokenRange in
            guard let tag, relevantLexicalClasses.contains(tag) else {
                return true // continue to next token
            }

            let word = String(text[tokenRange]).lowercased()

            // Filter out short words (noise) and pure numbers
            guard word.count >= minimumWordLength,
                  !word.allSatisfy(\.isNumber) else {
                return true
            }

            frequencyMap[word, default: 0] += 1
            return true // continue enumeration
        }

        // Sort by frequency (descending), then alphabetically for determinism
        let sortedKeywords = frequencyMap
            .sorted { lhs, rhs in
                if lhs.value != rhs.value {
                    return lhs.value > rhs.value
                }
                return lhs.key < rhs.key
            }
            .prefix(maxKeywordCount)
            .map(\.key)

        return Array(sortedKeywords)
    }

    // MARK: - Private: Sentiment Analysis

    /// Computes a normalized sentiment score for the transcript.
    ///
    /// Uses `NLTagger` with the `.sentimentScore` tag scheme. The tagger evaluates
    /// the text at the paragraph level and returns a raw score. Individual sentence
    /// scores are averaged if the transcript spans multiple sentences.
    ///
    /// The final score is clamped to `[-1.0, 1.0]`:
    /// - `-1.0` → extremely negative (crisis language, distress indicators)
    /// - `0.0`  → neutral or mixed emotional valence
    /// - `+1.0` → extremely positive (recovery language, optimistic outlook)
    ///
    /// - Parameter text: The input text to analyze.
    /// - Returns: A normalized sentiment polarity score.
    private func computeSentiment(for text: String) -> Double {
        let tagger = NLTagger(tagSchemes: [.sentimentScore])
        tagger.string = text

        var sentimentScores: [Double] = []
        let range = text.startIndex..<text.endIndex

        // Evaluate sentiment at the sentence level for finer granularity
        tagger.enumerateTags(
            in: range,
            unit: .sentence,
            scheme: .sentimentScore,
            options: [.omitPunctuation, .omitWhitespace, .omitOther]
        ) { tag, _ in
            if let tag, let score = Double(tag.rawValue) {
                sentimentScores.append(score)
            }
            return true // continue enumeration
        }

        // If no sentence-level scores, try paragraph-level as fallback
        if sentimentScores.isEmpty {
            tagger.enumerateTags(
                in: range,
                unit: .paragraph,
                scheme: .sentimentScore,
                options: [.omitPunctuation, .omitWhitespace, .omitOther]
            ) { tag, _ in
                if let tag, let score = Double(tag.rawValue) {
                    sentimentScores.append(score)
                }
                return true
            }
        }

        // Average all collected scores; default to 0.0 (neutral) if none found
        guard !sentimentScores.isEmpty else {
            logger.debug("⚠️ No sentiment scores extracted — defaulting to neutral (0.0)")
            return 0.0
        }

        let averageScore = sentimentScores.reduce(0.0, +) / Double(sentimentScores.count)

        // Clamp to [-1.0, 1.0] for safety
        return max(-1.0, min(1.0, averageScore))
    }

    // MARK: - Private: Vector Embedding

    /// Generates a dense vector embedding for the transcript using `NLEmbedding`.
    ///
    /// Uses `NLEmbedding.sentenceEmbedding(for:)` to produce a high-dimensional
    /// vector representation of the full transcript. This vector enables semantic
    /// similarity search between journal entries via cosine similarity.
    ///
    /// If the sentence embedding model is unavailable for the detected language,
    /// falls back to a word-level averaging strategy: each word is embedded
    /// individually via `NLEmbedding.wordEmbedding(for:)`, and the resulting
    /// vectors are averaged element-wise. This fallback ensures the pipeline
    /// never returns an empty vector for valid input.
    ///
    /// - Parameters:
    ///   - text: The transcript text to embed.
    ///   - language: The detected language for model selection.
    /// - Returns: A dense `[Double]` array representing the semantic meaning.
    /// - Throws: `IntelligenceError.embeddingModelUnavailable` if neither sentence
    ///   nor word embedding models are available for the language.
    private func generateEmbedding(for text: String, language: NLLanguage) throws -> [Double] {

        // Attempt 1: Sentence-level embedding (preferred — captures full context)
        if let sentenceEmbedding = NLEmbedding.sentenceEmbedding(for: language) {
            if let vector = sentenceEmbedding.vector(for: text) {
                logger.debug("📐 Sentence embedding succeeded — \(vector.count) dimensions")
                return vector
            }
            // Model loaded but couldn't embed this specific text; try fallback
            logger.debug("⚠️ Sentence embedding model loaded but returned nil for input — trying word fallback")
        } else {
            logger.debug("⚠️ Sentence embedding model unavailable for \(language.rawValue) — trying word fallback")
        }

        // Attempt 2: Word-level embedding fallback (average of word vectors)
        if let wordEmbedding = NLEmbedding.wordEmbedding(for: language) {
            let vector = computeAveragedWordEmbedding(text: text, embedding: wordEmbedding)
            if !vector.isEmpty {
                logger.debug("📐 Word embedding fallback succeeded — \(vector.count) dimensions")
                return vector
            }
        }

        // Both models failed — this is a fatal error for the pipeline
        logger.error("❌ No embedding model available for language: \(language.rawValue)")
        throw IntelligenceError.embeddingModelUnavailable(language: language.rawValue)
    }

    // MARK: - Private: Word Embedding Fallback

    /// Computes an averaged word embedding as a fallback when sentence embedding
    /// is unavailable.
    ///
    /// Tokenizes the text into words using `NLTokenizer`, retrieves the embedding
    /// vector for each word, and returns the element-wise average across all
    /// successfully embedded words.
    ///
    /// - Parameters:
    ///   - text: The input text to tokenize and embed.
    ///   - embedding: The `NLEmbedding` word model to use.
    /// - Returns: The averaged embedding vector, or an empty array if no words
    ///   could be embedded.
    private func computeAveragedWordEmbedding(text: String, embedding: NLEmbedding) -> [Double] {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text

        let dimension = embedding.dimension
        var sumVector = [Double](repeating: 0.0, count: dimension)
        var wordCount = 0

        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { tokenRange, _ in
            let word = String(text[tokenRange])
            if let wordVector = embedding.vector(for: word) {
                for i in 0..<dimension {
                    sumVector[i] += wordVector[i]
                }
                wordCount += 1
            }
            return true // continue enumeration
        }

        guard wordCount > 0 else {
            return []
        }

        // Normalize by word count to produce the average
        return sumVector.map { $0 / Double(wordCount) }
    }
}
