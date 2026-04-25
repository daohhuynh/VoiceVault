//
//  MockEmpathyService.swift
//  VoiceVault
//
//  Created by VoiceVault Team on 4/25/26.
//  Hackathon Day 1 — Mock: Empathetic Response Service
//

import Foundation

// MARK: - MockEmpathyService

/// A deterministic mock of `EmpathyServiceProtocol` for previews and unit tests.
///
/// Returns canned empathetic responses based on sentiment score thresholds.
/// No LLM, no latency, instant results.
final class MockEmpathyService: EmpathyServiceProtocol, @unchecked Sendable {

    /// Simulated availability flag. Set to `false` to test unavailable code paths.
    var simulateUnavailable: Bool = false

    func isModelAvailable() -> Bool {
        return !simulateUnavailable
    }

    func generateResponse(for sentimentResult: SentimentResult) async throws -> EmpathyResponse {
        guard !simulateUnavailable else {
            throw EmpathyError.modelUnavailable
        }

        let mode: EmpathyMode
        let message: String

        switch sentimentResult.score {
        case ..<(-0.8):
            mode = .crisis
            message = "I hear you. What you're feeling is real, and you are not alone in this."
        case -0.8..<(-0.4):
            mode = .distress
            message = "It sounds like things have been really heavy lately. That takes a lot of strength to share."
        case -0.4...0.4:
            mode = .neutral
            message = "Thank you for checking in with yourself today. That awareness matters."
        default:
            mode = .positive
            message = "It's wonderful to hear some brightness in your voice. You're doing something right."
        }

        return EmpathyResponse(message: message, mode: mode)
    }
}
