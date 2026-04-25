//
//  IntakeService.swift
//  VoiceVault
//
//  Owner: Feature Layer — Provider Intake Intelligence Engine
//  Hackathon Day 1 — Deterministic Clinical Telemetry Aggregation
//
//  Consumes historical JournalEntry data from StorageService and generates
//  a 100% deterministic "Intake Cheat Sheet" for the clinician.
//
//  Architecture:
//    StorageService.fetchEntries() → Aggregate → Rank → Regress → IntakeCheatSheet
//
//  ZERO AI. ZERO LLM. Every output is derived from objective stored data.
//

import Foundation
import Observation
import os

// MARK: - IntakeService

/// Production implementation of `IntakeServiceProtocol`.
///
/// ## Design Philosophy
///
/// This service exists to bridge the gap between therapy sessions by giving the
/// provider a deterministic, objective snapshot of the patient's recent state.
///
/// **What it IS:**
/// - A statistical aggregator. It counts keywords, averages scores, and runs
///   linear regression on time-series sentiment data.
/// - A quote retriever. It finds the rawest, most extreme entries and presents
///   them as unmodified "Direct Quotes" for clinical review.
///
/// **What it is NOT:**
/// - An AI summarizer. No LLM touches this data.
/// - An interpreter. It presents facts, not opinions.
///
/// ## Pipeline
/// ```
/// StorageService
///   → fetchEntries(from:to:)
///   → Fact Extraction (keyword frequency counting)
///   → Evidence Retrieval (sort by |sentiment|, take extremes)
///   → Trajectory Analysis (linear regression on scores vs time)
///   → IntakeCheatSheet
/// ```
@Observable
final class IntakeService: IntakeServiceProtocol, @unchecked Sendable {

    // MARK: - Private Properties

    @ObservationIgnored
    private let logger = Logger(subsystem: "com.voicevault.app", category: "intake")

    /// Reference to the storage layer. Protocol-typed — never touches concrete.
    @ObservationIgnored
    private let storageService: StorageServiceProtocol

    // MARK: - Initializer

    /// Creates a new IntakeService with a storage service dependency.
    ///
    /// - Parameter storageService: The persistence layer to query historical entries from.
    init(storageService: StorageServiceProtocol) {
        self.storageService = storageService
    }

    // MARK: - Protocol Conformance

    /// Generates a deterministic intake cheat sheet for the provider.
    ///
    /// Aggregates the last N days of journal entries and produces:
    /// - Top 5 keywords by frequency
    /// - Top 3 most extreme sentiment entries as direct quotes
    /// - Sentiment trend via linear regression
    /// - Min/max/average sentiment statistics
    ///
    /// - Parameter days: Number of days to look back. Defaults to 7.
    /// - Returns: A fully populated `IntakeCheatSheet`.
    /// - Throws: `IntakeError.insufficientData` if no entries exist in the period.
    func generateCheatSheet(forLastDays days: Int = 7) async throws -> IntakeCheatSheet {
        logger.info("📋 generateCheatSheet() called — window: \(days) days")

        // 1. Calculate date range
        let endDate = Date.now
        guard let startDate = Calendar.current.date(byAdding: .day, value: -days, to: endDate) else {
            throw IntakeError.analysisFailure(underlying: "Failed to compute date range")
        }

        // 2. Fetch entries from storage
        let entries: [JournalEntry]
        do {
            entries = try await storageService.fetchEntries(from: startDate, to: endDate)
        } catch {
            logger.error("❌ Storage fetch failed: \(error.localizedDescription)")
            throw IntakeError.storageFailure(underlying: error.localizedDescription)
        }

        guard !entries.isEmpty else {
            logger.warning("⚠️ No entries found in the last \(days) days")
            throw IntakeError.insufficientData(
                message: "No journal entries found in the last \(days) days."
            )
        }

        logger.info("📊 Found \(entries.count) entries in range")

        // 3. Fact Extraction: Top keywords
        let keywords = computeTopKeywords(from: entries, limit: 5)
        logger.info("🔑 Top keywords: \(keywords.map(\.keyword).joined(separator: ", "))")

        // 4. Evidence Retrieval: Critical quotes
        let quotes = extractCriticalQuotes(from: entries, limit: 3)
        logger.info("📝 Extracted \(quotes.count) critical quotes")

        // 5. Trajectory Analysis: Sentiment trend
        let trend = computeTrend(from: entries)
        logger.info("📈 Sentiment trend: \(trend.rawValue)")

        // 6. Statistical summary
        let scores = entries.map(\.sentimentScore)
        let average = scores.reduce(0.0, +) / Double(scores.count)
        let minimum = scores.min() ?? 0.0
        let maximum = scores.max() ?? 0.0

        let sheet = IntakeCheatSheet(
            periodStart: startDate,
            periodEnd: endDate,
            totalEntries: entries.count,
            topKeywords: keywords,
            criticalQuotes: quotes,
            trend: trend,
            averageSentiment: (average * 100).rounded() / 100, // round to 2 dp
            minimumSentiment: minimum,
            maximumSentiment: maximum
        )

        logger.info("✅ Cheat sheet generated — \(sheet.totalEntries) entries, trend: \(sheet.trend.rawValue)")
        return sheet
    }

    /// Retrieves the top N most frequent keywords across entries in a date range.
    func topKeywords(from startDate: Date, to endDate: Date, limit: Int = 5) async throws -> [(keyword: String, count: Int)] {
        let entries: [JournalEntry]
        do {
            entries = try await storageService.fetchEntries(from: startDate, to: endDate)
        } catch {
            throw IntakeError.storageFailure(underlying: error.localizedDescription)
        }

        return computeTopKeywords(from: entries, limit: limit)
    }

    /// Computes the sentiment trend direction for entries in a date range.
    func sentimentTrend(from startDate: Date, to endDate: Date) async throws -> SentimentTrend {
        let entries: [JournalEntry]
        do {
            entries = try await storageService.fetchEntries(from: startDate, to: endDate)
        } catch {
            throw IntakeError.storageFailure(underlying: error.localizedDescription)
        }

        guard entries.count >= 2 else {
            throw IntakeError.insufficientData(
                message: "At least 2 entries are required to compute a trend."
            )
        }

        return computeTrend(from: entries)
    }

    // MARK: - Private: Fact Extraction

    /// Counts keyword frequencies across all entries and returns the top N.
    ///
    /// Each entry's `extractedKeywords` array is iterated. Keywords are
    /// lowercased and deduplicated per-entry (a keyword appearing 3 times
    /// in one entry counts as 1 occurrence for that entry).
    private func computeTopKeywords(from entries: [JournalEntry], limit: Int) -> [(keyword: String, count: Int)] {
        var frequencyMap: [String: Int] = [:]

        for entry in entries {
            // Deduplicate within a single entry to avoid inflated counts
            let uniqueKeywords = Set(entry.extractedKeywords.map { $0.lowercased() })
            for keyword in uniqueKeywords {
                frequencyMap[keyword, default: 0] += 1
            }
        }

        return frequencyMap
            .sorted { lhs, rhs in
                if lhs.value != rhs.value { return lhs.value > rhs.value }
                return lhs.key < rhs.key
            }
            .prefix(limit)
            .map { (keyword: $0.key, count: $0.value) }
    }

    // MARK: - Private: Evidence Retrieval

    /// Extracts the N most extreme sentiment entries as raw clinical quotes.
    ///
    /// "Extreme" = furthest from zero (either direction), but prioritizes
    /// negative extremes for clinical safety.
    ///
    /// The transcript is truncated to 200 characters for readability.
    private func extractCriticalQuotes(from entries: [JournalEntry], limit: Int) -> [ClinicalQuote] {
        // Sort by sentiment score ascending (most negative first)
        let sorted = entries.sorted { $0.sentimentScore < $1.sentimentScore }

        return sorted
            .prefix(limit)
            .map { entry in
                let truncated: String
                if entry.rawTranscript.count <= 200 {
                    truncated = entry.rawTranscript
                } else {
                    truncated = String(entry.rawTranscript.prefix(200)) + "…"
                }

                return ClinicalQuote(
                    text: truncated,
                    sentimentScore: entry.sentimentScore,
                    timestamp: entry.timestamp,
                    keywords: entry.extractedKeywords
                )
            }
    }

    // MARK: - Private: Trajectory Analysis

    /// Computes the sentiment trend using simple linear regression.
    ///
    /// ## Method
    /// Entries are sorted chronologically. Each entry is assigned an index
    /// (0, 1, 2, ...) and its sentiment score is the dependent variable.
    /// We compute the least-squares slope:
    ///
    /// ```
    /// slope = (n * Σ(xi * yi) - Σxi * Σyi) / (n * Σ(xi²) - (Σxi)²)
    /// ```
    ///
    /// ## Thresholds
    /// - slope > +0.05 → `.improving`
    /// - slope < -0.05 → `.declining`
    /// - else → `.stable`
    ///
    /// The ±0.05 threshold prevents noise from small fluctuations being
    /// interpreted as meaningful trends.
    private func computeTrend(from entries: [JournalEntry]) -> SentimentTrend {
        guard entries.count >= 2 else { return .stable }

        // Sort chronologically (oldest first)
        let sorted = entries.sorted { $0.timestamp < $1.timestamp }

        let n = Double(sorted.count)
        var sumX: Double = 0
        var sumY: Double = 0
        var sumXY: Double = 0
        var sumX2: Double = 0

        for (i, entry) in sorted.enumerated() {
            let x = Double(i)
            let y = entry.sentimentScore
            sumX += x
            sumY += y
            sumXY += x * y
            sumX2 += x * x
        }

        let denominator = n * sumX2 - sumX * sumX

        // Avoid division by zero (all x values identical — shouldn't happen but safety first)
        guard abs(denominator) > 0.0001 else { return .stable }

        let slope = (n * sumXY - sumX * sumY) / denominator

        logger.debug("📉 Linear regression slope: \(slope)")

        if slope > 0.05 {
            return .improving
        } else if slope < -0.05 {
            return .declining
        } else {
            return .stable
        }
    }
}
