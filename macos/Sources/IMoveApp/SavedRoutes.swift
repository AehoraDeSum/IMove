import Foundation
import IMoveCore

struct RouteWaypoint: Codable, Equatable {
    let latitude: Double
    let longitude: Double

    init(_ coordinate: Coordinate) {
        latitude = coordinate.latitude
        longitude = coordinate.longitude
    }

    var coordinate: Coordinate {
        try! Coordinate(latitude: String(latitude), longitude: String(longitude))
    }

    var response: [String: Any] { ["latitude": latitude, "longitude": longitude] }
}

enum RouteTimingMode: String, Codable {
    case equal
    case custom
}

struct SavedRoute: Codable, Equatable {
    let id: UUID
    let name: String
    let timingMode: RouteTimingMode
    let segmentDurationsSeconds: [Int]
    let points: [RouteWaypoint]
    let segmentPaths: [[RouteWaypoint]]
    let segmentDescriptions: [String]

    var totalDurationSeconds: Int { segmentDurationsSeconds.reduce(0, +) }

    var response: [String: Any] {
        ["id": id.uuidString, "name": name, "timingMode": timingMode.rawValue,
         "segmentDurationsSeconds": segmentDurationsSeconds,
         "totalDurationSeconds": totalDurationSeconds,
         "points": points.map(\.response),
         "segmentPaths": segmentPaths.map { $0.map(\.response) },
         "segmentDescriptions": segmentDescriptions]
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, timingMode, segmentDurationsSeconds, points, segmentPaths, segmentDescriptions, minutesPerSegment
    }

    init(id: UUID, name: String, timingMode: RouteTimingMode,
         segmentDurationsSeconds: [Int], points: [RouteWaypoint], segmentPaths: [[RouteWaypoint]] = [],
         segmentDescriptions: [String] = []) {
        self.id = id
        self.name = name
        self.timingMode = timingMode
        self.segmentDurationsSeconds = segmentDurationsSeconds
        self.points = points
        self.segmentPaths = segmentPaths
        self.segmentDescriptions = segmentDescriptions
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        points = try container.decode([RouteWaypoint].self, forKey: .points)
        segmentPaths = try container.decodeIfPresent([[RouteWaypoint]].self, forKey: .segmentPaths) ?? []
        segmentDescriptions = try container.decodeIfPresent([String].self, forKey: .segmentDescriptions) ?? []
        if let durations = try container.decodeIfPresent([Int].self, forKey: .segmentDurationsSeconds) {
            segmentDurationsSeconds = durations
            timingMode = try container.decode(RouteTimingMode.self, forKey: .timingMode)
        } else {
            // Routes saved by earlier releases used the same duration for each leg.
            let minutes = try container.decode(Int.self, forKey: .minutesPerSegment)
            let (seconds, overflow) = minutes.multipliedReportingOverflow(by: 60)
            guard !overflow else { throw DecodingError.dataCorruptedError(
                forKey: .minutesPerSegment, in: container, debugDescription: "Duration overflow") }
            segmentDurationsSeconds = Array(repeating: seconds, count: max(0, points.count - 1))
            timingMode = .equal
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(timingMode, forKey: .timingMode)
        try container.encode(segmentDurationsSeconds, forKey: .segmentDurationsSeconds)
        try container.encode(points, forKey: .points)
        if !segmentPaths.isEmpty { try container.encode(segmentPaths, forKey: .segmentPaths) }
        if !segmentDescriptions.isEmpty { try container.encode(segmentDescriptions, forKey: .segmentDescriptions) }
    }
}

enum RouteTiming {
    static func distributed(totalSeconds: Int, segments: Int) -> [Int]? {
        guard segments > 0, totalSeconds >= segments else { return nil }
        let base = totalSeconds / segments
        let remainder = totalSeconds % segments
        return (0..<segments).map { base + ($0 < remainder ? 1 : 0) }
    }

    static func label(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let remainder = seconds % 60
        if hours > 0 { return "\(hours) h \(minutes) min \(remainder) s" }
        if minutes > 0 { return "\(minutes) min \(remainder) s" }
        return "\(remainder) s"
    }
}

enum RouteGeometry {
    static func interpolate(path: [RouteWaypoint], fraction: Double) -> Coordinate {
        guard path.count >= 2 else { return path[0].coordinate }
        let lengths = zip(path, path.dropFirst()).map { first, second in
            let latitudeScale = 111_000.0
            let longitudeScale = 111_000.0 * cos((first.latitude + second.latitude) * .pi / 360)
            return hypot((second.latitude - first.latitude) * latitudeScale,
                         (second.longitude - first.longitude) * longitudeScale)
        }
        let total = lengths.reduce(0, +)
        guard total > 0 else { return path.last!.coordinate }
        var remaining = min(1, max(0, fraction)) * total
        for index in lengths.indices {
            if remaining <= lengths[index] || index == lengths.count - 1 {
                return interpolate(from: path[index], to: path[index + 1],
                                   fraction: lengths[index] > 0 ? remaining / lengths[index] : 1)
            }
            remaining -= lengths[index]
        }
        return path.last!.coordinate
    }

    static func interpolate(from start: RouteWaypoint, to end: RouteWaypoint, fraction: Double) -> Coordinate {
        let t = min(1, max(0, fraction))
        var longitudeDelta = end.longitude - start.longitude
        if longitudeDelta > 180 { longitudeDelta -= 360 }
        if longitudeDelta < -180 { longitudeDelta += 360 }
        var longitude = start.longitude + longitudeDelta * t
        if longitude > 180 { longitude -= 360 }
        if longitude < -180 { longitude += 360 }
        return try! Coordinate(latitude: String(start.latitude + (end.latitude - start.latitude) * t),
                               longitude: String(longitude))
    }
}

@MainActor
final class SavedRoutes {
    private(set) var all: [SavedRoute]
    private let file: URL

    static var defaultFile: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("IMove", isDirectory: true)
            .appendingPathComponent("saved-routes.json")
    }

    init(file: URL? = nil) throws {
        self.file = file ?? Self.defaultFile
        let folder = self.file.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path)
        if FileManager.default.fileExists(atPath: self.file.path) {
            let loaded = try JSONDecoder().decode([SavedRoute].self, from: Data(contentsOf: self.file))
            guard Set(loaded.map(\.id)).count == loaded.count,
                  loaded.allSatisfy(Self.isValid) else {
                throw IMoveError.message("The saved routes file is invalid. Check the file.")
            }
            all = loaded
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: self.file.path)
        } else {
            all = []
        }
    }

    @discardableResult
    func add(name rawName: String, timingMode: RouteTimingMode,
             segmentDurationsSeconds: [Int], points: [Coordinate],
             segmentPaths: [[Coordinate]] = [], segmentDescriptions: [String] = []) throws -> SavedRoute {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 50,
              !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw IMoveError.message("Route names must be 1–50 characters.")
        }
        guard points.count >= 2 else { throw IMoveError.message("A route must have at least two points.") }
        guard segmentDurationsSeconds.count == points.count - 1,
              segmentDurationsSeconds.allSatisfy({ (1...86_400).contains($0) }) else {
            throw IMoveError.message("Each segment must last between 1 second and 24 hours.")
        }
        guard segmentPaths.isEmpty || (segmentPaths.count == points.count - 1 &&
              segmentPaths.reduce(0) { $0 + $1.count } <= 20_000 &&
              segmentPaths.enumerated().allSatisfy { index, path in
                  path.count >= 2 && path.count <= 2_000 &&
                  path.first == points[index] && path.last == points[index + 1]
              }) else { throw IMoveError.message("Route paths do not match the stops.") }
        guard segmentDescriptions.isEmpty || (segmentDescriptions.count == points.count - 1 &&
              segmentDescriptions.allSatisfy { $0.count <= 120 }) else {
            throw IMoveError.message("Invalid route segment descriptions.")
        }
        guard !all.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
            throw IMoveError.message("A route with this name already exists.")
        }
        let route = SavedRoute(id: UUID(), name: name, timingMode: timingMode,
                               segmentDurationsSeconds: segmentDurationsSeconds,
                               points: points.map(RouteWaypoint.init),
                               segmentPaths: segmentPaths.map { $0.map(RouteWaypoint.init) },
                               segmentDescriptions: segmentDescriptions)
        let next = all + [route]
        try persist(next)
        all = next
        return route
    }

    @discardableResult
    func add(name: String, minutesPerSegment: Int, points: [Coordinate]) throws -> SavedRoute {
        guard (1...60).contains(minutesPerSegment) else {
            throw IMoveError.message("Time between points must be 1–60 minutes.")
        }
        return try add(name: name, timingMode: .equal,
                       segmentDurationsSeconds: Array(repeating: minutesPerSegment * 60,
                                                      count: max(0, points.count - 1)), points: points)
    }

    func remove(id: UUID) throws {
        guard all.contains(where: { $0.id == id }) else {
            throw IMoveError.message("Saved route not found.")
        }
        let next = all.filter { $0.id != id }
        try persist(next)
        all = next
    }

    private static func isValid(_ route: SavedRoute) -> Bool {
        !route.name.isEmpty && route.name.count <= 50 &&
        !route.name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) &&
        route.points.count >= 2 &&
        (route.segmentDescriptions.isEmpty || (route.segmentDescriptions.count == route.points.count - 1 &&
         route.segmentDescriptions.allSatisfy { $0.count <= 120 })) &&
        (route.segmentPaths.isEmpty || (route.segmentPaths.count == route.points.count - 1 &&
         route.segmentPaths.reduce(0) { $0 + $1.count } <= 20_000 &&
         route.segmentPaths.enumerated().allSatisfy { index, path in
             path.count >= 2 && path.count <= 2_000 &&
             path.first == route.points[index] && path.last == route.points[index + 1] &&
             path.allSatisfy { $0.latitude.isFinite && $0.longitude.isFinite &&
                 (-90...90).contains($0.latitude) && (-180...180).contains($0.longitude) }
         })) &&
        route.segmentDurationsSeconds.count == route.points.count - 1 &&
        route.segmentDurationsSeconds.allSatisfy { (1...86_400).contains($0) } &&
        route.points.allSatisfy { point in
            point.latitude.isFinite && point.longitude.isFinite &&
            (-90...90).contains(point.latitude) && (-180...180).contains(point.longitude)
        }
    }

    private func persist(_ routes: [SavedRoute]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(routes).write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }
}
