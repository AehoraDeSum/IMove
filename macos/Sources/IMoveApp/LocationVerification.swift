import Foundation
import IMoveCore

struct DeviceLocationReport: Equatable {
    let coordinate: Coordinate
    let horizontalAccuracy: Double
    let measuredAt: Date
    let receivedAt: Date
    let source: String
    let simulatedBySoftware: Bool?

    init(coordinate: Coordinate, horizontalAccuracy: Double, measuredAt: Date,
         receivedAt: Date, source: String, simulatedBySoftware: Bool?) throws {
        guard horizontalAccuracy.isFinite, (0...2_000).contains(horizontalAccuracy),
              (-120...10).contains(measuredAt.timeIntervalSince(receivedAt)),
              source == "safari" || source == "ios-app" else {
            throw IMoveError.message("The iPhone location report is invalid or too old.")
        }
        self.coordinate = coordinate
        self.horizontalAccuracy = horizontalAccuracy
        self.measuredAt = measuredAt
        self.receivedAt = receivedAt
        self.source = source
        self.simulatedBySoftware = simulatedBySoftware
    }
}

struct LocationVerification: Equatable {
    enum State: String {
        case noReport, noCommand, stale, waiting, lowAccuracy, matching, different
    }

    let state: State
    let distanceMeters: Double?
    let message: String

    static func evaluate(expected: Coordinate?, sentAt: Date?, report: DeviceLocationReport?,
                         now: Date) -> LocationVerification {
        guard let report else {
            return .init(state: .noReport, distanceMeters: nil,
                         message: "No location reading has arrived from the iPhone yet.")
        }
        guard now.timeIntervalSince(report.receivedAt) <= 30,
              now.timeIntervalSince(report.measuredAt) <= 45 else {
            return .init(state: .stale, distanceMeters: nil,
                         message: "The iPhone location reading is out of date.")
        }
        guard let expected, let sentAt else {
            return .init(state: .noCommand, distanceMeters: nil,
                         message: "There is no sent location to compare with.")
        }
        guard report.measuredAt.timeIntervalSince(sentAt) >= -1 else {
            return .init(state: .waiting, distanceMeters: nil,
                         message: "Waiting for an iPhone reading taken after the last USB command.")
        }
        guard report.horizontalAccuracy <= 100 else {
            return .init(state: .lowAccuracy, distanceMeters: nil,
                         message: "iPhone location accuracy is low; waiting for a new reading.")
        }
        let distance = meters(from: expected, to: report.coordinate)
        let tolerance = max(75, report.horizontalAccuracy * 2)
        if distance <= tolerance {
            return .init(state: .matching, distanceMeters: distance,
                         message: "The iPhone's Core Location reading matches the sent location (about \(Int(distance.rounded())) m apart).")
        }
        return .init(state: .different, distanceMeters: distance,
                     message: "The iPhone's Core Location reading is about \(Int(distance.rounded())) m away from the sent location.")
    }

    static func meters(from start: Coordinate, to end: Coordinate) -> Double {
        let radians = Double.pi / 180
        let latitudeDelta = (end.latitude - start.latitude) * radians
        let longitudeDelta = (end.longitude - start.longitude) * radians
        let a = pow(sin(latitudeDelta / 2), 2) +
            cos(start.latitude * radians) * cos(end.latitude * radians) * pow(sin(longitudeDelta / 2), 2)
        return 6_371_000 * 2 * atan2(sqrt(a), sqrt(max(0, 1 - a)))
    }
}
