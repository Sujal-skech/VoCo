// JobsView.swift
// Accessible remote job listings — voice-navigable.

import SwiftUI

struct JobListing: Identifiable {
    let id = UUID()
    let title: String
    let company: String
    let type: String
    let description: String
    let skills: [String]
    let isAccessibilityFriendly: Bool
}

struct JobsView: View {

    @EnvironmentObject var appState: AppState
    @EnvironmentObject var voiceEngine: VoCoVoiceEngine

    @State private var selectedJob: JobListing?
    @State private var searchText: String = ""

    private let listings = JobListing.sampleListings

    private var filtered: [JobListing] {
        guard !searchText.isEmpty else { return listings }
        return listings.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            $0.company.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {
                navHeader(title: "Job Opportunities", onBack: {
                    appState.navigate(to: .dashboard, via: voiceEngine)
                })

                if let job = selectedJob {
                    JobDetailView(job: job, onBack: {
                        selectedJob = nil
                        announceListings()
                    })
                } else {
                    jobList
                }
            }
        }
        .onAppear { startJobsListener() }
        .onDisappear { voiceEngine.stopListening() }
    }

    private var jobList: some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(Array(filtered.enumerated()), id: \.element.id) { index, job in
                    JobRowView(job: job, index: index + 1) {
                        selectedJob = job
                        voiceEngine.speak("Opening \(job.title) at \(job.company). \(job.description). Required skills: \(job.skills.joined(separator: ", ")). Say 'apply' to express interest, or 'back' to return to listings.")
                    }
                }
            }
            .padding(20)
        }
    }

    private func startJobsListener() {
        announceListings()
        voiceEngine.startListening { intent in
            switch intent {
            case .query(let q):
                let lower = q.lowercased()
                if lower.contains("back") || lower.contains("home") {
                    if selectedJob != nil {
                        selectedJob = nil
                    } else {
                        appState.navigate(to: .dashboard, via: voiceEngine)
                    }
                } else if lower.contains("apply") {
                    voiceEngine.speak("Application of interest registered. A recruiter will contact you within 3 business days.")
                    WatchSessionManager.shared.sendHaptic(.navigationSuccess)
                } else {
                    // Voice search
                    searchText = q
                    let count = filtered.count
                    voiceEngine.speak("Found \(count) job\(count == 1 ? "" : "s") matching \(q).")
                }
            default:
                break
            }
        }
    }

    private func announceListings() {
        let count = filtered.count
        voiceEngine.speak("\(count) remote accessible jobs available. Say a job number to hear details, or speak keywords to search.")
    }
}

// MARK: - Job Row

struct JobRowView: View {
    let job: JobListing
    let index: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Text("\(index)")
                    .font(.system(.headline, design: .monospaced))
                    .foregroundColor(.yellow)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 4) {
                    Text(job.title)
                        .font(.headline)
                        .foregroundColor(.white)
                    Text(job.company)
                        .font(.subheadline)
                        .foregroundColor(.gray)
                    HStack(spacing: 6) {
                        Label(job.type, systemImage: "house")
                            .font(.caption)
                            .foregroundColor(.cyan)
                        if job.isAccessibilityFriendly {
                            Label("Accessible", systemImage: "figure.roll")
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                    }
                }
                Spacer()
            }
            .padding(16)
            .background(Color(white: 0.1))
            .cornerRadius(14)
        }
        .accessibilityLabel("Job \(index): \(job.title) at \(job.company), \(job.type)\(job.isAccessibilityFriendly ? ", accessibility friendly" : "")")
        .accessibilityHint("Double-tap or say the job number to hear full details")
    }
}

// MARK: - Job Detail

struct JobDetailView: View {
    let job: JobListing
    let onBack: () -> Void

    @EnvironmentObject var voiceEngine: VoCoVoiceEngine

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Button(action: onBack) {
                    Label("Back to listings", systemImage: "chevron.left")
                        .font(.subheadline)
                        .foregroundColor(.yellow)
                }
                .padding(.top, 16)
                .accessibilityLabel("Back to job listings")

                Text(job.title)
                    .font(.title2).bold()
                    .foregroundColor(.white)
                Text(job.company + " · " + job.type)
                    .font(.subheadline)
                    .foregroundColor(.gray)

                Divider().background(Color.gray.opacity(0.3))

                Text(job.description)
                    .font(.body)
                    .foregroundColor(.white.opacity(0.9))

                VStack(alignment: .leading, spacing: 8) {
                    Text("Required Skills")
                        .font(.headline)
                        .foregroundColor(.yellow)
                    ForEach(job.skills, id: \.self) { skill in
                        Label(skill, systemImage: "checkmark.circle.fill")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.8))
                    }
                }

                Button {
                    voiceEngine.speak("Application of interest submitted for \(job.title). A recruiter will contact you soon.")
                    WatchSessionManager.shared.sendHaptic(.navigationSuccess)
                } label: {
                    Text("Express Interest")
                        .font(.headline)
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.yellow)
                        .cornerRadius(14)
                }
                .accessibilityLabel("Express interest in \(job.title)")
                .padding(.top, 8)
            }
            .padding(20)
        }
    }
}

// MARK: - Sample Data

extension JobListing {
    static let sampleListings: [JobListing] = [
        JobListing(
            title: "Remote Customer Support Specialist",
            company: "ClearVoice Inc.",
            type: "Full-time Remote",
            description: "Handle inbound customer queries via phone and chat. Excellent listening skills and patience required. Full audio-only workflow supported.",
            skills: ["Active listening", "De-escalation", "CRM navigation by voice", "English fluency"],
            isAccessibilityFriendly: true
        ),
        JobListing(
            title: "Virtual Executive Assistant",
            company: "Nexus Partners",
            type: "Part-time Remote",
            description: "Manage calendars, draft emails, and coordinate meetings for a senior executive. Voice-dictation tools provided.",
            skills: ["Calendar management", "Email drafting", "Voice dictation", "Time management"],
            isAccessibilityFriendly: true
        ),
        JobListing(
            title: "Audio Content Reviewer",
            company: "SoundGuard AI",
            type: "Contract Remote",
            description: "Review AI-flagged audio clips for policy compliance. Headphone-first workflow. Training provided.",
            skills: ["Critical listening", "Policy comprehension", "Attention to detail"],
            isAccessibilityFriendly: true
        ),
        JobListing(
            title: "Podcast Production Assistant",
            company: "WaveStudio",
            type: "Freelance Remote",
            description: "Support podcast hosts with scheduling, show notes via voice transcription, and audience queries.",
            skills: ["Transcription", "Scheduling", "Written communication"],
            isAccessibilityFriendly: false
        )
    ]
}
