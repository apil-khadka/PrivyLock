import AppKit
import Foundation

private func check(_ condition: @autoclosure () -> Bool, _ label: String) {
    let passed = condition()
    print((passed ? "PASS" : "FAIL") + " - " + label)
    if !passed { exit(1) }
}

private func temporaryJSONURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("applock-smoke-\(UUID().uuidString).json")
}

func run() {
    let url = temporaryJSONURL()
    defer { try? FileManager.default.removeItem(at: url) }

    let target = TargetApp(
        name: "Calculator",
        bundleIdentifier: "com.apple.calculator",
        url: URL(fileURLWithPath: "/System/Applications/Calculator.app")
    )

    let store = LockStore(fileURL: url)
    check(store.state.apps.isEmpty, "initial store has no protected apps")

    store.add(target)
    check(store.state.apps[target.bundleIdentifier]?.target == target,
          "adding an app stores it by bundle identifier")
    check(store.state.apps[target.bundleIdentifier]?.isLocked == false,
          "newly added apps start unlocked")

    store.setLocked(bundleIdentifier: target.bundleIdentifier, true)
    let reloaded = LockStore(fileURL: url)
    _ = reloaded.load()
    check(reloaded.state.apps[target.bundleIdentifier]?.target == target,
          "JSON round-trip preserves the target app")
    check(reloaded.state.apps[target.bundleIdentifier]?.isLocked == true,
          "JSON round-trip preserves locked state")

    // Verify migration from the original single-app file format.
    let legacyURL = temporaryJSONURL()
    defer { try? FileManager.default.removeItem(at: legacyURL) }
    let legacy = """
    {"target":{"name":"Notes","bundleIdentifier":"com.apple.Notes","url":"/System/Applications/Notes.app"},"isLocked":true}
    """
    try! Data(legacy.utf8).write(to: legacyURL)
    let migrated = LockStore(fileURL: legacyURL)
    _ = migrated.load()
    check(migrated.state.apps["com.apple.Notes"]?.isLocked == true,
          "legacy single-app state migrates to the app map")

    print("Touch ID available on this Mac: \(TouchID.isAvailable)")
    print("ALL SMOKE CHECKS PASSED")
}

@main
struct SmokeRunner {
    static func main() { run() }
}
