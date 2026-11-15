import Foundation

struct Point: Codable, Equatable, Identifiable {
    var latitude: Double
    var longitude: Double
    var id: String { "\(latitude),\(longitude)" }

    init(_ latitude: Double, _ longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    var isValid: Bool {
        latitude.isFinite && longitude.isFinite && (-90...90).contains(latitude) && (-180...180).contains(longitude)
    }

    var label: String {
        String(format: "%.6f, %.6f", locale: Locale(identifier: "en_US_POSIX"), latitude, longitude)
    }
}

struct Place: Codable, Identifiable {
    let id: UUID
    let name: String
    let latitude: Double
    let longitude: Double
    var point: Point { Point(latitude, longitude) }
}

struct SavedRoute: Codable, Identifiable {
    let id: UUID
    let name: String
    let timingMode: String
    let segmentDurationsSeconds: [Int]
    let totalDurationSeconds: Int
    let points: [Point]
    let segmentPaths: [[Point]]
    let segmentDescriptions: [String]
}

struct ServerStatus: Codable {
    let ready: Bool
    let busy: Bool
    let lastSent: String
    let refreshing: Bool
    let renewOnSend: Bool
    let updateIntervalSeconds: Int
    let routeID: String
    let routeName: String
    let routeProgress: Double
    let routeSegmentIndex: Int
    let routeSegmentCount: Int
    let message: String

    var sentPoint: Point? {
        let parts = lastSent.split(separator: ",", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        return IMoveValidation.point(latitude: String(parts[0]).trimmingCharacters(in: .whitespaces),
                                     longitude: String(parts[1]).trimmingCharacters(in: .whitespaces))
    }
}

struct TransitLine: Codable, Identifiable {
    let id: String
    let name: String
    let stations: [TransitStation]
}

struct TransitStation: Codable, Identifiable {
    let id: String
    let name: String
    let latitude: Double
    let longitude: Double
    let pathToNext: [[Double]]?
    var point: Point { Point(latitude, longitude) }
}

enum IMoveValidation {
    static func endpoint(_ value: String) -> URL? {
        guard let components = URLComponents(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
              components.scheme?.lowercased() == "https",
              let host = components.host?.lowercased(), host.hasSuffix(".ts.net"),
              host.count > ".ts.net".count, components.port == nil,
              components.user == nil, components.password == nil,
              components.path.isEmpty || components.path == "/",
              components.query == nil, components.fragment == nil else { return nil }
        return components.url
    }

    static func pairingCode(_ value: String) -> String? {
        let code = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard code.count == 32, code.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "0123456789abcdef").contains($0) }) else { return nil }
        return code
    }

    static func point(latitude: String, longitude: String) -> Point? {
        guard let latitude = Double(latitude.replacingOccurrences(of: ",", with: ".")),
              let longitude = Double(longitude.replacingOccurrences(of: ",", with: ".")) else { return nil }
        let point = Point(latitude, longitude)
        return point.isValid ? point : nil
    }

    static func equalDurations(totalSeconds: Int, segments: Int) -> [Int]? {
        guard segments > 0, totalSeconds >= segments else { return nil }
        let base = totalSeconds / segments
        let remainder = totalSeconds % segments
        return (0..<segments).map { base + ($0 < remainder ? 1 : 0) }
    }
}
