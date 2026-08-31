import AppKit
import CoreGraphics
import Foundation

/// Drives the protection lifecycle for every protected app.
///
/// Responsibilities:
///   - terminate a protected app when it is locked
    ///   - relaunch a protected app when it is unlocked (after owner authentication)
///   - keep locked apps dead even if they are relaunched
///   - auto-lock everything when the screen locks or the machine idles out
public final class AppGuard {

    public static let shared = AppGuard()

    /// Injectable for tests - normally the shared store is used.
    public var storeOverride: LockStore?
    public var store: LockStore { storeOverride ?? LockStore.shared }

    /// Called whenever lock state changes so the UI can refresh.
    public var onStateChange: (() -> Void)?

    /// Called when a user tries to launch a locked app. The guard stops the
    /// process first; the UI can then offer authentication and relaunch it.
    public var onBlockedLaunch: ((TargetApp) -> Void)?

    private var killTimer: Timer?
    private var idleTimer: Timer?
    private var observers: [NSObjectProtocol] = []

    public init() {
        observeAppLaunches()
        observeScreenLock()

        // Safety net: every second, re-assert the lock against any instance that
        // sneaked through a launch notification race.
        killTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.enforceLocks()
        }

        // Idle auto-lock: poll the system idle time every 30s.
        idleTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            self?.checkIdle()
        }
    }

    // MARK: - Public control surface

    /// All protected apps, sorted by name, with current lock state.
    public var protectedApps: [ProtectedApp] {
        store.state.apps.values.sorted { $0.target.name.localizedCaseInsensitiveCompare($1.target.name) == .orderedAscending }
    }

    public func app(bundleIdentifier: String) -> TargetApp? {
        store.state.apps[bundleIdentifier]?.target
    }

    public func isLocked(bundleIdentifier: String) -> Bool {
        store.state.apps[bundleIdentifier]?.isLocked ?? false
    }

    /// Adds a newly chosen app to the protection list - unlocked to start.
    public func add(_ target: TargetApp) {
        store.add(target)
        onStateChange?()
    }

    /// Removes an app from protection entirely. Locked apps require owner authentication
    /// so removal cannot be used as a way around the lock.
    public func remove(bundleIdentifier: String) {
        store.remove(bundleIdentifier: bundleIdentifier)
        onStateChange?()
    }

    public func requestRemove(bundleIdentifier: String,
                              completion: @escaping (Bool) -> Void = { _ in }) {
        guard let target = app(bundleIdentifier: bundleIdentifier) else {
            completion(false)
            return
        }
        guard isLocked(bundleIdentifier: bundleIdentifier) else {
            remove(bundleIdentifier: bundleIdentifier)
            completion(true)
            return
        }

        TouchID.authenticate(localizedReason: "remove protection from \(target.name)") { [weak self] outcome in
            guard let self else { completion(false); return }
            guard case .success = outcome else { completion(false); return }
            self.remove(bundleIdentifier: bundleIdentifier)
            completion(true)
        }
    }

    /// Locks immediately: marks locked and kills the app.
    public func lock(bundleIdentifier: String) {
        guard let target = app(bundleIdentifier: bundleIdentifier) else { return }
        store.setLocked(bundleIdentifier: bundleIdentifier, true)
        terminate(target)
        onStateChange?()
    }

    /// Locks every protected app.
    public func lockAll() {
        for protected in protectedApps {
            store.setLocked(bundleIdentifier: protected.target.bundleIdentifier, true)
            terminate(protected.target)
        }
        onStateChange?()
    }

    /// Unlocks one app, but only after successful owner authentication.
    public func requestUnlock(bundleIdentifier: String,
                              completion: @escaping (Bool) -> Void = { _ in }) {
        guard let target = app(bundleIdentifier: bundleIdentifier) else {
            completion(false)
            return
        }
        TouchID.authenticate(localizedReason: "open \(target.name)") { [weak self] outcome in
            guard let self = self else { return }
            switch outcome {
            case .success:
                self.store.setLocked(bundleIdentifier: bundleIdentifier, false)
                self.launch(target)
                self.onStateChange?()
                completion(true)
            case .cancelled:
                completion(false)
            case .failed:
                completion(false)
            }
        }
    }

    /// Unlocks all apps after a single successful owner-authentication prompt.
    public func requestUnlockAll(completion: @escaping (Bool) -> Void = { _ in }) {
        let lockedApps = protectedApps.filter { $0.isLocked }
        guard !lockedApps.isEmpty else { completion(true); return }

        TouchID.authenticate(localizedReason: "unlock \(lockedApps.count) protected app\(lockedApps.count == 1 ? "" : "s")") { [weak self] outcome in
            guard let self = self else { return }
            switch outcome {
            case .success:
                for app in lockedApps {
                    self.store.setLocked(bundleIdentifier: app.target.bundleIdentifier, false)
                    self.launch(app.target)
                }
                self.onStateChange?()
                completion(true)
            case .cancelled, .failed:
                completion(false)
            }
        }
    }

    /// Unlocks without auth - used only for tests/internal flows.
    public func unlockDirect(bundleIdentifier: String) {
        store.setLocked(bundleIdentifier: bundleIdentifier, false)
        onStateChange?()
    }

    // MARK: - Settings glue

    public func setAutoLockOnScreenLock(_ enabled: Bool) {
        store.setAutoLockOnScreenLock(enabled)
    }

    public func setIdleAutoLockMinutes(_ minutes: Int?) {
        store.setIdleAutoLockMinutes(minutes)
        // Re-evaluate immediately: if idle time already exceeds the new threshold.
        if minutes != nil { checkIdle() }
    }

    public var launchAtLoginEnabled: Bool { LaunchAtLogin.isEnabled }

    public func setLaunchAtLogin(_ enabled: Bool) {
        let ok = enabled ? LaunchAtLogin.enable() : LaunchAtLogin.disable()
        store.setLaunchAtLogin(ok)
        onStateChange?()
    }

    // MARK: - Process enforcement

    private func matchingRunningApps(_ target: TargetApp) -> [NSRunningApplication] {
        NSRunningApplication.runningApplications(withBundleIdentifier: target.bundleIdentifier)
    }

    private func terminate(_ target: TargetApp) {
        matchingRunningApps(target).forEach { app in
            // Ask the app to exit cleanly first, then force it if it refuses or
            // gets stuck. This also handles Chromium-style browser processes
            // more reliably than killing only the first PID we see.
            if !app.terminate() {
                app.forceTerminate()
            } else {
                let pid = app.processIdentifier
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    let stillRunning = NSRunningApplication
                        .runningApplications(withBundleIdentifier: target.bundleIdentifier)
                        .contains { $0.processIdentifier == pid }
                    if stillRunning { app.forceTerminate() }
                }
            }
        }
    }

    private func launch(_ target: TargetApp) {
        let ws = NSWorkspace.shared
        ws.openApplication(at: target.url,
                           configuration: NSWorkspace.OpenConfiguration()) { _, error in
            if let error = error {
                NSLog("AppLock: failed to launch \(target.name): \(error)")
            }
        }
    }

    /// Watchdog called every second: if locked and the app is running, kill it.
    private func enforceLocks() {
        for protected in protectedApps where protected.isLocked {
            let running = matchingRunningApps(protected.target)
            if !running.isEmpty {
                terminate(protected.target)
            }
        }
    }

    // MARK: - Auto-lock triggers

    /// Hooks the launch notification so a locked app is killed the moment it shows up.
    private func observeAppLaunches() {
        let center = NSWorkspace.shared.notificationCenter
        let handleLaunch: (Notification) -> Void = { [weak self] note in
            guard let self, let info = note.userInfo,
                  let app = info[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let bid = app.bundleIdentifier,
                  let target = self.app(bundleIdentifier: bid) else { return }
            if self.isLocked(bundleIdentifier: bid) {
                if !app.terminate() { app.forceTerminate() }
                self.onBlockedLaunch?(target)
            }
        }
        observers.append(center.addObserver(
            forName: NSWorkspace.willLaunchApplicationNotification,
            object: nil,
            queue: .main,
            using: handleLaunch
        ))
        observers.append(center.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main,
            using: handleLaunch
        ))
    }

    /// Listens for the screen interface lock (notifications published by loginwindow).
    private func observeScreenLock() {
        let center = DistributedNotificationCenter.default()
        center.addObserver(self,
                           selector: #selector(screenDidLock),
                           name: NSNotification.Name("com.apple.screen.lock"),
                           object: nil)
        center.addObserver(self,
                           selector: #selector(screenDidLock),
                           name: NSNotification.Name("com.apple.screen.screenShieldLock"),
                           object: nil)
    }

    @objc private func screenDidLock() {
        guard store.state.autoLockOnScreenLock else { return }
        lockAll()
    }

    /// If idle auto-lock is on and the system has been idle past the threshold, lock all.
    private func checkIdle() {
        guard let minutes = store.state.idleAutoLockMinutes else { return }
        let idleSeconds = CGEventSource.secondsSinceLastEventType(
            .combinedSessionState,
            eventType: CGEventType(rawValue: ~0)!
        )
        guard idleSeconds >= Double(minutes * 60) else { return }
        lockAll()
    }
}
