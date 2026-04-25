import SwiftUI

struct ContentView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var isRecording = false
    @State private var entries: [JournalEntry] = []
    
    var body: some View {
        VStack {
            Button(action: {
                toggleRecording()
            }) {
                Text(isRecording ? "STOP RECORDING" : "START RECORDING")
            }
            
            Text("Current Transcript:")
            if let liveAudio = env.audioService as? AudioTranscriptionService {
                Text(liveAudio.currentTranscript)
            } else {
                Text(isRecording ? "Recording... (Mock enabled)" : "Waiting for audio...")
            }
            
            Button(action: {
                Task { @MainActor in
                    await loadEntries()
                }
            }) {
                Text("REFRESH ENTRIES")
            }
            
            List(entries) { entry in
                VStack {
                    Text(entry.transcriptPreview)
                    Text("Score: \(entry.sentimentScore)")
                    Text("Keywords: \(entry.extractedKeywords.joined(separator: ", "))")
                }
            }
        }
        .task { @MainActor in
            await loadEntries()
        }
    }
    
    private func toggleRecording() {
        if isRecording {
            Task { @MainActor in
                await env.audioService.stopRecording()
            }
        } else {
            isRecording = true
            Task { @MainActor in
                do {
                    // 1. Transcribe audio
                    let finalTranscript = try await env.audioService.transcribe(intent: .init())
                    
                    // 2. Intelligence: Analyze transcript
                    let result = try await env.intelligenceService.analyze(transcript: finalTranscript)
                    
                    // 3. Storage: Save to DB
                    let entry = JournalEntry(
                        rawTranscript: finalTranscript,
                        sentimentScore: result.score,
                        extractedKeywords: result.keywords,
                        vectorEmbedding: result.vector, // It is nonisolated anyway, or generated safely
                        isFullyProcessed: true
                    )
                    try await env.storageService.save(entry: entry)
                    
                    // 4. Update the List
                    await loadEntries()
                } catch {
                    print("Error: \(error)")
                }
                isRecording = false
            }
        }
    }
    
    @MainActor
    private func loadEntries() async {
        do {
            entries = try await env.storageService.fetchAll(sortedBy: .newestFirst)
        } catch {
            print("Error loading entries: \(error)")
        }
    }
}