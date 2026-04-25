//
//  DebugContentView.swift
//  VoiceVault
//
//  Owner: Integration Test Flight — Brutalist Hardware Verification UI
//  Hackathon Day 1 — Exercises ALL backend branches end-to-end
//
//  This view is purely functional. Zero styling. Zero design.
//  Its sole purpose is to trigger every code path in the production
//  backend and surface the raw output for physical device verification.
//
//  Pipeline Coverage:
//    Patient Mode:  Audio → Intelligence → Empathy → Storage
//    Provider Mode: Storage → IntakeService → Cheat Sheet
//

import SwiftUI

// MARK: - DebugContentView

struct DebugContentView: View {

    @Environment(AppEnvironment.self) private var env

    // MARK: - Local UI State

    @State private var selectedMode = 0 // 0 = Patient, 1 = Provider
    @State private var isRecording = false

    // Patient pipeline outputs
    @State private var liveTranscript = ""
    @State private var finalTranscript = ""
    @State private var analysisResult: SentimentResult?
    @State private var empathyResponse: EmpathyResponse?
    @State private var patientError = ""

    // Provider pipeline outputs
    @State private var cheatSheet: IntakeCheatSheet?
    @State private var providerError = ""
    @State private var isLoadingIntake = false

    // Shared
    @State private var entries: [JournalEntry] = []
    @State private var statusLog: [String] = []

    var body: some View {
        NavigationStack {
            VStack {
                Picker("Mode", selection: $selectedMode) {
                    Text("Patient Mode").tag(0)
                    Text("Provider Mode").tag(1)
                }
                .pickerStyle(.segmented)

                if selectedMode == 0 {
                    patientModeView
                } else {
                    providerModeView
                }

                Section("STATUS LOG") {
                    List(statusLog.reversed(), id: \.self) { log in
                        Text(log)
                            .font(.caption)
                    }
                    .frame(maxHeight: 150)
                }
            }
            .navigationTitle("VoiceVault Debug")
        }
        .task { @MainActor in
            await loadEntries()
        }
    }

    // MARK: - Patient Mode

    private var patientModeView: some View {
        List {
            // ── Recording Controls ──
            Section("1. AUDIO PIPELINE") {
                Button(isRecording ? "STOP RECORDING" : "START RECORDING") {
                    toggleRecording()
                }

                if isRecording {
                    if let liveAudio = env.audioService as? AudioTranscriptionService {
                        Text("LIVE: \(liveAudio.currentTranscript)")
                    } else {
                        Text("LIVE: (Mock — recording in progress)")
                    }
                }

                if !finalTranscript.isEmpty {
                    Text("FINAL TRANSCRIPT: \(finalTranscript)")
                }
            }

            // ── Intelligence Output ──
            Section("2. INTELLIGENCE PIPELINE") {
                if let result = analysisResult {
                    Text("Score: \(result.score, specifier: "%.4f")")
                    Text("Label: \(result.label)")
                    Text("Keywords: \(result.keywords.joined(separator: ", "))")
                    Text("Vector dims: \(result.vector.count)")
                } else {
                    Text("Waiting for analysis...")
                }
            }

            // ── Empathy Output ──
            Section("3. EMPATHY PIPELINE") {
                if let empathy = empathyResponse {
                    Text("Mode: \(empathy.mode.rawValue)")
                    Text("Response: \(empathy.message)")
                } else {
                    Text("Waiting for empathy response...")
                }
            }

            // ── Storage ──
            Section("4. STORAGE (\(entries.count) entries)") {
                Button("REFRESH ENTRIES") {
                    Task { @MainActor in
                        await loadEntries()
                    }
                }
                ForEach(entries) { entry in
                    VStack(alignment: .leading) {
                        Text(entry.transcriptPreview)
                        Text("Score: \(entry.sentimentScore, specifier: "%.2f") | Keywords: \(entry.extractedKeywords.joined(separator: ", "))")
                            .font(.caption)
                    }
                }
            }

            // ── Errors ──
            if !patientError.isEmpty {
                Section("ERRORS") {
                    Text(patientError)
                }
            }
        }
    }

    // MARK: - Provider Mode

    private var providerModeView: some View {
        List {
            Section("GENERATE INTAKE") {
                Button(isLoadingIntake ? "LOADING..." : "GENERATE INTAKE PROFILE (7 days)") {
                    generateIntake()
                }
                .disabled(isLoadingIntake)
            }

            if let sheet = cheatSheet {
                Section("PERIOD") {
                    Text("From: \(sheet.periodStart.formatted())")
                    Text("To: \(sheet.periodEnd.formatted())")
                    Text("Total Entries: \(sheet.totalEntries)")
                }

                Section("TOP KEYWORDS (Facts)") {
                    ForEach(sheet.topKeywords, id: \.keyword) { item in
                        Text("\(item.keyword) — \(item.count) occurrences")
                    }
                }

                Section("CRISIS QUOTES (Evidence)") {
                    ForEach(Array(sheet.criticalQuotes.enumerated()), id: \.offset) { _, quote in
                        VStack(alignment: .leading) {
                            Text("\"\(quote.text)\"")
                            Text("Score: \(quote.sentimentScore, specifier: "%.2f") | \(quote.timestamp.formatted())")
                                .font(.caption)
                            Text("Keywords: \(quote.keywords.joined(separator: ", "))")
                                .font(.caption)
                        }
                    }
                }

                Section("SENTIMENT TRAJECTORY") {
                    Text("Trend: \(sheet.trend.rawValue)")
                    Text("Average: \(sheet.averageSentiment, specifier: "%.3f")")
                    Text("Min: \(sheet.minimumSentiment, specifier: "%.3f")")
                    Text("Max: \(sheet.maximumSentiment, specifier: "%.3f")")
                }
            }

            if !providerError.isEmpty {
                Section("ERRORS") {
                    Text(providerError)
                }
            }
        }
    }

    // MARK: - Patient Pipeline Actions

    private func toggleRecording() {
        if isRecording {
            // Stop recording — transcribe() will return the final transcript
            Task { @MainActor in
                await env.audioService.stopRecording()
            }
        } else {
            // Start the full pipeline: Audio → Intelligence → Empathy → Storage
            isRecording = true
            finalTranscript = ""
            analysisResult = nil
            empathyResponse = nil
            patientError = ""

            log("▶️ Recording started")

            Task { @MainActor in
                do {
                    // ── Stage 1: Audio ──
                    log("🎙️ Stage 1: Transcribing...")
                    let transcript = try await env.audioService.transcribe(intent: .init())
                    finalTranscript = transcript
                    isRecording = false
                    log("🎙️ Stage 1 DONE: \"\(String(transcript.prefix(60)))...\"")

                    guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        log("⚠️ Empty transcript — pipeline halted")
                        patientError = "Empty transcript. Speak into the microphone."
                        return
                    }

                    // ── Stage 2: Intelligence ──
                    log("🧠 Stage 2: Analyzing...")
                    let result = try await env.intelligenceService.analyze(transcript: transcript)
                    analysisResult = result
                    log("🧠 Stage 2 DONE: score=\(String(format: "%.4f", result.score)), keywords=\(result.keywords.count), vector=\(result.vector.count)D")

                    // ── Stage 3: Empathy ──
                    log("💜 Stage 3: Generating empathy response...")
                    let empathy = try await env.empathyService.generateResponse(for: result)
                    empathyResponse = empathy
                    log("💜 Stage 3 DONE: mode=\(empathy.mode.rawValue), msg=\"\(String(empathy.message.prefix(60)))...\"")

                    // ── Stage 4: Storage ──
                    log("💾 Stage 4: Saving to database...")
                    let entry = JournalEntry(
                        rawTranscript: transcript,
                        sentimentScore: result.score,
                        extractedKeywords: result.keywords,
                        vectorEmbedding: result.vector,
                        isFullyProcessed: true
                    )
                    try await env.storageService.save(entry: entry)
                    log("💾 Stage 4 DONE: Entry saved (\(entry.id.uuidString.prefix(8)))")

                    // ── Refresh ──
                    await loadEntries()
                    log("✅ Full patient pipeline COMPLETE")

                } catch {
                    isRecording = false
                    patientError = error.localizedDescription
                    log("❌ Pipeline FAILED: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Provider Pipeline Actions

    private func generateIntake() {
        isLoadingIntake = true
        cheatSheet = nil
        providerError = ""
        log("📋 Generating intake profile (7 days)...")

        Task { @MainActor in
            do {
                let sheet = try await env.intakeService.generateCheatSheet(forLastDays: 7)
                cheatSheet = sheet
                log("📋 Intake DONE: \(sheet.totalEntries) entries, trend=\(sheet.trend.rawValue), keywords=\(sheet.topKeywords.count)")
            } catch {
                providerError = error.localizedDescription
                log("❌ Intake FAILED: \(error.localizedDescription)")
            }
            isLoadingIntake = false
        }
    }

    // MARK: - Shared Helpers

    @MainActor
    private func loadEntries() async {
        do {
            entries = try await env.storageService.fetchAll(sortedBy: .newestFirst)
            log("📂 Loaded \(entries.count) entries from storage")
        } catch {
            log("❌ Failed to load entries: \(error.localizedDescription)")
        }
    }

    private func log(_ message: String) {
        let timestamp = Date.now.formatted(date: .omitted, time: .standard)
        statusLog.append("[\(timestamp)] \(message)")
    }
}

// MARK: - Preview

#Preview {
    DebugContentView()
        .environment(AppEnvironment.preview())
}
