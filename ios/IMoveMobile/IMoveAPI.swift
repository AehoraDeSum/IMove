import Foundation
import Security

enum APIError: LocalizedError {
    case missingConnection
    case invalidConnection
    case server(String)

    var errorDescription: String? {
        switch self {
        case .missingConnection: return "Pair with the Mac first."
        case .invalidConnection: return "Only a Tailscale HTTPS address and a 32-character code can be used."
        case .server(let message): return message
        }
    }
}

struct Connection: Equatable {
    let baseURL: URL
    let code: String

    init?(address: String, code: String) {
        guard let baseURL = IMoveValidation.endpoint(address),
              let code = IMoveValidation.pairingCode(code) else { return nil }
        self.baseURL = baseURL
        self.code = code
    }
}

enum PairingKeychain {
    private static let service = "local.imove.mobile.pairing"
    private static let account = "pairing-code"

    static func read() -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: account,
                                    kSecReturnData as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitOne]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func save(_ code: String) -> Bool {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: account]
        let data = Data(code.utf8)
        let update = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if update == errSecSuccess { return true }
        guard update == errSecItemNotFound else { return false }
        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    static func delete() {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: account]
        SecItemDelete(query as CFDictionary)
    }
}

struct IMoveAPI {
    let connection: Connection
    var session: URLSession = .shared

    private func request(_ path: String, body: [String: Any]? = nil,
                         tracking: Bool = false) async throws -> Data {
        let url = connection.baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.timeoutInterval = 35
        request.setValue(connection.code, forHTTPHeaderField: "X-IMove-Token")
        if tracking { request.setValue("tracking", forHTTPHeaderField: "X-IMove-Source") }
        if let body {
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw APIError.server("The server did not respond.") }
        guard (200...299).contains(response.statusCode) else {
            let payload = try? JSONDecoder().decode(MessageResponse.self, from: data)
            throw APIError.server(payload?.message ?? "Server error (\(response.statusCode)).")
        }
        return data
    }

    func status() async throws -> ServerStatus {
        let data = try await request("api/status")
        return try JSONDecoder().decode(ServerStatus.self, from: data)
    }

    func places() async throws -> [Place] {
        let data = try await request("api/places")
        return try JSONDecoder().decode(PlacesResponse.self, from: data).places
    }

    func routes() async throws -> [SavedRoute] {
        let data = try await request("api/routes")
        return try JSONDecoder().decode(RoutesResponse.self, from: data).routes
    }

    func transit() async throws -> [TransitLine] {
        let data = try await request("api/transit")
        return try JSONDecoder().decode(TransitResponse.self, from: data).lines
    }

    func send(_ point: Point, renew: Bool, tracking: Bool = false) async throws -> String {
        let data = try await request("api/location", body: ["latitude": String(point.latitude),
                                                            "longitude": String(point.longitude),
                                                            "renew": renew], tracking: tracking)
        return (try JSONDecoder().decode(MessageResponse.self, from: data)).message
    }

    func addPlace(name: String, point: Point) async throws {
        _ = try await request("api/places", body: ["name": name, "latitude": String(point.latitude),
                                                  "longitude": String(point.longitude)])
    }

    func deletePlace(_ id: UUID) async throws {
        _ = try await request("api/places/delete", body: ["id": id.uuidString])
    }

    func setInterval(_ seconds: Int) async throws {
        _ = try await request("api/settings/interval", body: ["seconds": seconds])
    }

    func stopRenewal() async throws { _ = try await request("api/refresh/stop", body: [:]) }
    func clear() async throws { _ = try await request("api/clear", body: [:]) }
    func activateTracking() async throws { _ = try await request("api/tracking/activate", body: [:]) }

    func startRoute(_ id: UUID) async throws {
        _ = try await request("api/routes/start", body: ["id": id.uuidString])
    }

    func stopRoute() async throws { _ = try await request("api/routes/stop", body: [:]) }

    func deleteRoute(_ id: UUID) async throws {
        _ = try await request("api/routes/delete", body: ["id": id.uuidString])
    }

    func saveRoute(name: String, points: [Point], durations: [Int],
                   paths: [[Point]], descriptions: [String], timingMode: String) async throws {
        func object(_ point: Point) -> [String: Double] {
            ["latitude": point.latitude, "longitude": point.longitude]
        }
        _ = try await request("api/routes", body: ["name": name,
                                                   "points": points.map(object),
                                                   "timingMode": timingMode,
                                                   "segmentDurationsSeconds": durations,
                                                   "segmentPaths": paths.map { $0.map(object) },
                                                   "segmentDescriptions": descriptions])
    }

    func walkingPath(_ points: [Point]) async throws -> ([Point], Int) {
        let data = try await request("api/route/walking", body: ["points": points.map {
            ["latitude": $0.latitude, "longitude": $0.longitude]
        }])
        let value = try JSONDecoder().decode(WalkingResponse.self, from: data)
        return (value.points, value.estimatedSeconds)
    }
}

private struct MessageResponse: Decodable { let message: String }
private struct PlacesResponse: Decodable { let places: [Place] }
private struct RoutesResponse: Decodable { let routes: [SavedRoute] }
private struct TransitResponse: Decodable { let lines: [TransitLine] }
private struct WalkingResponse: Decodable { let points: [Point]; let estimatedSeconds: Int }
