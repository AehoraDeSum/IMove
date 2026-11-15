import Foundation

@main
struct CoreSmoke {
    static func main() async throws {
        precondition(IMoveValidation.endpoint("https://mac.tailnet.ts.net") != nil)
        precondition(IMoveValidation.endpoint("http://mac.tailnet.ts.net") == nil)
        precondition(IMoveValidation.endpoint("https://mac.tailnet.ts.net:8765") == nil)
        precondition(IMoveValidation.endpoint("https://mac.tailnet.ts.net/evil") == nil)
        precondition(IMoveValidation.endpoint("https://mac.ts.net.evil.com") == nil)
        precondition(IMoveValidation.pairingCode(String(repeating: "a", count: 32)) != nil)
        precondition(IMoveValidation.pairingCode(String(repeating: "z", count: 32)) == nil)
        precondition(IMoveValidation.point(latitude: "41,0082", longitude: "28,9784") != nil)
        precondition(IMoveValidation.point(latitude: "91", longitude: "0") == nil)
        precondition(IMoveValidation.equalDurations(totalSeconds: 10, segments: 3) == [4, 3, 3])
        if CommandLine.arguments.count > 1 {
            let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
            let catalogue = try JSONDecoder().decode(Catalogue.self, from: data)
            precondition(Set(catalogue.lines.map(\.id)) == Set(["B1", "M2", "M6"]))
            precondition(catalogue.lines.allSatisfy { $0.stations.count > 2 })
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let connection = Connection(address: "https://mac.tailnet.ts.net",
                                    code: String(repeating: "a", count: 32))!
        let api = IMoveAPI(connection: connection, session: session)
        let status = try await api.status()
        precondition(status.ready && status.updateIntervalSeconds == 20)
        precondition(status.sentPoint == Point(41, 29))
        precondition(MockURLProtocol.lastPath == "/api/status")
        precondition(MockURLProtocol.lastToken == String(repeating: "a", count: 32))
        let places = try await api.places()
        precondition(places.count == 1 && places[0].name == "Ev")
        _ = try await api.send(Point(41.0, 29.0), renew: true)
        precondition(MockURLProtocol.lastPath == "/api/location")
        precondition(MockURLProtocol.lastMethod == "POST")
        precondition(MockURLProtocol.lastBody?["latitude"] as? String == "41.0")
        precondition(MockURLProtocol.lastBody?["renew"] as? Bool == true)
        try await api.saveRoute(name: "Deneme", points: [Point(41, 29), Point(41.1, 29.1)],
                                durations: [75], paths: [[Point(41, 29), Point(41.05, 29.05), Point(41.1, 29.1)]],
                                descriptions: ["Hand-edited path"], timingMode: "custom")
        precondition(MockURLProtocol.lastPath == "/api/routes")
        precondition(MockURLProtocol.lastBody?["timingMode"] as? String == "custom")
        precondition((MockURLProtocol.lastBody?["segmentPaths"] as? [[[String: Double]]])?.first?.count == 3)
        print("IMove iOS core checks passed.")
    }
}

private struct Catalogue: Decodable { let lines: [TransitLine] }

private final class MockURLProtocol: URLProtocol {
    static var lastPath = ""
    static var lastToken = ""
    static var lastMethod = ""
    static var lastBody: [String: Any]?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lastPath = request.url?.path ?? ""
        Self.lastToken = request.value(forHTTPHeaderField: "X-IMove-Token") ?? ""
        Self.lastMethod = request.httpMethod ?? ""
        let body: Data?
        if let direct = request.httpBody {
            body = direct
        } else if let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 4096)
            var collected = Data()
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                collected.append(contentsOf: buffer.prefix(count))
            }
            body = collected
        } else {
            body = nil
        }
        if let body {
            Self.lastBody = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
        }
        let json: String
        switch Self.lastPath {
        case "/api/status":
            json = #"{"ready":true,"busy":false,"lastSent":"41.000000, 29.000000","refreshing":false,"renewOnSend":true,"updateIntervalSeconds":20,"routeID":"","routeName":"","routeProgress":0,"routeSegmentIndex":0,"routeSegmentCount":0,"message":"Ready"}"#
        case "/api/places":
            json = #"{"places":[{"id":"9DCC4E3B-9E47-4FDF-88A9-2CBAE28F91C5","name":"Ev","latitude":41,"longitude":29}]}"#
        default:
            json = #"{"ok":true,"message":"Sent"}"#
        }
        let data = Data(json.utf8)
        let response = HTTPURLResponse(url: request.url!, statusCode: 200,
                                       httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
