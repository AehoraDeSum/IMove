import Foundation
import IMoveCore

struct SavedPlace: Codable, Equatable {
    let id: UUID
    let name: String
    let latitude: Double
    let longitude: Double

    var response: [String: Any] {
        ["id": id.uuidString, "name": name, "latitude": latitude, "longitude": longitude]
    }
}

@MainActor
final class SavedPlaces {
    private(set) var all: [SavedPlace]
    private let file: URL
    private static let maximumCount = 50

    static var defaultFile: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("IMove", isDirectory: true)
            .appendingPathComponent("saved-places.json")
    }

    init(file: URL? = nil) throws {
        let file = file ?? Self.defaultFile
        self.file = file
        let folder = file.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path)
        if FileManager.default.fileExists(atPath: file.path) {
            let loaded = try JSONDecoder().decode([SavedPlace].self, from: Data(contentsOf: file))
            guard loaded.count <= Self.maximumCount,
                  Set(loaded.map(\.id)).count == loaded.count,
                  loaded.allSatisfy({ place in
                      !place.name.isEmpty && place.name.count <= 50 &&
                      place.latitude.isFinite && place.longitude.isFinite &&
                      (-90...90).contains(place.latitude) && (-180...180).contains(place.longitude)
                  }) else {
                throw IMoveError.message("The saved places file is invalid. Check the file.")
            }
            all = loaded
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        } else {
            all = []
        }
    }

    @discardableResult
    func add(name rawName: String, coordinate: Coordinate) throws -> SavedPlace {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 50,
              !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw IMoveError.message("Place names must be 1–50 characters.")
        }
        guard all.count < Self.maximumCount else {
            throw IMoveError.message("You can save up to 50 places.")
        }
        guard !all.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
            throw IMoveError.message("A place with this name already exists.")
        }
        let place = SavedPlace(id: UUID(), name: name,
                               latitude: coordinate.latitude, longitude: coordinate.longitude)
        let next = all + [place]
        try persist(next)
        all = next
        return place
    }

    func remove(id: UUID) throws {
        guard all.contains(where: { $0.id == id }) else {
            throw IMoveError.message("Saved place not found.")
        }
        let next = all.filter { $0.id != id }
        try persist(next)
        all = next
    }

    private func persist(_ places: [SavedPlace]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(places).write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }
}
