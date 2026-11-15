import AppKit
import SwiftUI
import IMoveCore

enum Transport: String, CaseIterable, Identifiable {
    case demo = "Test mode"
    case usb = "Real USB"
    var id: String { rawValue }
}

struct Activity: Identifiable {
    let id = UUID()
    let time = Date()
    let title: String
    let detail: String
    let symbol: String
    let isError: Bool
}

@MainActor
final class AppModel: ObservableObject {
    @Published var transport: Transport = .demo
    @Published var latitude = ""
    @Published var longitude = ""
    @Published var toolPath = ""
    @Published var devices: [Device] = []
    @Published var selectedDeviceID = ""
    @Published var isBusy = false
    @Published var keepLocationActive = false
    @Published private(set) var updateIntervalSeconds = 20
    @Published var simulateFailure = false
    @Published var status = "Choose your first location"
    @Published var detail = "In test mode no commands are sent to a physical device."
    @Published var lastCommand: Coordinate?
    @Published var lastCommandDate: Date?
    @Published private(set) var latestDeviceLocation: DeviceLocationReport?
    @Published private(set) var isMaintainingLocation = false
    @Published private(set) var lastRefreshDate: Date?
    @Published private(set) var refreshCount = 0
    @Published private(set) var lastSuccessfulUSBSetDurationSeconds: Double?
    @Published var errorMessage: String?
    @Published var errorDetails: String?
    @Published var activities: [Activity] = []
    @Published var scannedAt: Date?
    @Published var showResetConfirmation = false
    @Published private(set) var activeRouteID: UUID?
    @Published private(set) var activeRouteName = ""
    @Published private(set) var routeProgress = 0.0
    @Published private(set) var routeSegmentIndex = 0
    @Published private(set) var routeSegmentCount = 0
    @Published private(set) var routeOwnsLocation = false

    private var refreshInterval: TimeInterval
    private var routeTickInterval: TimeInterval
    private let connectionCheckInterval: TimeInterval
    private let preferences: HostPreferences?
    private var maintenanceTask: Task<Void, Never>?
    private var routeTask: Task<Void, Never>?
    private var connectionCheckTask: Task<Void, Never>?
    private var didRestoreConnection = false
    private var maintainedCoordinate: Coordinate?
    private var maintainedDeviceID = ""
    private var maintainedToolPath = ""
    private var consecutiveRefreshFailures = 0

    init(refreshInterval: TimeInterval = 20, routeTickInterval: TimeInterval = 20,
         connectionCheckInterval: TimeInterval = 30, preferences: HostPreferences? = nil) {
        self.refreshInterval = max(0.02, refreshInterval)
        self.routeTickInterval = max(0.02, routeTickInterval)
        self.connectionCheckInterval = max(0.02, connectionCheckInterval)
        self.preferences = preferences
        toolPath = HostPreferences.bundledToolPath ?? ""
        if let preferences {
            updateIntervalSeconds = preferences.updateIntervalSeconds
            self.refreshInterval = Double(updateIntervalSeconds)
            self.routeTickInterval = Double(updateIntervalSeconds)
        }
    }

    func restoreConnection() async {
        guard !didRestoreConnection else { return }
        didRestoreConnection = true
        guard let preferences, preferences.restoreUSBAtLaunch else { return }
        guard let target = preferences.restorableTarget else {
            status = "Could not open the saved USB target"
            detail = "Check the USB tool's location and execute permission, then select it again on the Connection screen."
            return
        }
        transport = .usb
        toolPath = target.toolPath
        selectedDeviceID = target.deviceID
        status = "Looking for the saved iPhone"
        detail = "No location command is sent until the connection is verified."
        await checkConnection()
        startConnectionChecks()
    }

    var coordinate: Coordinate? { try? Coordinate(latitude: latitude, longitude: longitude) }
    var validationMessage: String? {
        guard !latitude.isEmpty || !longitude.isEmpty else { return nil }
        do { _ = try Coordinate(latitude: latitude, longitude: longitude); return nil }
        catch { return error.localizedDescription }
    }
    var hasTarget: Bool {
        transport == .demo || (!toolPath.isEmpty && devices.contains { $0.id == selectedDeviceID })
    }
    var canSend: Bool { !isBusy && coordinate != nil && hasTarget }
    var locationVerification: LocationVerification {
        LocationVerification.evaluate(expected: lastCommand, sentAt: lastCommandDate,
                                      report: latestDeviceLocation, now: Date())
    }

    func recordDeviceLocation(_ report: DeviceLocationReport) {
        guard transport == .usb else { return }
        guard latestDeviceLocation.map({ report.measuredAt >= $0.measuredAt }) ?? true else { return }
        latestDeviceLocation = report
    }

    func changeTransport(_ mode: Transport) {
        guard !isBusy, mode != transport else { return }
        stopConnectionChecks()
        cancelRouteWithoutWaiting()
        routeOwnsLocation = false
        stopMaintenance()
        transport = mode
        if mode == .usb, let bundledTool = HostPreferences.bundledToolPath {
            toolPath = bundledTool
        }
        lastCommand = nil
        lastCommandDate = nil
        latestDeviceLocation = nil
        errorMessage = nil
        errorDetails = nil
        devices = []
        selectedDeviceID = ""
        scannedAt = nil
        status = mode == .demo ? "Choose your first location" : "Prepare the USB connection"
        detail = mode == .demo ? "In test mode no commands are sent to a physical device." : "Choose the tool and scan for USB devices. The iPhone's current location is not known yet."
        log("\(mode.rawValue) enabled", "Switching modes does not change the location on the iPhone.", "arrow.triangle.2.circlepath")
        if mode == .usb, !toolPath.isEmpty, !selectedDeviceID.isEmpty { startConnectionChecks() }
    }

    func chooseTool() {
        guard !isBusy else { return }
        let panel = NSOpenPanel()
        panel.title = "Choose the pymobiledevice3 executable"
        panel.message = "Choose the pymobiledevice3 executable to use instead of the bundled tool."
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        if panel.runModal() == .OK, let url = panel.url {
            guard url.lastPathComponent == "pymobiledevice3", FileManager.default.isExecutableFile(atPath: url.path) else {
                errorMessage = "You must choose an executable pymobiledevice3 file."
                return
            }
            cancelRouteWithoutWaiting()
            routeOwnsLocation = false
            stopMaintenance()
            toolPath = url.path
            preferences?.rememberTool(url.path)
            devices = []
            selectedDeviceID = ""
            stopConnectionChecks()
            scannedAt = nil
            lastCommand = nil
            lastCommandDate = nil
            latestDeviceLocation = nil
            status = "USB tool selected"
            detail = "Continue by scanning for devices."
            errorMessage = nil
            errorDetails = nil
        }
    }

    func selectDevice(_ id: String) {
        guard !isBusy, id != selectedDeviceID else { return }
        cancelRouteWithoutWaiting()
        routeOwnsLocation = false
        stopMaintenance()
        selectedDeviceID = id
        preferences?.rememberDevice(id)
        if id.isEmpty { stopConnectionChecks() }
        else { startConnectionChecks() }
        lastCommand = nil
        lastCommandDate = nil
        latestDeviceLocation = nil
        status = "Target device selected"
        detail = "The device's current location was not read. Make sure the target is your iPhone before sending."
    }

    func scan() async {
        await checkConnection()
    }

    func checkConnection() async {
        guard !isBusy, transport == .usb, !toolPath.isEmpty,
              activeRouteID == nil, !isMaintainingLocation else { return }
        let wasReady = hasTarget
        isBusy = true
        errorMessage = nil
        errorDetails = nil
        defer { isBusy = false }
        do {
            let result = try await execute(USBCommand.list)
            let found = try USBCommand.parseDevices(result.stdout)
            devices = found
            scannedAt = Date()
            if !selectedDeviceID.isEmpty, !hasTarget {
                status = "Waiting for the iPhone USB connection"
                detail = "The saved target was not found. Check the cable and screen lock; the connection will be retried automatically."
                if wasReady { log("iPhone disconnected", "No location command was sent; the target ID was kept.", "cable.connector", isError: true) }
            } else if !selectedDeviceID.isEmpty, hasTarget {
                if !wasReady {
                    status = "iPhone reconnected"
                    detail = "The target ID matched. Previous route or location commands were not restarted automatically."
                    log(status, "USB target verified; no location was sent.", "checkmark.circle")
                }
            } else {
                status = found.isEmpty ? "No USB device found" : "\(found.count) USB device(s) found"
                detail = found.isEmpty ? "Check the iPhone cable and scan again." : "Choose the target device. Being listed does not mean that pairing trust or the location service is ready."
            }
        } catch {
            devices = []
            scannedAt = nil
            fail(error)
        }
    }

    private func startConnectionChecks() {
        stopConnectionChecks()
        guard preferences != nil, transport == .usb, !toolPath.isEmpty, !selectedDeviceID.isEmpty else { return }
        connectionCheckTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                do { try await Task.sleep(nanoseconds: UInt64(self.connectionCheckInterval * 1_000_000_000)) }
                catch { return }
                await self.checkConnection()
            }
        }
    }

    private func stopConnectionChecks() {
        connectionCheckTask?.cancel()
        connectionCheckTask = nil
    }

    func mountDeveloperImage() async {
        guard !isBusy, transport == .usb, hasTarget else { return }
        guard activeRouteID == nil else {
            errorMessage = "Stop the route before mounting the developer image."
            return
        }
        isBusy = true
        errorMessage = nil
        errorDetails = nil
        status = "Mounting the developer image"
        detail = "The image may be downloaded if needed. Keep the iPhone connected over USB until this finishes."
        defer { isBusy = false }
        do {
            _ = try await execute(USBCommand.mountDeveloperImage(deviceID: selectedDeviceID), timeout: 300)
            status = "Mount completed"
            detail = "The USB tool finished successfully. Send the location again and check the result in Find My."
            log(status, "The developer image is ready for the selected USB device.", "checkmark.circle")
        } catch { fail(error) }
    }

    func send() async {
        if activeRouteID != nil { await stopRoute() }
        routeOwnsLocation = false
        guard canSend, let point = coordinate else { return }
        do { try await performSend(point) }
        catch { fail(error) }
    }

    func sendRemote(_ point: Coordinate, renew: Bool? = nil) async throws {
        if activeRouteID != nil { await stopRoute() }
        routeOwnsLocation = false
        guard transport == .usb, hasTarget else {
            throw IMoveError.message("The USB connection and target iPhone are not ready on the Mac.")
        }
        guard !isBusy else { throw IMoveError.message("The Mac is busy with another operation.") }
        if let renew { setKeepLocationActive(renew) }
        do { try await performSend(point) }
        catch { fail(error); throw error }
    }

    private func performSend(_ point: Coordinate) async throws {
        isBusy = true
        errorMessage = nil
        errorDetails = nil
        defer { isBusy = false }
        if transport == .demo { try await demoCommand() }
        else { try await sendUSBSet(point, deviceID: selectedDeviceID) }
        lastCommand = point
        lastCommandDate = Date()
        status = transport == .demo ? "Test location saved" : "Location command sent"
        detail = transport == .demo ? "Only the in-app test state changed. The iPhone was not contacted." : "The tool finished successfully. The iPhone location was not read back; verify it in Find My."
        log(status, "\(point.label) · \(transport.rawValue)", "location.fill")
        if transport == .usb {
            if keepLocationActive { startMaintenance(point) }
            else { stopMaintenance() }
        }
    }

    func clear() async {
        if activeRouteID != nil { await stopRoute() }
        routeOwnsLocation = false
        guard !isBusy, hasTarget else { return }
        do { try await performClear() }
        catch { fail(error) }
    }

    func clearRemote() async throws {
        if activeRouteID != nil { await stopRoute() }
        routeOwnsLocation = false
        guard transport == .usb, hasTarget else {
            throw IMoveError.message("The USB connection and target iPhone are not ready on the Mac.")
        }
        guard !isBusy else { throw IMoveError.message("The Mac is busy with another operation.") }
        do { try await performClear() }
        catch { fail(error); throw error }
    }

    private func performClear() async throws {
        stopMaintenance()
        isBusy = true
        errorMessage = nil
        errorDetails = nil
        defer { isBusy = false }
        if transport == .demo { try await demoCommand() }
        else { _ = try await execute(USBCommand.clear(deviceID: selectedDeviceID)) }
        lastCommand = nil
        lastCommandDate = Date()
        status = transport == .demo ? "Test location cleared" : "Clear command sent"
        detail = transport == .demo ? "The test returned to its initial state. No physical device was affected." : "The iPhone may return to its real location. Verify the result in Find My."
        log(status, transport.rawValue, "location.slash")
    }

    func startRoute(_ route: SavedRoute, segmentDurationOverride: TimeInterval? = nil) async throws {
        guard hasTarget else {
            throw IMoveError.message("Prepare the USB target first or choose test mode.")
        }
        guard !isBusy, activeRouteID == nil else {
            throw IMoveError.message("Stop the active route first or wait for the current operation to finish.")
        }
        stopMaintenance()
        keepLocationActive = false
        routeOwnsLocation = true
        activeRouteID = route.id
        activeRouteName = route.name
        routeProgress = 0
        routeSegmentIndex = 0
        routeSegmentCount = route.points.count - 1
        do {
            try await sendRouteCoordinate(route.points[0].coordinate, routeName: route.name)
        } catch {
            cancelRouteWithoutWaiting()
            routeOwnsLocation = false
            fail(error)
            throw error
        }
        guard activeRouteID == route.id else { return }
        routeTask = Task { [weak self] in
            guard let self else { return }
            await self.playRoute(route, segmentDurationOverride: segmentDurationOverride)
        }
        status = "Route started: \(route.name)"
        detail = "Moves linearly between points using the chosen durations. Verify in Find My."
        log(status, "\(route.points.count) points · total \(RouteTiming.label(route.totalDurationSeconds))", "point.topleft.down.to.point.bottomright.curvepath")
    }

    func stopRoute() async {
        guard activeRouteID != nil else { return }
        activeRouteID = nil
        activeRouteName = ""
        let task = routeTask
        task?.cancel()
        await task?.value
        routeTask = nil
        if transport == .usb, let point = lastCommand, hasTarget {
            keepLocationActive = true
            startMaintenance(point)
        }
        status = "Route stopped"
        detail = "Progress stopped. The last sent point is kept; a USB command in progress may still complete."
        log(status, "The last point was not cleared.", "pause.circle")
    }

    func activateTracking() async {
        if activeRouteID != nil { await stopRoute() }
        routeOwnsLocation = false
        stopMaintenance()
        keepLocationActive = false
        status = "Android tracking active"
        detail = "The phone's 5-minute location relay has taken control again."
    }

    private func playRoute(_ route: SavedRoute, segmentDurationOverride: TimeInterval?) async {
        let totalDuration = segmentDurationOverride.map { $0 * Double(route.segmentDurationsSeconds.count) }
            ?? Double(route.totalDurationSeconds)
        var previousDuration: TimeInterval = 0
        for segment in 0..<(route.points.count - 1) {
            let segmentDuration = max(0.02, segmentDurationOverride ?? Double(route.segmentDurationsSeconds[segment]))
            let started = ProcessInfo.processInfo.systemUptime
            while activeRouteID == route.id && !Task.isCancelled {
                let elapsed = ProcessInfo.processInfo.systemUptime - started
                let remaining = segmentDuration - elapsed
                if remaining > 0 {
                    do { try await Task.sleep(nanoseconds: UInt64(min(routeTickInterval, remaining) * 1_000_000_000)) }
                    catch { return }
                }
                guard activeRouteID == route.id, !Task.isCancelled else { return }
                let fraction = min(1, (ProcessInfo.processInfo.systemUptime - started) / segmentDuration)
                let point = route.segmentPaths.isEmpty
                    ? RouteGeometry.interpolate(from: route.points[segment], to: route.points[segment + 1], fraction: fraction)
                    : RouteGeometry.interpolate(path: route.segmentPaths[segment], fraction: fraction)
                do { try await sendRouteCoordinate(point, routeName: route.name) }
                catch {
                    guard activeRouteID == route.id, !Task.isCancelled else { return }
                    cancelRouteWithoutWaiting()
                    fail(error)
                    detail = "The route stopped on a USB error. Check the iPhone connection; the last location's state on the device is unknown."
                    return
                }
                guard activeRouteID == route.id, !Task.isCancelled else { return }
                routeSegmentIndex = segment + 1
                routeProgress = min(1, (previousDuration + fraction * segmentDuration) / totalDuration)
                if fraction >= 1 { break }
            }
            previousDuration += segmentDuration
        }
        guard activeRouteID == route.id, !Task.isCancelled else { return }
        activeRouteID = nil
        activeRouteName = ""
        routeTask = nil
        routeProgress = 1
        if transport == .usb, let point = lastCommand {
            keepLocationActive = true
            startMaintenance(point)
        }
        status = "Route completed: \(route.name)"
        detail = "The last point is kept. You can stop USB auto-refresh on the Location screen."
        log(status, "\(route.points.count) points completed.", "checkmark.circle")
    }

    private func sendRouteCoordinate(_ point: Coordinate, routeName: String) async throws {
        isBusy = true
        errorMessage = nil
        errorDetails = nil
        defer { isBusy = false }
        if transport == .demo { try await demoCommand() }
        else { try await sendUSBSet(point, deviceID: selectedDeviceID) }
        lastCommand = point
        lastCommandDate = Date()
        status = "Route in progress: \(routeName)"
        detail = "Last sent: \(point.label). The iPhone location was not read back."
    }

    private func cancelRouteWithoutWaiting() {
        routeTask?.cancel()
        routeTask = nil
        activeRouteID = nil
        activeRouteName = ""
        routeProgress = 0
        routeSegmentIndex = 0
        routeSegmentCount = 0
    }

    func stopRefreshing() {
        keepLocationActive = false
        guard isMaintainingLocation else { return }
        stopMaintenance()
        status = "Auto-refresh stopped"
        detail = "The simulated location on the iPhone was not cleared; it may return to the real location after a while. Check Find My."
        log(status, "Refresh stopped; no clear command was sent.", "pause.circle")
    }

    func setKeepLocationActive(_ enabled: Bool) {
        keepLocationActive = enabled
        if !enabled { stopRefreshing() }
    }

    func setUpdateIntervalSeconds(_ seconds: Int) throws {
        guard (1...60).contains(seconds) else {
            throw IMoveError.message("The refresh interval must be 1–60 seconds.")
        }
        updateIntervalSeconds = seconds
        refreshInterval = Double(seconds)
        routeTickInterval = Double(seconds)
        preferences?.updateIntervalSeconds = seconds
        if isMaintainingLocation, let point = maintainedCoordinate { startMaintenance(point) }
    }

    private func startMaintenance(_ point: Coordinate) {
        stopMaintenance()
        maintainedCoordinate = point
        maintainedDeviceID = selectedDeviceID
        maintainedToolPath = toolPath
        lastRefreshDate = nil
        refreshCount = 0
        consecutiveRefreshFailures = 0
        isMaintainingLocation = true
        detail = "The command will be resent at most every \(updateIntervalSeconds) seconds. Keep the Mac and USB connection on; verify in Find My."
        maintenanceTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                do { try await Task.sleep(nanoseconds: UInt64(self.refreshInterval * 1_000_000_000)) }
                catch { return }
                guard !Task.isCancelled else { return }
                await self.refreshLocation()
            }
        }
    }

    private func refreshLocation() async {
        guard isMaintainingLocation, !isBusy, transport == .usb,
              let point = maintainedCoordinate,
              !maintainedDeviceID.isEmpty,
              selectedDeviceID == maintainedDeviceID,
              toolPath == maintainedToolPath else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            try await sendUSBSet(point, deviceID: maintainedDeviceID)
            guard isMaintainingLocation else { return }
            let now = Date()
            lastCommand = point
            lastCommandDate = now
            lastRefreshDate = now
            refreshCount += 1
            consecutiveRefreshFailures = 0
            errorMessage = nil
            errorDetails = nil
            status = "Location is refreshing regularly"
            detail = "The last command was sent successfully. The iPhone location was not read back; verify it in Find My."
            if refreshCount == 1 || refreshCount.isMultiple(of: 10) {
                log("Location refreshed", "\(point.label) · refresh #\(refreshCount)", "arrow.clockwise")
            }
        } catch {
            consecutiveRefreshFailures += 1
            fail(error)
            if consecutiveRefreshFailures >= 3 {
                stopMaintenance()
                status = "Auto-refresh paused"
                detail = "Three refreshes failed. Check the iPhone lock and USB connection, then send the location again."
                log(status, "Three consecutive USB errors", "pause.circle", isError: true)
            } else {
                detail = "Refresh failed; the next attempt is in at least \(updateIntervalSeconds) seconds. Check the iPhone lock and USB connection."
            }
        }
    }

    private func stopMaintenance() {
        maintenanceTask?.cancel()
        maintenanceTask = nil
        isMaintainingLocation = false
        maintainedCoordinate = nil
        maintainedDeviceID = ""
        maintainedToolPath = ""
        consecutiveRefreshFailures = 0
    }

    private func execute(_ arguments: [String], timeout: TimeInterval = 20) async throws -> ProcessOutput {
        let output = try await ProcessRunner.run(executable: URL(fileURLWithPath: toolPath), arguments: arguments, timeout: timeout)
        guard output.status == 0 else {
            let raw = output.stderr.isEmpty ? output.stdout : output.stderr
            errorDetails = "Exit code: \(output.status)\n\n" + raw
            throw IMoveError.message(USBFailure.explain(status: output.status, stdout: output.stdout, stderr: output.stderr))
        }
        return output
    }

    private func sendUSBSet(_ point: Coordinate, deviceID: String) async throws {
        let started = ProcessInfo.processInfo.systemUptime
        _ = try await execute(USBCommand.set(point, deviceID: deviceID))
        lastSuccessfulUSBSetDurationSeconds = ProcessInfo.processInfo.systemUptime - started
    }

    private func demoCommand() async throws {
        try await Task.sleep(nanoseconds: 450_000_000)
        if simulateFailure { throw IMoveError.message("Test connection lost. This result is generated to try out error handling.") }
    }

    private func fail(_ error: Error) {
        errorMessage = error.localizedDescription
        status = "The operation could not be completed"
        detail = transport == .demo ? "The last successful test operation was kept." : "The device's actual state is unknown. The last command record is not proof of the current location."
        log(status, error.localizedDescription, "exclamationmark.triangle", isError: true)
    }

    private func log(_ title: String, _ detail: String, _ symbol: String, isError: Bool = false) {
        activities.insert(Activity(title: title, detail: detail, symbol: symbol, isError: isError), at: 0)
        if activities.count > 50 { activities.removeLast(activities.count - 50) }
    }
}
