# AppLock

A Swift macOS menu-bar app that protects a chosen app so it can only be opened
again after you authenticate with **Touch ID or your Mac login password**.

- Pick any installed app to protect (e.g. Messages, Notes, a banking app).
- **Lock** quits that app and keeps it closed - if anything tries to relaunch it,
  AppLock terminates it again immediately.
- **Unlock** requires device-owner authentication. AppLock prefers Touch ID and
  falls back to the Mac login password when Touch ID is unavailable or declined.

AppLock runs quietly in the menu bar (no Dock icon). Its state survives restarts.

---

## Why AppLock uses macOS owner authentication

macOS does **not** expose a public "enroll arbitrary app into Touch ID" API that
lets any process silently check a fingerprint. The clean, supported path is the
public **`LocalAuthentication`** framework (`LAContext` +
`LAPolicy.deviceOwnerAuthentication`), which shows the system authentication
prompt. This policy prefers Touch ID and allows the Mac password fallback. On
success we get a plain `true`; AppLock never sees, stores, or transmits your
fingerprint or password.

If neither Touch ID nor the Mac password can be evaluated, the menu shows a
warning and a "locked" app stays locked.

## Architecture

```
Sources/
  AppLockCore/                 (library - no UI)
    TargetApp.swift            value model: name, bundle id, .app url
    LockStore.swift            persist state (JSON in ~/Library/Application Support/AppLock)
    TouchID.swift              the only code that touches LocalAuthentication
    AppGuard.swift             lifecycle: terminate / relaunch / watchdog enforcement
  AppLock/                     (executable - menu bar UI)
    main.swift                 NSStatusItem menu + app picker, bootstraps AppKit
```

- **Deep seam:** all process/security decisions live in `AppLockCore`. The UI is a
  thin menu-bar shell, so the lock logic is testable without a GUI.
- **Enforcement:** while locked, AppGuard (a) quits the target on `lock()`, and
  (b) listens for the app's launch and re-terminates it, backed by a 1-second
  watchdog timer that catches races.

## Building and running

Requirements: macOS 12+, Xcode command line tools (or Xcode). Swift 5.9+.

```bash
./build.sh release          # produces build/AppLock.app
open build/AppLock.app      # launches it (menu bar icon: lock shield)
```

You can also run the un-bundled binary:

```bash
swift run AppLock
```

> **Note on code signing:** the build script ad-hoc signs the bundle so the OS
> treats it as a regular app and system prompts work. For distribution you would
> sign with your Developer ID and notarize.

## Using it

1. Click the lock shield in the menu bar.
2. Choose **Choose App to Protect...**, search, pick an app.
3. Choose **Lock <app>** - it quits and stays locked.
4. To open it again choose **Unlock <app>**, then authenticate with Touch ID or
   your Mac login password.

The menu reflects current state (`<app>: Locked / Unlocked`).

## Essential protection behavior

The current implementation includes the core behaviors expected from a macOS
app locker:

- A visible inventory of protected apps, including each app's icon and current
  locked/unlocked state.
- Per-app and “unlock all” device-owner authentication using Touch ID or the Mac
  login password fallback.
- Lock enforcement before and after launch, plus a watchdog for launch races.
- Locked-app removal requires owner authentication, so removing an entry cannot bypass its
  protection.
- Quitting AppLock while apps are locked requires owner authentication, because quitting
  would otherwise disable enforcement.
- Persistent state, screen-lock auto-lock, inactivity auto-lock, and optional
  launch at login.

Access history and scheduled rules are useful next-stage features.

## Tests

Smoke tests (no XCTest dependency) are kept under `Tests/AppLockCoreTests/`.

```bash
# Build the core smoke check as a CLI and run it:
swiftc -parse-as-library -o /tmp/applock-smoke \
  Sources/AppLockCore/TargetApp.swift Sources/AppLockCore/LockStore.swift Sources/AppLockCore/TouchID.swift \
  Tests/AppLockCoreTests/Smoke.swift && /tmp/applock-smoke
```

There is also an end-to-end lifecycle check (locks/relaunches a real app) shown in
the session; it verifies launch -> lock -> kill-while-locked -> unlock -> relaunch.

## Configuration

State is a single JSON file:

```
~/Library/Application Support/AppLock/applock.json
```

Delete it to reset AppLock completely.

## Security model and limitations

- Uses the system owner-authentication prompt; fingerprints and passwords never
  leave macOS's protected authentication services.
- AppLock is not a hard OS-level sandbox: a determined process with root can always
  start any app. This is a strong convenience/safety lock, not a security boundary
  against a privileged attacker. It is comparable to app-lockers on other platforms.
- Multiple apps can be protected at the same time; each app keeps its own lock state.
