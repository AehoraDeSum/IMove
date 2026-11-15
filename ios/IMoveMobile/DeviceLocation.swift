import Combine
import CoreLocation
import Foundation

final class DeviceLocation: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var point: Point?
    @Published private(set) var tracking = false
    @Published private(set) var permission: CLAuthorizationStatus = .notDetermined
    @Published private(set) var message = ""

    var onTrackingPoint: ((Point) -> Void)?
    var onTrackingStopped: (() -> Void)?
    private let manager = CLLocationManager()
    private var pending: CheckedContinuation<Point, Error>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        permission = manager.authorizationStatus
    }

    func currentPoint() async throws -> Point {
        guard CLLocationManager.locationServicesEnabled() else {
            throw APIError.server("Location Services are off on this device.")
        }
        if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted {
            throw APIError.server("Turn on location access for IMove in Settings.")
        }
        return try await withCheckedThrowingContinuation { continuation in
            if let pending { pending.resume(throwing: APIError.server("A new location reading has started.")) }
            pending = continuation
            if manager.authorizationStatus == .notDetermined {
                manager.requestWhenInUseAuthorization()
            } else {
                manager.requestLocation()
            }
        }
    }

    @discardableResult
    func startTracking() -> Bool {
        guard CLLocationManager.locationServicesEnabled() else {
            message = "Location Services are off."
            return false
        }
        guard manager.authorizationStatus != .denied && manager.authorizationStatus != .restricted else {
            message = "Turn on location access for IMove in Settings."
            return false
        }
        tracking = true
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 25
        manager.pausesLocationUpdatesAutomatically = false
        manager.allowsBackgroundLocationUpdates = true
        if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() }
        if manager.authorizationStatus == .authorizedWhenInUse { manager.requestAlwaysAuthorization() }
        manager.startUpdatingLocation()
        return true
    }

    func stopTracking() {
        tracking = false
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        onTrackingStopped?()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        permission = manager.authorizationStatus
        if permission == .denied || permission == .restricted {
            message = "Location permission was not granted."
            stopTracking()
            pending?.resume(throwing: APIError.server(message))
            pending = nil
        }
        if tracking && permission == .authorizedWhenInUse { manager.requestAlwaysAuthorization() }
        if pending != nil && (permission == .authorizedWhenInUse || permission == .authorizedAlways) {
            manager.requestLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last, location.horizontalAccuracy >= 0 else { return }
        let value = Point(location.coordinate.latitude, location.coordinate.longitude)
        guard value.isValid else { return }
        point = value
        if let pending {
            pending.resume(returning: value)
            self.pending = nil
        }
        if tracking { onTrackingPoint?(value) }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        message = error.localizedDescription
        pending?.resume(throwing: error)
        pending = nil
    }
}
