// WatchRootView.swift
// Apple Watch face — shows real-time wellness and haptic status.

import SwiftUI
import WatchKit

struct WatchRootView: View {

    @EnvironmentObject var store: WatchStore

    private var wellnessColor: Color {
        store.wellnessScore > 70 ? .green : store.wellnessScore > 40 ? .yellow : .red
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {

                // App identity
                HStack(spacing: 6) {
                    Image(systemName: "waveform.circle.fill")
                        .foregroundStyle(LinearGradient(colors: [.yellow, .orange],
                                                        startPoint: .topLeading,
                                                        endPoint: .bottomTrailing))
                    Text("VoCo")
                        .font(.headline)
                        .foregroundColor(.white)
                }

                Divider().background(Color.gray.opacity(0.3))

                // Wellness ring
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.15), lineWidth: 8)
                    Circle()
                        .trim(from: 0, to: CGFloat(store.wellnessScore / 100))
                        .stroke(wellnessColor,
                                style: StrokeStyle(lineWidth: 8, lineCap: .round))
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

                // Stats grid
                HStack(spacing: 8) {
                    watchStat(label: "Pitch", value: String(format: "%.0f Hz", store.pitchHz))
                    watchStat(label: "Fatigue", value: String(format: "%.0f%%", store.fatigueIndex * 100))
                }

                // Route indicator
                if !store.currentRoute.isEmpty {
                    Text(store.currentRoute)
                        .font(.caption2)
                        .foregroundColor(.gray)
                        .padding(.top, 2)
                }

                // Test haptic button (for demo)
                Button {
                    WKInterfaceDevice.current().play(.notification)
                } label: {
                    Label("Test Haptic", systemImage: "bolt.fill")
                        .font(.caption2)
                        .foregroundColor(.yellow)
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
            .padding(12)
        }
        .background(Color.black)
        .accessibilityElement(children: .contain)
    }

    private func watchStat(label: String, value: String) -> some View {
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
