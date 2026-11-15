import Foundation
import IMoveCore

struct RailCatalogue: Decodable {
    let source: String
    let lines: [RailLine]

    static func load() -> RailCatalogue? {
        guard let url = Bundle.main.url(forResource: "istanbul-rail", withExtension: "json"),
              let catalogue = try? load(from: url) else { return nil }
        return catalogue
    }

    static func load(from url: URL) throws -> RailCatalogue {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(Self.self, from: data)
    }
}

struct RailLine: Decodable, Identifiable {
    let id: String
    let name: String
    let stations: [RailStation]

    func section(from start: Int, to end: Int) -> [(Coordinate, Coordinate, [Coordinate], String)]? {
        guard stations.indices.contains(start), stations.indices.contains(end), start != end else { return nil }
        let indices = start < end ? Array(start..<end) : Array((end..<start).reversed())
        let sections = indices.compactMap { index -> (Coordinate, Coordinate, [Coordinate], String)? in
            let a = start < end ? stations[index] : stations[index + 1]
            let b = start < end ? stations[index + 1] : stations[index]
            let source = stations[index].pathToNext ?? []
            let path = (start < end ? source : source.reversed()).compactMap { values -> Coordinate? in
                guard values.count == 2 else { return nil }
                return try? Coordinate(latitude: String(values[0]), longitude: String(values[1]))
            }
            guard path.count >= 2 else { return nil }
            return (a.coordinate, b.coordinate, path,
                    "\(id) · \(a.name) → \(b.name)" + (stations[index].geometryApproximate == true ? " · approximate path" : ""))
        }
        return sections.count == indices.count ? sections : nil
    }
}

struct RailStation: Decodable, Identifiable {
    let id: String
    let name: String
    let latitude: Double
    let longitude: Double
    let pathToNext: [[Double]]?
    let geometryApproximate: Bool?

    var coordinate: Coordinate {
        try! Coordinate(latitude: String(latitude), longitude: String(longitude))
    }
}
