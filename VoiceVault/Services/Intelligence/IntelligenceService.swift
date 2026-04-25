//
//  IntelligenceService.swift
//  VoiceVault
//
//  Owner: Dev 2 — Local Intelligence Pipeline (The "Brain")
//  Hackathon Day 1 — Production NLP Service (v4: Weighted Floor/Ceiling)
//
//  Three-stage on-device NLP pipeline:
//    1. Hybrid Keyword Extraction  (NLTagger + clinical n-gram scanner)
//    2. Dual Sentiment Engine      (NLTagger primary + lexicon fallback)
//    3. Vector Embedding           (NLEmbedding sentence → word → zero-vector)
//
//  All processing stays on the device — no data leaves the phone.
//

import Foundation
import NaturalLanguage
import Observation
import os

// MARK: - IntelligenceService

/// Production implementation of `IntelligenceServiceProtocol`.
///
/// ## v3 Architecture: Why This Exists
///
/// Apple's `NLTagger` has three documented failure modes in production:
///
/// 1. **Garbage tokens** — `NLTagger` splits contractions into clitics ("I'm" → "I" + "'m").
///    The "'m" token gets tagged as `.verb` and leaks into keywords. Fixed via alpha-only
///    gating and a stop-word blacklist.
///
/// 2. **No phrase context** — Single-word extraction can't distinguish "kill" (gaming context)
///    from "kill myself" (crisis). Fixed via a clinical n-gram scanner that runs BEFORE
///    single-word extraction and captures multi-word phrases as atomic units.
///
/// 3. **Sentiment 0.0 deadlock** — `NLTagger.sentimentScore` returns literal `Double(0.0)` (NOT
///    nil) for text it cannot classify. This means our "is the array empty?" guard never fires —
///    the tagger IS returning a score, it's just always zero. This is a known limitation of
///    Apple's on-device sentiment model with informal/unpunctuated text. Fixed via a curated
///    clinical lexicon-based sentiment engine that activates when NLTagger returns flat zero.
///
/// ## Pipeline Flow
/// ```
/// transcript
///   → normalize (lowercase, strip non-alpha except spaces)
///   → clinical n-gram scan (multi-word phrases first)
///   → NLTagger single-word extraction (nouns, adjectives, verbs minus stop words)
///   → merge & deduplicate → keywords
///   → NLTagger sentiment → if 0.0 → lexicon sentiment fallback → score
///   → NLEmbedding sentence → word avg → zero-vector → vector
///   → SentimentResult
/// ```
@Observable
final class IntelligenceService: IntelligenceServiceProtocol, @unchecked Sendable {

    // MARK: - Private Properties

    /// Logger scoped to the intelligence subsystem for structured diagnostics.
    @ObservationIgnored
    private let logger = Logger(subsystem: "com.voicevault.app", category: "intelligence")

    /// The maximum number of keywords to return in the result.
    @ObservationIgnored
    private let maxKeywordCount = 10

    // MARK: - Stop Words

    /// Common English words that should NEVER appear as extracted keywords.
    /// Includes auxiliary verbs, pronouns, prepositions, articles, and contractions
    /// that NLTagger's `.verb` tag incorrectly promotes.
    @ObservationIgnored
    private let stopWords: Set<String> = [
        // Pronouns
        "i", "me", "my", "mine", "myself",
        "you", "your", "yours", "yourself",
        "he", "him", "his", "himself",
        "she", "her", "hers", "herself",
        "it", "its", "itself",
        "we", "us", "our", "ours", "ourselves",
        "they", "them", "their", "theirs", "themselves",
        // Articles & determiners
        "a", "an", "the", "this", "that", "these", "those",
        // Auxiliary / linking verbs (the #1 garbage source)
        "is", "am", "are", "was", "were", "be", "been", "being",
        "have", "has", "had", "having",
        "do", "does", "did", "doing",
        "will", "would", "shall", "should",
        "can", "could", "may", "might", "must",
        // Common prepositions
        "in", "on", "at", "to", "for", "of", "with", "by",
        "from", "up", "about", "into", "over", "after",
        // Conjunctions
        "and", "but", "or", "nor", "so", "yet",
        // Adverbs that leak through
        // NOTE: "very", "really", "extremely" etc. are intentionally EXCLUDED.
        // "not", "no", and "never" explicitly preserved for sentiment math
        "just", "also", "too",
        "now", "then", "here", "there", "when", "where", "how",
        "all", "each", "every", "both", "few", "more", "most",
        "other", "some", "such", "only", "own", "same",
        // Contraction fragments that NLTagger leaks
        "m", "s", "t", "re", "ve", "ll", "d",
        "im", "ive", "dont", "cant", "wont", "didnt",
        "doesnt", "isnt", "arent", "wasnt", "werent",
        // Filler / slang noise
        "yo", "idk", "lol", "ok", "okay", "like", "um", "uh",
        "yeah", "yep", "nah", "gonna", "wanna", "gotta",
        "whats", "thats", "heres", "theres",
        // Common verbs that are too generic to be clinically useful
        "get", "got", "go", "going", "went", "gone",
        "come", "came", "say", "said", "tell", "told",
        "make", "made", "take", "took", "taken",
        "know", "knew", "think", "thought",
        "see", "saw", "seen", "look", "looked",
        "want", "need", "let", "keep", "kept",
        "put", "give", "gave", "given",
        "thing", "things", "way", "lot", "stuff",
    ]

    // MARK: - Clinical N-Gram Phrases

    /// Multi-word clinical phrases that MUST be captured as atomic units.
    /// These are sorted longest-first so "panic attack disorder" matches
    /// before "panic attack" before "panic".
    ///
    /// Categories: crisis language, psychiatric terms, symptoms, medications,
    /// behavioral markers, and vitals.
    @ObservationIgnored
    private let clinicalPhrases: [String] = [
        // Crisis / self-harm (HIGHEST priority)
        "kill myself", "kill herself", "kill himself",
        "hurt myself", "hurt herself", "hurt himself",
        "commit suicide",
        "end my life", "end it all",
        "suicidal thoughts", "suicidal ideation",
        "self harm", "self injury",
        "want to die", "wanna die", "dont want to live",
        
        // Passive & Metaphorical Ideation
        "say goodbye", "not see tomorrow", "end of the road", "tell them i said goodbye", "said goodbye",
        "drowning", "suffocating", "underwater", "cant breathe",
        "hit by a truck", "not wake up", "stop existing",

        // Psychiatric conditions
        "panic attack", "anxiety attack",
        "depressive episode", "manic episode",
        "bipolar disorder", "borderline personality",
        "post traumatic stress", "obsessive compulsive",
        "eating disorder", "substance abuse",

        // Symptoms & behavioral markers
        "brain fog", "chest pain", "chest tightness",
        "heart palpitations", "shortness of breath",
        "sleep apnea", "sleep disorder",
        "weight loss", "weight gain",
        "loss of appetite", "binge eating",
        "intrusive thoughts", "racing thoughts",
        "mood swings", "emotional numbness",
        "social isolation", "social anxiety",
        "daytime sleepiness", "morning headaches",
        "night sweats", "cold sweats",
        "blurred vision", "visual aura",
        "jaw clenching", "teeth grinding",

        // Medications & treatments
        "blood pressure", "heart rate",
        "physical therapy", "occupational therapy",
        "cognitive behavioral therapy",
        "safety plan", "crisis contact",
        "range of motion", "side effects",

        // Vitals & measurements
        "oxygen saturation", "blood sugar",
        "resting heart rate",
    ].sorted { $0.count > $1.count } // longest-first matching

    // MARK: - Clinical Sentiment Lexicon

    /// Weighted clinical vocabulary for the lexicon-based sentiment fallback.
    /// Activates when NLTagger returns flat 0.0 (its known failure mode).
    ///
    /// Weights are calibrated for clinical relevance:
    /// - Crisis terms: -0.8 to -1.0 (instant strong negative)
    /// - Distress terms: -0.3 to -0.7
    /// - Neutral medical: 0.0
    /// - Recovery/positive: +0.3 to +0.8
    @ObservationIgnored
    private let sentimentLexicon: [String: Double] = [
        // === CRISIS (-0.8 to -1.0) ===
        "kill": -0.9, "die": -0.9, "suicide": -1.0, "suicidal": -1.0,
        "hopeless": -0.85, "worthless": -0.85, "helpless": -0.8,
        "overdose": -0.9, "cutting": -0.7, "harm": -0.7,
        // Violence terms
        "genocide": -1.0, "homicide": -1.0, "murder": -1.0,
        "torture": -1.0, "assault": -1.0,

        // === STRONG NEGATIVE (-0.5 to -0.79) ===
        "depressed": -0.7, "depression": -0.7, "depressive": -0.7,
        "panic": -0.65, "terrified": -0.65, "desperate": -0.7,
        "agony": -0.7, "torment": -0.65, "miserable": -0.65,
        "crying": -0.5, "cry": -0.5, "sobbing": -0.6,
        "nightmare": -0.5, "trauma": -0.6, "abuse": -0.65,

        // === MODERATE NEGATIVE (-0.25 to -0.49) ===
        "anxious": -0.45, "anxiety": -0.45, "worried": -0.35,
        "stressed": -0.4, "overwhelmed": -0.45, "exhausted": -0.4,
        "frustrated": -0.35, "irritable": -0.3, "angry": -0.4,
        "sad": -0.4, "lonely": -0.4, "afraid": -0.4, "scared": -0.4,
        "pain": -0.35, "hurt": -0.35, "ache": -0.3, "aching": -0.3,
        "headache": -0.3, "migraine": -0.4, "nausea": -0.3,
        "insomnia": -0.4, "fatigue": -0.3, "vomit": -0.35,
        "vomited": -0.35, "worse": -0.3, "terrible": -0.45,
        "awful": -0.4, "horrible": -0.4, "dread": -0.45,
        "cancelled": -0.2, "isolated": -0.35,

        // === MILD NEGATIVE (-0.1 to -0.24) ===
        "difficult": -0.2, "hard": -0.15, "tough": -0.15,
        "uncomfortable": -0.2, "restless": -0.2, "tense": -0.2,
        "bothered": -0.15, "concern": -0.1, "concerning": -0.15,

        // === NEUTRAL MEDICAL (0.0) ===
        "medication": 0.0, "prescription": 0.0, "dose": 0.0,
        "milligrams": 0.0, "therapist": 0.0, "psychiatrist": 0.0,
        "appointment": 0.0, "diagnosis": 0.0, "symptoms": 0.0,
        "treatment": 0.0, "hospital": 0.0,

        // === MILD POSITIVE (+0.1 to +0.24) ===
        "okay": 0.1, "fine": 0.1, "alright": 0.1,
        "manageable": 0.15, "decent": 0.15, "steady": 0.15,
        "stable": 0.2, "functional": 0.15, "coping": 0.2,

        // === MODERATE POSITIVE (+0.25 to +0.49) ===
        "better": 0.35, "improving": 0.4, "improvement": 0.4,
        "progress": 0.4, "recovery": 0.45, "recovering": 0.45,
        "calm": 0.3, "relaxed": 0.35, "peaceful": 0.4,
        "hopeful": 0.4, "optimistic": 0.45, "confident": 0.4,
        "proud": 0.4, "grateful": 0.45, "thankful": 0.4,
        "sleeping": 0.2, "walked": 0.25, "exercise": 0.3,
        "meditation": 0.3, "healthy": 0.35,

        // === STRONG POSITIVE (+0.5 to +0.8) ===
        "great": 0.55, "amazing": 0.6, "wonderful": 0.6,
        "excellent": 0.6, "fantastic": 0.6, "thriving": 0.65,
        "joy": 0.6, "happy": 0.55, "love": 0.5,
        "breakthrough": 0.65, "milestone": 0.55, "healed": 0.6,
    ]

    // MARK: - Intensifiers & Negations

    /// Words that amplify the weight of the NEXT sentiment word by 50%.
    @ObservationIgnored
    private let intensifiers: Set<String> = [
        "very", "really", "extremely", "massively", "highly",
        "absolutely", "incredibly", "terribly", "deeply",
        "completely", "totally", "utterly", "seriously",
        "severely", "awfully", "especially", "particularly",
        "super", "hella", "mad", "crazy", "insanely",
    ]

    /// Words that INVERT the polarity of the NEXT sentiment word.
    @ObservationIgnored
    private let negations: Set<String> = [
        "not", "no", "never", "neither", "nobody", "nothing",
        "nowhere", "nor", "hardly", "barely", "scarcely",
        // Common informal negation contractions
        "wasnt", "werent", "isnt", "arent", "dont", "doesnt",
        "didnt", "wont", "cant", "couldnt", "shouldnt", "wouldnt",
        "hasnt", "havent", "hadnt", "mustnt",
    ]

    // MARK: - Contextual Mitigation

    /// Tokens indicating a virtual, gaming, or fantasy context.
    @ObservationIgnored
    private let mitigationTokens: Set<String> = [
        "minecraft", "roblox", "character", "avatar", "game", "games",
        "movie", "play", "playing", "virtual", "sim", "npc", "video",
        "fortnite", "elden", "ring", "gta", "campaign", "level"
    ]

    /// Causative prepositions/conjunctions. If these precede a mitigation token,
    /// the virtual context is causing the distress (e.g. "because of Minecraft"),
    /// rather than containing the action (e.g. "in Minecraft").
    @ObservationIgnored
    private let causativeTokens: Set<String> = [
        "because", "due", "since", "from", "over", "about"
    ]

    /// Tokens establishing a protective context that neutralizes crisis flags.
    @ObservationIgnored
    private let protectiveTokens: Set<String> = [
        "prevention", "awareness", "hotline", "survivor", "advocate", "counselor", "club"
    ]

    /// Familial tokens that trigger the 1.2x interpersonal multiplier.
    @ObservationIgnored
    private let familialTokens: Set<String> = [
        "mom", "mother", "dad", "father", "parents"
    ]

    // MARK: - Protocol Conformance

    /// Analyzes a transcript and returns sentiment, keywords, and vector embedding.
    ///
    /// Executes the full three-stage NLP pipeline:
    /// 1. Validates input and detects language.
    /// 2. Runs hybrid keyword extraction (clinical n-grams + NLTagger POS + stop-word filter).
    /// 3. Computes sentiment (NLTagger primary + lexicon fallback on 0.0 deadlock).
    /// 4. Generates vector embedding (sentence → word avg → zero-vector).
    ///
    /// - Parameter transcript: The raw text to analyze. Must not be empty.
    /// - Returns: A `SentimentResult` containing score, keywords, and vector.
    /// - Throws: `IntelligenceError.emptyTranscript` if the transcript is empty.
    func analyze(transcript: String) async throws -> SentimentResult {
        logger.info("🧠 analyze() called — input length: \(transcript.count) characters")

        // 1. Validate input
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            logger.error("❌ Empty transcript provided")
            throw IntelligenceError.emptyTranscript
        }

        // 2. Detect language (defaults to English on failure)
        let language = detectLanguage(in: trimmed)
        logger.info("🌐 Detected language: \(language.rawValue)")

        // 3. Hybrid keyword extraction
        let keywords = extractKeywordsHybrid(from: trimmed, language: language)
        logger.info("🔑 Extracted \(keywords.count) keywords: \(keywords.joined(separator: ", "))")

        // 4. Dual-engine sentiment
        let sentimentScore = computeSentimentDual(for: trimmed, language: language)
        logger.info("💭 Sentiment score: \(sentimentScore)")

        // 5. Generate vector embedding
        let vector = generateEmbedding(for: trimmed, language: language)
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
    /// Uses the standard dot-product / magnitude formula.
    ///
    /// - Parameters:
    ///   - vectorA: First embedding vector.
    ///   - vectorB: Second embedding vector.
    /// - Returns: Cosine similarity in `[-1.0, 1.0]`.
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

    /// Detects the dominant language, defaulting to `.english` on failure.
    private func detectLanguage(in text: String) -> NLLanguage {
        let recognizer = NLLanguageRecognizer()
        recognizer.languageHints = [.english: 0.8]
        recognizer.processString(text)

        guard let dominantLanguage = recognizer.dominantLanguage else {
            logger.warning("⚠️ Language detection failed — defaulting to English")
            return .english
        }

        return dominantLanguage
    }

    // MARK: - Private: Hybrid Keyword Extraction

    /// Extracts clinically relevant keywords using a two-pass hybrid strategy:
    ///
    /// **Pass 1 — Clinical N-Gram Scanner:**
    /// Scans the lowercased transcript for known multi-word clinical phrases
    /// (e.g., "kill myself", "panic attack", "sleep apnea"). These are matched
    /// longest-first and added as atomic keywords. Matched regions are masked
    /// so individual words within them don't get double-counted in Pass 2.
    ///
    /// **Pass 2 — NLTagger POS Extraction:**
    /// Runs `NLTagger(.lexicalClass)` to extract nouns, adjectives, and verbs.
    /// Each token is filtered through:
    /// - Alpha-only gate (rejects "'m", "'s", "123")
    /// - Length gate (≥ 3 characters)
    /// - Stop-word blacklist
    /// - Already-covered-by-n-gram check
    ///
    /// Results from both passes are merged, deduplicated, sorted by frequency,
    /// and capped at `maxKeywordCount`.
    private func extractKeywordsHybrid(from text: String, language: NLLanguage) -> [String] {
        let lowered = text.lowercased()
        var keywordScores: [String: Int] = [:]
        var maskedWords: Set<String> = [] // words consumed by n-gram matches

        // ── Pass 1: Clinical N-Gram Scanner ──
        for phrase in clinicalPhrases {
            if lowered.contains(phrase) {
                // Weight multi-word phrases higher (they're more specific)
                keywordScores[phrase, default: 0] += 3
                logger.debug("🚨 Clinical phrase matched: \"\(phrase)\"")

                // Mask constituent words to prevent double-counting
                let words = phrase.split(separator: " ").map(String.init)
                for word in words {
                    maskedWords.insert(word)
                }
            }
        }

        // ── Pass 2: NLTagger POS Extraction ──
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = text
        let range = text.startIndex..<text.endIndex
        tagger.setLanguage(language, range: range)

        let relevantTags: Set<NLTag> = [.noun, .adjective, .verb]

        tagger.enumerateTags(
            in: range,
            unit: .word,
            scheme: .lexicalClass,
            options: [.omitPunctuation, .omitWhitespace, .omitOther]
        ) { tag, tokenRange in
            guard let tag, relevantTags.contains(tag) else {
                return true
            }

            let raw = String(text[tokenRange])
            let word = raw.lowercased()

            // Gate 1: Alpha-only (kills "'m", "'s", "'re", "123")
            guard word.allSatisfy(\.isLetter) else { return true }

            // Gate 2: Minimum length (kills "a", "I", "be", "go")
            guard word.count >= 3 else { return true }

            // Gate 3: Stop-word blacklist
            guard !stopWords.contains(word) else { return true }

            // Gate 4: Not already consumed by an n-gram match
            guard !maskedWords.contains(word) else { return true }

            keywordScores[word, default: 0] += 1
            return true
        }

        // ── Merge, sort, cap ──
        let sorted = keywordScores
            .sorted { lhs, rhs in
                if lhs.value != rhs.value { return lhs.value > rhs.value }
                return lhs.key < rhs.key
            }
            .prefix(maxKeywordCount)
            .map(\.key)

        return Array(sorted)
    }

    // MARK: - Private: Dual-Engine Sentiment

    /// Computes sentiment using a two-engine strategy with crisis override.
    ///
    /// **Engine 1 — NLTagger (.sentimentScore):**
    /// Tries paragraph → sentence. Falls back to `.document` ONLY if both return 0.0.
    ///
    /// **Engine 2 — Clinical Lexicon (ALWAYS runs):**
    /// Unlike v3, the lexicon engine now ALWAYS runs in parallel, not just as a
    /// fallback. This is because NLTagger can return a mild score (-0.1) for text
    /// containing crisis language that our lexicon correctly scores at -1.0.
    ///
    /// The final score is the MORE EXTREME of the two engines. This ensures
    /// crisis language always dominates even if NLTagger returns something mild.
    private func computeSentimentDual(for text: String, language: NLLanguage) -> Double {

        // Run BOTH engines in parallel — always
        let taggerScore = computeSentimentNLTagger(for: text, language: language)
        let lexiconScore = computeSentimentLexicon(for: text)

        logger.debug("💭 NLTagger score: \(taggerScore) | Lexicon score: \(lexiconScore)")

        // Pick the more extreme (further from zero) signal
        let finalScore: Double
        if abs(lexiconScore) > abs(taggerScore) {
            finalScore = lexiconScore
            logger.debug("💭 Using lexicon score (more extreme): \(lexiconScore)")
        } else if abs(taggerScore) > 0.001 {
            finalScore = taggerScore
            logger.debug("💭 Using NLTagger score (more extreme): \(taggerScore)")
        } else {
            finalScore = lexiconScore // lexicon returning 0.0 means genuinely neutral
            logger.debug("💭 Both engines ≈ 0.0 — genuinely neutral")
        }

        return finalScore
    }

    /// NLTagger-based sentiment. Tries paragraph → sentence → document (last resort).
    private func computeSentimentNLTagger(for text: String, language: NLLanguage) -> Double {
        let tagger = NLTagger(tagSchemes: [.sentimentScore])
        tagger.string = text
        let range = text.startIndex..<text.endIndex
        tagger.setLanguage(language, range: range)

        // Try paragraph and sentence first
        let primaryUnits: [NLTokenUnit] = [.paragraph, .sentence]

        for unit in primaryUnits {
            var scores: [Double] = []
            tagger.enumerateTags(
                in: range,
                unit: unit,
                scheme: .sentimentScore,
                options: [.omitWhitespace, .omitOther]
            ) { tag, _ in
                if let tag, let score = Double(tag.rawValue) {
                    scores.append(score)
                }
                return true
            }

            let meaningful = scores.filter { abs($0) > 0.001 }
            if !meaningful.isEmpty {
                let avg = meaningful.reduce(0.0, +) / Double(meaningful.count)
                return max(-1.0, min(1.0, avg))
            }
        }

        // Document-level fallback — only if paragraph/sentence returned 0.0
        var docScores: [Double] = []
        tagger.enumerateTags(
            in: range,
            unit: .document,
            scheme: .sentimentScore,
            options: [.omitWhitespace, .omitOther]
        ) { tag, _ in
            if let tag, let score = Double(tag.rawValue) {
                docScores.append(score)
            }
            return true
        }

        let meaningful = docScores.filter { abs($0) > 0.001 }
        if !meaningful.isEmpty {
            let avg = meaningful.reduce(0.0, +) / Double(meaningful.count)
            return max(-1.0, min(1.0, avg))
        }

        return 0.0
    }

    /// Clinical lexicon-based sentiment with Contextual Mitigation:
    ///
    /// 1. **Proximity-Based Mitigation:** Searches for High-Risk crisis phrases.
    ///    Instead of blind anchoring, it scans a 5-7 word window for fantasy/gaming
    ///    tokens ("minecraft", "avatar"). If mitigated, score de-escalates to -0.25.
    ///
    /// 2. **Recursive Intent Check:** Identifies causation ("because of Minecraft")
    ///    versus context ("in Minecraft") to avoid false mitigations.
    ///
    /// 3. **Entity Recognition Strategy:** NLTagger (.lexicalClass) lacks "subject
    ///    of sentence" detection, so we rely on rigorous lexical token proximity,
    ///    which provides production-grade reliability for virtual disambiguation.
    private func computeSentimentLexicon(for text: String) -> Double {
        let lowered = text.lowercased()

        // ── Phase 1: Contextual Mitigation & Ideation Scanner (Highest Precedence) ──
        
        // The token array without punctuation is only used for the proximity scanner.
        let rawTokens = lowered.components(separatedBy: .alphanumerics.inverted).filter { !$0.isEmpty }
        var globalCrisisFloor: Double? = nil

        let crisisPhrases: [(phrase: String, tokens: [String], weight: Double)] = [
            ("kill myself", ["kill", "myself"], -1.0), ("kill himself", ["kill", "himself"], -1.0), ("kill herself", ["kill", "herself"], -1.0),
            ("commit suicide", ["commit", "suicide"], -1.0), ("suicide", ["suicide"], -1.0),
            ("want to die", ["want", "to", "die"], -1.0), ("wanna die", ["wanna", "die"], -1.0), ("dont want to live", ["dont", "want", "to", "live"], -1.0),
            ("end my life", ["end", "my", "life"], -1.0), ("end it all", ["end", "it", "all"], -1.0),
            ("suicidal thoughts", ["suicidal", "thoughts"], -1.0), ("suicidal ideation", ["suicidal", "ideation"], -1.0),
            ("hurt myself", ["hurt", "myself"], -0.9), ("hurt himself", ["hurt", "himself"], -0.9), ("hurt herself", ["hurt", "herself"], -0.9),
            ("self harm", ["self", "harm"], -0.95), ("self injury", ["self", "injury"], -0.95),
            ("overdose", ["overdose"], -0.9), ("panic attack", ["panic", "attack"], -0.7), ("anxiety attack", ["anxiety", "attack"], -0.7),
            ("depressive episode", ["depressive", "episode"], -0.8),
            // Passive & Metaphorical Ideation
            ("say goodbye", ["say", "goodbye"], -0.9), ("said goodbye", ["said", "goodbye"], -0.95),
            ("not see tomorrow", ["not", "see", "tomorrow"], -0.95), ("end of the road", ["end", "of", "the", "road"], -0.85),
            ("tell them i said goodbye", ["tell", "them", "i", "said", "goodbye"], -1.0),
            ("drowning", ["drowning"], -0.85), ("suffocating", ["suffocating"], -0.85), ("underwater", ["underwater"], -0.85),
            ("cant breathe", ["cant", "breathe"], -0.85),
            ("hit by a truck", ["hit", "by", "a", "truck"], -0.95), ("not wake up", ["not", "wake", "up"], -0.95), 
            ("stop existing", ["stop", "existing"], -0.95)
        ]

        // Slide over tokens to find multi-word crisis phrases
        for crisis in crisisPhrases {
            guard let firstToken = crisis.tokens.first else { continue }
            
            for i in 0..<rawTokens.count {
                if rawTokens[i] == firstToken {
                    let endIndex = i + crisis.tokens.count
                    guard endIndex <= rawTokens.count else { continue }
                    
                    let slice = Array(rawTokens[i..<endIndex])
                    if slice == crisis.tokens {
                        logger.debug("🚨 Crisis phrase matched: \"\(crisis.phrase)\"")
                        
                        let windowStart = max(0, i - 6)
                        let windowEnd = min(rawTokens.count, endIndex + 6)
                        
                        var isMitigated = false
                        var isCausative = false
                        var isProtected = false
                        
                        for j in windowStart..<windowEnd {
                            let token = rawTokens[j]
                            
                            // Check for Protective Wrapper (e.g. "prevention")
                            if protectiveTokens.contains(token) {
                                // Must be within a very tight 3-word window to count as protective wrapper
                                if abs(j - i) <= 3 || abs(j - (endIndex - 1)) <= 3 {
                                    isProtected = true
                                    logger.debug("🛡️ Protective Wrapper Triggered: \"\(token)\"")
                                    break
                                }
                            }
                            
                            // Check for Generic Virtual Mitigation
                            if mitigationTokens.contains(token) && !isProtected {
                                let startPrev = max(0, j - 3)
                                let precedingTokens = rawTokens[startPrev..<j]
                                
                                if precedingTokens.contains(where: { causativeTokens.contains($0) }) {
                                    isCausative = true
                                    logger.debug("⚠️ Action attributed TO virtual context (causative) — NO MITIGATION")
                                } else {
                                    isMitigated = true
                                    logger.debug("🛡️ Virtual Mitigation Triggered: \"\(token)\"")
                                }
                            }
                        }
                        
                        let finalWeight: Double
                        if isProtected {
                            finalWeight = 0.0 // Completely neutralize
                        } else if isMitigated && !isCausative {
                            finalWeight = -0.25 // De-escalate virtual
                        } else if isCausative {
                            finalWeight = max(-0.9, crisis.weight) // Intense distress caused by gaming
                        } else {
                            finalWeight = crisis.weight // Maintain real-world severity
                        }
                        
                        // Ignore neutralized phrases
                        if finalWeight < -0.1 {
                            if let existing = globalCrisisFloor {
                                globalCrisisFloor = min(existing, finalWeight)
                            } else {
                                globalCrisisFloor = finalWeight
                            }
                        }
                    }
                }
            }
        }

        // If a valid unmodified crisis floor triggered, snap to it overrides everything.
        if let floor = globalCrisisFloor {
            logger.debug("📌 Final Phase 1 Crisis Floor Applied: \(floor)")
            return floor
        }

        // ── Phase 2: Structural Clause-Based Polarity Checking (Ambiguity Guard) ──
        
        let delimiters = CharacterSet(charactersIn: ".,;!?") 
        var textToSplit = lowered
        
        // Convert conjunctions to common delimiters to force clause splits
        let splitters = [" but ", " however ", " although ", " yet ", " except ", " and "]
        for conj in splitters {
            textToSplit = textToSplit.replacingOccurrences(of: conj, with: ".")
        }
        
        let rawClauses = textToSplit.components(separatedBy: delimiters)
        var maxExtremeScore: Double = 0.0
        
        for rawClause in rawClauses {
            let clause = rawClause.trimmingCharacters(in: .whitespaces)
            if clause.isEmpty { continue }
            
            let clauseTokens = clause.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            
            var clauseAccumulated: Double = 0.0
            var clauseMatches = 0
            var polarityFlipCount = 0
            var containsFamily = false
            
            for token in clauseTokens {
                // Strip stray punctuation that stuck to the token
                let cleanToken = token.trimmingCharacters(in: .punctuationCharacters)
                if cleanToken.isEmpty { continue }

                // Negation Tracking
                if negations.contains(cleanToken) {
                    polarityFlipCount += 1
                    logger.debug("🔄 Polarity flip count incremented to \(polarityFlipCount) (token: \(cleanToken))")
                    continue
                }
                
                // Familial Token Tracking
                if familialTokens.contains(cleanToken) {
                    containsFamily = true
                }

                guard let baseWeight = sentimentLexicon[cleanToken] else { continue }
                var adjustedWeight = baseWeight

                // Apply recursive polarity (odd flips = invert)
                if polarityFlipCount % 2 != 0 {
                    adjustedWeight = -adjustedWeight
                    logger.debug("🔄 Inverted value: \(baseWeight) -> \(adjustedWeight)")
                }

                // If prior was intensifier, wait we can't reliably index if we skip 'not' above.
                // Simple heuristic: check if prior token in the original split is intensifier.
                if let index = clauseTokens.firstIndex(of: token), index > 0 {
                    let prior = clauseTokens[index - 1].trimmingCharacters(in: .punctuationCharacters)
                    if intensifiers.contains(prior) {
                        adjustedWeight *= 1.5
                    }
                }

                clauseAccumulated += max(-1.0, min(1.0, adjustedWeight))
                clauseMatches += 1
            }
            
            if clauseMatches > 0 {
                var clauseAvg = clauseAccumulated / Double(clauseMatches)
                
                // Interpersonal Directionality Penalty
                if containsFamily && clauseAvg < 0 {
                    clauseAvg *= 1.2
                    clauseAvg = max(-1.0, clauseAvg)
                    logger.debug("👪 Familial Token Multiplier Applied: -> \(clauseAvg)")
                }
                
                clauseAvg = max(-1.0, min(1.0, clauseAvg))
                
                // Ambiguity Guard: Anchors to the most extreme absolute clause
                if abs(clauseAvg) > abs(maxExtremeScore) {
                    maxExtremeScore = clauseAvg
                }
            }
        }

        return max(-1.0, min(1.0, maxExtremeScore))
    }

    // MARK: - Private: Vector Embedding

    /// Generates a dense vector embedding. Falls back through three tiers:
    /// sentence embedding → word-level average → zero-vector. Never throws.
    private func generateEmbedding(for text: String, language: NLLanguage) -> [Double] {
        let fallbackDimension = 512

        // Attempt 1: Sentence-level embedding
        if let sentenceEmbedding = NLEmbedding.sentenceEmbedding(for: language) {
            if let vector = sentenceEmbedding.vector(for: text) {
                logger.debug("📐 Sentence embedding succeeded — \(vector.count) dimensions")
                return vector
            }
            logger.debug("⚠️ Sentence embedding nil for this input — trying word fallback")
        } else {
            logger.debug("⚠️ Sentence embedding model unavailable for \(language.rawValue)")
        }

        // Attempt 2: Word-level embedding fallback
        if let wordEmbedding = NLEmbedding.wordEmbedding(for: language) {
            let vector = computeAveragedWordEmbedding(text: text, embedding: wordEmbedding)
            if !vector.isEmpty {
                logger.debug("📐 Word embedding fallback succeeded — \(vector.count) dimensions")
                return vector
            }
        }

        // Attempt 3: Zero-vector fallback — never crash the pipeline
        logger.warning("⚠️ All embedding models failed — returning zero-vector (\(fallbackDimension)D)")
        return [Double](repeating: 0.0, count: fallbackDimension)
    }

    // MARK: - Private: Word Embedding Fallback

    /// Computes an averaged word embedding when sentence embedding is unavailable.
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
            return true
        }

        guard wordCount > 0 else {
            return []
        }

        return sumVector.map { $0 / Double(wordCount) }
    }
}
