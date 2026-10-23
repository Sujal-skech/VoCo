// WatchSessionManager.swift
// Bridges iOS app ↔ Apple Watch via WatchConnectivity.
// Sends haptic commands and biomarker summaries to the Watch.

import WatchConnectivity
import Combine
import SwiftUI

// MARK: - Haptic Command

/// Mirrors WKHapticType values but keeps iOS side decoupled from watchOS framework.
enum VoCoHapticCommand: String, Codable {
    case navigationSuccess = "navigation_success"   // .success
    case navigationFailure = "navigation_failure"   // .failure
    case moduleStart       = "module_start"         // .start
    case moduleComplete    = "module_complete"      // .stop
    case wellnessAlert     = "wellness_alert"       // .notification
    case heartbeat         = "heartbeat"            // .directionUp
    case restReminder      = "rest_reminder"        // .retry
}

// MARK: - Manager

@MainActor
final class WatchSessionManager: NSObject, ObservableObject {

    static let shared = WatchSessionManager()

    @Published var isWatchReachable: Bool = false
    @Published var lastWatchMessage: [String: Any] = [:]

    private var session: WCSession?

    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        let s = WCSession.default
        s.delegate = self
        s.activate()
        self.session = s
    }

    // MARK: - Send Haptic

    func sendHaptic(_ command: VoCoHapticCommand) {
        guard let session, session.isReachable else { return }
        let message: [String: Any] = [
            "type": "haptic",
            "command": command.rawValue
        ]
        session.sendMessage(message, replyHandler: nil) { error in
            print("[WatchSession] sendHaptic error: \(error.localizedDescription)")
        }
    }

    // MARK: - Push Biomarker Summary

    func pushBiomarkerSummary(_ snapshot: BiomarkerSnapshot) {
        guard let session else { return }
        let context: [String: Any] = [
            "type": "biomarker",
            "pitchHz": snapshot.pitchHz,
            "jitter": snapshot.jitterPercent,
            "shimmer": snapshot.shimmerPercent,
            "fatigue": snapshot.fatigueIndex,
            "wellness": snapshot.wellnessScore
        ]
        do {
            try session.updateApplicationContext(context)
        } catch {
            print("[WatchSession] context update error: \(error.localizedDescription)")
        }
    }

    // MARK: - Send Navigation Event

    func sendNavigation(to route: String) {
        guard let session, session.isReachable else { return }
        session.sendMessage(["type": "navigate", "route": route],
                             replyHandler: nil,
                             errorHandler: nil)
    }
}

// MARK: - WCSessionDelegate

extension WatchSessionManager: WCSessionDelegate {
    nonisolated func session(_ session: WCSession,
                             activationDidCompleteWith state: WCSessionActivationState,
                             error: Error?) {
        Task { @MainActor in
            self.isWatchReachable = (state == .activated) && session.isReachable
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {
        Task { @MainActor in self.isWatchReachable = false }
    }

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in self.isWatchReachable = session.isReachable }
    }

    nonisolated func session(_ session: WCSession,
                             didReceiveMessage message: [String: Any]) {
        Task { @MainActor in self.lastWatchMessage = message }
    }
}
