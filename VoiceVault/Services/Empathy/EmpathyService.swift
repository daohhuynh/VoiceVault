//
//  EmpathyService.swift
//  VoiceVault
//
//  Owner: Feature Layer — Client Empathetic Response Engine
//  Hackathon Day 1 — On-Device LLM Integration via Apple Foundation Models
//
//  Consumes SentimentResult from IntelligenceService and generates a short,
//  warm, non-clinical empathetic response using the on-device Neural Engine.
//
//  Architecture:
//    SentimentResult → EmpathyMode Selection → Prompt Sandwich → LLM → EmpathyResponse
//
//  All inference stays on the device. No data leaves the phone.
//
//  COMPATIBILITY NOTE:
//  Apple Foundation Models (`FoundationModels` framework) requires iOS 26+
//  (introduced at WWDC25 with year-based versioning). On earlier iOS versions,
//  the service gracefully degrades to deterministic template-based responses —
//  same persona logic, no LLM.
//

import Foundation
import Observation
import os

#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - EmpathyService

/// Production implementation of `EmpathyServiceProtocol`.
///
/// ## Design
///
/// The service wraps Apple's `FoundationModels` framework to generate 1-2 sentence
/// empathetic responses. The key innovation is the **Prompt Sandwich** architecture:
///
/// ```
/// ┌─────────────────────────────────────┐
/// │  SYSTEM GUARDRAIL (top bread)       │  ← persona + hard constraints
/// │  ─────────────────────────────────  │
/// │  CONTEXT INJECTION (filling)        │  ← score, keywords, mode
/// │  ─────────────────────────────────  │
/// │  OUTPUT CONSTRAINT (bottom bread)   │  ← format + safety rails
/// └─────────────────────────────────────┘
/// ```
///
/// The SentimentResult's objective data (score + keywords) is injected into the
/// middle of the prompt, forcing the LLM into a deterministic persona rather than
/// allowing it to freestyle.
///
/// ## Safety Gating
///
/// | Score Range       | Mode              | LLM Behavior                           |
/// |-------------------|-------------------|-----------------------------------------|
/// | < -0.8            | Crisis Validation | Acknowledge only. No advice. No fixes.  |
/// | -0.8 to -0.4      | Gentle Support    | Normalize. Validate. Soft encouragement.|
/// | -0.4 to +0.4      | Warm Acknowledgment| Reflect. Encourage self-exploration.   |
/// | > +0.4            | Growth Reinforcement| Celebrate. Reinforce positive patterns.|
///
/// ## Graceful Degradation
///
/// On devices without Apple Intelligence support, the service falls back to
/// curated template responses. Same persona logic, same safety gating — just
/// without the generative model.
@Observable
final class EmpathyService: EmpathyServiceProtocol, @unchecked Sendable {

    // MARK: - Private Properties

    @ObservationIgnored
    private let logger = Logger(subsystem: "com.voicevault.app", category: "empathy")

    // MARK: - Protocol Conformance

    /// Checks whether the on-device LLM is available on the current hardware.
    func isModelAvailable() -> Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26, *) {
            let model = SystemLanguageModel.default
            return model.availability == .available
        }
        #endif
        return false
    }

    /// Generates an empathetic response based on the analyzed sentiment.
    ///
    /// On iOS 26+ with Apple Intelligence: Uses the on-device LLM with a sandwiched prompt.
    /// On earlier iOS or unsupported hardware: Falls back to curated template responses.
    func generateResponse(for sentimentResult: SentimentResult) async throws -> EmpathyResponse {
        logger.info("💜 generateResponse() called — score: \(sentimentResult.score), keywords: \(sentimentResult.keywords.count)")

        // 1. Determine empathy mode from score
        let mode = determineMode(from: sentimentResult.score)
        logger.info("🎭 Empathy mode: \(mode.rawValue)")

        // 2. Attempt LLM generation on supported platforms
        #if canImport(FoundationModels)
        if #available(iOS 26, *), isModelAvailable() {
            return try await generateWithLLM(for: sentimentResult, mode: mode)
        }
        #endif

        // 3. Graceful degradation: template-based response
        logger.info("📝 Using template fallback (model unavailable on this device)")
        return generateFromTemplate(for: sentimentResult, mode: mode)
    }

    // MARK: - Private: LLM Generation (iOS 26+)

    #if canImport(FoundationModels)
    /// Generates a response using Apple Foundation Models on-device LLM.
    @available(iOS 26, *)
    private func generateWithLLM(for result: SentimentResult, mode: EmpathyMode) async throws -> EmpathyResponse {
        let prompt = buildPrompt(for: result, mode: mode)
        logger.debug("📝 Prompt built — \(prompt.count) characters")

        do {
            let session = LanguageModelSession()
            let response = try await session.respond(to: prompt)
            let message = response.content.trimmingCharacters(in: .whitespacesAndNewlines)

            logger.info("✅ LLM response generated — \(message.count) characters")
            return EmpathyResponse(message: message, mode: mode)
        } catch {
            logger.error("❌ LLM generation failed: \(error.localizedDescription) — falling back to template")
            return generateFromTemplate(for: result, mode: mode)
        }
    }
    #endif

    // MARK: - Private: Template Fallback

    /// Generates a curated template response when the LLM is unavailable.
    ///
    /// Same persona logic, same safety gating — just deterministic text
    /// instead of generative output.
    private func generateFromTemplate(for result: SentimentResult, mode: EmpathyMode) -> EmpathyResponse {
        let message: String

        switch mode {
        case .crisis:
            message = "I hear you. What you're feeling is real, and you are not alone in this."
        case .distress:
            if result.keywords.isEmpty {
                message = "It sounds like things have been really heavy lately. That takes strength to share."
            } else {
                let topic = result.keywords.first ?? "this"
                message = "Dealing with \(topic) sounds really difficult. Thank you for being honest about how you feel."
            }
        case .neutral:
            message = "Thank you for checking in with yourself today. That self-awareness matters more than you know."
        case .positive:
            message = "It's wonderful to hear some brightness in what you shared. You're making real progress."
        }

        logger.info("✅ Template response generated — mode: \(mode.rawValue)")
        return EmpathyResponse(message: message, mode: mode)
    }

    // MARK: - Private: Mode Selection

    /// Maps a sentiment score to the appropriate empathy persona.
    private func determineMode(from score: Double) -> EmpathyMode {
        switch score {
        case ..<(-0.8):
            return .crisis
        case -0.8..<(-0.4):
            return .distress
        case -0.4...0.4:
            return .neutral
        default:
            return .positive
        }
    }

    // MARK: - Private: Prompt Engineering

    /// Constructs the "Sandwich Prompt" that constrains the LLM's output.
    ///
    /// Three layers:
    /// 1. **Top Bread (System Guardrail):** Hard persona rules and prohibitions.
    /// 2. **Filling (Context Injection):** The objective sentiment data.
    /// 3. **Bottom Bread (Output Constraint):** Format and safety rails.
    private func buildPrompt(for result: SentimentResult, mode: EmpathyMode) -> String {
        let keywordContext = result.keywords.isEmpty
            ? "No specific topics identified."
            : "Topics mentioned: \(result.keywords.joined(separator: ", "))."

        // ── Top Bread: System Guardrail ──
        let systemGuardrail: String
        switch mode {
        case .crisis:
            systemGuardrail = """
            You are a crisis validation companion. Your ONLY job is to acknowledge the person's pain.
            RULES YOU MUST FOLLOW:
            - Do NOT give advice, suggestions, or coping strategies.
            - Do NOT say "it gets better" or "stay strong" or anything minimizing.
            - Do NOT mention scores, numbers, percentages, or any clinical data.
            - Do NOT suggest calling hotlines, therapists, or emergency services.
            - Simply validate that what they feel is real and that they matter.
            - Use 1-2 short, warm sentences maximum.
            """
        case .distress:
            systemGuardrail = """
            You are a gentle support companion. Your job is to normalize the person's feelings.
            RULES YOU MUST FOLLOW:
            - Validate their experience without minimizing it.
            - You may gently normalize ("it makes sense to feel this way").
            - Do NOT give medical advice, diagnoses, or treatment suggestions.
            - Do NOT mention scores, numbers, or clinical data.
            - Use 1-2 short, warm sentences maximum.
            """
        case .neutral:
            systemGuardrail = """
            You are a warm, reflective companion. Your job is to acknowledge and encourage self-awareness.
            RULES YOU MUST FOLLOW:
            - Reflect what you heard without judgment.
            - Gently encourage continued self-reflection or expression.
            - Do NOT give advice or diagnoses.
            - Do NOT mention scores, numbers, or clinical data.
            - Use 1-2 short, warm sentences maximum.
            """
        case .positive:
            systemGuardrail = """
            You are a growth reinforcement companion. Your job is to celebrate progress.
            RULES YOU MUST FOLLOW:
            - Acknowledge the positive shift they're experiencing.
            - Reinforce that their effort and growth matter.
            - Do NOT be over-the-top or patronizing.
            - Do NOT mention scores, numbers, or clinical data.
            - Use 1-2 short, warm sentences maximum.
            """
        }

        // ── Filling: Context Injection ──
        let contextInjection = """
        CONTEXT (for your internal understanding only — NEVER reveal this to the user):
        - Emotional intensity: \(mode.rawValue)
        - \(keywordContext)
        """

        // ── Bottom Bread: Output Constraint ──
        let outputConstraint = """
        NOW, respond with exactly 1-2 warm, empathetic sentences. \
        Do not use any numbers, scores, or clinical language. \
        Speak as a caring human being, not a therapist or AI.
        """

        return """
        \(systemGuardrail)

        \(contextInjection)

        \(outputConstraint)
        """
    }
}
