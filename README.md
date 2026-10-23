# VoCo — Voice-Powered Vocational Training Platform

> **Healthcare Track · Team Innovus**
> Ayush Vishwakarma (Leader) · Divyanshi Khemani · Raghav Pathak · Sujal Singh

---

## Overview

VoCo is a **zero-touch, voice-first** vocational training ecosystem for visually impaired users. It
replaces all visual menus with continuous natural speech recognition, spatial audio cues, and Apple
Watch haptic guidance — enabling complete hands-free operation.

---

## Repository Structure

```
VoCo/
├── iOS/
│   ├── VoCo/                         # iOS SwiftUI application
│   │   ├── VoCoApp.swift             # App entry point
│   │   ├── Engine/
│   │   │   ├── VoCoVoiceEngine.swift         # Continuous speech loop + TTS + intent parser
│   │   │   └── AcousticBiomarkerAnalyzer.swift # Pitch / jitter / shimmer / fatigue (vDSP)
│   │   ├── Services/
│   │   │   ├── VoCoAPIService.swift          # Async HTTP client for FastAPI backend
│   │   │   └── WatchSessionManager.swift     # WatchConnectivity bridge
│   │   ├── Models/
│   │   │   └── AppState.swift                # Navigation state, user session, modules
│   │   ├── Views/
│   │   │   ├── RootView.swift
│   │   │   ├── SplashView.swift
│   │   │   ├── AuthenticationView.swift      # Face ID + voice PIN
│   │   │   ├── DashboardView.swift
│   │   │   ├── PronunciationView.swift       # Module player
│   │   │   ├── AssistantView.swift           # Gemini AI chat
│   │   │   ├── WellnessView.swift            # Biomarker dashboard + chart
│   │   │   ├── JobsView.swift                # Accessible job listings
│   │   │   └── SettingsView.swift
│   │   └── Info.plist
│   └── VoCoWatch Watch App/          # watchOS companion
│       ├── VoCoWatchApp.swift        # WCSession delegate + haptic dispatch
│       └── WatchRootView.swift       # Wellness glance face
└── backend/
    ├── main.py                       # FastAPI app + lifespan
    ├── routers/
    │   ├── voice.py                  # /api/v1/voice/router  (intent + Gemini)
    │   ├── biomarker.py              # /api/v1/biomarker/ingest + summary
    │   └── wellness.py               # /api/v1/wellness/trend/:user_id
    ├── services/
    │   ├── gemini_service.py         # Gemini 2.0 Flash wrapper
    │   ├── database.py               # Async SQLAlchemy (SQLite dev / Postgres prod)
    │   └── cache.py                  # Redis async cache
    ├── models/
    │   └── biomarker_model.py        # ORM table
    ├── requirements.txt
    └── .env.example
```

---

## iOS Setup (Xcode)

### Prerequisites
- Xcode 15+, iOS 17+ target
- A physical device (speech recognition does not run on Simulator)
- Apple Developer account (for WatchConnectivity + speech entitlements)

### Steps
1. Open `iOS/` in Xcode by **File → Add Files** or create a new Xcode project and add the Swift
   files from `iOS/VoCo/` manually.
2. Set Bundle ID to `com.innovus.voco` (or your own, matching `Info.plist`).
3. In **Signing & Capabilities**, add:
   - Speech Recognition
   - Microphone (NSMicrophoneUsageDescription already in plist)
   - Face ID (NSFaceIDUsageDescription already in plist)
   - Background Modes → Audio
4. For the Watch target, add the `VoCoWatch Watch App/` files and set the companion app to the iOS target.
5. Set `baseURL` in `VoCoAPIService.swift` to your backend host (default: `http://localhost:8000`).
6. Build and run on device.

---

## Backend Setup

### Prerequisites
- Python 3.11+
- Redis (optional — caching degrades gracefully without it)

### Quick Start

```bash
cd backend

# 1. Install dependencies
pip install -r requirements.txt

# 2. Configure environment
cp .env.example .env
# Edit .env and set GEMINI_API_KEY

# 3. Run the server
uvicorn main:app --reload --host 0.0.0.0 --port 8000
```

### API Endpoints

| Method | Path | Description |
|--------|------|-------------|
| POST | `/api/v1/voice/router` | Route voice command or query Gemini |
| POST | `/api/v1/biomarker/ingest` | Persist a biomarker reading |
| GET | `/api/v1/biomarker/summary/{user_id}` | Aggregate biomarker stats |
| GET | `/api/v1/wellness/trend/{user_id}` | Wellness trend + recommendation |
| GET | `/health` | Service health check |

Interactive docs available at `http://localhost:8000/docs`.

---

## Architecture

```
[User Speech]
      │
      ▼
[SFSpeechRecognizer (iOS)]
      │─────────────────────────────────────────────────┐
      │                                                  │
      ▼                                                  ▼
[Acoustic Biomarker (vDSP)]              [Text Token Intent Classifier]
  Pitch / Jitter / Shimmer                      │
  Fatigue Index                     ┌───────────┴───────────────┐
                                    ▼                           ▼
                          [Local Command Router]    [FastAPI Cloud Endpoint]
                          (Navigation/Pronunciation)  [Gemini 2.0 Flash AI]
                                    │                           │
                                    └───────────┬───────────────┘
                                                ▼
                                    [AVSpeechSynthesizer] ─── Audio Output
                                    [Apple Watch Taptic]  ─── Wrist Haptic
```

---

## Core Accessibility Features

| Feature | Implementation |
|---------|---------------|
| Zero-touch navigation | `VoCoVoiceEngine` continuous speech loop with intent parser |
| TTS confirmation on every state change | `speak()` called on all route transitions |
| Acoustic biomarker analysis | `AcousticBiomarkerAnalyzer` — vDSP autocorrelation pitch + jitter + shimmer |
| Apple Watch haptics | 7 distinct `WKHapticType` patterns mapped to navigation events |
| Face ID + voice PIN auth | `LocalAuthentication` + fallback digit PIN via speech |
| VoiceOver compatible | All views use `accessibilityLabel` + `accessibilityHint` |
| Fatigue-aware AI | Gemini prompt prefixed with fatigue context when index > 0.65 |

---

## Social Impact Roadmap

| Phase | Focus |
|-------|-------|
| 1 — Core Launch | Voice engine, 4 vocational modules, biomarker analysis, 24/7 AI |
| 2 — Multilingual | Regional Indian + global languages |
| 3 — B2B Partnerships | Corporate hiring pipelines + NGO placement |
| 4 — Clinical Biomarkers | Medical-grade cognitive wellness + fatigue monitoring |

---

*VoCo Blueprint & Technical Specification — Team Innovus*
