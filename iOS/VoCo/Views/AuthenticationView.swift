// AuthenticationView.swift
// Voice PIN or Face ID authentication — zero-touch.

import SwiftUI

struct AuthenticationView: View {

    @EnvironmentObject var appState: AppState
    @EnvironmentObject var voiceEngine: VoCoVoiceEngine

    @State private var statusText = "Say your voice PIN, or use Face ID"
    @State private var attempts: Int = 0
    @State private var isAnimating = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 40) {

                // Logo mark
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(LinearGradient(colors: [.yellow, .orange],
                                                   startPoint: .top,
                                                   endPoint: .bottom))
                    .scaleEffect(isAnimating ? 1.05 : 1.0)
                    .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true),
                               value: isAnimating)

                Text("VoCo")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                // Live transcription readout
                Text(voiceEngine.transcribedText.isEmpty ? "Listening…" : voiceEngine.transcribedText)
                    .font(.title3)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .accessibilityLabel("Transcribed: \(voiceEngine.transcribedText)")

                // Status
                Text(statusText)
                    .font(.footnote)
                    .foregroundColor(.yellow)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)

                // Face ID button (accessible backup)
                Button {
                    Task { await appState.authenticate() }
                } label: {
                    Label("Use Face ID", systemImage: "faceid")
                        .font(.headline)
                        .foregroundColor(.black)
                        .padding(.horizontal, 36)
                        .padding(.vertical, 14)
                        .background(Color.yellow)
                        .cornerRadius(14)
                }
                .accessibilityHint("Double-tap to authenticate with Face ID")
            }
        }
        .onAppear {
            isAnimating = true
            voiceEngine.speak("Authentication required. Say your 4-digit voice PIN, or double-tap to use Face ID.")
            startVoicePINListener()
        }
        .onDisappear {
            voiceEngine.stopListening()
        }
    }

    private func startVoicePINListener() {
        voiceEngine.startListening { intent in
            switch intent {
            case .query(let text):
                // Extract digits from spoken text
                let digits = text.components(separatedBy: .whitespaces)
                    .compactMap { Int($0) }
                    .map { String($0) }
                    .joined()
                if !digits.isEmpty {
                    let success = appState.voiceAuthenticate(pin: digits)
                    if success {
                        statusText = "Welcome back!"
                        voiceEngine.speak("Welcome back. You are now logged in.")
                        WatchSessionManager.shared.sendHaptic(.navigationSuccess)
                    } else {
                        attempts += 1
                        statusText = "Incorrect PIN. Try again."
                        voiceEngine.speak("Incorrect PIN. Please try again.")
                        WatchSessionManager.shared.sendHaptic(.navigationFailure)
                        if attempts >= 3 {
                            voiceEngine.speak("Too many attempts. Please use Face ID.")
                            Task { await appState.authenticate() }
                        }
                    }
                }
            default:
                break
            }
        }
    }
}
