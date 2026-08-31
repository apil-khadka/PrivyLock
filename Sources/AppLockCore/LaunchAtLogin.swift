import Foundation

/// Manages PrivyLock's "start at login" via a per-user LaunchAgent.
///
/// A LaunchAgent plist in `~/Library/LaunchAgents` is the classic, reliable,
/// entitlement-free way for a login item to auto-launch a bundled app. We avoid
/// ServiceManagement's `SMApp` because it requires the app to be signed with a
/// provisioning profile and is finicky for ad-hoc builds.
public enum LaunchAtLogin {

    private static let agentLabel = "com.applock.helper"

    private static let baseURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/LaunchAgents")

    private static var plistURL: URL {
        baseURL.appendingPathComponent("com.applock.helper.plist")
    }

    /// Whether the current app bundle is the executable registered at login.
    /// A stale plist is removed so moving or deleting the app cannot leave a
    /// LaunchAgent pointing at a dead path.
    public static var isEnabled: Bool {
        guard FileManager.default.fileExists(atPath: plistURL.path),
              let configuredPath = configuredExecutablePath(),
              let currentPath = executablePath(),
              configuredPath == currentPath,
              FileManager.default.fileExists(atPath: configuredPath) else {
            cleanupStaleAgentIfNeeded()
            return false
        }
        return true
    }

    /// Removes an existing LaunchAgent if its executable no longer exists or
    /// belongs to a different copy of PrivyLock.
    public static func cleanupStaleAgentIfNeeded() {
        guard FileManager.default.fileExists(atPath: plistURL.path) else { return }
        guard let configuredPath = configuredExecutablePath(),
              let currentPath = executablePath(),
              configuredPath == currentPath,
              FileManager.default.fileExists(atPath: configuredPath) else {
            _ = disable()
            return
        }
    }

    /// Registers a LaunchAgent that runs the current app bundle at login.
    @discardableResult
    public static func enable() -> Bool {
        // Find this app's executable: use the running bundle, or cast a guess.
        guard let execPath = executablePath() else { return false }
        // Unload an old path before replacing the plist, including after the
        // app has been moved or reinstalled.
        _ = disable()
        try? FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)

        let job: [String: Any] = [
            "Label": agentLabel,
            "ProgramArguments": [execPath],
            "RunAtLoad": true,
            "ProcessType": "Background",
        ]
        guard let data = try? PropertyListSerialization.data(fromPropertyList: job,
                                                             format: .xml,
                                                             options: 0) else { return false }
        do {
            try data.write(to: plistURL, options: .atomic)
        } catch {
            return false
        }
        launchctl(tryLoad: true)
        return true
    }

    @discardableResult
    public static func disable() -> Bool {
        launchctl(tryLoad: false)
        do {
            if FileManager.default.fileExists(atPath: plistURL.path) {
                try FileManager.default.removeItem(at: plistURL)
            }
            return true
        } catch {
            return false
        }
    }

    private static func launchctl(tryLoad: Bool) {
        if tryLoad {
            guard FileManager.default.fileExists(atPath: plistURL.path) else { return }
            _ = run("/bin/launchctl", ["bootstrap", "gui/\(getuid())", plistURL.path])
        } else {
            // Removing the plist alone does not unload an already-bootstrapped
            // LaunchAgent; it would continue running until the next login.
            _ = run("/bin/launchctl", ["bootout", "gui/\(getuid())/\(agentLabel)"])
        }
    }

    private static func executablePath() -> String? {
        if let path = Bundle.main.executablePath, FileManager.default.fileExists(atPath: path), !path.hasSuffix("lldb-rpc-server") {
            return path
        }
        return nil
    }

    private static func configuredExecutablePath() -> String? {
        guard let data = try? Data(contentsOf: plistURL),
              let propertyList = try? PropertyListSerialization.propertyList(from: data,
                                                                              options: [],
                                                                              format: nil),
              let job = propertyList as? [String: Any],
              let arguments = job["ProgramArguments"] as? [String],
              let executable = arguments.first,
              !executable.isEmpty else {
            return nil
        }
        return executable
    }

    private static func run(_ path: String, _ args: [String]) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do {
            try p.run()
            p.waitUntilExit()
        } catch {
            return nil
        }
        let data = (try? pipe.fileHandleForReading.readToEnd()) ?? nil
        return data.flatMap { String(data: $0, encoding: .utf8) }
    }
}
