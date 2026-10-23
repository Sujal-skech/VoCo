// RootView.swift
// Top-level router — switches content based on AppState.currentRoute.

import SwiftUI

struct RootView: View {

    @EnvironmentObject var appState: AppState
    @EnvironmentObject var voiceEngine: VoCoVoiceEngine

    var body: some View {
        ZStack {
            // Background
            Color.black.ignoresSafeArea()

            // Route switch
            Group {
                switch appState.currentRoute {
                case .splash:
                    SplashView()
                case .authentication:
                    AuthenticationView()
                case .dashboard:
                    DashboardView()
                case .pronunciation:
                    PronunciationView()
                case .assistant:
                    AssistantView()
                case .wellness:
                    WellnessView()
                case .jobs:
                    JobsView()
                case .settings:
                    SettingsView()
                }
            }
            .transition(.opacity)
            .animation(.easeInOut(duration: 0.35), value: appState.currentRoute)

            // Floating toast
            if let msg = appState.toastMessage {
                ToastView(message: msg)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .animation(.spring(), value: appState.toastMessage)
            }
        }
        .onAppear {
            // Auto-advance from splash after brief delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                if appState.currentRoute == .splash {
                    appState.currentRoute = .authentication
                    Task { await appState.authenticate() }
                }
            }
        }
    }
}

// MARK: - Toast

struct ToastView: View {
    let message: String

    var body: some View {
        VStack {
            Text(message)
                .font(.subheadline)
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Color(white: 0.15).opacity(0.95))
                .cornerRadius(14)
                .shadow(radius: 6)
            Spacer()
        }
        .padding(.top, 56)
    }
}
