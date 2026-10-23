// VoCoVoiceEngine.swift
// Continuous Speech Recognition & TTS Engine
// Zero-touch: every state change is spoken aloud.

import AVFoundation
import Speech
import SwiftUI
import Combine

// MARK: - Intent Model

/// Parsed intent from raw transcribed text.
enum VoCoIntent: Equatable {
    case navigate(Route)
    case query(String)
    case stopListening
    case repeatLast
    case help
    case unknown(String)

    enum Route: String, CaseIterable {
        case dashboard       = "dashboard"
        case pronunciation   = "pronunciation"
        case assistant       = "assistant"
        case wellness        = "wellness"
        case jobs            = "jobs"
        case settings        = "settings"
    }
}

// MARK: - Voice Engine

@MainActor
final class VoCoVoiceEngine: NSObject, ObservableObject {

    // MARK: Published State

    @Published var transcribedText: String = ""
    @Published var isListening: Bool = false
    @Published var isSpeaking: Bool = false
    @Published var lastSpokenText: String = ""
    @Published var permissionGranted: Bool = false

    // MARK: Private Properties

    private let speechRecognizer: SFSpeechRecognizer
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private let synthesizer = AVSpeechSynthesizer()
    private var commandHandler: ((VoCoIntent) -> Void)?
    private var silenceTimer: Timer?
    private let silenceThreshold: TimeInterval = 1.8   // seconds of silence before commit
    private var lastTranscript: String = ""
    private var speechRate: Float = AVSpeechUtteranceDefaultSpeechRate

    // MARK: Init

    override init() {
        self.speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))!
        super.init()
        speechRecognizer.delegate = self
        synthesizer.delegate = self
    }

    // MARK: Permissions

    func requestPermissions() async {
        let speechAuth = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0) }
        }
        let micAuth = await AVAudioApplication.requestRecordPermission()
        await MainActor.run {
            permissionGranted = (speechAuth == .authorized) && micAuth
        }
    }

    // MARK: - Start Listening

    /// Begin continuous recognition. `onCommand` fires on every committed intent.
    func startListening(onCommand: @escaping (VoCoIntent) -> Void) {
        guard permissionGranted else {
            speak("Microphone and speech permissions are required. Please enable them in Settings.")
            return
        }
        guard !isListening else { return }
        commandHandler = onCommand
        do {
            try configureAudioSession()
            try startRecognitionTask()
            isListening = true
            speak("VoCo is listening. Say a command or ask a question.")
        } catch {
            speak("Could not start microphone. \(error.localizedDescription)")
        }
    }

    // MARK: - Stop Listening

    func stopListening() {
        silenceTimer?.invalidate()
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        isListening = false
    }

    // MARK: - TTS Speak

    /// Speaks text. Interrupts any ongoing utterance.
    func speak(_ text: String, rate: Float? = nil) {
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = rate ?? speechRate
        utterance.pitchMultiplier = 1.05
        utterance.volume = 1.0
        utterance.postUtteranceDelay = 0.12
        lastSpokenText = text
        synthesizer.speak(utterance)
    }

    func setSpeechRate(_ rate: Float) {
        speechRate = min(max(rate, AVSpeechUtteranceMinimumSpeechRate),
                         AVSpeechUtteranceMaximumSpeechRate)
    }

    // MARK: - Private Helpers

    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord,
                                mode: .measurement,
                                options: [.duckOthers, .allowBluetooth])
        try session.setActive(true, options: .notifyOthersOnDeactivation)
    }

    private func startRecognitionTask() throws {
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let request = recognitionRequest else { return }
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = false   // allow server for accuracy

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()

        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let result {
                let text = result.bestTranscription.formattedString
                Task { @MainActor in
                    self.transcribedText = text
                    self.resetSilenceTimer(text: text)
                }
            }
            if let error {
                // SFSpeechRecognizerErrorDomain code 301 = cancelled — ignore
                let nsErr = error as NSError
                if nsErr.code != 301 {
                    Task { @MainActor in
                        self.isListening = false
                    }
                }
            }
        }
    }

    private func resetSilenceTimer(text: String) {
        lastTranscript = text
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: silenceThreshold, repeats: false) { [weak self] _ in
            guard let self, !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
            Task { @MainActor in
                let intent = VoCoIntentParser.parse(text)
                self.commandHandler?(intent)
                // Auto-restart for next command
                self.restartRecognitionLoop()
            }
        }
    }

    private func restartRecognitionLoop() {
        stopListening()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self, let handler = self.commandHandler else { return }
            self.startListening(onCommand: handler)
        }
    }
}

// MARK: - SFSpeechRecognizerDelegate

extension VoCoVoiceEngine: SFSpeechRecognizerDelegate {
    nonisolated func speechRecognizer(_ speechRecognizer: SFSpeechRecognizer,
                                      availabilityDidChange available: Bool) {
        Task { @MainActor in
            if !available {
                self.speak("Speech recognition is temporarily unavailable.")
            }
        }
    }
}

// MARK: - AVSpeechSynthesizerDelegate

extension VoCoVoiceEngine: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       didStart utterance: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = true }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = false }
    }
}

// MARK: - Intent Parser

enum VoCoIntentParser {

    private static let navigationKeywords: [String: VoCoIntent.Route] = [
        "dashboard": .dashboard,
        "home": .dashboard,
        "pronunciation": .pronunciation,
        "pronounce": .pronunciation,
        "speak": .pronunciation,
        "assistant": .assistant,
        "talk": .assistant,
        "chat": .assistant,
        "wellness": .wellness,
        "health": .wellness,
        "fatigue": .wellness,
        "jobs": .jobs,
        "career": .jobs,
        "employment": .jobs,
        "work": .jobs,
        "settings": .settings,
        "preferences": .settings
    ]

    static func parse(_ raw: String) -> VoCoIntent {
        let text = raw.lowercased().trimmingCharacters(in: .whitespaces)

        if text.contains("stop") || text.contains("quit") || text.contains("exit") {
            return .stopListening
        }
        if text.contains("repeat") || text.contains("say again") || text.contains("what did you say") {
            return .repeatLast
        }
        if text.contains("help") || text.contains("what can") || text.contains("commands") {
            return .help
        }
        for (keyword, route) in navigationKeywords {
            if text.contains(keyword) {
                return .navigate(route)
            }
        }
        if !text.isEmpty {
            return .query(raw)
        }
        return .unknown(raw)
    }
}
