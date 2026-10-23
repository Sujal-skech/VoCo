// VoCoWatchApp.swift
// Apple Watch Companion — receives haptic commands and biomarker summaries from iOS.

import SwiftUI
import WatchConnectivity
import WatchKit

@main
struct VoCoWatchApp: App {
    @StateObject private var watchStore = WatchStore()

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environmentObject(watchStore)
        }
    }
}

// MARK: - Store

@MainActor
final class WatchStore: NSObject, ObservableObject {

    @Published var pitchHz: Float = 0
    @Published var fatigueIndex: Float = 0
    @Published var wellnessScore: Float = 0
    @Published var currentRoute: String = "Dashboard"
    @Published var lastHaptic: String = ""

    override init() {
        super.init()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    // MARK: - Haptic Dispatch

    func fire(_ command: String) {
        lastHaptic = command
        let device = WKInterfaceDevice.current()
        switch command {
        case "navigation_success": device.play(.success)
        case "navigation_failure": device.play(.failure)
        case "module_start":       device.play(.start)
        case "module_complete":    device.play(.stop)
        case "wellness_alert":     device.play(.notification)
        case "heartbeat":          device.play(.directionUp)
        case "rest_reminder":      device.play(.retry)
        default:                   device.play(.click)
        }
    }
}

// MARK: - WCSessionDelegate

extension WatchStore: WCSessionDelegate {
    nonisolated func session(_ session: WCSession,
                             activationDidCompleteWith state: WCSessionActivationState,
                             error: Error?) {}

    nonisolated func session(_ session: WCSession,
                             didReceiveMessage message: [String: Any]) {
        Task { @MainActor in
            if let type = message["type"] as? String {
                switch type {
                case "haptic":
                    if let cmd = message["command"] as? String { self.fire(cmd) }
                case "navigate":
                    self.currentRoute = message["route"] as? String ?? ""
                default:
                    break
                }
            }
        }
    }

    nonisolated func session(_ session: WCSession,
                             didReceiveApplicationContext context: [String: Any]) {
        Task { @MainActor in
            self.pitchHz      = context["pitchHz"] as? Float ?? 0
            self.fatigueIndex = context["fatigue"] as? Float ?? 0
            self.wellnessScore = context["wellness"] as? Float ?? 0
        }
    }
}
