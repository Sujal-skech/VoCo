// DashboardView.swift
// Main hub — audio-first, VoiceOver-optimised.

import SwiftUI

struct DashboardView: View {

    @EnvironmentObject var appState: AppState
    @EnvironmentObject var voiceEngine: VoCoVoiceEngine
    @EnvironmentObject var biomarker: AcousticBiomarkerAnalyzer

    private let modules: [(title: String, route: AppRoute, icon: String, color: Color)] = [
        ("Pronunciation",  .pronunciation, "mouth.fill",                    .yellow),
        ("AI Assistant",   .assistant,     "brain.head.profile",            .cyan),
        ("Wellness",       .wellness,      "waveform.path.ecg.rectangle",   .green),
        ("Job Paths",      .jobs,          "briefcase.fill",                .orange),
        ("Settings",       .settings,      "gearshape.fill",                .gray)
    ]

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 28) {
                    // Header
                    VStack(spacing: 6) {
                        Text("Hello, \(appState.currentUser?.displayName ?? "there")")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(.white)
                        Text("What would you like to do?")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                    .padding(.top, 56)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Dashboard. Hello \(appState.currentUser?.displayName ?? ""). What would you like to do?")

                    // Wellness ticker
                    if let snap = biomarker.currentSnapshot {
                        WellnessBannerView(snapshot: snap)
                    }

                    // Module grid
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                        ForEach(modules, id: \.title) { item in
                            ModuleCardView(title: item.title,
                                           icon: item.icon,
                                           color: item.color) {
                                appState.navigate(to: item.route, via: voiceEngine)
                            }
                        }
                    }
                    .padding(.horizontal, 20)

                    // Voice status indicator
                    VoiceStatusBar()
                        .padding(.bottom, 32)
                }
            }
        }
        .onAppear {
            biomarker.startAnalysis()
            startCommandListener()
        }
        .onDisappear {
            voiceEngine.stopListening()
        }
    }

    private func startCommandListener() {
        voiceEngine.startListening { intent in
            switch intent {
            case .navigate(let route):
                guard let appRoute = appRouteFor(vocoRoute: route) else { return }
                appState.navigate(to: appRoute, via: voiceEngine)
            case .help:
                voiceEngine.speak("Available commands: pronunciation, assistant, wellness, jobs, settings. You can also ask any question.")
            case .repeatLast:
                voiceEngine.speak(voiceEngine.lastSpokenText)
            case .query(let q):
                // Pass open queries to AI assistant
                appState.navigate(to: .assistant, via: voiceEngine)
                NotificationCenter.default.post(name: .vocoQueryPassed, object: q)
            default:
                voiceEngine.speak("Sorry, I did not understand that. Say 'help' for a list of commands.")
            }
        }
    }

    private func appRouteFor(vocoRoute: VoCoIntent.Route) -> AppRoute? {
        switch vocoRoute {
        case .dashboard:     return .dashboard
        case .pronunciation: return .pronunciation
        case .assistant:     return .assistant
        case .wellness:      return .wellness
        case .jobs:          return .jobs
        case .settings:      return .settings
        }
    }
}

// MARK: - Module Card

struct ModuleCardView: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 36))
                    .foregroundColor(color)
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
            .background(Color(white: 0.1))
            .cornerRadius(18)
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(color.opacity(0.35), lineWidth: 1.5)
            )
        }
        .accessibilityLabel("\(title), navigate by saying \(title)")
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Wellness Banner

struct WellnessBannerView: View {
    let snapshot: BiomarkerSnapshot

    private var color: Color {
        snapshot.wellnessScore > 70 ? .green : snapshot.wellnessScore > 40 ? .yellow : .red
    }

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "waveform.path.ecg")
                .font(.title2)
                .foregroundColor(color)
            VStack(alignment: .leading, spacing: 2) {
                Text("Vocal Wellness")
                    .font(.caption)
                    .foregroundColor(.gray)
                Text(String(format: "%.0f / 100", snapshot.wellnessScore))
                    .font(.headline)
                    .foregroundColor(.white)
            }
            Spacer()
            Text(String(format: "Fatigue: %.0f%%", snapshot.fatigueIndex * 100))
                .font(.caption)
                .foregroundColor(.gray)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Color(white: 0.08))
        .cornerRadius(14)
        .padding(.horizontal, 20)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Vocal wellness score \(Int(snapshot.wellnessScore)) out of 100. Fatigue level \(Int(snapshot.fatigueIndex * 100)) percent.")
    }
}

// MARK: - Voice Status Bar

struct VoiceStatusBar: View {
    @EnvironmentObject var voiceEngine: VoCoVoiceEngine

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(voiceEngine.isListening ? Color.green : Color.red)
                .frame(width: 10, height: 10)
            Text(voiceEngine.isListening ? "Listening" : "Microphone off")
                .font(.caption)
                .foregroundColor(.gray)
            Spacer()
            if voiceEngine.isSpeaking {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.caption)
                    .foregroundColor(.yellow)
            }
        }
        .padding(.horizontal, 24)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(voiceEngine.isListening ? "Microphone active" : "Microphone inactive")
    }
}

// MARK: - Notification

extension Notification.Name {
    static let vocoQueryPassed = Notification.Name("voco.queryPassed")
}
