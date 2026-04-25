//
//  MockAudioTranscriptionService.swift
//  VoiceVault
//
//  Created by VoiceVault Team on 4/25/26.
//  Hackathon Day 1 — Mock: Audio Pipeline
//

import Foundation

// MARK: - MockAudioTranscriptionService

/// A mock implementation of `AudioTranscriptionServiceProtocol` for previews and testing.
///
/// Returns realistic, medical-grade transcript samples instantly without
/// requiring microphone access or the Speech framework.
///
/// **Owner:** Shared (scaffolding), maintained by Developer A.
final class MockAudioTranscriptionService: AudioTranscriptionServiceProtocol, @unchecked Sendable {

    // MARK: - Configuration

    /// The simulated delay before returning a transcript (in seconds).
    /// Set to 0 for instant results in unit tests.
    var simulatedDelay: TimeInterval = 1.5

    /// If set, the mock will throw this error instead of returning a transcript.
    /// Useful for testing error handling paths.
    var simulatedError: TranscriptionError?

    /// Index tracking which sample transcript to return next (cycles through all samples).
    private var currentIndex = 0

    // MARK: - Sample Transcripts

    /// Realistic medical voice journal transcripts for testing.
    /// These cover a range of clinical scenarios and emotional states.
    private let sampleTranscripts: [String] = [
        """
        Today was a better day overall. I managed to sleep about seven hours last night \
        which is a significant improvement from the four or five hours I was getting last week. \
        The new sleep hygiene routine my therapist suggested seems to be helping. I avoided \
        screens after nine PM and did the breathing exercises. I still woke up once around \
        three AM with some anxiety, but I was able to fall back asleep within twenty minutes. \
        My energy level during the day was noticeably higher. I even went for a thirty minute \
        walk in the afternoon which I haven't done in weeks.
        """,

        """
        I'm feeling quite frustrated today. The headaches have been coming back more frequently \
        this week, almost daily now. I took ibuprofen twice today which I know isn't ideal for \
        long term use. The pain is mostly behind my left eye and radiates to my temple. It's \
        worse in the morning and tends to ease up by evening. I also noticed my appetite has \
        decreased significantly. I skipped lunch entirely today because the nausea was too much. \
        My mood has been affected by all of this. I feel irritable and short tempered with my \
        family and I know that's not fair to them.
        """,

        """
        This is my weekly check in. Overall I would rate my mental health this week as a six \
        out of ten. The sertraline adjustment from fifty to seventy five milligrams seems to be \
        stabilizing. I noticed fewer intrusive thoughts this week compared to last. I had one \
        panic episode on Wednesday during a work meeting but I was able to use the grounding \
        technique. Five things I can see, four I can touch, three I can hear. It helped bring \
        me back faster than before. I'm still having trouble with social situations. I cancelled \
        plans with friends twice this week because the anticipatory anxiety was overwhelming. \
        I want to work on this with my therapist next session.
        """,

        """
        Good news from my appointment today. My blood pressure readings have been consistently \
        lower this month. The combination of the lisinopril and the dietary changes seems to be \
        working. I've been tracking my sodium intake and keeping it under two thousand milligrams \
        most days. I've also been doing the morning meditation for fifteen minutes every day \
        without missing a single session this month. I feel proud of that consistency. My resting \
        heart rate has also dropped from eighty two to seventy five beats per minute according to \
        my watch data. I feel more optimistic about my cardiovascular health than I have in years.
        """,

        """
        Today was really hard. I had a major depressive episode that lasted most of the afternoon. \
        I couldn't get out of bed until almost two PM. The thoughts were very dark and I felt \
        completely hopeless about the future. I did reach out to my crisis support person like \
        my safety plan says and that helped some. We talked for about forty five minutes. I also \
        took my prescribed lorazepam point five milligrams which took the edge off the worst of \
        the anxiety. By evening I was feeling more stable but exhausted. I know these episodes \
        are part of the process but they still scare me. I'm documenting this so my psychiatrist \
        can see the pattern at our next appointment on Friday.
        """
    ]

    // MARK: - Protocol Conformance

    /// Returns a realistic sample transcript after a simulated delay.
    ///
    /// Cycles through 5 diverse medical journal transcripts covering:
    /// sleep improvement, chronic pain, medication adjustment, cardiovascular health,
    /// and crisis episodes.
    ///
    /// - Parameter intent: The recording configuration (ignored in mock).
    /// - Returns: A realistic medical voice journal transcript.
    /// - Throws: `TranscriptionError` if `simulatedError` is set.
    func transcribe(intent: AudioRecordingIntent) async throws -> String {
        if let error = simulatedError {
            throw error
        }

        // Simulate recording duration
        if simulatedDelay > 0 {
            try await Task.sleep(for: .seconds(simulatedDelay))
        }

        let transcript = sampleTranscripts[currentIndex % sampleTranscripts.count]
        currentIndex += 1
        return transcript
    }

    /// Always returns `true` in mock — permissions are assumed granted.
    ///
    /// - Returns: `true`
    @discardableResult
    func requestPermissions() async -> Bool {
        return true
    }

    /// No-op in mock implementation.
    func stopRecording() async {
        // No-op: no real audio engine to stop.
    }
}
