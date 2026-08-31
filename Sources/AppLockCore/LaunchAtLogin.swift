import Foundation

/// Manages AppLock's "start at login" via a per-user LaunchAgent.
///
/// A LaunchAgent plist in `~/Library/LaunchAgents` is the classic, reliable,
/// entitlement-free way for a login item to auto-launch a bundled app. We avoid
/// ServiceManagement's `SMApp` because it requires the app to be signed with a
/// provisioning profile and is finicky for ad-hoc builds.
public enum LaunchAtLogin {

    private static let baseURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/LaunchAgents")

    private static var plistURL: URL {
        baseURL.appendingPathComponent("com.applock.helper.plist")
    }

    private static var isEnabledFile: Bool {
        FileManager.default.fileExists(atPath: plistURL.path)
    }

    /// Whether AppLock *thinks* it should launch at login.
    public static var isEnabled: Bool { isEnabledFile }

    /// Registers a LaunchAgent that runs the current app bundle at login.
    @discardableResult
    public static func enable() -> Bool {
        // Find this app's executable: use the running bundle, or cast a guess.
        guard let execPath = executablePath() else { return false }
        try? FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)

        let job: [String: Any] = [
            "Label": "com.applock.helper",
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
            _ = run("/bin/launchctl", ["bootout", "gui/\(getuid())/com.applock.helper"])
        }
    }

    private static func executablePath() -> String? {
        if let path = Bundle.main.executablePath, FileManager.default.fileExists(atPath: path), !path.hasSuffix("lldb-rpc-server") {
            return path
        }
        return nil
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
