import SwiftUI
import CoreLocation
import Security

@main
struct IMoveProbeApp: App {
    @StateObject private var reporter = LocationReporter()
    @AppStorage("imoveProbeEndpoint") private var endpoint = ""
    @State private var code = ProbeKeychain.load() ?? ""

    var body: some Scene {
        WindowGroup {
            NavigationView {
                Form {
                    Section(header: Text("Mac connection")) {
                        TextField("https://your-mac…ts.net", text: $endpoint)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                        SecureField("32-character pairing code", text: $code)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button(reporter.isRunning ? "Stop reading" : "Start reading") {
                            if reporter.isRunning { reporter.stop() }
                            else { reporter.start(endpoint: endpoint, code: code) }
                        }
                    }
                    Section(header: Text("iPhone reading")) {
                        Text(reporter.status)
                        if let location = reporter.lastLocation {
                            Text(String(format: "%.6f, %.6f · ±%.0f m", location.coordinate.latitude,
                                        location.coordinate.longitude, location.horizontalAccuracy))
                                .font(.system(.body, design: .monospaced))
                            Text(location.timestamp, style: .time).foregroundColor(.secondary)
                            if let simulated = location.sourceInformation?.isSimulatedBySoftware {
                                Text(simulated ? "Source: simulated by software" : "Source: no simulation flag")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    Section {
                        Text("This app reports the iPhone's Core Location result to the Mac. A match does not confirm what the other person sees in Find My.")
                        Text("For regular background readings, set Location access to Always and do not close the app from the app switcher. iOS may delay readings.")
                    }
                }
                .navigationTitle("IMove Probe")
            }
        }
    }
}

private enum ProbeKeychain {
    private static let account = "imove-iphone-probe-token"

    static func load() -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrAccount as String: account,
                                    kSecReturnData as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func save(_ value: String) -> Bool {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrAccount as String: account]
        SecItemDelete(query as CFDictionary)
        var attributes = query
        attributes[kSecValueData as String] = Data(value.utf8)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
    }
}

final class LocationReporter: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var isRunning = false
    @Published private(set) var status = "Reading not started."
    @Published private(set) var lastLocation: CLLocation?

    private let manager = CLLocationManager()
    private var destination: URL?
    private var code = ""
    private var lastReport = Date.distantPast

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = kCLDistanceFilterNone
        manager.activityType = .other
        manager.pausesLocationUpdatesAutomatically = false
    }

    func start(endpoint: String, code: String) {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count == 32, trimmed.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "0123456789abcdefABCDEF").contains($0) }) else {
            status = "Enter the Mac's 32-character pairing code."
            return
        }
        guard var components = URLComponents(string: endpoint.trimmingCharacters(in: .whitespacesAndNewlines)),
              components.scheme == "https", components.host?.hasSuffix(".ts.net") == true,
              components.user == nil, components.password == nil,
              components.path.isEmpty || components.path == "/" else {
            status = "Enter the private Tailscale HTTPS address (https://…ts.net)."
            return
        }
        components.path = "/api/device-location"
        components.query = nil
        guard let url = components.url else { status = "Invalid HTTPS address."; return }
        guard ProbeKeychain.save(trimmed) else { status = "Could not store the pairing code securely."; return }
        destination = url
        self.code = trimmed
        lastReport = .distantPast
        lastLocation = nil
        isRunning = true
        switch manager.authorizationStatus {
        case .notDetermined:
            status = "Waiting for location permission…"
            manager.requestAlwaysAuthorization()
        case .denied, .restricted:
            status = "Turn on Location access for IMove in Settings."
            isRunning = false
        default:
            beginUpdates()
        }
    }

    private func beginUpdates() {
        guard isRunning else { return }
        manager.allowsBackgroundLocationUpdates = true
        manager.startUpdatingLocation()
        status = manager.authorizationStatus == .authorizedAlways
            ? "Reading location; new readings will be reported to the Mac."
            : "Reading location. Allow Always access in Settings to keep it running on the lock screen."
    }

    func stop() {
        manager.stopUpdatingLocation()
        isRunning = false
        status = "Reading stopped."
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard isRunning else { return }
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse: beginUpdates()
        case .denied, .restricted: stop(); status = "Location permission denied."
        default: break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard isRunning, let location = locations.last,
              location.horizontalAccuracy >= 0,
              abs(location.timestamp.timeIntervalSinceNow) <= 60 else { return }
        lastLocation = location
        guard Date().timeIntervalSince(lastReport) >= 5 else { return }
        lastReport = Date()
        status = "Location read; reporting to the Mac…"
        send(location)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if isRunning {
            let issue = error as NSError
            status = "Could not read the iPhone location: \(issue.localizedDescription) (\(issue.domain), code \(issue.code)). Waiting for a new reading."
        }
    }

    private func send(_ location: CLLocation) {
        guard let destination else { return }
        var payload: [String: Any] = [
            "latitude": location.coordinate.latitude,
            "longitude": location.coordinate.longitude,
            "horizontalAccuracy": location.horizontalAccuracy,
            "timestamp": location.timestamp.timeIntervalSince1970,
            "source": "ios-app"
        ]
        if let simulated = location.sourceInformation?.isSimulatedBySoftware {
            payload["simulatedBySoftware"] = simulated
        }
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return }
        var request = URLRequest(url: destination)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(code, forHTTPHeaderField: "X-IMove-Token")
        request.httpBody = body
        request.timeoutInterval = 15
        var backgroundTask = UIBackgroundTaskIdentifier.invalid
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "IMove location report") {
            UIApplication.shared.endBackgroundTask(backgroundTask)
        }
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                defer { UIApplication.shared.endBackgroundTask(backgroundTask) }
                guard let self, self.isRunning else { return }
                if let error { self.status = "Mac connection: \(error.localizedDescription)"; return }
                guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                      let data,
                      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let verification = object["verification"] as? [String: Any],
                      let message = verification["message"] as? String else {
                    self.status = "The Mac rejected the report; check the address and code."
                    return
                }
                self.status = message
            }
        }.resume()
    }
}
