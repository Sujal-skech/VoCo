// SettingsView.swift
// User preferences — adjustable entirely by voice.

import SwiftUI
import AVFoundation

struct SettingsView: View {

    @EnvironmentObject var appState: AppState
    @EnvironmentObject var voiceEngine: VoCoVoiceEngine

    @State private var speechRate: Float = AVSpeechUtteranceDefaultSpeechRate
    @State private var displayName: String = ""
    @State private var showResetConfirm = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {
                navHeader(title: "Settings", onBack: {
                    appState.navigate(to: .dashboard, via: voiceEngine)
                })

                Form {
                    Section("Voice") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Speech Rate")
                                .foregroundColor(.white)
                            Slider(value: $speechRate,
                                   in: AVSpeechUtteranceMinimumSpeechRate...AVSpeechUtteranceMaximumSpeechRate,
                                   step: 0.05) {
                                Text("Speech Rate")
                            } minimumValueLabel: {
                                Image(systemName: "tortoise")
                                    .foregroundColor(.gray)
                            } maximumValueLabel: {
                                Image(systemName: "hare")
                                    .foregroundColor(.gray)
                            }
                            .onChange(of: speechRate) { rate in
                                voiceEngine.setSpeechRate(rate)
                                voiceEngine.speak("Speech rate updated.")
                            }
                            .accessibilityLabel("Speech rate slider, current value \(Int(speechRate * 100)) percent")
                        }
                        .listRowBackground(Color(white: 0.1))
                    }

                    Section("Profile") {
                        HStack {
                            Text("Display Name")
                                .foregroundColor(.gray)
                            TextField("Your name", text: $displayName)
                                .foregroundColor(.white)
                                .onSubmit { saveDisplayName() }
                        }
                        .listRowBackground(Color(white: 0.1))
                    }

                    Section("Account") {
                        Button(role: .destructive) {
                            showResetConfirm = true
                            voiceEngine.speak("Are you sure you want to log out? Say 'confirm' or tap the button to proceed.")
                        } label: {
                            Label("Log Out", systemImage: "arrow.right.square")
                                .foregroundColor(.red)
                        }
                        .listRowBackground(Color(white: 0.1))
                        .accessibilityHint("Double-tap or say 'log out' to sign out")
                    }

                    Section("Watch") {
                        WatchStatusRow()
                            .listRowBackground(Color(white: 0.1))
                    }

                    Section("About") {
                        LabeledContent("Version", value: "1.0.0")
                            .foregroundColor(.white)
                        LabeledContent("Build", value: "VoCo · Team Innovus")
                            .foregroundColor(.gray)
                    }
                    .listRowBackground(Color(white: 0.1))
                }
                .scrollContentBackground(.hidden)
            }
        }
        .alert("Log Out", isPresented: $showResetConfirm) {
            Button("Log Out", role: .destructive) { appState.logout() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You will need to authenticate again to access VoCo.")
        }
        .onAppear {
            displayName = appState.currentUser?.displayName ?? ""
            speechRate = appState.currentUser?.preferredSpeechRate ?? AVSpeechUtteranceDefaultSpeechRate
            startSettingsListener()
        }
        .onDisappear { voiceEngine.stopListening() }
    }

    private func saveDisplayName() {
        guard var user = appState.currentUser else { return }
        user = VoCoUser(id: user.id, displayName: displayName,
                        preferredSpeechRate: speechRate,
                        preferredLanguage: user.preferredLanguage)
        appState.saveUser(user)
        voiceEngine.speak("Name saved as \(displayName).")
    }

    private func startSettingsListener() {
        voiceEngine.speak("Settings. Say 'speech faster', 'speech slower', 'log out', or 'back'.")
        voiceEngine.startListening { intent in
            switch intent {
            case .query(let q):
                let lower = q.lowercased()
                if lower.contains("faster") || lower.contains("speed up") {
                    speechRate = min(speechRate + 0.1, AVSpeechUtteranceMaximumSpeechRate)
                    voiceEngine.setSpeechRate(speechRate)
                    voiceEngine.speak("Speech rate increased.")
                } else if lower.contains("slower") || lower.contains("slow down") {
                    speechRate = max(speechRate - 0.1, AVSpeechUtteranceMinimumSpeechRate)
                    voiceEngine.setSpeechRate(speechRate)
                    voiceEngine.speak("Speech rate decreased.")
                } else if lower.contains("log out") || lower.contains("logout") {
                    showResetConfirm = true
                } else if lower.contains("confirm") && showResetConfirm {
                    appState.logout()
                } else if lower.contains("back") {
                    appState.navigate(to: .dashboard, via: voiceEngine)
                }
            default:
                break
            }
        }
    }
}

struct WatchStatusRow: View {
    @EnvironmentObject var watchManager: WatchSessionManager

    var body: some View {
        HStack {
            Image(systemName: "applewatch")
                .foregroundColor(watchManager.isWatchReachable ? .green : .gray)
            Text("Apple Watch")
                .foregroundColor(.white)
            Spacer()
            Text(watchManager.isWatchReachable ? "Connected" : "Not paired")
                .font(.caption)
                .foregroundColor(watchManager.isWatchReachable ? .green : .gray)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Apple Watch: \(watchManager.isWatchReachable ? "connected" : "not paired")")
    }
}
