import SwiftUI

struct ContentView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var isRecording = false
    @State private var transcript = "Waiting for audio..."
    
    var body: some View {
        VStack(spacing: 30) {
            Text(transcript)
                .font(.system(.body, design: .monospaced))
                .padding()
            
            Button(action: {
                Task {
                    if isRecording {
                        await env.audioService.stopRecording()
                        isRecording = false
                    } else {
                        isRecording = true
                        do {
                            // The intent might require different params based on your protocol
                            transcript = try await env.audioService.transcribe(intent: .init())
                        } catch {
                            transcript = "Error: \(error.localizedDescription)"
                            isRecording = false
                        }
                    }
                }
            }) {
                Text(isRecording ? "STOP RECORDING" : "TEST MICROPHONE")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding()
                    .background(isRecording ? Color.red : Color.blue)
                    .cornerRadius(10)
            }
        }
    }
}