//
//  IntakeServiceProtocol.swift
//  VoiceVault
//
//  Created by VoiceVault Team on 4/25/26.
//  Hackathon Day 1 — Service Contract: Provider Intake Intelligence
//

import Foundation

// MARK: - IntakeError

/// Errors that can occur during intake cheat sheet generation.
enum IntakeError: Error, LocalizedError, Sendable {

    /// No journal entries exist in the specified date range.
    case insufficientData(message: String)

    /// A storage operation failed while retrieving historical data.
    case storageFailure(underlying: String)

    /// The analysis computation failed.
    case analysisFailure(underlying: String)

    var errorDescription: String? {
        switch self {
        case .insufficientData(let msg):
            return "Insufficient data for intake analysis: \(msg)"
        case .storageFailure(let msg):
            return "Storage error during intake: \(msg)"
        case .analysisFailure(let msg):
            return "Intake analysis failed: \(msg)"
        }
    }
}

// MARK: - SentimentTrend

/// The mathematical direction of the patient's sentiment over a time window.
///
/// Calculated via linear regression on chronologically ordered sentiment scores.
enum SentimentTrend: String, Sendable, Equatable, Codable {
    /// Sentiment scores are trending upward (slope > +0.05 per entry).
    case improving = "Improving"
    /// Sentiment scores are relatively stable (slope within ±0.05).
    case stable    = "Stable"
    /// Sentiment scores are trending downward (slope < -0.05 per entry).
    case declining = "Declining"
}

// MARK: - ClinicalQuote

/// A direct quote from a journal entry associated with an extreme sentiment marker.
///
/// Designed for providers to review raw patient language without interpretation.
/// The quote is never paraphrased, summarized, or modified by any AI model.
struct ClinicalQuote: Sendable, Equatable, Codable {

    /// The raw transcript excerpt (first ~200 characters).
    let text: String

    /// The sentiment score associated with this entry.
    let sentimentScore: Double

    /// When this entry was recorded.
    let timestamp: Date

    /// The keywords that were extracted for this entry.
    let keywords: [String]
}

// MARK: - IntakeCheatSheet

/// A deterministic, provider-facing summary of the patient's recent journal history.
///
/// ZERO AI-generated content. Every field is derived from objective telemetry
/// stored in the vault: sentiment scores, keyword frequencies, and timestamps.
struct IntakeCheatSheet: Sendable, Equatable {

    /// The date range covered by this analysis.
    let periodStart: Date
    let periodEnd: Date

    /// The total number of journal entries analyzed.
    let totalEntries: Int

    /// The top 5 most frequently occurring clinical keywords over the period.
    /// Ordered by frequency descending.
    /// Example: `[("anxiety", 12), ("sleep", 9), ("headache", 7), ("stress", 5), ("fatigue", 4)]`
    let topKeywords: [(keyword: String, count: Int)]

    /// The 3 most extreme (lowest sentiment) entries as raw direct quotes.
    /// These are the entries most likely to warrant clinical attention.
    let criticalQuotes: [ClinicalQuote]

    /// The mathematical sentiment trajectory over the period.
    let trend: SentimentTrend

    /// The average sentiment score across all entries in the period.
    let averageSentiment: Double

    /// The lowest (most negative) sentiment score observed.
    let minimumSentiment: Double

    /// The highest (most positive) sentiment score observed.
    let maximumSentiment: Double
}

// MARK: - Equatable Conformance for IntakeCheatSheet

extension IntakeCheatSheet {
    static func == (lhs: IntakeCheatSheet, rhs: IntakeCheatSheet) -> Bool {
        lhs.periodStart == rhs.periodStart &&
        lhs.periodEnd == rhs.periodEnd &&
        lhs.totalEntries == rhs.totalEntries &&
        lhs.trend == rhs.trend &&
        lhs.averageSentiment == rhs.averageSentiment
    }
}

// MARK: - IntakeServiceProtocol

/// Defines the contract for deterministic provider-facing intake analysis.
///
/// ## Responsibilities
/// - Aggregate historical `JournalEntry` objects from `StorageService`.
/// - Extract the top 5 most frequent clinical keywords over a time window.
/// - Retrieve raw transcript quotes from the most extreme sentiment entries.
/// - Compute a mathematical sentiment trajectory (improving/stable/declining).
///
/// ## CRITICAL CONSTRAINT
/// This service is 100% deterministic. It MUST NOT use any LLM, generative AI,
/// or probabilistic model. All outputs are derived from objective facts and
/// vectors already stored in the vault.
///
/// ## Usage
/// ```swift
/// let intake: IntakeServiceProtocol = environment.intakeService
/// let sheet = try await intake.generateCheatSheet(
///     forLast: 7,
///     unit: .day
/// )
/// print(sheet.topKeywords)     // [("anxiety", 12), ("sleep", 9), ...]
/// print(sheet.trend)           // .declining
/// print(sheet.criticalQuotes)  // Raw quotes from worst entries
/// ```
protocol IntakeServiceProtocol: Sendable {

    /// Generates a deterministic intake cheat sheet for the provider.
    ///
    /// - Parameters:
    ///   - days: The number of days to look back from today. Defaults to 7.
    /// - Returns: An `IntakeCheatSheet` containing objective telemetry.
    /// - Throws: `IntakeError` if insufficient data exists or storage fails.
    func generateCheatSheet(forLastDays days: Int) async throws -> IntakeCheatSheet

    /// Retrieves the top N most frequent keywords across all entries in a date range.
    ///
    /// - Parameters:
    ///   - startDate: Beginning of the date range (inclusive).
    ///   - endDate: End of the date range (inclusive).
    ///   - limit: Maximum number of keywords to return. Defaults to 5.
    /// - Returns: An array of (keyword, count) tuples sorted by frequency descending.
    /// - Throws: `IntakeError` if storage access fails.
    func topKeywords(from startDate: Date, to endDate: Date, limit: Int) async throws -> [(keyword: String, count: Int)]

    /// Computes the sentiment trend direction for entries in a date range.
    ///
    /// Uses linear regression on chronologically ordered sentiment scores.
    ///
    /// - Parameters:
    ///   - startDate: Beginning of the date range (inclusive).
    ///   - endDate: End of the date range (inclusive).
    /// - Returns: The computed `SentimentTrend`.
    /// - Throws: `IntakeError` if insufficient data exists.
    func sentimentTrend(from startDate: Date, to endDate: Date) async throws -> SentimentTrend
}
