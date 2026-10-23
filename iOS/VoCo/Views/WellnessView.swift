// WellnessView.swift
// Real-time vocal biomarker dashboard + cognitive wellness index.

import SwiftUI
import Charts

struct WellnessView: View {

    @EnvironmentObject var appState: AppState
    @EnvironmentObject var voiceEngine: VoCoVoiceEngine
    @EnvironmentObject var biomarker: AcousticBiomarkerAnalyzer

    @State private var trend: WellnessTrend?
    @State private var showingBreathingExercise = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {
                navHeader(title: "Vocal Wellness", onBack: {
                    appState.navigate(to: .dashboard, via: voiceEngine)
                })

                ScrollView {
                    VStack(spacing: 20) {
                        // Wellness score ring
                        WellnessRingView(score: biomarker.currentSnapshot?.wellnessScore ?? 0)

                        // Biomarker cards
                        HStack(spacing: 12) {
                            BiomarkerCard(
                                label: "Pitch",
                                value: String(format: "%.0f Hz", biomarker.currentSnapshot?.pitchHz ?? 0),
                                icon: "tuningfork",
                                color: .cyan
                            )
                            BiomarkerCard(
                                label: "Jitter",
                                value: String(format: "%.1f%%", biomarker.currentSnapshot?.jitterPercent ?? 0),
                                icon: "waveform.path",
                                color: .yellow
                            )
                            BiomarkerCard(
                                label: "Shimmer",
                                value: String(format: "%.1f%%", biomarker.currentSnapshot?.shimmerPercent ?? 0),
                                icon: "waveform",
                                color: .orange
                            )
                        }
                        .padding(.horizontal, 20)

                        // Fatigue bar
                        FatigueBarView(fatigueIndex: biomarker.currentSnapshot?.fatigueIndex ?? 0)
                            .padding(.horizontal, 20)

                        // History chart
                        if biomarker.history.count > 3 {
                            WellnessChartView(history: biomarker.history)
                                .padding(.horizontal, 20)
                        }

                        // Alert
                        if let alert = biomarker.alertMessage {
                            AlertBannerView(message: alert)
                                .padding(.horizontal, 20)
                        }

                        // Trend from server
                        if let t = trend {
                            TrendCardView(trend: t)
                                .padding(.horizontal, 20)
                        }

                        // Breathing exercise CTA
                        Button {
                            showingBreathingExercise = true
                            voiceEngine.speak("Starting breathing exercise. Breathe in for 4 counts, hold for 4, breathe out for 4. Ready? Breathe in: 1, 2, 3, 4. Hold: 1, 2, 3, 4. Breathe out: 1, 2, 3, 4. Well done.")
                        } label: {
                            Label("Breathing Exercise", systemImage: "lungs.fill")
                                .font(.headline)
                                .foregroundColor(.black)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(Color.green)
                                .cornerRadius(14)
                                .padding(.horizontal, 20)
                        }
                        .accessibilityLabel("Start breathing exercise")
                        .accessibilityHint("Guides you through a 4-4-4 box breathing session")

                        Spacer(minLength: 32)
                    }
                    .padding(.top, 8)
                }
            }
        }
        .onAppear {
            biomarker.startAnalysis()
            startWellnessListener()
            Task { await fetchTrend() }
        }
        .onDisappear {
            biomarker.stopAnalysis()
            voiceEngine.stopListening()
        }
    }

    // MARK: - Listener

    private func startWellnessListener() {
        voiceEngine.speak("Vocal wellness dashboard. Your real-time biomarkers are displayed. Say 'back' to return, or 'breathing' for a guided exercise.")
        voiceEngine.startListening { intent in
            switch intent {
            case .query(let q):
                let lower = q.lowercased()
                if lower.contains("back") || lower.contains("home") {
                    appState.navigate(to: .dashboard, via: voiceEngine)
                } else if lower.contains("breath") {
                    voiceEngine.speak("Starting box breathing: in for 4, hold for 4, out for 4. Begin.")
                } else if lower.contains("status") || lower.contains("score") {
                    let score = biomarker.currentSnapshot?.wellnessScore ?? 0
                    let fatigue = (biomarker.currentSnapshot?.fatigueIndex ?? 0) * 100
                    voiceEngine.speak("Your wellness score is \(Int(score)) out of 100. Fatigue level is \(Int(fatigue)) percent.")
                }
            default:
                break
            }
        }
    }

    private func fetchTrend() async {
        guard let uid = appState.currentUser?.id else { return }
        trend = try? await VoCoAPIService.shared.getWellnessTrend(userId: uid)
    }
}

// MARK: - Subviews

struct WellnessRingView: View {
    let score: Float

    private var color: Color {
        score > 70 ? .green : score > 40 ? .yellow : .red
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.1), lineWidth: 18)
            Circle()
                .trim(from: 0, to: CGFloat(score / 100))
                .stroke(color, style: StrokeStyle(lineWidth: 18, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.spring(), value: score)
            VStack(spacing: 2) {
                Text("\(Int(score))")
                    .font(.system(size: 42, weight: .bold))
                    .foregroundColor(.white)
                Text("Wellness")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
        .frame(width: 160, height: 160)
        .padding(.top, 16)
        .accessibilityLabel("Wellness score \(Int(score)) out of 100")
    }
}

struct BiomarkerCard: View {
    let label: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(color)
            Text(value)
                .font(.system(.headline, design: .monospaced))
                .foregroundColor(.white)
            Text(label)
                .font(.caption2)
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color(white: 0.1))
        .cornerRadius(12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }
}

struct FatigueBarView: View {
    let fatigueIndex: Float

    private var color: Color {
        fatigueIndex < 0.3 ? .green : fatigueIndex < 0.65 ? .yellow : .red
    }
    private var label: String {
        fatigueIndex < 0.3 ? "Fresh" : fatigueIndex < 0.65 ? "Moderate" : "High Fatigue"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Vocal Fatigue")
                    .font(.subheadline)
                    .foregroundColor(.white)
                Spacer()
                Text(label)
                    .font(.caption)
                    .foregroundColor(color)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.white.opacity(0.1))
                    RoundedRectangle(cornerRadius: 6)
                        .fill(color)
                        .frame(width: geo.size.width * CGFloat(fatigueIndex))
                        .animation(.spring(), value: fatigueIndex)
                }
            }
            .frame(height: 12)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Vocal fatigue: \(label), \(Int(fatigueIndex * 100)) percent")
    }
}

struct WellnessChartView: View {
    let history: [BiomarkerSnapshot]

    private var recent: [BiomarkerSnapshot] {
        Array(history.suffix(60))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Wellness Trend")
                .font(.subheadline)
                .foregroundColor(.white)
            if #available(iOS 16.0, *) {
                Chart(recent) { snap in
                    LineMark(
                        x: .value("Time", snap.timestamp),
                        y: .value("Score", snap.wellnessScore)
                    )
                    .foregroundStyle(Color.green)
                    .interpolationMethod(.catmullRom)
                }
                .chartXAxis(.hidden)
                .chartYScale(domain: 0...100)
                .frame(height: 100)
                .background(Color(white: 0.08))
                .cornerRadius(12)
            }
        }
        .accessibilityLabel("Wellness trend chart showing last \(recent.count) data points")
    }
}

struct AlertBannerView: View {
    let message: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
            Text(message)
                .font(.subheadline)
                .foregroundColor(.white)
        }
        .padding(14)
        .background(Color.orange.opacity(0.15))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.orange.opacity(0.4), lineWidth: 1)
        )
        .cornerRadius(12)
        .accessibilityLabel("Alert: \(message)")
    }
}

struct TrendCardView: View {
    let trend: WellnessTrend

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your Wellness Summary")
                .font(.subheadline).bold()
                .foregroundColor(.white)
            HStack {
                Label("\(Int(trend.averageWellness)) avg", systemImage: "chart.bar")
                    .foregroundColor(.cyan)
                Spacer()
                Text("\(trend.sessionCount) sessions")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            Text(trend.recommendation)
                .font(.caption)
                .foregroundColor(.gray)
        }
        .padding(16)
        .background(Color(white: 0.08))
        .cornerRadius(14)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Wellness summary: average score \(Int(trend.averageWellness)). \(trend.recommendation)")
    }
}
