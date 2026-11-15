import Foundation
import ServiceManagement
import SwiftUI

struct HostPreferences {
    static var bundledToolPath: String? {
        guard let resources = Bundle.main.resourceURL else { return nil }
        let path = resources.appendingPathComponent("USB/pymobiledevice3/pymobiledevice3").path
        return FileManager.default.isExecutableFile(atPath: path) ? path : nil
    }
    private enum Key {
        static let toolPath = "host.usbToolPath"
        static let deviceID = "host.usbDeviceID"
        static let restoreUSB = "host.restoreUSBAtLaunch"
        static let startRemote = "host.startRemoteAtLaunch"
        static let updateInterval = "host.updateIntervalSeconds"
    }

    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    var toolPath: String { defaults.string(forKey: Key.toolPath) ?? "" }
    var deviceID: String { defaults.string(forKey: Key.deviceID) ?? "" }
    var restoreUSBAtLaunch: Bool {
        get { defaults.bool(forKey: Key.restoreUSB) }
        nonmutating set { defaults.set(newValue, forKey: Key.restoreUSB) }
    }
    var startRemoteAtLaunch: Bool {
        get { defaults.bool(forKey: Key.startRemote) }
        nonmutating set { defaults.set(newValue, forKey: Key.startRemote) }
    }
    var updateIntervalSeconds: Int {
        get {
            let value = defaults.integer(forKey: Key.updateInterval)
            return (1...60).contains(value) ? value : 20
        }
        nonmutating set { defaults.set(newValue, forKey: Key.updateInterval) }
    }

    func rememberTool(_ path: String) {
        defaults.set(path, forKey: Key.toolPath)
        defaults.removeObject(forKey: Key.deviceID)
    }

    func rememberDevice(_ id: String) {
        if id.isEmpty { defaults.removeObject(forKey: Key.deviceID) }
        else { defaults.set(id, forKey: Key.deviceID) }
    }

    var restorableTarget: (toolPath: String, deviceID: String)? {
        let path = Self.bundledToolPath ?? toolPath
        let id = deviceID
        guard restoreUSBAtLaunch, !id.isEmpty,
              URL(fileURLWithPath: path).lastPathComponent == "pymobiledevice3",
              FileManager.default.isExecutableFile(atPath: path) else { return nil }
        return (path, id)
    }
}

@MainActor
final class StartupOptions: ObservableObject {
    @Published var restoreUSBAtLaunch: Bool
    @Published var startRemoteAtLaunch: Bool
    @Published private(set) var loginItemStatus: SMAppService.Status
    @Published private(set) var errorMessage: String?

    private let preferences: HostPreferences
    private var didBootstrap = false

    init(preferences: HostPreferences = HostPreferences()) {
        self.preferences = preferences
        restoreUSBAtLaunch = preferences.restoreUSBAtLaunch
        startRemoteAtLaunch = preferences.startRemoteAtLaunch
        loginItemStatus = SMAppService.mainApp.status
    }

    func setRestoreUSB(_ enabled: Bool) {
        preferences.restoreUSBAtLaunch = enabled
        restoreUSBAtLaunch = enabled
    }

    func setStartRemote(_ enabled: Bool) {
        preferences.startRemoteAtLaunch = enabled
        startRemoteAtLaunch = enabled
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled, loginItemStatus == .requiresApproval { return }
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            errorMessage = nil
        } catch {
            errorMessage = "Could not change launch at login: \(error.localizedDescription)"
        }
        loginItemStatus = SMAppService.mainApp.status
    }

    func refreshLoginItemStatus() { loginItemStatus = SMAppService.mainApp.status }

    func beginBootstrap() -> Bool {
        guard !didBootstrap else { return false }
        didBootstrap = true
        return true
    }

    var isLoginItemRegistered: Bool {
        loginItemStatus == .enabled || loginItemStatus == .requiresApproval
    }
}
