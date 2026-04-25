//
//  ContentView.swift
//  VoiceVault
//
//  Created by Dao Huynh on 4/25/26.
//
//  NOTE: This is a placeholder root view. Developer D owns this file.
//  Replace with the real UI implementation.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        NavigationStack {
            Text("VoiceVault")
                .font(.largeTitle)
                .fontWeight(.bold)
        }
    }
}

#Preview {
    ContentView()
        .environment(AppEnvironment.preview())
}
