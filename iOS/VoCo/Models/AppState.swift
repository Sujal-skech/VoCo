// AppState.swift
// Single source of truth for navigation and session state.

import SwiftUI
import LocalAuthentication
import Combine

// MARK: - App Route

enum AppRoute: Hashable {
    case splash
    case authentication
    case dashboard
    case pronunciation
    case assistant
    case wellness
    case jobs
    case settings
}

// MARK: - Vocational Module

struct VocationalModule: Identifiable, Hashable {
    let id: UUID
    let title: String
    let description: String
    let audioGuideScript: String
    let estimatedMinutes: Int
    let icon: String
}

extension VocationalModule {
    static let catalog: [VocationalModule] = [
        VocationalModule(
            id: UUID(),
            title: "Customer Service Excellence",
            description: "Master remote customer service calls, empathy scripts, and de-escalation.",
            audioGuideScript: """
                Welcome to Customer Service Excellence.
                In this module you will practice active listening, empathy responses, and professional call etiquette.
                We will begin with a simulation of an inbound support call.
                Say 'ready' when you would like to begin, or 'menu' to return.
            """,
            estimatedMinutes: 25,
            icon: "headphones"
        ),
        VocationalModule(
            id: UUID(),
            title: "Digital Virtual Assistant",
            description: "Learn tools and workflows for remote executive assistance and scheduling.",
            audioGuideScript: """
                Welcome to Digital Virtual Assistant training.
                You will learn calendar management, email drafting, and task prioritisation — all by voice.
                Say 'start lesson one' to begin, or 'menu' to return.
            """,
            estimatedMinutes: 30,
            icon: "calendar"
        ),
        VocationalModule(
            id: UUID(),
            title: "Audio Content Moderation",
            description: "Evaluate audio clips for policy compliance in a remote reviewer role.",
            audioGuideScript: """
                Welcome to Audio Content Moderation.
                This module trains your ear to identify policy violations in audio samples.
                Say 'play sample' to hear a clip, then say 'approve', 'flag', or 'escalate'.
                Say 'menu' to return.
            """,
            estimatedMinutes: 20,
            icon: "waveform.and.magnifyingglass"
        ),
        VocationalModule(
            id: UUID(),
            title: "Professional Pronunciation",
            description: "Sharpen clarity, pace, and pronunciation for professional communication.",
            audioGuideScript: """
                Welcome to Professional Pronunciation.
                Clear speech builds confidence with clients and employers.
                We will practise tongue twisters, word stress, and intonation patterns.
                Say 'exercise one' to begin, or 'menu' to return.
            """,
            estimatedMinutes: 15,
            icon: "mouth"
        )
    ]
}

// MARK: - User Session

struct VoCoUser: Identifiable, Codable {
    let id: String
    var displayName: String
    var preferredSpeechRate: Float
    var preferredLanguage: String
    var totalModulesCompleted: Int
    var wellnessSessionCount: Int

    init(id: String = UUID().uuidString,
         displayName: String,
         preferredSpeechRate: Float = AVSpeechUtteranceDefaultSpeechRate,
         preferredLanguage: String = "en-US") {
        self.id = id
        self.displayName = displayName
        self.preferredSpeechRate = preferredSpeechRate
        self.preferredLanguage = preferredLanguage
        self.totalModulesCompleted = 0
        self.wellnessSessionCount = 0
    }
}

import AVFoundation

// MARK: - App State (ViewModel)

@MainActor
final class AppState: ObservableObject {

    @Published var currentRoute: AppRoute = .splash
    @Published var isAuthenticated: Bool = false
    @Published var currentUser: VoCoUser?
    @Published var isLoading: Bool = false
    @Published var toastMessage: String?

    private let userDefaultsKey = "voco_user"

    init() {
        loadUser()
    }

    // MARK: - Authentication

    func authenticate() async {
        let context = LAContext()
        var error: NSError?

        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            do {
                let success = try await context.evaluatePolicy(
                    .deviceOwnerAuthenticationWithBiometrics,
                    localizedReason: "Authenticate to access VoCo"
                )
                if success {
                    isAuthenticated = true
                    currentRoute = .dashboard
                }
            } catch {
                // Fallback to voice PIN (handled by VoiceEngine)
                currentRoute = .authentication
            }
        } else {
            // No biometrics — go to voice PIN flow
            currentRoute = .authentication
        }
    }

    func voiceAuthenticate(pin: String) -> Bool {
        // In production: compare against securely stored voice PIN hash
        let storedPin = UserDefaults.standard.string(forKey: "voco_voice_pin") ?? "1234"
        let success = pin.filter(\.isNumber) == storedPin
        if success {
            isAuthenticated = true
            currentRoute = .dashboard
        }
        return success
    }

    func logout() {
        isAuthenticated = false
        currentRoute = .authentication
    }

    // MARK: - Navigation

    func navigate(to route: AppRoute, via engine: VoCoVoiceEngine) {
        currentRoute = route
        let announcement = routeAnnouncement(route)
        engine.speak(announcement)
        WatchSessionManager.shared.sendNavigation(to: "\(route)")
        WatchSessionManager.shared.sendHaptic(.navigationSuccess)
    }

    private func routeAnnouncement(_ route: AppRoute) -> String {
        switch route {
        case .splash:         return "Loading VoCo."
        case .authentication: return "Authentication required. Please use Face ID or speak your voice PIN."
        case .dashboard:      return "Dashboard. Say 'pronunciation', 'assistant', 'wellness', 'jobs', or 'settings'."
        case .pronunciation:  return "Pronunciation training. Choose a module by speaking its name."
        case .assistant:      return "VoCo AI Assistant is active. Ask me anything."
        case .wellness:       return "Wellness dashboard. Your vocal health metrics are displayed."
        case .jobs:           return "Job opportunities. Current listings for remote accessible roles."
        case .settings:       return "Settings. Adjust speech rate, language, and account preferences."
        }
    }

    // MARK: - User Persistence

    func saveUser(_ user: VoCoUser) {
        currentUser = user
        if let data = try? JSONEncoder().encode(user) {
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        }
    }

    private func loadUser() {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let user = try? JSONDecoder().decode(VoCoUser.self, from: data) else { return }
        currentUser = user
    }

    // MARK: - Toast

    func showToast(_ message: String) {
        toastMessage = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            self?.toastMessage = nil
        }
    }
}
