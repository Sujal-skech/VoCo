// PronunciationView.swift
// Audio-first vocational module selector and player.

import SwiftUI
import AVFoundation

struct PronunciationView: View {

    @EnvironmentObject var appState: AppState
    @EnvironmentObject var voiceEngine: VoCoVoiceEngine
    @EnvironmentObject var biomarker: AcousticBiomarkerAnalyzer

    @State private var selectedModule: VocationalModule?
    @State private var lessonStep: Int = 0
    @State private var isInLesson: Bool = false

    private let modules = VocationalModule.catalog

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {
                // Header
                navHeader(title: "Training Modules", onBack: {
                    appState.navigate(to: .dashboard, via: voiceEngine)
                })

                if isInLesson, let mod = selectedModule {
                    LessonPlayerView(module: mod,
                                     step: $lessonStep,
                                     onComplete: {
                        isInLesson = false
                        selectedModule = nil
                        voiceEngine.speak("Module complete. Great work! Returning to module list.")
                        WatchSessionManager.shared.sendHaptic(.moduleComplete)
                    })
                } else {
                    moduleList
                }
            }
        }
        .onAppear { startModuleListener() }
        .onDisappear { voiceEngine.stopListening() }
    }

    // MARK: - Module List

    private var moduleList: some View {
        ScrollView {
            VStack(spacing: 14) {
                ForEach(modules) { mod in
                    ModuleRowView(module: mod) {
                        launchModule(mod)
                    }
                }
            }
            .padding(20)
        }
    }

    // MARK: - Launch

    private func launchModule(_ mod: VocationalModule) {
        selectedModule = mod
        isInLesson = true
        lessonStep = 0
        voiceEngine.speak("Starting \(mod.title). \(mod.audioGuideScript)")
        WatchSessionManager.shared.sendHaptic(.moduleStart)
    }

    // MARK: - Voice Commands

    private func startModuleListener() {
        voiceEngine.speak("Pronunciation training. Available modules: Customer Service, Digital Virtual Assistant, Audio Content Moderation, Professional Pronunciation. Say a module name to begin, or say 'back' to return to dashboard.")

        voiceEngine.startListening { intent in
            switch intent {
            case .navigate(let route) where route == .dashboard:
                appState.navigate(to: .dashboard, via: voiceEngine)
            case .query(let q):
                let lower = q.lowercased()
                if lower.contains("back") || lower.contains("menu") {
                    appState.navigate(to: .dashboard, via: voiceEngine)
                } else if lower.contains("customer") { launchModule(modules[0]) }
                else if lower.contains("digital") || lower.contains("virtual") { launchModule(modules[1]) }
                else if lower.contains("audio") || lower.contains("moderation") { launchModule(modules[2]) }
                else if lower.contains("pronunciation") || lower.contains("professional") { launchModule(modules[3]) }
                else if lower.contains("ready") || lower.contains("start") {
                    if let mod = selectedModule { launchModule(mod) }
                } else {
                    voiceEngine.speak("I didn't catch that. Say a module name, or 'back' to return.")
                }
            default:
                break
            }
        }
    }
}

// MARK: - Module Row

struct ModuleRowView: View {
    let module: VocationalModule
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: module.icon)
                    .font(.title2)
                    .foregroundColor(.yellow)
                    .frame(width: 44)
                VStack(alignment: .leading, spacing: 4) {
                    Text(module.title)
                        .font(.headline)
                        .foregroundColor(.white)
                    Text(module.description)
                        .font(.caption)
                        .foregroundColor(.gray)
                        .lineLimit(2)
                    Text("~\(module.estimatedMinutes) min")
                        .font(.caption2)
                        .foregroundColor(.yellow.opacity(0.7))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundColor(.gray)
            }
            .padding(16)
            .background(Color(white: 0.1))
            .cornerRadius(14)
        }
        .accessibilityLabel("\(module.title), \(module.description), approximately \(module.estimatedMinutes) minutes")
        .accessibilityHint("Double-tap or say the module name to start")
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Lesson Player

struct LessonPlayerView: View {
    let module: VocationalModule
    @Binding var step: Int
    let onComplete: () -> Void

    @EnvironmentObject var voiceEngine: VoCoVoiceEngine
    @EnvironmentObject var biomarker: AcousticBiomarkerAnalyzer

    // Simplified linear lesson steps
    private var steps: [String] {
        module.audioGuideScript
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        VStack(spacing: 24) {
            Text(module.title)
                .font(.title2).bold()
                .foregroundColor(.white)
                .padding(.top, 24)

            // Progress bar
            ProgressView(value: Double(step + 1), total: Double(max(steps.count, 1)))
                .tint(.yellow)
                .padding(.horizontal, 24)
                .accessibilityLabel("Step \(step + 1) of \(steps.count)")

            // Current step text
            if step < steps.count {
                Text(steps[step])
                    .font(.body)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
                    .accessibilityLabel(steps[step])
            }

            // Biomarker mini badge
            if let snap = biomarker.currentSnapshot, snap.pitchHz > 0 {
                HStack(spacing: 8) {
                    Label(String(format: "%.0f Hz", snap.pitchHz), systemImage: "waveform")
                    Label(String(format: "Fatigue %.0f%%", snap.fatigueIndex * 100),
                          systemImage: "bolt.heart")
                }
                .font(.caption)
                .foregroundColor(.gray)
            }

            Spacer()

            // Controls
            HStack(spacing: 20) {
                if step > 0 {
                    controlButton(title: "Back", icon: "arrow.left") {
                        step -= 1
                        playStep()
                    }
                }
                controlButton(title: step < steps.count - 1 ? "Next" : "Finish",
                              icon: step < steps.count - 1 ? "arrow.right" : "checkmark") {
                    if step < steps.count - 1 {
                        step += 1
                        playStep()
                    } else {
                        onComplete()
                    }
                }
            }
            .padding(.bottom, 36)
        }
        .onAppear { playStep() }
    }

    private func playStep() {
        guard step < steps.count else { return }
        voiceEngine.speak(steps[step])
    }

    private func controlButton(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundColor(.black)
                .padding(.horizontal, 28)
                .padding(.vertical, 14)
                .background(Color.yellow)
                .cornerRadius(12)
        }
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Helpers

private func navHeader(title: String, onBack: @escaping () -> Void) -> some View {
    HStack {
        Button(action: onBack) {
            Image(systemName: "chevron.left")
                .font(.title3)
                .foregroundColor(.yellow)
                .padding(14)
        }
        .accessibilityLabel("Back")

        Text(title)
            .font(.headline)
            .foregroundColor(.white)
        Spacer()
    }
    .padding(.horizontal, 8)
    .padding(.top, 52)
}
