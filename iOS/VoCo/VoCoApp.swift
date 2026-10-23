// VoCoApp.swift
// App entry point — injects all environment objects.

import SwiftUI

@main
struct VoCoApp: App {

    @StateObject private var appState      = AppState()
    @StateObject private var voiceEngine   = VoCoVoiceEngine()
    @StateObject private var biomarker     = AcousticBiomarkerAnalyzer()
    @StateObject private var watchManager  = WatchSessionManager.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .environmentObject(voiceEngine)
                .environmentObject(biomarker)
                .environmentObject(watchManager)
                // Request permissions on first launch
                .task {
                    await voiceEngine.requestPermissions()
                }
        }
    }
}
