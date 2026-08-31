import Foundation

/// The application a user chooses to protect with PrivyLock.
///
/// Stored value object; no logic lives here. It captures enough about an app to
/// re-find it later (bundle identifier), to terminate it (running app lookup),
/// and to relaunch it (its .app URL).
public struct TargetApp: Codable, Equatable {
    /// Display name, e.g. "Messages".
    public let name: String
    /// Stable identifier used to find/terminate the app and its children, e.g. "com.apple.MobileSMS".
    public let bundleIdentifier: String
    /// Absolute path to the .app bundle used to relaunch it, e.g. "/System/Applications/Messages.app".
    public let url: URL

    public init(name: String, bundleIdentifier: String, url: URL) {
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.url = url
    }
}

/// One protected application and its current lock state.
public struct ProtectedApp: Codable, Equatable {
    public var target: TargetApp
    public var isLocked: Bool

    public init(target: TargetApp, isLocked: Bool = false) {
        self.target = target
        self.isLocked = isLocked
    }
}

/// The full, persisted PrivyLock configuration.
public struct LockState: Codable, Equatable {
    /// Protected apps keyed by bundle identifier.
    public var apps: [String: ProtectedApp]

    /// When the system screen locks, all protected apps are locked automatically.
    public var autoLockOnScreenLock: Bool

    /// After this many minutes of no user activity, all protected apps lock. nil = disabled.
    public var idleAutoLockMinutes: Int?

    /// Launch PrivyLock at login so protection survives restarts.
    public var launchAtLogin: Bool

    public init(apps: [String: ProtectedApp] = [:],
                autoLockOnScreenLock: Bool = true,
                idleAutoLockMinutes: Int? = nil,
                launchAtLogin: Bool = false) {
        self.apps = apps
        self.autoLockOnScreenLock = autoLockOnScreenLock
        self.idleAutoLockMinutes = idleAutoLockMinutes
        self.launchAtLogin = launchAtLogin
    }
}