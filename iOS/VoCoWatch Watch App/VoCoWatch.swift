// VoCoWatch.swift
// Single-file Apple Watch companion for VoCo.
// Target: watchOS 10+ — add ONLY to the "VoCoWatch Watch App" target, NOT the iOS target.
//
// Frameworks used:
//   SwiftUI         — UI (available on watchOS)
//   WatchKit        — WKInterfaceDevice.current().play() for haptics (watchOS only)
//   WatchConnectivity — WCSession for iOS ↔ Watch messaging (watchOS only)
//
// DO NOT add this file to the iOS app target — WatchKit is not available on iOS.

import SwiftUI
import WatchKit          // watchOS target only
import WatchConnectivity // watchOS target only

// ─────────────────────────────────────────────────────────
// MARK: - App Entry Point
// ─────────────────────────────────────────────────────────

@main
struct VoCoWatchApp: App {
    @StateObject private var store = WatchStore()

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environmentObject(store)
        }
    }
}

// ─────────────────────────────────────────────────────────
// MARK: - Watch Store (WCSession delegate + state)
// ─────────────────────────────────────────────────────────

@MainActor
final class WatchStore: NSObject, ObservableObject {

    @Published var pitchHz: Float     = 0
    @Published var fatigueIndex: Float = 0
    @Published var wellnessScore: Float = 0
    @Published var currentRoute: String = "Dashboard"
    @Published var lastHaptic: String  = ""

    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    // MARK: Haptic dispatch — maps string command → WKHapticType

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

// ─────────────────────────────────────────────────────────
// MARK: - WCSessionDelegate
// ─────────────────────────────────────────────────────────

extension WatchStore: WCSessionDelegate {

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith state: WCSessionActivationState,
        error: Error?
    ) {
        // No iOS-side counterparts needed on watchOS
    }

    /// Handles real-time messages sent from the iOS app.
    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any]
    ) {
        Task { @MainActor in
            guard let type = message["type"] as? String else { return }
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

    /// Handles background context updates (biomarker summaries).
    nonisolated func session(
        _ session: WCSession,
        didReceiveApplicationContext context: [String: Any]
    ) {
        Task { @MainActor in
            self.pitchHz       = context["pitchHz"]   as? Float ?? 0
            self.fatigueIndex  = context["fatigue"]   as? Float ?? 0
            self.wellnessScore = context["wellness"]  as? Float ?? 0
        }
    }
}

// ─────────────────────────────────────────────────────────
// MARK: - Root View
// ─────────────────────────────────────────────────────────

struct WatchRootView: View {

    @EnvironmentObject var store: WatchStore

    private var wellnessColor: Color {
        store.wellnessScore > 70 ? .green
            : store.wellnessScore > 40 ? .yellow
            : .red
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {

                // ── Header ──
                HStack(spacing: 5) {
                    Image(systemName: "waveform.circle.fill")
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.yellow, .orange],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Text("VoCo")
                        .font(.headline)
                        .foregroundColor(.white)
                }

                Divider().background(Color.gray.opacity(0.3))

                // ── Wellness Ring ──
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.15), lineWidth: 8)
                    Circle()
                        .trim(from: 0, to: CGFloat(store.wellnessScore / 100))
                        .stroke(
                            wellnessColor,
                            style: StrokeStyle(lineWidth: 8, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .animation(.spring(), value: store.wellnessScore)
                    VStack(spacing: 1) {
                        Text("\(Int(store.wellnessScore))")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(.white)
                        Text("Wellness")
                            .font(.system(size: 9))
                            .foregroundColor(.gray)
                    }
                }
                .frame(width: 80, height: 80)
                .accessibilityLabel("Wellness score \(Int(store.wellnessScore)) out of 100")

                // ── Stats ──
                HStack(spacing: 8) {
                    statTile(label: "Pitch",
                             value: String(format: "%.0f Hz", store.pitchHz))
                    statTile(label: "Fatigue",
                             value: String(format: "%.0f%%", store.fatigueIndex * 100))
                }

                // ── Active Route ──
                if !store.currentRoute.isEmpty {
                    Text(store.currentRoute)
                        .font(.caption2)
                        .foregroundColor(.gray)
                        .padding(.top, 2)
                        .accessibilityLabel("Current screen: \(store.currentRoute)")
                }

                // ── Test Haptic (demo / QA) ──
                Button {
                    WKInterfaceDevice.current().play(.notification)
                } label: {
                    Label("Test Haptic", systemImage: "bolt.fill")
                        .font(.caption2)
                        .foregroundColor(.yellow)
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
                .accessibilityLabel("Test haptic feedback")
            }
            .padding(12)
        }
        .background(Color.black)
    }

    // ── Stat tile helper ──
    private func statTile(label: String, value: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundColor(.white)
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color(white: 0.12))
        .cornerRadius(8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }
}
