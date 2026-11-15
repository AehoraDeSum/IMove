import Foundation
import Network
import Security
import SwiftUI
import IMoveCore

struct RemoteRequest {
    let method: String
    let path: String
    let headers: [String: String]
    let body: Data
}

enum RequestParseResult {
    case incomplete
    case request(RemoteRequest)
    case error(Int, String)
}

enum RemoteHTTP {
    static let port: UInt16 = 8765
    private static let separator = Data("\r\n\r\n".utf8)

    static func parse(_ data: Data) -> RequestParseResult {
        guard data.count <= 2_008_192 else { return .error(413, "Request too large.") }
        guard let range = data.range(of: separator) else {
            return data.count > 8_192 ? .error(431, "Headers too large.") : .incomplete
        }
        guard range.lowerBound <= 8_192,
              let head = String(data: data[..<range.lowerBound], encoding: .utf8) else {
            return .error(400, "Invalid HTTP header.")
        }
        let lines = head.components(separatedBy: "\r\n")
        guard let first = lines.first else { return .error(400, "Invalid request.") }
        let parts = first.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count == 3, parts[2] == "HTTP/1.1",
              (parts[0] == "GET" || parts[0] == "POST"),
              parts[1].first == "/", !parts[1].contains("?") else {
            return .error(400, "Unsupported request.")
        }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { return .error(400, "Invalid header.") }
            let name = line[..<colon].lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, headers[name] == nil else { return .error(400, "Duplicate header.") }
            headers[name] = value
        }
        guard headers["transfer-encoding"] == nil else { return .error(400, "Transfer encoding not supported.") }
        let length: Int
        if let raw = headers["content-length"] {
            guard let parsed = Int(raw), (0...2_000_000).contains(parsed) else {
                return .error(413, "Request body too large.")
            }
            length = parsed
        } else {
            length = 0
        }
        let body = data[range.upperBound...]
        guard body.count >= length else { return .incomplete }
        guard body.count == length else { return .error(400, "Only one request per connection is accepted.") }
        return .request(RemoteRequest(method: String(parts[0]), path: String(parts[1]), headers: headers, body: Data(body)))
    }

    static func response(_ status: Int, contentType: String, body: Data) -> Data {
        let reason: String
        switch status {
        case 200: reason = "OK"
        case 400: reason = "Bad Request"
        case 401: reason = "Unauthorized"
        case 404: reason = "Not Found"
        case 409: reason = "Conflict"
        case 413: reason = "Payload Too Large"
        case 431: reason = "Request Header Fields Too Large"
        case 502: reason = "Bad Gateway"
        default: reason = "Error"
        }
        let head = "HTTP/1.1 \(status) \(reason)\r\nContent-Type: \(contentType)\r\nContent-Length: \(body.count)\r\nConnection: close\r\nCache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\nReferrer-Policy: strict-origin-when-cross-origin\r\nContent-Security-Policy: default-src 'none'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data: https://tile.openstreetmap.org; frame-src 'self'; connect-src 'self'; form-action 'none'; base-uri 'none'; frame-ancestors 'self'\r\n\r\n"
        return Data(head.utf8) + body
    }

    static func json(_ status: Int, _ value: [String: Any]) -> Data {
        let body = (try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])) ?? Data("{}".utf8)
        return response(status, contentType: "application/json; charset=utf-8", body: body)
    }

    static func equalToken(_ candidate: String, _ expected: String) -> Bool {
        let left = Array(candidate.utf8)
        let right = Array(expected.utf8)
        guard left.count == right.count else { return false }
        var difference: UInt8 = 0
        for index in left.indices { difference |= left[index] ^ right[index] }
        return difference == 0
    }
}

private final class RemoteSession {
    let id = UUID()
    private let connection: NWConnection
    private let queue: DispatchQueue
    private let handler: (RemoteRequest, @escaping (Data) -> Void) -> Void
    private let finished: (UUID) -> Void
    private var buffer = Data()
    private var completed = false
    private let closeLock = NSLock()
    private var closed = false

    init(connection: NWConnection, queue: DispatchQueue,
         handler: @escaping (RemoteRequest, @escaping (Data) -> Void) -> Void,
         finished: @escaping (UUID) -> Void) {
        self.connection = connection
        self.queue = queue
        self.handler = handler
        self.finished = finished
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready: self.receive()
            case .failed, .cancelled: self.close()
            default: break
            }
        }
        connection.start(queue: queue)
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8_192) { [weak self] bytes, _, done, error in
            guard let self, !self.completed else { return }
            if let bytes { self.buffer.append(bytes) }
            switch RemoteHTTP.parse(self.buffer) {
            case .incomplete:
                if done || error != nil { self.close() }
                else { self.receive() }
            case .error(let status, let message):
                self.reply(RemoteHTTP.json(status, ["ok": false, "message": message]))
            case .request(let request):
                self.completed = true
                self.handler(request) { [weak self] response in self?.reply(response) }
            }
        }
    }

    private func reply(_ data: Data) {
        connection.send(content: data, completion: .contentProcessed { [weak self] _ in
            self?.close()
        })
    }

    func close() {
        closeLock.lock()
        let shouldClose = !closed
        closed = true
        closeLock.unlock()
        guard shouldClose else { return }
        connection.cancel()
        finished(id)
    }
}

@MainActor
final class RemoteServer: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var isStarting = false
    @Published private(set) var pairingCode = ""
    @Published private(set) var errorMessage: String?
    @Published private(set) var places: [SavedPlace] = []
    @Published private(set) var routes: [SavedRoute] = []

    private let queue = DispatchQueue(label: "local.imove.remote-http")
    private var listener: NWListener?
    private var sessions: [UUID: RemoteSession] = [:]
    private weak var model: AppModel?
    private var savedPlaces: SavedPlaces?
    private var savedRoutes: SavedRoutes?

    init() {
        do {
            savedPlaces = try SavedPlaces()
            places = savedPlaces?.all ?? []
            savedRoutes = try SavedRoutes()
            routes = savedRoutes?.all ?? []
        } catch {
            errorMessage = "Could not open saved places: \(error.localizedDescription)"
        }
    }

    @discardableResult
    func addPlace(name: String, coordinate: Coordinate) throws -> SavedPlace {
        if savedPlaces == nil { savedPlaces = try SavedPlaces() }
        let place = try savedPlaces!.add(name: name, coordinate: coordinate)
        places = savedPlaces?.all ?? []
        return place
    }

    func removePlace(id: UUID) throws {
        if savedPlaces == nil { savedPlaces = try SavedPlaces() }
        try savedPlaces?.remove(id: id)
        places = savedPlaces?.all ?? []
    }

    @discardableResult
    func addRoute(name: String, timingMode: RouteTimingMode,
                  segmentDurationsSeconds: [Int], points: [Coordinate],
                  segmentPaths: [[Coordinate]] = [], segmentDescriptions: [String] = []) throws -> SavedRoute {
        if savedRoutes == nil { savedRoutes = try SavedRoutes() }
        let route = try savedRoutes!.add(name: name, timingMode: timingMode,
                                         segmentDurationsSeconds: segmentDurationsSeconds, points: points,
                                         segmentPaths: segmentPaths,
                                         segmentDescriptions: segmentDescriptions)
        routes = savedRoutes?.all ?? []
        return route
    }

    func removeRoute(id: UUID) throws {
        guard model?.activeRouteID != id else {
            throw IMoveError.message("Stop the active route before deleting it.")
        }
        if savedRoutes == nil { savedRoutes = try SavedRoutes() }
        try savedRoutes?.remove(id: id)
        routes = savedRoutes?.all ?? []
    }

    func start(model: AppModel) {
        guard listener == nil else { return }
        do {
            pairingCode = try loadOrCreateToken()
            if savedPlaces == nil { savedPlaces = try SavedPlaces() }
            places = savedPlaces?.all ?? []
            if savedRoutes == nil { savedRoutes = try SavedRoutes() }
            routes = savedRoutes?.all ?? []
            self.model = model
            let port = NWEndpoint.Port(rawValue: RemoteHTTP.port)!
            let parameters = NWParameters.tcp
            parameters.requiredLocalEndpoint = .hostPort(host: NWEndpoint.Host("127.0.0.1"), port: port)
            let server = try NWListener(using: parameters)
            server.stateUpdateHandler = { [weak self] state in
                Task { @MainActor [weak self] in self?.update(state) }
            }
            server.newConnectionHandler = { [weak self] connection in
                Task { @MainActor [weak self] in self?.accept(connection) }
            }
            listener = server
            isStarting = true
            errorMessage = nil
            server.start(queue: queue)
        } catch {
            isStarting = false
            errorMessage = "Could not start the control page: \(error.localizedDescription)"
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        for session in sessions.values { session.close() }
        sessions.removeAll()
        isRunning = false
        isStarting = false
    }

    private func update(_ state: NWListener.State) {
        switch state {
        case .ready:
            isRunning = true
            isStarting = false
        case .failed(let error):
            errorMessage = "Could not open the control page: \(error.localizedDescription)"
            stop()
        case .cancelled:
            isRunning = false
            isStarting = false
        default: break
        }
    }

    private func accept(_ connection: NWConnection) {
        guard listener != nil else { connection.cancel(); return }
        let session = RemoteSession(connection: connection, queue: queue, handler: { [weak self] request, completion in
            Task { @MainActor [weak self] in
                let response = await self?.route(request) ?? RemoteHTTP.json(502, ["ok": false, "message": "Mac connection closed."])
                completion(response)
            }
        }, finished: { [weak self] id in
            Task { @MainActor [weak self] in self?.sessions.removeValue(forKey: id) }
        })
        sessions[session.id] = session
        session.start()
    }

    private func route(_ request: RemoteRequest) async -> Data {
        if request.method == "GET", request.path == "/" {
            return asset("Controller", extension: "html", contentType: "text/html; charset=utf-8")
        }
        if request.method == "GET", request.path == "/controller.js" {
            return asset("controller", extension: "js", contentType: "text/javascript; charset=utf-8")
        }
        if request.method == "GET", request.path == "/iphone-probe" {
            return asset("iPhoneProbe", extension: "html", contentType: "text/html; charset=utf-8")
        }
        if request.method == "GET", request.path == "/iphone-probe.js" {
            return asset("iphone-probe", extension: "js", contentType: "text/javascript; charset=utf-8")
        }
        if request.method == "GET", request.path == "/map" {
            return asset("Map", extension: "html", contentType: "text/html; charset=utf-8")
        }
        if request.method == "GET", request.path == "/map.js" {
            return asset("map", extension: "js", contentType: "text/javascript; charset=utf-8")
        }
        if request.method == "GET", request.path == "/leaflet.js" {
            return asset("leaflet", extension: "js", contentType: "text/javascript; charset=utf-8")
        }
        if request.method == "GET", request.path == "/leaflet.css" {
            return asset("leaflet", extension: "css", contentType: "text/css; charset=utf-8")
        }
        guard request.path.hasPrefix("/api/") else {
            return RemoteHTTP.json(404, ["ok": false, "message": "Page not found."])
        }
        guard RemoteHTTP.equalToken(request.headers["x-imove-token"] ?? "", pairingCode) else {
            return RemoteHTTP.json(401, ["ok": false, "message": "Incorrect pairing code."])
        }
        guard let model else {
            return RemoteHTTP.json(502, ["ok": false, "message": "The Mac app is not ready."])
        }
        if request.method == "GET", request.path == "/api/transit" {
            guard let url = Bundle.main.url(forResource: "istanbul-rail", withExtension: "json"),
                  let data = try? Data(contentsOf: url) else {
                return RemoteHTTP.json(500, ["ok": false, "message": "Istanbul line data not found."])
            }
            return RemoteHTTP.response(200, contentType: "application/json; charset=utf-8", body: data)
        }
        if request.method == "POST", request.path == "/api/route/walking" {
            guard request.headers["content-type"]?.lowercased().hasPrefix("application/json") == true,
                  let object = try? JSONSerialization.jsonObject(with: request.body) as? [String: Any],
                  let rawPoints = object["points"] as? [[String: Any]],
                  (2...10).contains(rawPoints.count) else {
                return RemoteHTTP.json(400, ["ok": false, "message": "Walking requires 2–10 points."])
            }
            do {
                let waypoints = try rawPoints.map { item -> Coordinate in
                    guard let latitude = item["latitude"], let longitude = item["longitude"] else {
                        throw IMoveError.message("Walking coordinate missing.")
                    }
                    return try Coordinate(latitude: String(describing: latitude), longitude: String(describing: longitude))
                }
                let (path, seconds) = try await WalkingRouter.calculate(waypoints)
                return RemoteHTTP.json(200, ["ok": true, "points": path.map { RouteWaypoint($0).response },
                                             "estimatedSeconds": seconds])
            } catch {
                return RemoteHTTP.json(400, ["ok": false, "message": "Could not get a walking route: \(error.localizedDescription)"])
            }
        }
        if request.method == "GET", request.path == "/api/status" {
            return RemoteHTTP.json(200, [
                "ok": true,
                "ready": model.transport == .usb && model.hasTarget,
                "busy": model.isBusy,
                "lastSent": model.lastCommand?.label ?? "",
                "refreshing": model.isMaintainingLocation,
                "renewOnSend": model.keepLocationActive,
                "updateIntervalSeconds": model.updateIntervalSeconds,
                "lastUSBSetDurationMs": model.lastSuccessfulUSBSetDurationSeconds.map { Int(($0 * 1_000).rounded()) as Any } ?? NSNull(),
                "verification": verificationResponse(model),
                "routeID": model.activeRouteID?.uuidString ?? "",
                "routeName": model.activeRouteName,
                "routeProgress": model.routeProgress,
                "routeSegmentIndex": model.routeSegmentIndex,
                "routeSegmentCount": model.routeSegmentCount,
                "message": model.status
            ])
        }
        if request.method == "POST", request.path == "/api/device-location" {
            guard model.transport == .usb else {
                return RemoteHTTP.json(409, ["ok": false, "message": "Select Real USB mode on the Mac first."])
            }
            guard request.headers["content-type"]?.lowercased().hasPrefix("application/json") == true,
                  let object = try? JSONSerialization.jsonObject(with: request.body) as? [String: Any],
                  let latitude = object["latitude"] as? NSNumber,
                  let longitude = object["longitude"] as? NSNumber,
                  let accuracy = object["horizontalAccuracy"] as? NSNumber,
                  let timestamp = object["timestamp"] as? NSNumber,
                  let source = object["source"] as? String else {
                return RemoteHTTP.json(400, ["ok": false, "message": "iPhone location report missing."])
            }
            do {
                let coordinate = try Coordinate(latitude: latitude.stringValue, longitude: longitude.stringValue)
                let report = try DeviceLocationReport(
                    coordinate: coordinate, horizontalAccuracy: accuracy.doubleValue,
                    measuredAt: Date(timeIntervalSince1970: timestamp.doubleValue),
                    receivedAt: Date(), source: source,
                    simulatedBySoftware: object["simulatedBySoftware"] as? Bool)
                model.recordDeviceLocation(report)
                return RemoteHTTP.json(200, ["ok": true, "verification": verificationResponse(model)])
            } catch {
                return RemoteHTTP.json(400, ["ok": false, "message": error.localizedDescription])
            }
        }
        if request.method == "POST", request.path == "/api/settings/interval" {
            guard request.headers["content-type"]?.lowercased().hasPrefix("application/json") == true,
                  let object = try? JSONSerialization.jsonObject(with: request.body) as? [String: Any],
                  let seconds = object["seconds"] as? Int else {
                return RemoteHTTP.json(400, ["ok": false, "message": "An interval of 1–60 seconds is required."])
            }
            do {
                try model.setUpdateIntervalSeconds(seconds)
                return RemoteHTTP.json(200, ["ok": true, "message": "Refresh interval set to \(seconds) seconds.",
                                             "updateIntervalSeconds": seconds])
            } catch {
                return RemoteHTTP.json(400, ["ok": false, "message": error.localizedDescription])
            }
        }
        if request.method == "POST", request.path == "/api/refresh/stop" {
            model.stopRefreshing()
            return RemoteHTTP.json(200, ["ok": true, "message": "Fixed location refresh stopped; the iPhone location was not cleared."])
        }
        if request.method == "GET", request.path == "/api/routes" {
            return RemoteHTTP.json(200, ["ok": true, "routes": routes.map(\.response)])
        }
        if request.method == "POST", request.path == "/api/routes" {
            guard request.headers["content-type"]?.lowercased().hasPrefix("application/json") == true,
                  let object = try? JSONSerialization.jsonObject(with: request.body) as? [String: Any],
                  let name = object["name"] as? String,
                  let rawPoints = object["points"] as? [[String: Any]],
                  rawPoints.count >= 2 else {
                return RemoteHTTP.json(400, ["ok": false, "message": "A route name and at least two points are required."])
            }
            do {
                let points = try rawPoints.map { item -> Coordinate in
                    guard let latitude = item["latitude"], let longitude = item["longitude"],
                          (latitude is NSNumber || latitude is String),
                          (longitude is NSNumber || longitude is String) else {
                        throw IMoveError.message("Invalid route coordinate.")
                    }
                    return try Coordinate(latitude: String(describing: latitude), longitude: String(describing: longitude))
                }
                let paths: [[Coordinate]]
                if let rawPaths = object["segmentPaths"] as? [[[String: Any]]] {
                    paths = try rawPaths.map { path in try path.map { item in
                        guard let latitude = item["latitude"], let longitude = item["longitude"] else {
                            throw IMoveError.message("Route path coordinate missing.")
                        }
                        return try Coordinate(latitude: String(describing: latitude), longitude: String(describing: longitude))
                    }}
                } else { paths = [] }
                let mode: RouteTimingMode
                let durations: [Int]
                if let rawMode = object["timingMode"] as? String,
                   let selectedMode = RouteTimingMode(rawValue: rawMode),
                   let values = object["segmentDurationsSeconds"] as? [Int] {
                    mode = selectedMode
                    durations = values
                } else if let minutes = object["minutesPerSegment"] as? Int,
                          (1...60).contains(minutes) {
                    mode = .equal
                    durations = Array(repeating: minutes * 60, count: points.count - 1)
                } else {
                    throw IMoveError.message("Invalid route timing.")
                }
                let route = try addRoute(name: name, timingMode: mode,
                                         segmentDurationsSeconds: durations, points: points,
                                         segmentPaths: paths,
                                         segmentDescriptions: object["segmentDescriptions"] as? [String] ?? [])
                return RemoteHTTP.json(200, ["ok": true, "message": "Route saved.", "route": route.response])
            } catch {
                return RemoteHTTP.json(400, ["ok": false, "message": error.localizedDescription])
            }
        }
        if request.method == "POST", request.path == "/api/routes/delete" {
            guard request.headers["content-type"]?.lowercased().hasPrefix("application/json") == true,
                  let object = try? JSONSerialization.jsonObject(with: request.body) as? [String: String],
                  let rawID = object["id"], let id = UUID(uuidString: rawID) else {
                return RemoteHTTP.json(400, ["ok": false, "message": "No valid route selected."])
            }
            do {
                try removeRoute(id: id)
                return RemoteHTTP.json(200, ["ok": true, "message": "Route deleted."])
            } catch {
                return RemoteHTTP.json(400, ["ok": false, "message": error.localizedDescription])
            }
        }
        if request.method == "POST", request.path == "/api/routes/start" {
            guard request.headers["content-type"]?.lowercased().hasPrefix("application/json") == true,
                  let object = try? JSONSerialization.jsonObject(with: request.body) as? [String: String],
                  let rawID = object["id"], let id = UUID(uuidString: rawID),
                  let route = routes.first(where: { $0.id == id }) else {
                return RemoteHTTP.json(404, ["ok": false, "message": "Saved route not found."])
            }
            do {
                guard model.transport == .usb else {
                    throw IMoveError.message("Turn on Real USB mode on the Mac to run routes.")
                }
                try await model.startRoute(route)
                return RemoteHTTP.json(200, ["ok": true, "message": "Route started. The first point was sent to the iPhone."])
            } catch {
                return RemoteHTTP.json(502, ["ok": false, "message": error.localizedDescription])
            }
        }
        if request.method == "POST", request.path == "/api/routes/stop" {
            await model.stopRoute()
            return RemoteHTTP.json(200, ["ok": true, "message": "Route progress stopped. The last location was not cleared."])
        }
        if request.method == "POST", request.path == "/api/tracking/activate" {
            await model.activateTracking()
            return RemoteHTTP.json(200, ["ok": true, "message": "Android tracking enabled."])
        }
        if request.method == "GET", request.path == "/api/places" {
            return RemoteHTTP.json(200, ["ok": true, "places": places.map(\.response)])
        }
        if request.method == "POST", request.path == "/api/places" {
            guard request.headers["content-type"]?.lowercased().hasPrefix("application/json") == true,
                  let object = try? JSONSerialization.jsonObject(with: request.body) as? [String: String],
                  let name = object["name"], let latitude = object["latitude"],
                  let longitude = object["longitude"] else {
                return RemoteHTTP.json(400, ["ok": false, "message": "A place name, latitude and longitude are required."])
            }
            do {
                let point = try Coordinate(latitude: latitude, longitude: longitude)
                let place = try addPlace(name: name, coordinate: point)
                return RemoteHTTP.json(200, ["ok": true, "message": "Place saved.", "place": place.response])
            } catch {
                return RemoteHTTP.json(400, ["ok": false, "message": error.localizedDescription])
            }
        }
        if request.method == "POST", request.path == "/api/places/delete" {
            guard request.headers["content-type"]?.lowercased().hasPrefix("application/json") == true,
                  let object = try? JSONSerialization.jsonObject(with: request.body) as? [String: String],
                  let rawID = object["id"], let id = UUID(uuidString: rawID) else {
                return RemoteHTTP.json(400, ["ok": false, "message": "No valid place selected."])
            }
            do {
                try removePlace(id: id)
                return RemoteHTTP.json(200, ["ok": true, "message": "Place deleted."])
            } catch {
                return RemoteHTTP.json(404, ["ok": false, "message": error.localizedDescription])
            }
        }
        if request.method == "POST", request.path == "/api/location" {
            if model.routeOwnsLocation, request.headers["x-imove-source"] == "tracking" {
                return RemoteHTTP.json(409, ["ok": false, "message": "The route location is kept; restarting tracking will take control."])
            }
            guard request.headers["content-type"]?.lowercased().hasPrefix("application/json") == true,
                  let object = try? JSONSerialization.jsonObject(with: request.body) as? [String: Any],
                  let latitude = object["latitude"] as? String,
                  let longitude = object["longitude"] as? String,
                  object["renew"] == nil || object["renew"] is Bool else {
                return RemoteHTTP.json(400, ["ok": false, "message": "Latitude and longitude are required."])
            }
            do {
                let point = try Coordinate(latitude: latitude, longitude: longitude)
                let renew = request.headers["x-imove-source"] == "tracking" ? false : object["renew"] as? Bool
                try await model.sendRemote(point, renew: renew)
                return RemoteHTTP.json(200, ["ok": true, "message": "Location sent to the iPhone. Verify it in Find My.", "coordinate": point.label])
            } catch {
                return RemoteHTTP.json(502, ["ok": false, "message": error.localizedDescription])
            }
        }
        if request.method == "POST", request.path == "/api/clear" {
            do {
                try await model.clearRemote()
                return RemoteHTTP.json(200, ["ok": true, "message": "Command to remove the simulated location sent."])
            } catch {
                return RemoteHTTP.json(502, ["ok": false, "message": error.localizedDescription])
            }
        }
        return RemoteHTTP.json(404, ["ok": false, "message": "Not found."])
    }

    private func verificationResponse(_ model: AppModel) -> [String: Any] {
        let result = model.locationVerification
        let report = model.latestDeviceLocation
        return [
            "state": result.state.rawValue,
            "message": result.message,
            "distanceMeters": result.distanceMeters.map { $0 as Any } ?? NSNull(),
            "coordinate": report?.coordinate.label ?? "",
            "horizontalAccuracy": report.map { $0.horizontalAccuracy as Any } ?? NSNull(),
            "measuredAt": report.map { $0.measuredAt.timeIntervalSince1970 as Any } ?? NSNull(),
            "source": report?.source ?? "",
            "simulatedBySoftware": report?.simulatedBySoftware.map { $0 as Any } ?? NSNull()
        ]
    }

    private func asset(_ name: String, extension suffix: String, contentType: String) -> Data {
        guard let url = Bundle.main.url(forResource: name, withExtension: suffix),
              let body = try? Data(contentsOf: url) else {
            return RemoteHTTP.json(502, ["ok": false, "message": "Control page file not found."])
        }
        return RemoteHTTP.response(200, contentType: contentType, body: body)
    }

    private func loadOrCreateToken() throws -> String {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("IMove", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("remote-token")
        if let existing = try? String(contentsOf: url, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
           existing.count == 32, existing.allSatisfy({ $0.isHexDigit }) {
            return existing
        }
        var bytes = [UInt8](repeating: 0, count: 16)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw IMoveError.message("Could not create a pairing code.")
        }
        let token = bytes.map { String(format: "%02x", $0) }.joined()
        try token.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return token
    }
}
