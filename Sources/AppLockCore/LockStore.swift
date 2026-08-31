import Foundation

/// Loads and saves the current AppLock configuration to a small JSON file on disk.
///
/// Storing to a normal file (rather than UserDefaults) keeps the state inspectable
/// and easy to back up, and avoids surprises from app-sandbox container relocation.
public final class LockStore {
    public static let shared = LockStore()

    private let fileURL: URL

    public init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let base = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/AppLock")
            try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
            self.fileURL = base.appendingPathComponent("applock.json")
        }
    }

    public private(set) var state = LockState()

    /// Loads persisted state, migrating the old single-app format if present.
    @discardableResult
    public func load() -> LockState {
        guard let data = try? Data(contentsOf: fileURL) else { return state }

        // Preferred: current multi-app format.
        if let decoded = try? JSONDecoder().decode(LockState.self, from: data) {
            state = decoded
            return state
        }

        // Legacy: v1 kept { "target": TargetApp?, "isLocked": Bool }.
        struct Legacy: Codable {
            let target: TargetApp?
            let isLocked: Bool
        }
        if let legacy = try? JSONDecoder().decode(Legacy.self, from: data),
           let target = legacy.target {
            var migrated = LockState()
            migrated.apps[target.bundleIdentifier] = ProtectedApp(target: target, isLocked: legacy.isLocked)
            state = migrated
            save()
        }
        return state
    }

    /// Persists the current in-memory state to disk synchronously.
    public func save() {
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    // MARK: - App list mutations

    public func add(_ target: TargetApp) {
        state.apps[target.bundleIdentifier] = ProtectedApp(target: target, isLocked: false)
        save()
    }

    public func remove(bundleIdentifier: String) {
        state.apps[bundleIdentifier] = nil
        save()
    }

    public func setLocked(bundleIdentifier: String, _ locked: Bool) {
        guard state.apps[bundleIdentifier] != nil else { return }
        state.apps[bundleIdentifier]?.isLocked = locked
        save()
    }

    /// Convenience: all currently protected apps, sorted by name.
    public var protectedApps: [ProtectedApp] {
        state.apps.values.sorted { $0.target.name.localizedCaseInsensitiveCompare($1.target.name) == .orderedAscending }
    }

    // MARK: - Settings mutations

    public func setAutoLockOnScreenLock(_ enabled: Bool) {
        state.autoLockOnScreenLock = enabled
        save()
    }

    public func setIdleAutoLockMinutes(_ minutes: Int?) {
        state.idleAutoLockMinutes = minutes
        save()
    }

    public func setLaunchAtLogin(_ enabled: Bool) {
        state.launchAtLogin = enabled
        save()
    }
}