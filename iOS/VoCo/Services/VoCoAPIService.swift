// VoCoAPIService.swift
// Async/await HTTP client for the VoCo FastAPI backend.

import Foundation

// MARK: - Request / Response Models

struct VoiceRouterRequest: Encodable {
    let userId: String
    let transcribedText: String
    let fatigueIndex: Float
    let pitchHz: Float

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case transcribedText = "transcribed_text"
        case fatigueIndex = "fatigue_index"
        case pitchHz = "pitch_hz"
    }
}

struct VoiceRouterResponse: Decodable {
    let action: String       // "NAVIGATE" | "SPEAK_AI" | "WELLNESS_ALERT"
    let route: String
    let speak: String
    let data: [String: String]?

    enum CodingKeys: String, CodingKey {
        case action, route, speak, data
    }
}

struct BiomarkerUploadRequest: Encodable {
    let userId: String
    let pitchHz: Float
    let jitterPercent: Float
    let shimmerPercent: Float
    let fatigueIndex: Float
    let wellnessScore: Float
    let timestamp: String

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case pitchHz = "pitch_hz"
        case jitterPercent = "jitter_percent"
        case shimmerPercent = "shimmer_percent"
        case fatigueIndex = "fatigue_index"
        case wellnessScore = "wellness_score"
        case timestamp
    }
}

struct WellnessTrend: Decodable {
    let averageWellness: Float
    let sessionCount: Int
    let recommendation: String

    enum CodingKeys: String, CodingKey {
        case averageWellness = "average_wellness"
        case sessionCount = "session_count"
        case recommendation
    }
}

// MARK: - API Error

enum VoCoAPIError: LocalizedError {
    case invalidURL
    case httpError(statusCode: Int)
    case decodingError(String)
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid server URL."
        case .httpError(let code): return "Server returned error \(code)."
        case .decodingError(let msg): return "Decoding failed: \(msg)"
        case .networkError(let err): return "Network error: \(err.localizedDescription)"
        }
    }
}

// MARK: - Service

actor VoCoAPIService {

    static let shared = VoCoAPIService()

    private let baseURL: String
    private let session: URLSession
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    init(baseURL: String = "http://localhost:8000") {
        self.baseURL = baseURL
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        self.session = URLSession(configuration: config)
    }

    // MARK: - Route Voice Command

    func routeVoiceCommand(_ request: VoiceRouterRequest) async throws -> VoiceRouterResponse {
        return try await post(path: "/api/v1/voice/router", body: request)
    }

    // MARK: - Upload Biomarker

    func uploadBiomarker(_ snapshot: BiomarkerSnapshot, userId: String) async throws {
        let iso = ISO8601DateFormatter().string(from: snapshot.timestamp)
        let req = BiomarkerUploadRequest(
            userId: userId,
            pitchHz: snapshot.pitchHz,
            jitterPercent: snapshot.jitterPercent,
            shimmerPercent: snapshot.shimmerPercent,
            fatigueIndex: snapshot.fatigueIndex,
            wellnessScore: snapshot.wellnessScore,
            timestamp: iso
        )
        let _: EmptyResponse = try await post(path: "/api/v1/biomarker/ingest", body: req)
    }

    // MARK: - Get Wellness Trend

    func getWellnessTrend(userId: String) async throws -> WellnessTrend {
        return try await get(path: "/api/v1/wellness/trend/\(userId)")
    }

    // MARK: - Generic HTTP Helpers

    private func post<Req: Encodable, Res: Decodable>(path: String, body: Req) async throws -> Res {
        guard let url = URL(string: baseURL + path) else { throw VoCoAPIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)
        return try await execute(request: request)
    }

    private func get<Res: Decodable>(path: String) async throws -> Res {
        guard let url = URL(string: baseURL + path) else { throw VoCoAPIError.invalidURL }
        let request = URLRequest(url: url)
        return try await execute(request: request)
    }

    private func execute<Res: Decodable>(request: URLRequest) async throws -> Res {
        do {
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw VoCoAPIError.httpError(statusCode: http.statusCode)
            }
            do {
                return try decoder.decode(Res.self, from: data)
            } catch {
                throw VoCoAPIError.decodingError(error.localizedDescription)
            }
        } catch let error as VoCoAPIError {
            throw error
        } catch {
            throw VoCoAPIError.networkError(error)
        }
    }
}

// Sentinel for endpoints that return 204 / empty body
private struct EmptyResponse: Decodable {}
