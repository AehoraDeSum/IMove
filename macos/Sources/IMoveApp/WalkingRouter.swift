import Foundation
import MapKit
import IMoveCore

enum WalkingRouter {
    static func calculate(_ waypoints: [Coordinate]) async throws -> (path: [Coordinate], seconds: Int) {
        guard (2...10).contains(waypoints.count) else {
            throw IMoveError.message("Walking requires 2–10 points.")
        }
        do { return try await calculateWithMapKit(waypoints) }
        catch {
            do { return try await calculateWithValhalla(waypoints) }
            catch {
                throw IMoveError.message("No online walking path was found. Check your connection and the chosen waypoints.")
            }
        }
    }

    private static func calculateWithMapKit(_ waypoints: [Coordinate]) async throws -> (path: [Coordinate], seconds: Int) {
        var path = [waypoints[0]]
        var seconds = 0.0
        let pointsPerLeg = max(40, 1_500 / (waypoints.count - 1))
        for (start, end) in zip(waypoints, waypoints.dropFirst()) {
            let request = MKDirections.Request()
            request.source = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(
                latitude: start.latitude, longitude: start.longitude)))
            request.destination = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(
                latitude: end.latitude, longitude: end.longitude)))
            request.transportType = .walking
            let response = try await MKDirections(request: request).calculate()
            guard let route = response.routes.first else {
                throw IMoveError.message("No walking route was found between these points.")
            }
            let raw = route.polyline.points()
            let stride = max(1, (route.polyline.pointCount + pointsPerLeg - 1) / pointsPerLeg)
            for index in Swift.stride(from: 0, to: route.polyline.pointCount, by: stride) {
                let point = raw[index].coordinate
                path.append(try Coordinate(latitude: String(point.latitude), longitude: String(point.longitude)))
            }
            path.append(end)
            seconds += route.expectedTravelTime
        }
        guard path.count <= 2_000 else { throw IMoveError.message("Walking path too long.") }
        return (path, Int(seconds.rounded()))
    }

    private static func calculateWithValhalla(_ waypoints: [Coordinate]) async throws -> (path: [Coordinate], seconds: Int) {
        let url = URL(string: "https://valhalla1.openstreetmap.de/route")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("imove-personal-experiment", forHTTPHeaderField: "X-Client-Id")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "locations": waypoints.map { ["lat": $0.latitude, "lon": $0.longitude] },
            "costing": "pedestrian"])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200,
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let trip = object["trip"] as? [String: Any],
              let summary = trip["summary"] as? [String: Any],
              let seconds = summary["time"] as? Double,
              let legs = trip["legs"] as? [[String: Any]], !legs.isEmpty else {
            throw IMoveError.message("The fallback walking service returned no route.")
        }
        var path = [waypoints[0]]
        let pointsPerLeg = max(40, 1_500 / legs.count)
        for leg in legs {
            guard let shape = leg["shape"] as? String else {
                throw IMoveError.message("Walking path missing.")
            }
            let decoded = try decodePolyline6(shape)
            let stride = max(1, (decoded.count + pointsPerLeg - 1) / pointsPerLeg)
            path.append(contentsOf: Swift.stride(from: 0, to: decoded.count, by: stride).map { decoded[$0] })
            if let last = decoded.last { path.append(last) }
        }
        path.append(waypoints[waypoints.count - 1])
        guard path.count <= 2_000 else { throw IMoveError.message("Walking path too long.") }
        return (path, max(1, Int(seconds.rounded())))
    }

    static func decodePolyline6(_ shape: String) throws -> [Coordinate] {
        let bytes = Array(shape.utf8)
        var index = 0
        var latitude = 0
        var longitude = 0
        var points: [Coordinate] = []
        func component() throws -> Int {
            var value = 0
            var shift = 0
            while index < bytes.count && shift <= 30 {
                let byte = Int(bytes[index]) - 63
                index += 1
                guard byte >= 0 else { break }
                value |= (byte & 0x1f) << shift
                if byte < 0x20 { return (value & 1) != 0 ? ~(value >> 1) : value >> 1 }
                shift += 5
            }
            throw IMoveError.message("Could not decode the walking path.")
        }
        while index < bytes.count {
            latitude += try component()
            longitude += try component()
            points.append(try Coordinate(latitude: String(Double(latitude) / 1_000_000),
                                         longitude: String(Double(longitude) / 1_000_000)))
            guard points.count <= 20_000 else { throw IMoveError.message("Walking path too long.") }
        }
        guard points.count >= 2 else { throw IMoveError.message("Walking path is empty.") }
        return points
    }
}
