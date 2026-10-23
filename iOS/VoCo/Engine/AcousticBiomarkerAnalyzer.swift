// AcousticBiomarkerAnalyzer.swift
// Real-time pitch (Hz), jitter, shimmer, RMS, and vocal fatigue analysis
// via AVAudioEngine tap + Accelerate/vDSP — zero third-party dependencies.

import AVFoundation
import Accelerate
import Combine
import SwiftUI

// MARK: - Data Model

struct BiomarkerSnapshot: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let pitchHz: Float
    let jitterPercent: Float
    let shimmerPercent: Float
    let rmsAmplitude: Float
    let fatigueIndex: Float        // 0.0 (fresh) … 1.0 (exhausted)
    let wellnessScore: Float       // 0.0 (poor) … 100.0 (excellent)

    init(pitchHz: Float, jitterPercent: Float, shimmerPercent: Float,
         rmsAmplitude: Float, fatigueIndex: Float) {
        self.id = UUID()
        self.timestamp = Date()
        self.pitchHz = pitchHz
        self.jitterPercent = jitterPercent
        self.shimmerPercent = shimmerPercent
        self.rmsAmplitude = rmsAmplitude
        self.fatigueIndex = fatigueIndex
        // Wellness: higher pitch variance + high shimmer + high fatigue = lower score
        let raw = 100 - (fatigueIndex * 50) - (jitterPercent * 0.5) - (shimmerPercent * 0.3)
        self.wellnessScore = min(100, max(0, raw))
    }
}

// MARK: - Analyzer

@MainActor
final class AcousticBiomarkerAnalyzer: ObservableObject {

    // MARK: Published

    @Published var currentSnapshot: BiomarkerSnapshot?
    @Published var history: [BiomarkerSnapshot] = []
    @Published var isAnalyzing: Bool = false
    @Published var alertMessage: String?

    // MARK: Constants

    private let sampleRate: Double = 44100
    private let frameSize: Int = 2048          // FFT frame — power of 2
    private let hopSize: Int = 512
    private let historyLimit: Int = 200

    // MARK: AVAudio

    private let audioEngine = AVAudioEngine()
    private let analysisQueue = DispatchQueue(label: "voco.biomarker", qos: .userInitiated)

    // MARK: vDSP

    private var fftSetup: FFTSetup?
    private lazy var log2n: vDSP_Length = vDSP_Length(log2(Float(frameSize)))

    // Jitter / shimmer rolling buffers
    private var pitchBuffer: [Float] = []
    private var amplitudeBuffer: [Float] = []
    private let rollingWindowSize: Int = 20

    // MARK: Init / Deinit

    init() {
        fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(FFT_RADIX2))
    }

    deinit {
        if let setup = fftSetup { vDSP_destroy_fftsetup(setup) }
    }

    // MARK: - Start

    func startAnalysis() {
        guard !isAnalyzing else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord,
                                    mode: .measurement,
                                    options: [.duckOthers, .allowBluetooth])
            try session.setActive(true)

            let inputNode = audioEngine.inputNode
            let format = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                       sampleRate: sampleRate,
                                       channels: 1,
                                       interleaved: false)!
            inputNode.removeTap(onBus: 0)
            inputNode.installTap(onBus: 0,
                                  bufferSize: AVAudioFrameCount(frameSize),
                                  format: format) { [weak self] buffer, _ in
                self?.analysisQueue.async { self?.processBuffer(buffer) }
            }
            audioEngine.prepare()
            try audioEngine.start()
            isAnalyzing = true
        } catch {
            alertMessage = "Biomarker analysis unavailable: \(error.localizedDescription)"
        }
    }

    func stopAnalysis() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        isAnalyzing = false
    }

    // MARK: - Buffer Processing

    private func processBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameCount = Int(buffer.frameLength)
        guard frameCount >= frameSize else { return }

        let samples = Array(UnsafeBufferPointer(start: channelData, count: frameSize))

        // 1. RMS amplitude
        var rms: Float = 0
        vDSP_rmsqv(samples, 1, &rms, vDSP_Length(frameSize))

        // 2. Pitch via autocorrelation
        let pitch = estimatePitch(samples: samples, sampleRate: Float(sampleRate))

        // 3. Rolling jitter (cycle-to-cycle pitch variation)
        pitchBuffer.append(pitch)
        amplitudeBuffer.append(rms)
        if pitchBuffer.count > rollingWindowSize {
            pitchBuffer.removeFirst()
            amplitudeBuffer.removeFirst()
        }
        let jitter = computeJitter(pitches: pitchBuffer)
        let shimmer = computeShimmer(amplitudes: amplitudeBuffer)

        // 4. Fatigue index: combo of high jitter, high shimmer, low RMS
        let rawFatigue = min(1.0, (jitter / 100.0) * 0.5 + (shimmer / 100.0) * 0.3 + (1.0 - min(1.0, rms * 20)) * 0.2)

        let snapshot = BiomarkerSnapshot(
            pitchHz: pitch,
            jitterPercent: jitter,
            shimmerPercent: shimmer,
            rmsAmplitude: rms,
            fatigueIndex: rawFatigue
        )

        Task { @MainActor in
            self.currentSnapshot = snapshot
            self.history.append(snapshot)
            if self.history.count > self.historyLimit { self.history.removeFirst() }
            self.evaluateWellnessAlert(snapshot)
        }
    }

    // MARK: - Pitch Estimation (Autocorrelation)

    private func estimatePitch(samples: [Float], sampleRate: Float) -> Float {
        let n = samples.count
        var acf = [Float](repeating: 0, count: n)

        // Normalised autocorrelation via vDSP convolution
        var windowedSamples = samples
        var window = [Float](repeating: 0, count: n)
        vDSP_hann_window(&window, vDSP_Length(n), Int32(vDSP_HANN_NORM))
        vDSP_vmul(samples, 1, window, 1, &windowedSamples, 1, vDSP_Length(n))

        vDSP_conv(windowedSamples, 1,
                  windowedSamples, 1,
                  &acf, 1,
                  vDSP_Length(n / 2),
                  vDSP_Length(n))

        // Search for first peak in human voice range: 50 Hz – 500 Hz
        let minLag = Int(sampleRate / 500)
        let maxLag = Int(sampleRate / 50)
        guard maxLag < acf.count else { return 0 }

        var peakLag = minLag
        var peakVal: Float = 0
        for lag in minLag...maxLag {
            if acf[lag] > peakVal {
                peakVal = acf[lag]
                peakLag = lag
            }
        }

        // Require minimum energy to avoid noise
        guard rmsOf(samples) > 0.005, peakLag > 0 else { return 0 }
        return sampleRate / Float(peakLag)
    }

    // MARK: - Jitter (relative pitch perturbation, %)

    private func computeJitter(pitches: [Float]) -> Float {
        guard pitches.count >= 2 else { return 0 }
        let nonZero = pitches.filter { $0 > 0 }
        guard nonZero.count >= 2 else { return 0 }

        var diffs: Float = 0
        for i in 1..<nonZero.count {
            diffs += abs(nonZero[i] - nonZero[i - 1])
        }
        var mean: Float = 0
        vDSP_meanv(nonZero, 1, &mean, vDSP_Length(nonZero.count))
        guard mean > 0 else { return 0 }

        let avgDiff = diffs / Float(nonZero.count - 1)
        return (avgDiff / mean) * 100.0
    }

    // MARK: - Shimmer (relative amplitude perturbation, %)

    private func computeShimmer(amplitudes: [Float]) -> Float {
        guard amplitudes.count >= 2 else { return 0 }
        let nonZero = amplitudes.filter { $0 > 0 }
        guard nonZero.count >= 2 else { return 0 }

        var diffs: Float = 0
        for i in 1..<nonZero.count {
            diffs += abs(nonZero[i] - nonZero[i - 1])
        }
        var mean: Float = 0
        vDSP_meanv(nonZero, 1, &mean, vDSP_Length(nonZero.count))
        guard mean > 0 else { return 0 }

        let avgDiff = diffs / Float(nonZero.count - 1)
        return (avgDiff / mean) * 100.0
    }

    // MARK: - Helpers

    private func rmsOf(_ samples: [Float]) -> Float {
        var rms: Float = 0
        vDSP_rmsqv(samples, 1, &rms, vDSP_Length(samples.count))
        return rms
    }

    private func evaluateWellnessAlert(_ snapshot: BiomarkerSnapshot) {
        if snapshot.fatigueIndex > 0.75 {
            alertMessage = "High vocal fatigue detected. Consider a 5-minute rest."
        } else if snapshot.jitterPercent > 5.0 {
            alertMessage = "Elevated voice jitter. You may be under stress — take a breath."
        } else {
            alertMessage = nil
        }
    }
}
