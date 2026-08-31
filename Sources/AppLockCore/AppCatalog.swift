import AppKit
import Foundation

/// Discovers installed applications so the user can pick what to protect.
///
/// Candidate sources:
///   - /Applications and /Applications/Utilities
///   - /System/Applications
///   - ~/Applications
///   - everything currently running (so an open app is always reachable)
public enum AppCatalog {

    public static func installedApps() -> [TargetApp] {
        var found: [String: TargetApp] = [:]   // keyed by bundle identifier

        func add(from url: URL) {
            guard let bundle = Bundle(url: url), let bid = bundle.bundleIdentifier else { return }
            let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
                ?? url.deletingPathExtension().lastPathComponent
            // Prefer the app under /Applications over duplicates found elsewhere.
            let existing = found[bid]
            if existing == nil || (url.path.hasPrefix("/Applications") && !existing!.url.path.hasPrefix("/Applications")) {
                found[bid] = TargetApp(name: name, bundleIdentifier: bid, url: url)
            }
        }

        func scan(_ dir: URL) {
            let fm = FileManager.default
            guard let entries = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }
            for entry in entries where entry.pathExtension == "app" {
                add(from: entry)
            }
        }

        let home = FileManager.default.homeDirectoryForCurrentUser
        [URL(fileURLWithPath: "/Applications"),
         URL(fileURLWithPath: "/Applications/Utilities"),
         URL(fileURLWithPath: "/System/Applications"),
         home.appendingPathComponent("Applications")].forEach(scan)

        // Include whatever is running so an open app is always reachable.
        for app in NSWorkspace.shared.runningApplications {
            if let url = app.bundleURL, let bid = app.bundleIdentifier {
                let name = app.localizedName ?? url.deletingPathExtension().lastPathComponent
                if found[bid] == nil {
                    found[bid] = TargetApp(name: name, bundleIdentifier: bid, url: url)
                }
            }
        }

        return found.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}