# PrivyLock

A Swift macOS menu-bar app that protects a chosen app so it can only be opened
again after you authenticate with **Touch ID or your Mac login password**.

- Pick any installed app to protect (e.g. Messages, Notes, a banking app).
- **Lock** quits that app and keeps it closed - if anything tries to relaunch it,
  PrivyLock terminates it again immediately.
- **Unlock** requires device-owner authentication. PrivyLock prefers Touch ID and
  falls back to the Mac login password when Touch ID is unavailable or declined.

PrivyLock runs quietly in the menu bar (no Dock icon). Its state survives restarts.

---

## Why PrivyLock uses macOS owner authentication

macOS does **not** expose a public "enroll arbitrary app into Touch ID" API that
lets any process silently check a fingerprint. The clean, supported path is the
public **`LocalAuthentication`** framework (`LAContext` +
`LAPolicy.deviceOwnerAuthentication`), which shows the system authentication
prompt. This policy prefers Touch ID and allows the Mac password fallback. On
success we get a plain `true`; PrivyLock never sees, stores, or transmits your
fingerprint or password.

If neither Touch ID nor the Mac password can be evaluated, the menu shows a
warning and a "locked" app stays locked.

## Architecture

```
Sources/
  AppLockCore/                  (library - no UI)
    TargetApp.swift            value model: name, bundle id, .app url
    LockStore.swift            persist state (JSON in ~/Library/Application Support/AppLock)
    TouchID.swift              the only code that touches LocalAuthentication
    AppGuard.swift             lifecycle: terminate / relaunch / watchdog enforcement
  AppLock/                       (executable - menu bar UI)
    main.swift                 NSStatusItem menu + app picker, bootstraps AppKit
```

- **Deep seam:** all process/security decisions live in `PrivyLockCore`. The UI is a
  thin menu-bar shell, so the lock logic is testable without a GUI.
- **Enforcement:** while locked, AppGuard (a) quits the target on `lock()`, and
  (b) listens for the app's launch and re-terminates it, backed by a 1-second
  watchdog timer that catches races.

## Building and running

Requirements: macOS 12+, Xcode command line tools (or Xcode), Swift 5.9+.

The build script produces a universal `arm64` + `x86_64` app by default. Set
`ARCHS=arm64` or `ARCHS=x86_64` when a single-architecture build is needed.

```bash
./build.sh release          # produces build/PrivyLock.app
open build/PrivyLock.app      # launches it (menu bar icon: lock shield)
```

You can also run the un-bundled binary:

```bash
swift run PrivyLock
```

> **Local signing note:** local builds are ad-hoc signed so macOS treats the
> bundle as an app during development. The tagged release workflow signs with a
> Developer ID Application certificate, notarizes with Apple, staples the ticket,
> and validates with both `codesign` and Gatekeeper before publishing.

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
- Quitting PrivyLock while apps are locked requires owner authentication, because quitting
  would otherwise disable enforcement.
- Persistent state, screen-lock auto-lock, inactivity auto-lock, and optional
  launch at login.

Access history and scheduled rules are useful next-stage features.

## Tests

Smoke tests (no XCTest dependency) are kept under `Tests/AppLockCoreTests/`.

```bash
# Build the core smoke check as a CLI and run it:
swiftc -parse-as-library -o /tmp/privylock-smoke \
  Sources/AppLockCore/TargetApp.swift Sources/AppLockCore/LockStore.swift Sources/AppLockCore/TouchID.swift \
  Tests/AppLockCoreTests/Smoke.swift && /tmp/privylock-smoke
```

There is also an end-to-end lifecycle check (locks/relaunches a real app) shown in
the session; it verifies launch -> lock -> kill-while-locked -> unlock -> relaunch.

## Configuration

State is a single JSON file:

```
~/Library/Application Support/AppLock/applock.json
```

The legacy AppLock path is retained so existing installations keep their
protected-app configuration after the PrivyLock rename.

Delete it to reset PrivyLock completely.

## Distribution and Homebrew

The release workflow publishes a stable `PrivyLock-macOS.zip` asset and a
matching `PrivyLock-macOS.zip.sha256` file for each version tag. Production
artifacts support both Apple Silicon (`arm64`) and Intel (`x86_64`) Macs and
require macOS 12 or later. The ZIP contains only `PrivyLock.app`; it is signed
with Developer ID Application, notarized by Apple, stapled, and Gatekeeper
assessed before release.

To remove PrivyLock while ensuring its login agent is unloaded, run
`./uninstall.sh` before deleting the app bundle. On startup, PrivyLock also
removes a stale agent if its recorded executable path no longer matches the
current bundle.

## Security model and limitations

- Uses the system owner-authentication prompt; fingerprints and passwords never
  leave macOS's protected authentication services.
- PrivyLock is not a hard OS-level sandbox: a determined process with root can always
  start any app. This is a strong convenience/safety lock, not a security boundary
  against a privileged attacker. It is comparable to app-lockers on other platforms.
- Multiple apps can be protected at the same time; each app keeps its own lock state.

## License

PrivyLock is licensed under the [Apache License 2.0](LICENSE).
