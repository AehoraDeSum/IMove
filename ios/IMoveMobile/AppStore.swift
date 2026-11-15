import Combine
import Foundation

@MainActor
final class AppStore: ObservableObject {
    @Published private(set) var connection: Connection?
    @Published private(set) var status: ServerStatus?
    @Published private(set) var places: [Place] = []
    @Published private(set) var routes: [SavedRoute] = []
    @Published private(set) var transit: [TransitLine] = []
    @Published var selectedPoint: Point?
    @Published private(set) var lastSentPoint: Point?
    @Published private(set) var message = "Pair with your Mac to get started."
    @Published private(set) var working = false
    @Published private(set) var tracking = false

    let deviceLocation = DeviceLocation()
    private var lastTrackingSend = Date.distantPast
    private var polling: Task<Void, Never>?
    private var trackingTimer: Task<Void, Never>?

    init() {
        let address = UserDefaults.standard.string(forKey: "serverAddress") ?? ""
        let code = PairingKeychain.read() ?? ""
        connection = Connection(address: address, code: code)
        if let latitude = UserDefaults.standard.object(forKey: "lastLatitude") as? Double,
           let longitude = UserDefaults.standard.object(forKey: "lastLongitude") as? Double {
            lastSentPoint = Point(latitude, longitude)
        }
        deviceLocation.onTrackingPoint = { [weak self] point in
            Task { @MainActor in await self?.acceptTrackingPoint(point) }
        }
        deviceLocation.onTrackingStopped = { [weak self] in
            Task { @MainActor in
                self?.tracking = false
                self?.trackingTimer?.cancel()
                self?.trackingTimer = nil
            }
        }
        if connection != nil { startPolling() }
    }

    var address: String { connection?.baseURL.absoluteString ?? "" }

    private var api: IMoveAPI? { connection.map { IMoveAPI(connection: $0) } }

    func connect(address: String, code: String) async {
        guard let candidate = Connection(address: address, code: code) else {
            message = APIError.invalidConnection.localizedDescription
            return
        }
        working = true
        defer { working = false }
        do {
            let remote = try await IMoveAPI(connection: candidate).status()
            guard PairingKeychain.save(candidate.code) else {
                throw APIError.server("Could not save the pairing code to secure storage.")
            }
            UserDefaults.standard.set(candidate.baseURL.absoluteString, forKey: "serverAddress")
            connection = candidate
            status = remote
            lastSentPoint = remote.sentPoint
            message = remote.message
            startPolling()
            await refreshAll()
        } catch {
            message = "Could not connect: \(error.localizedDescription)"
        }
    }

    func disconnect() {
        stopTracking()
        polling?.cancel()
        polling = nil
        PairingKeychain.delete()
        UserDefaults.standard.removeObject(forKey: "serverAddress")
        connection = nil
        status = nil
        places = []
        routes = []
        transit = []
        lastSentPoint = nil
        selectedPoint = nil
        UserDefaults.standard.removeObject(forKey: "lastLatitude")
        UserDefaults.standard.removeObject(forKey: "lastLongitude")
        message = "Pairing removed."
    }

    func refreshAll() async {
        guard let api else { return }
        do {
            async let statusResult = api.status()
            async let placesResult = api.places()
            async let routesResult = api.routes()
            status = try await statusResult
            lastSentPoint = status?.sentPoint
            places = try await placesResult
            routes = try await routesResult
        } catch {
            message = error.localizedDescription
        }
    }

    func loadTransit() async {
        guard let api, transit.isEmpty else { return }
        do { transit = try await api.transit() }
        catch { message = error.localizedDescription }
    }

    func perform(_ operation: @escaping (IMoveAPI) async throws -> Void) async -> Bool {
        guard let api else { message = APIError.missingConnection.localizedDescription; return false }
        working = true
        defer { working = false }
        do {
            try await operation(api)
            message = "Done."
            await refreshAll()
            return true
        } catch {
            message = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func send(_ point: Point, renew: Bool = true) async -> Bool {
        guard point.isValid else { message = "Choose a valid coordinate."; return false }
        let done = await perform { api in _ = try await api.send(point, renew: renew) }
        if done { recordSent(point) }
        return done
    }

    func sendDeviceLocation() async {
        do {
            let point = try await deviceLocation.currentPoint()
            _ = await send(point)
        } catch { message = error.localizedDescription }
    }

    func startTracking() async {
        guard let api else { message = APIError.missingConnection.localizedDescription; return }
        do {
            try await api.activateTracking()
            tracking = true
            lastTrackingSend = .distantPast
            guard deviceLocation.startTracking() else {
                tracking = false
                message = deviceLocation.message
                return
            }
            trackingTimer?.cancel()
            trackingTimer = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 300_000_000_000)
                    if Task.isCancelled { break }
                    await self?.sendFreshTrackingLocation()
                }
            }
            message = "Device tracking is on. iOS will update the location when it can."
        } catch { message = error.localizedDescription }
    }

    func stopTracking() {
        tracking = false
        trackingTimer?.cancel()
        trackingTimer = nil
        deviceLocation.stopTracking()
        message = "Device tracking stopped."
    }

    private func sendFreshTrackingLocation() async {
        guard tracking else { return }
        do {
            let point = try await deviceLocation.currentPoint()
            await acceptTrackingPoint(point)
        } catch { message = "Could not get tracking location: \(error.localizedDescription)" }
    }

    private func acceptTrackingPoint(_ point: Point) async {
        guard tracking, let api, Date().timeIntervalSince(lastTrackingSend) >= 300 else { return }
        lastTrackingSend = Date()
        do {
            _ = try await api.send(point, renew: false, tracking: true)
            recordSent(point)
            message = "Device location sent: \(point.label)"
            status = try? await api.status()
            lastSentPoint = status?.sentPoint
        } catch {
            message = "Tracking send failed: \(error.localizedDescription)"
        }
    }

    private func recordSent(_ point: Point) {
        lastSentPoint = point
        selectedPoint = point
        UserDefaults.standard.set(point.latitude, forKey: "lastLatitude")
        UserDefaults.standard.set(point.longitude, forKey: "lastLongitude")
    }

    private func startPolling() {
        polling?.cancel()
        polling = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshStatus()
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
    }

    private func refreshStatus() async {
        guard let api else { return }
        status = try? await api.status()
        lastSentPoint = status?.sentPoint
    }
}
