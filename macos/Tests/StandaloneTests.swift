import Foundation
import IMoveCore

private struct CheckFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

private func check(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
    guard try condition() else { throw CheckFailure(message: message) }
}

private func expectThrow(_ message: String, _ operation: () throws -> Void) throws {
    do { try operation() } catch { return }
    throw CheckFailure(message: message)
}

private struct Fixture {
    let directory: URL
    let executable: URL

    init(_ body: String, name: String = "fixture") throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("imove-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        executable = directory.appendingPathComponent(name)
        do {
            let script = body.replacingOccurrences(of: "__FIXTURE_DIR__", with: directory.path)
            try ("#!/bin/sh\n" + script + "\n").write(to: executable, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    func remove() { try? FileManager.default.removeItem(at: directory) }
}

@main
@MainActor
struct StandaloneTests {
    static func main() async {
        let tests: [(String, @MainActor () async throws -> Void)] = [
            ("Inclusive coordinate boundaries", { try coordinateBoundaries() }),
            ("Turkish decimal comma and whitespace", { try decimalComma() }),
            ("Invalid and nonfinite coordinates", { try invalidCoordinates() }),
            ("Out-of-range coordinates", { try outOfRangeCoordinates() }),
            ("Set: explicit UDID and negative argument delimiter", { try setArguments() }),
            ("Clear: explicit UDID", { try clearArguments() }),
            ("Developer image: explicit UDID", { try mountArguments() }),
            ("Developer service failure has actionable guidance", { try serviceFailureGuidance() }),
            ("Python traceback is summarized without losing raw details", { try tracebackGuidance() }),
            ("List: USB simple output", { try listArguments() }),
            ("Parse valid identifier array", { try parseIdentifiers() }),
            ("Parse no devices", { try parseNoDevices() }),
            ("Reject malformed device output", { try rejectDeviceOutput() }),
            ("Literal process arguments", { try await literalArguments() }),
            ("Process environment cannot override USB target", { try await isolatedUSBEnvironment() }),
            ("Separate stdout/stderr and nonzero exit", { try await processOutput() }),
            ("Process timeout", { try await processTimeout() }),
            ("Large output without deadlock or truncation", { try await largeOutput() }),
            ("Reject missing executable", { try await missingExecutable() }),
            ("Model defaults to demo with send disabled", { try modelDefaults() }),
            ("Model demo send succeeds", { try await modelDemoSend() }),
            ("Model failure preserves last successful command", { try await modelFailure() }),
            ("Model demo clear succeeds", { try await modelClear() }),
            ("Model transport change invalidates target and command", { try await modelTransport() }),
            ("Model invalid input produces no activity", { try await modelInvalidInput() }),
            ("Model mounts developer image for selected device", { try await modelMountImage() }),
            ("Model retains complete failed mount diagnostic", { try await modelMountFailure() }),
            ("USB location is periodically resent and can be stopped", { try await modelMaintainsLocation() }),
            ("Repeated USB failures stop location renewal", { try await modelMaintenanceFailure() }),
            ("Remote HTTP parses fragmented, bounded requests", { try remoteHTTPParser() }),
            ("Remote pairing rejects incorrect codes", { try remotePairing() }),
            ("iPhone location readings compare only when fresh and accurate", { try locationVerification() }),
            ("Saved places persist and can be removed", { try savedPlacesPersistence() }),
            ("Saved places reject duplicate names and invalid names", { try savedPlacesValidation() }),
            ("Saved routes preserve custom timing and long routes", { try savedRoutesPersistence() }),
            ("Legacy routes migrate without changing their timing", { try legacyRouteMigration() }),
            ("Route interpolation follows the short dateline crossing", { try routeInterpolation() }),
            ("Bent route geometry survives reload and controls interpolation", { try routeGeometryPersistence() }),
            ("Pedestrian fallback decodes six-decimal route geometry", { try pedestrianPolyline() }),
            ("Bundled B1/M2/M6 catalogue has ordered, reversible station paths", { try railCatalogueGeometry() }),
            ("Demo route starts, reaches its final point, and stops", { try await modelRoutePlayback() }),
            ("Custom leg durations control route progress", { try await customRoutePlayback() }),
            ("USB route sends waypoints to the selected iPhone", { try await modelUSBRoutePlayback() }),
            ("Remote USB send and clear use the selected device", { try await modelRemoteCommands() }),
            ("Mac startup remembers the USB target and reconnects without sending", { try await restoredUSBTarget() }),
            ("Update interval validates and persists 1–60 seconds", { try updateIntervalSettings() }),
            ("Remote send can renew and stop the selected USB location", { try await remoteRenewal() })
        ]
        var passed = 0
        print("Running \(tests.count) IMove core tests")
        for (name, test) in tests {
            do {
                try await test()
                passed += 1
                print("PASS: \(name)")
            } catch {
                print("FAIL: \(name): \(error.localizedDescription)")
            }
        }
        print("Result: \(passed)/\(tests.count) passed")
        if passed != tests.count { exit(1) }
    }

    static func coordinateBoundaries() throws {
        for latitude in [-90.0, 0.0, 90.0] {
            for longitude in [-180.0, 0.0, 180.0] {
                let point = try Coordinate(latitude: String(latitude), longitude: String(longitude))
                try check(point.latitude == latitude && point.longitude == longitude, "Valid boundary changed")
            }
        }
    }

    static func savedPlacesPersistence() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("imove-places-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("places.json")
        let point = try Coordinate(latitude: "41.0082", longitude: "28.9784")
        let places = try SavedPlaces(file: file)
        let saved = try places.add(name: "  Home  ", coordinate: point)
        try check(saved.name == "Home", "Place name should be trimmed")
        try check(try SavedPlaces(file: file).all == [saved], "Saved place did not survive reload")
        try places.remove(id: saved.id)
        try check(try SavedPlaces(file: file).all.isEmpty, "Removed place survived reload")
    }

    static func savedPlacesValidation() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("imove-places-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let places = try SavedPlaces(file: directory.appendingPathComponent("places.json"))
        let point = try Coordinate(latitude: "0", longitude: "0")
        _ = try places.add(name: "Home", coordinate: point)
        try expectThrow("Duplicate place name accepted") { _ = try places.add(name: "home", coordinate: point) }
        try expectThrow("Blank place name accepted") { _ = try places.add(name: "  ", coordinate: point) }
        try expectThrow("Unknown place ID removed") { try places.remove(id: UUID()) }
        try check(places.all.count == 1, "Invalid operations modified saved places")
    }

    static func savedRoutesPersistence() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("imove-routes-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("routes.json")
        let a = try Coordinate(latitude: "41", longitude: "29")
        let b = try Coordinate(latitude: "40", longitude: "30")
        let routes = try SavedRoutes(file: file)
        let saved = try routes.add(name: "  Seaside  ", minutesPerSegment: 5, points: [a, b])
        try check(saved.name == "Seaside", "Route name should be trimmed")
        try check(try SavedRoutes(file: file).all == [saved], "Saved route did not survive reload")
        try check(RouteTiming.distributed(totalSeconds: 10, segments: 3) == [4, 3, 3], "Equal timing distribution changed")
        let longPoints = (0..<25).map { _ in a }
        let custom = try routes.add(name: "Long", timingMode: .custom,
                                    segmentDurationsSeconds: Array(1...24), points: longPoints)
        try check(custom.points.count == 25 && custom.segmentDurationsSeconds[23] == 24, "Long custom route changed")
        try check(try SavedRoutes(file: file).all.count == 2, "Custom route did not survive reload")
        try expectThrow("One-point route accepted") { _ = try routes.add(name: "Single", minutesPerSegment: 5, points: [a]) }
        try expectThrow("Duplicate route accepted") { _ = try routes.add(name: "seaside", minutesPerSegment: 5, points: [a, b]) }
        try expectThrow("Zero minute route accepted") { _ = try routes.add(name: "Quick", minutesPerSegment: 0, points: [a, b]) }
        try expectThrow("Wrong number of leg durations accepted") {
            _ = try routes.add(name: "Incomplete", timingMode: .custom, segmentDurationsSeconds: [60], points: [a, b, a])
        }
        try routes.remove(id: saved.id)
        try routes.remove(id: custom.id)
        try check(try SavedRoutes(file: file).all.isEmpty, "Removed route survived reload")
    }

    static func legacyRouteMigration() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("imove-legacy-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("routes.json")
        let legacy: [[String: Any]] = [["id": UUID().uuidString, "name": "Old route", "minutesPerSegment": 2,
                                        "points": [["latitude": 41, "longitude": 29], ["latitude": 40, "longitude": 30],
                                                   ["latitude": 39, "longitude": 31]]]]
        try JSONSerialization.data(withJSONObject: legacy).write(to: file)
        let route = try SavedRoutes(file: file).all[0]
        try check(route.timingMode == .equal && route.segmentDurationsSeconds == [120, 120], "Legacy timing changed")
    }

    static func routeInterpolation() throws {
        let east = RouteWaypoint(try Coordinate(latitude: "10", longitude: "179"))
        let west = RouteWaypoint(try Coordinate(latitude: "20", longitude: "-179"))
        let middle = RouteGeometry.interpolate(from: east, to: west, fraction: 0.5)
        try check(middle.latitude == 15, "Route latitude midpoint changed")
        try check(abs(middle.longitude) == 180, "Route took the long dateline path")
        try check(RouteGeometry.interpolate(from: east, to: west, fraction: 0).longitude == 179, "Route start changed")
        try check(RouteGeometry.interpolate(from: east, to: west, fraction: 1).longitude == -179, "Route end changed")
    }

    static func routeGeometryPersistence() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("imove-shaped-route-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("routes.json")
        let start = try Coordinate(latitude: "0", longitude: "0")
        let bend = try Coordinate(latitude: "0.01", longitude: "0")
        let end = try Coordinate(latitude: "0.01", longitude: "0.01")
        let store = try SavedRoutes(file: file)
        let saved = try store.add(name: "Walk", timingMode: .custom,
                                  segmentDurationsSeconds: [120], points: [start, end],
                                  segmentPaths: [[start, bend, end]],
                                  segmentDescriptions: ["Walk · follows streets"])
        let restored = try SavedRoutes(file: file).all[0]
        try check(restored == saved, "Shaped route did not survive reload")
        let midpoint = RouteGeometry.interpolate(path: restored.segmentPaths[0], fraction: 0.5)
        try check(midpoint.latitude > 0.009 && midpoint.longitude < 0.001,
                  "Route ignored the bend")
        try expectThrow("Mismatched path endpoints accepted") {
            _ = try store.add(name: "Broken", timingMode: .custom,
                              segmentDurationsSeconds: [120], points: [start, end],
                              segmentPaths: [[start, bend]], segmentDescriptions: ["Broken"])
        }
    }

    static func pedestrianPolyline() throws {
        let points = try WalkingRouter.decodePolyline6("_lajmAum{iv@qAcFs@gCeCpAkE|Bi@qB~AmYn@e@jMeHxDkBnAo@")
        try check(points.count > 5 && points.allSatisfy { (41...42).contains($0.latitude) &&
                  (29...30).contains($0.longitude) }, "Pedestrian polyline decoded at wrong precision")
        try expectThrow("Broken walking polyline accepted") { _ = try WalkingRouter.decodePolyline6("_") }
    }

    static func railCatalogueGeometry() throws {
        guard let path = ProcessInfo.processInfo.environment["IMOVE_RAIL_FILE"] else {
            throw IMoveError.message("Rail catalogue fixture missing")
        }
        let catalogue = try RailCatalogue.load(from: URL(fileURLWithPath: path))
        try check(catalogue.lines.map(\.id) == ["B1", "M2", "M6"], "Unexpected rail lines")
        try check(catalogue.lines.map { $0.stations.count } == [43, 15, 4], "Station catalogue changed")
        for line in catalogue.lines {
            for index in 0..<(line.stations.count - 1) {
                guard let forward = line.section(from: index, to: index + 1)?.first,
                      let reverse = line.section(from: index + 1, to: index)?.first else {
                    throw IMoveError.message("Rail path missing on \(line.id) \(index)")
                }
                try check(forward.2.first == forward.0 && forward.2.last == forward.1,
                          "Rail path does not start/end at its stations")
                try check(reverse.2 == Array(forward.2.reversed()), "Reverse rail path changed")
            }
        }
    }

    static func modelRoutePlayback() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("imove-route-play-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let routes = try SavedRoutes(file: directory.appendingPathComponent("routes.json"))
        let a = try Coordinate(latitude: "41", longitude: "29")
        let b = try Coordinate(latitude: "42", longitude: "30")
        let route = try routes.add(name: "Test", minutesPerSegment: 1, points: [a, b])
        let model = AppModel(routeTickInterval: 0.02)
        try await model.startRoute(route, segmentDurationOverride: 0.04)
        try check(model.activeRouteID == route.id, "Route did not start")
        try await Task.sleep(nanoseconds: 1_100_000_000)
        try check(model.activeRouteID == nil, "Route did not finish")
        try check(model.routeProgress == 1, "Route progress did not reach 100%")
        try check(model.lastCommand?.label == b.label, "Route did not reach final point")
        try check(model.routeOwnsLocation, "Completed route should protect its final point from stale tracking")
        await model.activateTracking()
        try check(!model.routeOwnsLocation, "Restarted tracking did not take control")
        try await model.startRoute(route, segmentDurationOverride: 5)
        await model.stopRoute()
        try check(model.activeRouteID == nil, "Stopped route remained active")
    }

    static func customRoutePlayback() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("imove-custom-play-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let routes = try SavedRoutes(file: directory.appendingPathComponent("routes.json"))
        let a = try Coordinate(latitude: "41", longitude: "29")
        let b = try Coordinate(latitude: "42", longitude: "30")
        let c = try Coordinate(latitude: "43", longitude: "31")
        let route = try routes.add(name: "Custom", timingMode: .custom,
                                   segmentDurationsSeconds: [1, 2], points: [a, b, c])
        let model = AppModel(routeTickInterval: 0.05)
        try await model.startRoute(route)
        try await Task.sleep(nanoseconds: 1_800_000_000)
        try check(model.routeProgress >= 1.0 / 3.0 && model.routeProgress < 0.8,
                  "Route progress ignored the custom leg durations")
        try await Task.sleep(nanoseconds: 2_700_000_000)
        try check(model.activeRouteID == nil && model.lastCommand?.label == c.label,
                  "Custom route did not reach its final point")
    }

    static func modelUSBRoutePlayback() async throws {
        let fixture = try Fixture("""
        if [ "$1" != "--no-color" ] || [ "$2" != "developer" ] || [ "$3" != "simulate-location" ] || [ "$4" != "set" ] || [ "$5" != "--udid" ] || [ "$6" != "iphone-6s" ]; then exit 7; fi
        printf '%s,%s\n' "$8" "$9" >> '__FIXTURE_DIR__/sent'
        """)
        defer { fixture.remove() }
        let routes = try SavedRoutes(file: fixture.directory.appendingPathComponent("routes.json"))
        let first = try Coordinate(latitude: "41", longitude: "29")
        let last = try Coordinate(latitude: "42", longitude: "30")
        let route = try routes.add(name: "USB", minutesPerSegment: 1, points: [first, last])
        let model = AppModel(refreshInterval: 5, routeTickInterval: 0.02)
        model.changeTransport(.usb)
        model.toolPath = fixture.executable.path
        model.devices = [Device(id: "iphone-6s", name: "USB device", version: "15.8.6")]
        model.selectDevice("iphone-6s")
        try await model.startRoute(route, segmentDurationOverride: 0.08)
        try await waitFor("USB route did not finish") { model.activeRouteID == nil }
        let lines = try String(contentsOf: fixture.directory.appendingPathComponent("sent"), encoding: .utf8)
            .split(separator: "\n").map(String.init)
        try check(lines.first == "41.0,29.0", "USB route first point changed")
        try check(lines.last == "42.0,30.0", "USB route final point changed")
        try check(model.selectedDeviceID == "iphone-6s", "USB route changed target device")
        try check(model.isMaintainingLocation, "USB route should keep the final point renewed")
        model.stopRefreshing()
    }

    static func decimalComma() throws {
        let point = try Coordinate(latitude: "  41,008238\n", longitude: "\t-28,978359 ")
        try check(abs(point.latitude - 41.008238) < 0.0000001, "Latitude comma was not parsed")
        try check(abs(point.longitude + 28.978359) < 0.0000001, "Longitude comma was not parsed")
        try check(point.label == "41.008238, -28.978359", "Label must use stable six-digit decimal formatting")
    }

    static func invalidCoordinates() throws {
        for input in ["", "  \n", "nan", "NaN", "inf", "-inf", "Infinity", "1e999", "abc", "12,3,4", "12.3.4", "40°"] {
            try expectThrow("Invalid latitude accepted: \(input)") { _ = try Coordinate(latitude: input, longitude: "0") }
            try expectThrow("Invalid longitude accepted: \(input)") { _ = try Coordinate(latitude: "0", longitude: input) }
        }
    }

    static func outOfRangeCoordinates() throws {
        for value in ["-90.000001", "90.000001"] {
            try expectThrow("Out-of-range latitude accepted") { _ = try Coordinate(latitude: value, longitude: "0") }
        }
        for value in ["-180.000001", "180.000001"] {
            try expectThrow("Out-of-range longitude accepted") { _ = try Coordinate(latitude: "0", longitude: value) }
        }
    }

    static func setArguments() throws {
        let point = try Coordinate(latitude: "-33,8688", longitude: "-151,2093")
        try check(USBCommand.set(point, deviceID: "chosen-iphone") == [
            "--no-color", "developer", "simulate-location", "set", "--udid", "chosen-iphone",
            "--", "-33.8688", "-151.2093"
        ], "Set must explicitly select the device before the argument delimiter")
    }

    static func clearArguments() throws {
        try check(USBCommand.clear(deviceID: "chosen-iphone") == [
            "--no-color", "developer", "simulate-location", "clear", "--udid", "chosen-iphone"
        ], "Clear must explicitly select the device")
    }

    static func mountArguments() throws {
        try check(USBCommand.mountDeveloperImage(deviceID: "chosen-iphone") == [
            "--no-color", "mounter", "auto-mount", "--udid", "chosen-iphone"
        ], "DDI mount must explicitly select the device")
    }

    static func serviceFailureGuidance() throws {
        let diagnostic = "Failed to start service. Possible reasons are:\nMake sure the DeveloperDiskImage/PersonalizedImage is mounted via mounter auto-mount."
        let message = USBFailure.explain(status: 1, stdout: "", stderr: diagnostic)
        try check(message.contains("Mount developer image"), "No recovery action in developer-service error")
        try check(!message.contains("Apple removed this service"), "Generic upstream diagnostic should not replace recovery guidance")
        let unrelated = USBFailure.explain(status: 5, stdout: "device disconnected", stderr: "")
        try check(unrelated.contains("device disconnected"), "Other errors should retain the tool's useful detail")
    }

    static func tracebackGuidance() throws {
        let diagnostic = "NotOpenSSLWarning: LibreSSL 2.8.3\n╭ Traceback (most recent call last) ╮\nRuntimeError: image not found"
        let message = USBFailure.explain(status: 1, stdout: "", stderr: diagnostic)
        try check(message.contains("Error details"), "Traceback should direct user to complete details")
        try check(!message.contains("LibreSSL 2.8.3"), "Warning must not be presented as the proven cause")
    }

    static func listArguments() throws {
        try check(USBCommand.list == ["--no-color", "usbmux", "list", "--usb", "--simple"], "List must request only USB identifiers")
    }

    static func parseIdentifiers() throws {
        let devices = try USBCommand.parseDevices("[\"first-device\", \"second-device\"]")
        try check(devices.map(\.id) == ["first-device", "second-device"], "Identifiers were not parsed")
    }

    static func parseNoDevices() throws {
        try check(try USBCommand.parseDevices("[]").isEmpty, "No devices must be represented by an empty list")
    }

    static func rejectDeviceOutput() throws {
        for input in ["", "not json", "null", "{}", "\"device\"", "[1]", "[null]", "[\"device\", 1]", "[{\"Identifier\":\"device\"}]", "[\"\"]", "[\"  \"]", "[\"device\", \"\"]"] {
            try expectThrow("Malformed output accepted: \(input)") { _ = try USBCommand.parseDevices(input) }
        }
    }

    static func literalArguments() async throws {
        let literal = "coordinate; $(echo expanded) 'quoted' $HOME"
        let result = try await ProcessRunner.run(executable: URL(fileURLWithPath: "/usr/bin/printf"), arguments: ["%s", literal])
        try check(result.status == 0, "printf failed")
        try check(result.stdout == literal && result.stderr.isEmpty, "Arguments were expanded or output changed")
    }

    static func processOutput() async throws {
        let fixture = try Fixture("printf 'normal output\\n'\nprintf 'diagnostic output\\n' >&2\nexit 7")
        defer { fixture.remove() }
        let result = try await ProcessRunner.run(executable: fixture.executable, arguments: [])
        try check(result.status == 7, "Nonzero exit status was lost")
        try check(result.stdout == "normal output\n", "stdout changed")
        try check(result.stderr == "diagnostic output\n", "stderr changed")
    }

    static func isolatedUSBEnvironment() async throws {
        let transportKeys = [
            "PYMOBILEDEVICE3_TUNNEL", "PYMOBILEDEVICE3_UDID", "PYMOBILEDEVICE3_USBMUX",
            "PYMOBILEDEVICE3_IMOVE_REGRESSION", "USBMUXD_SOCKET_ADDRESS"
        ]
        let ordinaryKey = "IMOVE_TEST_ORDINARY_ENV"
        let allKeys = transportKeys + [ordinaryKey]
        let originals = allKeys.map { key in
            (key: key, value: getenv(key).map { String(cString: $0) })
        }
        defer {
            for original in originals {
                if let value = original.value { setenv(original.key, value, 1) }
                else { unsetenv(original.key) }
            }
        }
        // Tests run sequentially; restore the parent's exact prior state even on failure.
        for key in transportKeys {
            try check(setenv(key, "imove-test-transport-override", 1) == 0, "Could not set regression environment variable")
        }
        try check(setenv(ordinaryKey, "ordinary-value-preserved", 1) == 0, "Could not set ordinary regression variable")
        let result = try await ProcessRunner.run(executable: URL(fileURLWithPath: "/usr/bin/env"), arguments: [])
        try check(result.status == 0, "Environment fixture failed")
        let lines = result.stdout.split(separator: "\n").map(String.init)
        for key in transportKeys {
            try check(!lines.contains(where: { $0.hasPrefix(key + "=") }), "Child inherited transport override: \(key)")
        }
        try check(lines.contains(ordinaryKey + "=ordinary-value-preserved"), "Ordinary environment variable was removed")
    }

    static func processTimeout() async throws {
        // exec replaces the shell, leaving no detached sleep subprocess behind.
        let fixture = try Fixture("exec /bin/sleep 10")
        defer { fixture.remove() }
        let start = Date()
        var timeoutError: Error?
        do { _ = try await ProcessRunner.run(executable: fixture.executable, arguments: [], timeout: 0.15) }
        catch { timeoutError = error }
        try check(timeoutError != nil, "Process exceeded timeout without an error")
        try check(timeoutError?.localizedDescription.contains("timed out") == true, "Expected timeout error")
        try check(Date().timeIntervalSince(start) < 5, "Timeout waited for normal process completion")
    }

    static func largeOutput() async throws {
        let fixture = try Fixture("""
        exec /usr/bin/awk 'BEGIN { for (i = 0; i < 8192; i++) { printf "%0127d\\n", 0; printf "%0127d\\n", 1 > "/dev/stderr" } }'
        """)
        defer { fixture.remove() }
        let result = try await ProcessRunner.run(executable: fixture.executable, arguments: [], timeout: 10)
        let stdoutLine = String(repeating: "0", count: 127) + "\n"
        let stderrLine = String(repeating: "0", count: 126) + "1\n"
        try check(result.status == 0, "Large output fixture failed")
        try check(result.stdout == String(repeating: stdoutLine, count: 8192), "1 MiB stdout was truncated or changed")
        try check(result.stderr == String(repeating: stderrLine, count: 8192), "1 MiB stderr was truncated or changed")
    }

    static func missingExecutable() async throws {
        var capturedError: Error?
        do {
            _ = try await ProcessRunner.run(executable: URL(fileURLWithPath: "/nonexistent-imove-\(UUID().uuidString)"), arguments: [])
        } catch { capturedError = error }
        try check(capturedError != nil, "Missing executable was not rejected")
    }

    static func modelDefaults() throws {
        let model = AppModel()
        try check(model.transport == .demo, "Fresh model must use demo mode")
        try check(model.latitude.isEmpty && model.longitude.isEmpty, "Fresh model must not invent coordinates")
        try check(!model.canSend && model.lastCommand == nil && model.activities.isEmpty, "Fresh state must have no sent command")
        try check(!model.keepLocationActive, "Automatic USB renewal must be opt-in")
    }

    static func preparedDemoModel() -> AppModel {
        let model = AppModel()
        model.latitude = "41,008238"
        model.longitude = "28,978359"
        return model
    }

    static func modelDemoSend() async throws {
        let model = preparedDemoModel()
        try check(model.canSend, "Valid demo coordinates must enable send")
        await model.send()
        try check(model.lastCommand == model.coordinate && model.lastCommandDate != nil, "Successful demo must record its coordinate and time")
        try check(model.errorMessage == nil && !model.isBusy, "Successful send must clear busy and error state")
        try check(model.activities.count == 1 && !model.activities[0].isError, "Successful send must produce one success activity")
    }

    static func modelFailure() async throws {
        let model = preparedDemoModel()
        await model.send()
        let previousCommand = model.lastCommand
        let previousDate = model.lastCommandDate
        model.latitude = "-33.8688"
        model.longitude = "151.2093"
        model.simulateFailure = true
        await model.send()
        try check(model.lastCommand == previousCommand && model.lastCommandDate == previousDate, "Failed operation must preserve the previous successful command")
        try check(model.errorMessage != nil && !model.isBusy, "Failed send must expose the error and release busy state")
        try check(model.activities.count == 2 && model.activities[0].isError, "Failure must appear as an error activity")
    }

    static func modelClear() async throws {
        let model = preparedDemoModel()
        await model.send()
        await model.clear()
        try check(model.lastCommand == nil && model.lastCommandDate != nil, "Successful clear must remove the coordinate and record its time")
        try check(!model.isBusy && model.errorMessage == nil, "Successful clear must finish without an error")
        try check(model.activities.count == 2 && !model.activities[0].isError, "Clear must produce a success activity")
    }

    static func modelTransport() async throws {
        let model = preparedDemoModel()
        await model.send()
        model.changeTransport(.usb)
        try check(model.transport == .usb, "Transport must switch to USB")
        try check(model.lastCommand == nil && model.lastCommandDate == nil, "Demo result must not carry into USB mode")
        try check(!model.hasTarget && !model.canSend && model.devices.isEmpty && model.selectedDeviceID.isEmpty, "USB mode must require an explicitly discovered target")
        // No send or scan occurs: the test never invokes a real USB executable.
    }

    static func restoredUSBTarget() async throws {
        let fixture = try Fixture("""
        if [ "$1" != "--no-color" ] || [ "$2" != "usbmux" ] || [ "$3" != "list" ]; then exit 7; fi
        if [ -f '__FIXTURE_DIR__/connected' ]; then printf '["iphone-6s"]'; else printf '[]'; fi
        """, name: "pymobiledevice3")
        defer { fixture.remove() }
        let suite = "local.imove.test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = HostPreferences(defaults: defaults)
        preferences.rememberTool(fixture.executable.path)
        preferences.rememberDevice("iphone-6s")
        preferences.restoreUSBAtLaunch = true
        preferences.startRemoteAtLaunch = true
        try check(preferences.restorableTarget?.deviceID == "iphone-6s", "Saved USB target was not loaded")
        try check(preferences.startRemoteAtLaunch, "Remote startup option was not saved")
        let model = AppModel(connectionCheckInterval: 0.06, preferences: preferences)
        await model.restoreConnection()
        try check(model.transport == .usb && model.selectedDeviceID == "iphone-6s", "Startup did not restore the USB choice")
        try check(!model.hasTarget && model.lastCommand == nil, "Missing iPhone was considered ready or received a command")
        try Data().write(to: fixture.directory.appendingPathComponent("connected"))
        try await waitFor("Automatic USB check did not notice reconnection") { model.hasTarget }
        try check(model.hasTarget && model.selectedDeviceID == "iphone-6s", "Reconnect did not recognize the same iPhone")
        try check(model.lastCommand == nil && model.activeRouteID == nil, "Reconnect replayed a location or route")
        try FileManager.default.removeItem(at: fixture.directory.appendingPathComponent("connected"))
        try await waitFor("Automatic USB check did not notice disconnection") { !model.hasTarget }
        try check(!model.hasTarget && model.selectedDeviceID == "iphone-6s", "Disconnect forgot the selected target")
    }

    static func updateIntervalSettings() throws {
        let suite = "local.imove.interval-test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = HostPreferences(defaults: defaults)
        try check(preferences.updateIntervalSeconds == 20, "Default interval must stay at 20 seconds")
        let model = AppModel(preferences: preferences)
        try model.setUpdateIntervalSeconds(1)
        try check(model.updateIntervalSeconds == 1 && preferences.updateIntervalSeconds == 1,
                  "One-second interval was not persisted")
        try expectThrow("Zero interval was accepted") { try model.setUpdateIntervalSeconds(0) }
        try expectThrow("Overlong interval was accepted") { try model.setUpdateIntervalSeconds(61) }
        try check(model.updateIntervalSeconds == 1, "Invalid interval changed the active value")
    }

    static func remoteRenewal() async throws {
        let fixture = try Fixture("""
        if [ "$4" != "set" ] || [ "$6" != "iphone-6s" ]; then exit 7; fi
        printf '%s %s\n' "$8" "$9" >> '__FIXTURE_DIR__/sent'
        """)
        defer { fixture.remove() }
        let model = AppModel(refreshInterval: 0.04)
        model.changeTransport(.usb)
        model.toolPath = fixture.executable.path
        model.devices = [Device(id: "iphone-6s", name: "USB device", version: "15.8.6")]
        model.selectDevice("iphone-6s")
        let first = try Coordinate(latitude: "41", longitude: "29")
        let second = try Coordinate(latitude: "42", longitude: "30")
        try await model.sendRemote(first, renew: true)
        try check(model.isMaintainingLocation, "Remote renewal did not start")
        try check(model.lastSuccessfulUSBSetDurationSeconds != nil, "USB command duration was not recorded")
        try await waitFor("Remote renewal did not repeat the USB command") { model.refreshCount > 0 }
        try await model.sendRemote(second, renew: false)
        try check(!model.isMaintainingLocation && !model.keepLocationActive,
                  "Single remote send did not stop the prior renewal")
        let lines = try String(contentsOf: fixture.directory.appendingPathComponent("sent"), encoding: .utf8)
            .split(separator: "\n").map(String.init)
        try check(lines.first == "41.0 29.0" && lines.last == "42.0 30.0", "Remote renewal used the wrong coordinates")
    }

    static func modelInvalidInput() async throws {
        let model = preparedDemoModel()
        model.latitude = "91"
        try check(!model.canSend && model.validationMessage != nil, "Invalid coordinates must disable send and explain why")
        await model.send()
        try check(model.activities.isEmpty && model.lastCommand == nil && model.lastCommandDate == nil, "Invalid input must not create a command or activity")
        try check(!model.isBusy, "Rejected input must not leave the model busy")
    }

    static func modelMountImage() async throws {
        let fixture = try Fixture("""
        if [ "$#" -ne 5 ] || [ "$1" != "--no-color" ] || [ "$2" != "mounter" ] || [ "$3" != "auto-mount" ] || [ "$4" != "--udid" ] || [ "$5" != "iphone-6s" ]; then
            printf 'wrong mount target\\n' >&2
            exit 7
        fi
        printf 'developer image mounted\\n'
        """)
        defer { fixture.remove() }
        let model = AppModel()
        model.changeTransport(.usb)
        model.toolPath = fixture.executable.path
        model.devices = [Device(id: "iphone-6s", name: "USB device", version: "15.8.6")]
        model.selectDevice("iphone-6s")
        await model.mountDeveloperImage()
        try check(model.status == "Mount completed", "Mount success was not shown")
        try check(model.errorMessage == nil && !model.isBusy, "Mount did not finish cleanly")
        try check(model.selectedDeviceID == "iphone-6s", "Mount changed the selected target")
        try check(model.lastCommand == nil, "Mount must not pretend a location was sent")
    }

    static func modelMountFailure() async throws {
        let fixture = try Fixture("printf 'NotOpenSSLWarning: LibreSSL 2.8.3\\nTraceback (most recent call last)\\nRuntimeError: image not found\\n' >&2\nexit 1")
        defer { fixture.remove() }
        let model = AppModel()
        model.changeTransport(.usb)
        model.toolPath = fixture.executable.path
        model.devices = [Device(id: "iphone-6s", name: "USB device", version: "15.8.6")]
        model.selectDevice("iphone-6s")
        await model.mountDeveloperImage()
        try check(model.errorMessage?.contains("Error details") == true, "Mount failure should show concise guidance")
        try check(model.errorDetails?.contains("RuntimeError: image not found") == true, "Mount failure lost final exception")
        try check(model.errorDetails?.contains("NotOpenSSLWarning") == true, "Mount failure lost original warning")
        try check(model.lastCommand == nil && !model.isBusy, "Failed mount must not update the location or remain busy")
    }

    static func waitFor(_ description: String, _ predicate: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(3)
        while !predicate() && Date() < deadline {
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        try check(predicate(), description)
    }

    static func modelMaintainsLocation() async throws {
        let fixture = try Fixture("""
        if [ "$1" = "--no-color" ] && [ "$2" = "developer" ] && [ "$3" = "simulate-location" ] && [ "$4" = "set" ] && [ "$5" = "--udid" ] && [ "$6" = "iphone-6s" ]; then
            printf '%s %s\n' "$8" "$9" >> '__FIXTURE_DIR__/sent'
            exit 0
        fi
        if [ "$4" = "clear" ] && [ "$6" = "iphone-6s" ]; then exit 0; fi
        exit 7
        """)
        defer { fixture.remove() }
        let model = AppModel(refreshInterval: 0.06)
        model.setKeepLocationActive(true)
        model.changeTransport(.usb)
        model.toolPath = fixture.executable.path
        model.devices = [Device(id: "iphone-6s", name: "USB device", version: "15.8.6")]
        model.selectDevice("iphone-6s")
        model.latitude = "41.0082"
        model.longitude = "28.9784"
        await model.send()
        try check(model.isMaintainingLocation, "Successful USB send did not start renewal")
        try await waitFor("No automatic refresh occurred") { model.refreshCount >= 2 }
        let firstLines = try String(contentsOf: fixture.directory.appendingPathComponent("sent"), encoding: .utf8)
        try check(firstLines.split(separator: "\n").count >= 3, "USB command was not run again")
        try check(firstLines.contains("41.0082 28.9784"), "Wrong coordinate was refreshed")

        model.latitude = "39.9334"
        model.longitude = "32.8597"
        await model.send()
        try check(model.isMaintainingLocation && model.refreshCount == 0, "New point did not restart renewal")
        try await waitFor("New point was not refreshed") { model.refreshCount >= 1 }
        let allLines = try String(contentsOf: fixture.directory.appendingPathComponent("sent"), encoding: .utf8)
        try check(allLines.split(separator: "\n").last == "39.9334 32.8597", "Renewal returned to the old coordinate")

        model.stopRefreshing()
        try check(!model.isMaintainingLocation, "Stop did not cancel renewal")
        let stoppedCount = try String(contentsOf: fixture.directory.appendingPathComponent("sent"), encoding: .utf8).split(separator: "\n").count
        try await Task.sleep(nanoseconds: 180_000_000)
        let afterStopCount = try String(contentsOf: fixture.directory.appendingPathComponent("sent"), encoding: .utf8).split(separator: "\n").count
        try check(stoppedCount == afterStopCount, "USB command continued after stopping")
        await model.clear()
        try check(!model.isMaintainingLocation && model.lastCommand == nil, "Clear did not leave renewal off")
    }

    static func modelMaintenanceFailure() async throws {
        let fixture = try Fixture("""
        if [ ! -f '__FIXTURE_DIR__/first-send' ]; then
            : > '__FIXTURE_DIR__/first-send'
            exit 0
        fi
        printf 'USB device locked\n' >&2
        exit 7
        """)
        defer { fixture.remove() }
        let model = AppModel(refreshInterval: 0.04)
        model.setKeepLocationActive(true)
        model.changeTransport(.usb)
        model.toolPath = fixture.executable.path
        model.devices = [Device(id: "iphone-6s", name: "USB device", version: "15.8.6")]
        model.selectDevice("iphone-6s")
        model.latitude = "41.0082"
        model.longitude = "28.9784"
        await model.send()
        try check(model.isMaintainingLocation, "Initial send did not start renewal")
        try await waitFor("Renewal did not stop after three errors") { !model.isMaintainingLocation }
        try check(model.status == "Auto-refresh paused", "Repeated failure status was not shown")
        try check(model.errorDetails?.contains("USB device locked") == true, "Renewal lost the tool diagnostic")
    }

    static func remoteHTTPParser() throws {
        let request = Data("POST /api/location HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Type: application/json\r\nContent-Length: 2\r\n\r\n{}".utf8)
        switch RemoteHTTP.parse(Data(request.dropLast())) {
        case .incomplete: break
        default: throw CheckFailure(message: "Incomplete HTTP body was accepted")
        }
        switch RemoteHTTP.parse(request) {
        case .request(let parsed):
            try check(parsed.method == "POST" && parsed.path == "/api/location", "HTTP route changed")
            try check(parsed.body == Data("{}".utf8), "HTTP body changed")
        default: throw CheckFailure(message: "Valid HTTP request was rejected")
        }
        let duplicate = Data("GET /api/status HTTP/1.1\r\nHost: one\r\nHost: two\r\n\r\n".utf8)
        switch RemoteHTTP.parse(duplicate) {
        case .error(400, _): break
        default: throw CheckFailure(message: "Duplicate Host header was accepted")
        }
        let oversized = Data("POST /api/location HTTP/1.1\r\nContent-Length: 2000001\r\n\r\n".utf8)
        switch RemoteHTTP.parse(oversized) {
        case .error(413, _): break
        default: throw CheckFailure(message: "Oversized HTTP body was accepted")
        }
    }

    static func locationVerification() throws {
        let now = Date()
        let expected = try Coordinate(latitude: "41.0082", longitude: "28.9784")
        let nearby = try Coordinate(latitude: "41.0083", longitude: "28.9784")
        let far = try Coordinate(latitude: "39.9334", longitude: "32.8597")
        let fresh = try DeviceLocationReport(coordinate: nearby, horizontalAccuracy: 20,
                                             measuredAt: now, receivedAt: now, source: "safari",
                                             simulatedBySoftware: nil)
        let match = LocationVerification.evaluate(expected: expected, sentAt: now.addingTimeInterval(-5),
                                                  report: fresh, now: now)
        try check(match.state == .matching && (match.distanceMeters ?? 1_000) < 75, "Nearby device fix did not match")
        let mismatch = try DeviceLocationReport(coordinate: far, horizontalAccuracy: 20,
                                                measuredAt: now, receivedAt: now, source: "ios-app",
                                                simulatedBySoftware: true)
        try check(LocationVerification.evaluate(expected: expected, sentAt: now.addingTimeInterval(-5),
                                                report: mismatch, now: now).state == .different,
                  "Distant device fix matched")
        try check(LocationVerification.evaluate(expected: expected, sentAt: now.addingTimeInterval(5),
                                                report: fresh, now: now).state == .waiting,
                  "Fix from before last command was compared")
        try check(LocationVerification.evaluate(expected: expected, sentAt: now.addingTimeInterval(-5),
                                                report: fresh, now: now.addingTimeInterval(40)).state == .stale,
                  "Stale report remained verified")
        try expectThrow("Ancient report accepted") {
            _ = try DeviceLocationReport(coordinate: nearby, horizontalAccuracy: 20,
                                         measuredAt: now.addingTimeInterval(-121), receivedAt: now,
                                         source: "safari", simulatedBySoftware: nil)
        }
    }

    static func remotePairing() throws {
        let token = "0123456789abcdef0123456789abcdef"
        try check(RemoteHTTP.equalToken(token, token), "Correct pairing code was rejected")
        try check(!RemoteHTTP.equalToken("0123456789abcdef0123456789abcdee", token), "Incorrect pairing code was accepted")
        try check(!RemoteHTTP.equalToken("", token), "Missing pairing code was accepted")
    }

    static func modelRemoteCommands() async throws {
        let fixture = try Fixture("""
        if [ "$1" != "--no-color" ] || [ "$2" != "developer" ] || [ "$3" != "simulate-location" ] || [ "$5" != "--udid" ] || [ "$6" != "iphone-6s" ]; then exit 7; fi
        if [ "$4" = "set" ]; then printf 'set %s %s\n' "$8" "$9" >> '__FIXTURE_DIR__/sent'; exit 0; fi
        if [ "$4" = "clear" ]; then printf 'clear\n' >> '__FIXTURE_DIR__/sent'; exit 0; fi
        exit 7
        """)
        defer { fixture.remove() }
        let model = AppModel()
        let point = try Coordinate(latitude: "39.9334", longitude: "32.8597")
        try await expectRemoteFailure { try await model.sendRemote(point) }
        model.changeTransport(.usb)
        model.toolPath = fixture.executable.path
        model.devices = [Device(id: "iphone-6s", name: "USB device", version: "15.8.6")]
        model.selectDevice("iphone-6s")
        try await model.sendRemote(point)
        try check(model.lastCommand == point && !model.isMaintainingLocation, "Remote send failed or started unwanted renewal")
        try await model.clearRemote()
        try check(model.lastCommand == nil, "Remote clear did not reset last command")
        let lines = try String(contentsOf: fixture.directory.appendingPathComponent("sent"), encoding: .utf8)
        try check(lines == "set 39.9334 32.8597\nclear\n", "Remote operations used wrong USB command")
    }

    static func expectRemoteFailure(_ operation: () async throws -> Void) async throws {
        do { try await operation() }
        catch { return }
        throw CheckFailure(message: "Remote operation unexpectedly succeeded without USB target")
    }
}
