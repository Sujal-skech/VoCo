// AssistantView.swift
// Real-time voice conversation with Gemini 2.0 Flash via VoCo backend.

import SwiftUI

struct ChatMessage: Identifiable {
    let id = UUID()
    let role: Role
    let text: String
    let timestamp: Date

    enum Role { case user, assistant }
}

struct AssistantView: View {

    @EnvironmentObject var appState: AppState
    @EnvironmentObject var voiceEngine: VoCoVoiceEngine
    @EnvironmentObject var biomarker: AcousticBiomarkerAnalyzer

    @State private var messages: [ChatMessage] = []
    @State private var isProcessing: Bool = false
    @State private var errorBanner: String?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {
                navHeader(title: "AI Assistant", onBack: {
                    appState.navigate(to: .dashboard, via: voiceEngine)
                })

                // Chat transcript
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(messages) { msg in
                                MessageBubble(message: msg)
                                    .id(msg.id)
                            }
                            if isProcessing {
                                ThinkingIndicator()
                            }
                        }
                        .padding(16)
                    }
                    .onChange(of: messages.count) { _ in
                        if let last = messages.last {
                            withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                        }
                    }
                }

                // Error banner
                if let err = errorBanner {
                    Text(err)
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(8)
                }

                // Mic status
                VoiceStatusBar()
                    .padding(.bottom, 20)
            }
        }
        .onAppear {
            startAssistantListener()
            // Handle query passed from Dashboard
            NotificationCenter.default.addObserver(forName: .vocoQueryPassed,
                                                    object: nil, queue: .main) { note in
                if let q = note.object as? String {
                    Task { await sendQuery(q) }
                }
            }
        }
        .onDisappear {
            voiceEngine.stopListening()
            NotificationCenter.default.removeObserver(self, name: .vocoQueryPassed, object: nil)
        }
    }

    // MARK: - Voice Listener

    private func startAssistantListener() {
        voiceEngine.speak("VoCo AI Assistant is active. Ask me anything, or say 'back' to return.")
        voiceEngine.startListening { intent in
            switch intent {
            case .navigate(let r) where r == .dashboard:
                appState.navigate(to: .dashboard, via: voiceEngine)
            case .query(let q):
                let lower = q.lowercased()
                if lower.contains("back") || lower.contains("exit") || lower.contains("home") {
                    appState.navigate(to: .dashboard, via: voiceEngine)
                } else {
                    Task { await sendQuery(q) }
                }
            case .help:
                voiceEngine.speak("Just ask me any question. I'll answer immediately. Say 'back' to return to the dashboard.")
            case .repeatLast:
                if let last = messages.last(where: { $0.role == .assistant }) {
                    voiceEngine.speak(last.text)
                }
            default:
                break
            }
        }
    }

    // MARK: - API Call

    @MainActor
    private func sendQuery(_ text: String) async {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        messages.append(ChatMessage(role: .user, text: text, timestamp: Date()))
        isProcessing = true
        errorBanner = nil

        do {
            let request = VoiceRouterRequest(
                userId: appState.currentUser?.id ?? "anonymous",
                transcribedText: text,
                fatigueIndex: biomarker.currentSnapshot?.fatigueIndex ?? 0,
                pitchHz: biomarker.currentSnapshot?.pitchHz ?? 0
            )
            let response = try await VoCoAPIService.shared.routeVoiceCommand(request)
            let reply = response.speak
            messages.append(ChatMessage(role: .assistant, text: reply, timestamp: Date()))
            voiceEngine.speak(reply)
            WatchSessionManager.shared.sendHaptic(.navigationSuccess)
        } catch {
            let errMsg = "Could not reach VoCo server. Please check your connection."
            errorBanner = errMsg
            voiceEngine.speak(errMsg)
        }
        isProcessing = false
    }
}

// MARK: - Message Bubble

struct MessageBubble: View {
    let message: ChatMessage

    private var isUser: Bool { message.role == .user }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 48) }
            Text(message.text)
                .font(.body)
                .foregroundColor(isUser ? .black : .white)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(isUser ? Color.yellow : Color(white: 0.15))
                .cornerRadius(18)
                .cornerRadius(isUser ? 4 : 18, corners: isUser ? .bottomRight : .bottomLeft)
            if !isUser { Spacer(minLength: 48) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(isUser ? "You said" : "VoCo replied"): \(message.text)")
    }
}

// MARK: - Thinking Indicator

struct ThinkingIndicator: View {
    @State private var dots = 0
    private let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack {
            Text("VoCo is thinking" + String(repeating: ".", count: dots))
                .font(.caption)
                .foregroundColor(.gray)
                .onReceive(timer) { _ in dots = (dots + 1) % 4 }
            Spacer()
        }
        .accessibilityLabel("VoCo is processing your request")
    }
}

// MARK: - Corner Radius Helper

extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat
    var corners: UIRectCorner

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(roundedRect: rect,
                                byRoundingCorners: corners,
                                cornerRadii: CGSize(width: radius, height: radius))
        return Path(path.cgPath)
    }
}
