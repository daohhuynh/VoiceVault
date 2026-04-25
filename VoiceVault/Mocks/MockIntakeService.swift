//
//  MockIntakeService.swift
//  VoiceVault
//
//  Created by VoiceVault Team on 4/25/26.
//  Hackathon Day 1 — Mock: Provider Intake Service
//

import Foundation

// MARK: - MockIntakeService

/// A deterministic mock of `IntakeServiceProtocol` for previews and unit tests.
///
/// Returns realistic sample data to demonstrate the provider-facing cheat sheet
/// in SwiftUI previews without requiring a populated database.
final class MockIntakeService: IntakeServiceProtocol, @unchecked Sendable {

    func generateCheatSheet(forLastDays days: Int = 7) async throws -> IntakeCheatSheet {
        let endDate = Date.now
        let startDate = Calendar.current.date(byAdding: .day, value: -days, to: endDate) ?? endDate

        return IntakeCheatSheet(
            periodStart: startDate,
            periodEnd: endDate,
            totalEntries: 12,
            topKeywords: [
                (keyword: "anxiety", count: 8),
                (keyword: "sleep", count: 6),
                (keyword: "headache", count: 4),
                (keyword: "stress", count: 3),
                (keyword: "fatigue", count: 2),
            ],
            criticalQuotes: [
                ClinicalQuote(
                    text: "I've been having these panic attacks every night before bed and I don't know what to do anymore",
                    sentimentScore: -0.85,
                    timestamp: Calendar.current.date(byAdding: .day, value: -2, to: endDate) ?? endDate,
                    keywords: ["panic", "anxiety", "sleep"]
                ),
                ClinicalQuote(
                    text: "The headaches are getting worse and the medication doesn't seem to help at all",
                    sentimentScore: -0.65,
                    timestamp: Calendar.current.date(byAdding: .day, value: -4, to: endDate) ?? endDate,
                    keywords: ["headache", "medication"]
                ),
                ClinicalQuote(
                    text: "I feel so exhausted all the time even when I sleep for eight hours",
                    sentimentScore: -0.45,
                    timestamp: Calendar.current.date(byAdding: .day, value: -6, to: endDate) ?? endDate,
                    keywords: ["fatigue", "sleep"]
                ),
            ],
            trend: .declining,
            averageSentiment: -0.35,
            minimumSentiment: -0.85,
            maximumSentiment: 0.15
        )
    }

    func topKeywords(from startDate: Date, to endDate: Date, limit: Int = 5) async throws -> [(keyword: String, count: Int)] {
        return [
            (keyword: "anxiety", count: 8),
            (keyword: "sleep", count: 6),
            (keyword: "headache", count: 4),
        ].prefix(limit).map { $0 }
    }

    func sentimentTrend(from startDate: Date, to endDate: Date) async throws -> SentimentTrend {
        return .declining
    }
}
