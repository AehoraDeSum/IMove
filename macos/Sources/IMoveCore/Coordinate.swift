import Foundation

public struct Coordinate: Equatable, Sendable {
    public let latitude: Double
    public let longitude: Double

    public init(latitude: String, longitude: String) throws {
        func parse(_ value: String) -> Double? {
            let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: ",", with: ".")
            guard let number = Double(normalized), number.isFinite else { return nil }
            return number
        }
        guard let lat = parse(latitude), (-90...90).contains(lat) else {
            throw IMoveError.message("Latitude must be a number between −90 and 90.")
        }
        guard let lon = parse(longitude), (-180...180).contains(lon) else {
            throw IMoveError.message("Longitude must be a number between −180 and 180.")
        }
        self.latitude = lat
        self.longitude = lon
    }

    public var label: String {
        String(format: "%.6f, %.6f", locale: Locale(identifier: "en_US_POSIX"), latitude, longitude)
    }
}

public enum IMoveError: LocalizedError {
    case message(String)
    public var errorDescription: String? {
        switch self { case .message(let message): return message }
    }
}

public struct Device: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let version: String

    public init(id: String, name: String, version: String) {
        self.id = id
        self.name = name
        self.version = version
    }
}

public enum USBCommand {
    public static var list: [String] { ["--no-color", "usbmux", "list", "--usb", "--simple"] }
    public static func mountDeveloperImage(deviceID: String) -> [String] {
        ["--no-color", "mounter", "auto-mount", "--udid", deviceID]
    }
    public static func set(_ point: Coordinate, deviceID: String) -> [String] {
        ["--no-color", "developer", "simulate-location", "set", "--udid", deviceID,
         "--", String(point.latitude), String(point.longitude)]
    }
    public static func clear(deviceID: String) -> [String] {
        ["--no-color", "developer", "simulate-location", "clear", "--udid", deviceID]
    }

    public static func parseDevices(_ text: String) throws -> [Device] {
        guard let data = text.data(using: .utf8),
              let rows = try JSONSerialization.jsonObject(with: data) as? [String],
              rows.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            throw IMoveError.message("Could not read the USB tool's device list. Check the tool's version and installation.")
        }
        return Array(Set(rows)).sorted().map { Device(id: $0, name: "USB device", version: "Unverified") }
    }
}

public enum USBFailure {
    public static func explain(status: Int32, stdout: String, stderr: String) -> String {
        let diagnostic = (stderr.isEmpty ? stdout : stderr).trimmingCharacters(in: .whitespacesAndNewlines)
        if diagnostic.contains("Failed to start service") && diagnostic.contains("DeveloperDiskImage") {
            return "Could not start the developer service needed for location. With the iPhone selected on the Connection screen, press ‘Mount developer image’, then send the location again. On iOS 15, ignore the on-screen Developer Mode and RSD tunnel suggestions."
        }
        if diagnostic.contains("Traceback (most recent call last)") {
            return "The USB tool stopped with a Python error (\(status)). Open ‘Error details’ to see the exact cause; the important lines may be at the end of the output."
        }
        let excerpt = String(diagnostic.prefix(1000))
        return "The USB tool could not complete the operation (\(status)). \(excerpt.isEmpty ? "The tool gave no error details." : excerpt)"
    }
}
