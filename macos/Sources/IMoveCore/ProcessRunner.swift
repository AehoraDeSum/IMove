import Foundation

public struct ProcessOutput: Sendable {
    public let status: Int32
    public let stdout: String
    public let stderr: String
}

public enum ProcessRunner {
    /// Runs a selected executable directly; coordinates and device IDs never enter a shell.
    public static func run(executable: URL, arguments: [String], timeout: TimeInterval = 20) async throws -> ProcessOutput {
        try await Task.detached(priority: .userInitiated) {
            try runBlocking(executable: executable, arguments: arguments, timeout: timeout)
        }.value
    }

    private static func runBlocking(executable: URL, arguments: [String], timeout: TimeInterval) throws -> ProcessOutput {
            guard FileManager.default.isExecutableFile(atPath: executable.path) else {
                throw IMoveError.message("The USB tool cannot be run. Reinstall the app or choose a valid file under advanced tool selection.")
            }
            let process = Process()
            process.executableURL = executable
            process.arguments = arguments
            var environment = ProcessInfo.processInfo.environment
            for key in Array(environment.keys) where key.hasPrefix("PYMOBILEDEVICE3_") || key == "USBMUXD_SOCKET_ADDRESS" {
                environment.removeValue(forKey: key)
            }
            environment["NO_COLOR"] = "1"
            environment["TERM"] = "dumb"
            process.environment = environment

            // Files avoid deadlocking on full stdout/stderr pipes from an external tool.
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("imove-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: folder) }
            let outURL = folder.appendingPathComponent("out")
            let errURL = folder.appendingPathComponent("err")
            FileManager.default.createFile(atPath: outURL.path, contents: nil)
            FileManager.default.createFile(atPath: errURL.path, contents: nil)
            let out = try FileHandle(forWritingTo: outURL)
            let err = try FileHandle(forWritingTo: errURL)
            defer { try? out.close(); try? err.close() }
            process.standardOutput = out
            process.standardError = err
            process.standardInput = FileHandle.nullDevice
            let finished = DispatchSemaphore(value: 0)
            process.terminationHandler = { _ in finished.signal() }
            try process.run()
            if finished.wait(timeout: .now() + timeout) == .timedOut {
                if process.isRunning { process.terminate() }
                if finished.wait(timeout: .now() + 1) == .timedOut && process.isRunning {
                    kill(process.processIdentifier, SIGKILL)
                }
                process.waitUntilExit()
                throw IMoveError.message("The USB operation timed out. The result is uncertain; check the iPhone and scan again.")
            }
            process.waitUntilExit()
            let stdout = (try? String(contentsOf: outURL, encoding: .utf8)) ?? ""
            let stderr = (try? String(contentsOf: errURL, encoding: .utf8)) ?? ""
            return ProcessOutput(status: process.terminationStatus, stdout: stdout, stderr: stderr)
    }
}
