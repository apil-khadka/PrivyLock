import AppKit
import AppLockCore

// MARK: - Small action target so menu rows and buttons can capture closures.

private final class ClosureAction: NSObject {
    let handler: () -> Void
    init(_ handler: @escaping () -> Void) { self.handler = handler; super.init() }
    @objc func run() { handler() }
}

// MARK: - Flipped document view so rows stack top-down inside the scroll view.

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

// MARK: - AppDelegate / status bar

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var guard_: AppGuard { .shared }
    private var windowController: MainWindowController?

    private var statusItem: NSStatusItem?
    private var menuRefs: [Any] = []   // retain closure targets / menus
    private var keyMonitor: Any?
    private var blockedLaunchPrompts = Set<String>()

    // Event handlers referenced by NSMenuItem.selectors.
    private var open: ClosureAction!
    private var addApp: ClosureAction!
    private var lockAll: ClosureAction!
    private var unlockAll: ClosureAction!
    private var quit: ClosureAction!

    func applicationDidFinishLaunching(_ notification: Notification) {
        LockStore.shared.load()
        NSApp.setActivationPolicy(.accessory)
        installQuitShortcut()

        buildStatusItem()

        guard_.onStateChange = { [weak self] in
            self?.rebuildMenu()
            self?.windowController?.refresh()
        }
        guard_.onBlockedLaunch = { [weak self] target in
            self?.presentUnlockPrompt(for: target)
        }

        // Launch-at-login descriptor is stored independently (LaunchAgent), so
        // reconcile the persisted preference with the actual agent on startup.
        reconcileLaunchAtLoginSetting()

        // Show the main window once on first launch so users see what this is.
        windowController = MainWindowController()
        windowController?.show()
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    private func reconcileLaunchAtLoginSetting() {
        // If the user has an old Agent but the pref is off, disable it; if the
        // pref is on but no agent exists, recreate it.
        DispatchQueue.main.async {
            if self.guard_.store.state.launchAtLogin != LaunchAtLogin.isEnabled {
                _ = LaunchAtLogin.isEnabled ? LaunchAtLogin.disable() : nil
                if self.guard_.store.state.launchAtLogin {
                    _ = LaunchAtLogin.enable()
                }
                self.guard_.store.save()
            }
        }
    }

    // MARK: Status item + menu

    private func buildStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "lock.shield", accessibilityDescription: "AppLock")
        statusItem = item
        rebuildMenu()
    }

    /// Status-item menus are not always the active menu, so their key
    /// equivalents alone do not reliably receive Command-Q. Handle it at the
    /// application level as well, ensuring the process actually terminates.
    private func installQuitShortcut() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let hasCommand = event.modifierFlags.contains(.command)
            let isQuit = event.charactersIgnoringModifiers?.lowercased() == "q"
            let isHideWindow = event.charactersIgnoringModifiers?.lowercased() == "w"
            guard hasCommand else { return event }

            if isQuit {
                (NSApp.delegate as? AppDelegate)?.requestQuit()
                return nil
            }
            if isHideWindow,
               let delegate = NSApp.delegate as? AppDelegate,
               let window = delegate.windowController?.window,
               event.window === window {
                delegate.windowController?.hide()
                return nil
            }
            return event
        }
    }

    private func requestQuit() {
        guard guard_.protectedApps.contains(where: { $0.isLocked }) else {
            NSApp.terminate(nil)
            return
        }

        // Quitting while a protected app is locked would silently disable the
        // watchdog. Require the same owner authentication used for unlocking.
        TouchID.authenticate(localizedReason: "quit AppLock while protected apps are locked") { outcome in
            if case .success = outcome {
                NSApp.terminate(nil)
            }
        }
    }

    private func rebuildMenu() {
        guard let statusItem else { return }
        menuRefs.removeAll()

        let menu = NSMenu()

        open = ClosureAction { [weak self] in self?.windowController?.show() }
        let openItem = NSMenuItem(title: "Open AppLock…", action: #selector(ClosureAction.run), keyEquivalent: "o")
        openItem.target = open
        menu.addItem(openItem)
        menuRefs.append(open!)

        menu.addItem(.separator())

        let apps = guard_.protectedApps
        if apps.isEmpty {
            let none = NSMenuItem(title: "No protected apps yet", action: nil, keyEquivalent: "")
            none.isEnabled = false
            menu.addItem(none)
        } else {
            for protected in apps {
                let locked = protected.isLocked
                let target = protected.target
                let title = locked ? "🔒 \(target.name)" : "🔓 \(target.name)"
                let item = NSMenuItem(title: title, action: #selector(ClosureAction.run), keyEquivalent: "")
                let action = ClosureAction { [weak self] in self?.toggleLock(bundleIdentifier: target.bundleIdentifier) }
                item.target = action
                menu.addItem(item)
                menuRefs.append(action)
            }
        }

        menu.addItem(.separator())

        addApp = ClosureAction { [weak self] in self?.beginAddApp() }
        let add = NSMenuItem(title: "Add Protected App…", action: #selector(ClosureAction.run), keyEquivalent: "n")
        add.target = addApp
        menu.addItem(add)
        menuRefs.append(addApp!)

        if !apps.isEmpty {
            lockAll = ClosureAction { [weak self] in self?.guard_.lockAll() }
            let la = NSMenuItem(title: "Lock All", action: #selector(ClosureAction.run), keyEquivalent: "l")
            la.target = lockAll
            menu.addItem(la)
            menuRefs.append(lockAll!)

            unlockAll = ClosureAction { [weak self] in self?.guard_.requestUnlockAll() }
            let ua = NSMenuItem(title: "Unlock All (Touch ID or Password)", action: #selector(ClosureAction.run), keyEquivalent: "u")
            ua.target = unlockAll
            menu.addItem(ua)
            menuRefs.append(unlockAll!)
        }

        menu.addItem(.separator())

        if !TouchID.isAvailable {
            let warn = NSMenuItem(title: "⚠ No authentication method is available",
                                  action: nil, keyEquivalent: "")
            warn.isEnabled = false
            menu.addItem(warn)
        }

        let state = NSMenuItem(
            title: "\(apps.filter { $0.isLocked }.count) of \(apps.count) protected apps locked",
            action: nil, keyEquivalent: "")
        state.isEnabled = false
        menu.addItem(state)

        quit = ClosureAction { [weak self] in self?.requestQuit() }
        let q = NSMenuItem(title: "Quit AppLock", action: #selector(ClosureAction.run), keyEquivalent: "q")
        q.target = quit
        menu.addItem(q)
        menuRefs.append(quit!)

        statusItem.menu = menu
    }

    private func toggleLock(bundleIdentifier: String) {
        if guard_.isLocked(bundleIdentifier: bundleIdentifier) {
            guard_.requestUnlock(bundleIdentifier: bundleIdentifier)
        } else {
            guard_.lock(bundleIdentifier: bundleIdentifier)
        }
    }

    private func presentUnlockPrompt(for target: TargetApp) {
        // willLaunch and didLaunch can both fire for one attempt. Keep one
        // prompt per app until the user has answered it.
        guard blockedLaunchPrompts.insert(target.bundleIdentifier).inserted else { return }

        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "\(target.name) is locked"
        alert.informativeText = "Authenticate with Touch ID or your Mac login password to open this protected app."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Unlock with Touch ID or Password")
        alert.addButton(withTitle: "Cancel")

        let finish: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard let self else { return }
            self.blockedLaunchPrompts.remove(target.bundleIdentifier)
            if response == .alertFirstButtonReturn {
                self.guard_.requestUnlock(bundleIdentifier: target.bundleIdentifier)
            }
        }

        if let window = windowController?.window, window.isVisible {
            alert.beginSheetModal(for: window) { finish($0) }
        } else {
            finish(alert.runModal())
        }
    }

    // MARK: Add-app chooser

    func beginAddApp() {
        let controller = windowController
        let window = controller?.window ?? NSApp.windows.first
        presentAddSheet(on: window)
    }

    private func presentAddSheet(on window: NSWindow?) {
        let apps = AppCatalog.installedApps()
        let alreadyProtected = Set(guard_.store.state.apps.keys)

        let alert = NSAlert()
        alert.messageText = "Add a Protected App"
        alert.informativeText = "Choose an app. It will be locked immediately and can be reopened with Touch ID or your Mac login password."
        alert.alertStyle = .informational

        let search = NSSearchField()
        search.placeholderString = "Search apps…"
        search.isEditable = true

        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        let stack = NSStackView(views: [search, popup])
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 8

        // NSAlert does not reliably size a bare NSStackView accessory. Give it
        // an explicit container so the alert's message text cannot overlap the
        // search field or popup (which otherwise makes the search field appear
        // visible but impossible to click).
        let accessory = NSView(frame: NSRect(x: 0, y: 0, width: 340, height: 60))
        accessory.translatesAutoresizingMaskIntoConstraints = false
        accessory.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            accessory.widthAnchor.constraint(equalToConstant: 340),
            accessory.heightAnchor.constraint(equalToConstant: 60),
            stack.topAnchor.constraint(equalTo: accessory.topAnchor),
            stack.leadingAnchor.constraint(equalTo: accessory.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: accessory.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: accessory.bottomAnchor),
            search.heightAnchor.constraint(equalToConstant: 24),
            popup.heightAnchor.constraint(equalToConstant: 26),
        ])
        alert.accessoryView = accessory

        func refill() {
            let query = search.stringValue.lowercased()
            let selected = popup.indexOfSelectedItem
            popup.removeAllItems()
            popup.addItem(withTitle: "Select an app…")
            for app in apps where !alreadyProtected.contains(app.bundleIdentifier) {
                if query.isEmpty || app.name.lowercased().contains(query) {
                    popup.addItem(withTitle: app.name)
                    popup.lastItem?.representedObject = app.bundleIdentifier
                }
            }
            if selected < popup.numberOfItems { popup.selectItem(at: selected) }
        }
        refill()

        let observer = NotificationCenter.default.addObserver(
            forName: NSSearchField.textDidChangeNotification,
            object: search, queue: .main
        ) { _ in refill() }

        alert.addButton(withTitle: "Protect")
        alert.addButton(withTitle: "Cancel")

        func finish(_ response: NSApplication.ModalResponse) {
            NotificationCenter.default.removeObserver(observer)
            guard response == .alertFirstButtonReturn else { return }
            guard popup.indexOfSelectedItem > 0,
                  let bundleIdentifier = popup.selectedItem?.representedObject as? String,
                  let app = apps.first(where: { $0.bundleIdentifier == bundleIdentifier }) else { return }
            self.guard_.add(app)
            self.guard_.lock(bundleIdentifier: app.bundleIdentifier)
        }

        if let window {
            alert.beginSheetModal(for: window) { finish($0) }
        } else {
            finish(alert.runModal())
        }
    }
}

// MARK: - Main window

final class MainWindowController: NSObject, NSWindowDelegate {

    let window: NSWindow
    private let guard_ = AppGuard.shared

    private let searchField = NSSearchField()
    private let addButton = NSButton(title: "Add App…", target: nil, action: nil)
    private let lockAllButton = NSButton(title: "Lock All", target: nil, action: nil)
    private let countLabel = NSTextField(labelWithString: "")
    private let listHost = FlippedView()
    private let listStack = NSStackView(views: [])
    private var listHeightConstraint: NSLayoutConstraint!

    private let autolockCheckbox = NSButton(checkboxWithTitle: "Auto-lock when the screen locks", target: nil, action: nil)
    private let idlePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let loginCheckbox = NSButton(checkboxWithTitle: "Start AppLock at login", target: nil, action: nil)
    private let touchIDWarning = NSTextField(wrappingLabelWithString: "")

    private var rowActionTargets: [Any] = []

    override init() {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 470, height: 430),
                         styleMask: [.titled, .closable, .resizable, .miniaturizable],
                         backing: .buffered, defer: true)
        w.title = "AppLock"
        w.isReleasedWhenClosed = false
        w.minSize = NSSize(width: 420, height: 360)
        self.window = w
        super.init()
        w.delegate = self
        buildContent()
    }

    func show() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        refresh()
    }

    func hide() {
        window.orderOut(nil)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        hide()
        return false
    }

    // MARK: Layout

    private func buildContent() {
        // Header row
        let title = NSTextField(labelWithString: "Protected Apps")
        title.font = NSFont.boldSystemFont(ofSize: 14)

        searchField.placeholderString = "Filter apps…"
        searchField.setAccessibilityLabel("Filter apps")
        searchField.target = self
        searchField.action = #selector(searchChanged(_:))

        addButton.bezelStyle = .rounded
        addButton.target = self
        addButton.action = #selector(addButtonClicked(_:))

        let header = NSStackView(views: [title, searchField, addButton])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 10

        // List area
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.documentView = listHost

        listStack.orientation = .vertical
        listStack.alignment = .width
        listStack.spacing = 2

        listHost.addSubview(listStack)
        listHost.translatesAutoresizingMaskIntoConstraints = false
        listStack.translatesAutoresizingMaskIntoConstraints = false
        listHeightConstraint = listHost.heightAnchor.constraint(equalToConstant: 120)
        NSLayoutConstraint.activate([
            listStack.topAnchor.constraint(equalTo: listHost.topAnchor, constant: 6),
            listStack.leadingAnchor.constraint(equalTo: listHost.leadingAnchor, constant: 8),
            listStack.trailingAnchor.constraint(equalTo: listHost.trailingAnchor, constant: -8),
            listStack.bottomAnchor.constraint(equalTo: listHost.bottomAnchor, constant: -6),
            listHost.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            listHeightConstraint,
        ])

        // Bottom action bar
        lockAllButton.bezelStyle = .rounded
        lockAllButton.target = self
        lockAllButton.action = #selector(lockAllClicked(_:))

        countLabel.textColor = .secondaryLabelColor
        countLabel.font = NSFont.systemFont(ofSize: 11)

        let bar = NSStackView(views: [countLabel, NSView(), lockAllButton])
        bar.orientation = .horizontal
        bar.alignment = .centerY
        bar.spacing = 8

        // Settings section
        autolockCheckbox.target = self
        autolockCheckbox.action = #selector(autolockToggled(_:))

        idlePopup.addItem(withTitle: "Never")
        idlePopup.addItem(withTitle: "1 minute")
        idlePopup.addItem(withTitle: "5 minutes")
        idlePopup.addItem(withTitle: "15 minutes")
        idlePopup.addItem(withTitle: "30 minutes")
        idlePopup.addItem(withTitle: "1 hour")
        idlePopup.target = self
        idlePopup.action = #selector(idleChanged(_:))

        loginCheckbox.target = self
        loginCheckbox.action = #selector(loginToggled(_:))

        let idleRow = NSStackView(views: [NSTextField(labelWithString: "Auto-lock after inactivity:"), idlePopup])
        idleRow.orientation = .horizontal
        idleRow.alignment = .centerY
        idleRow.spacing = 6

        let icons = [autolockCheckbox, idleRow, loginCheckbox]
        let settings = NSStackView(views: icons)
        settings.orientation = .vertical
        settings.alignment = .leading
        settings.spacing = 4

        touchIDWarning.textColor = .systemOrange
        touchIDWarning.font = NSFont.systemFont(ofSize: 11)
        touchIDWarning.isHidden = true

        let separator = NSBox()
        separator.boxType = .separator

        // Wrap everything in a background material for a modern panel look.
        let root = NSVisualEffectView()
        root.material = .underWindowBackground
        root.blendingMode = .behindWindow

        let vertical = NSStackView(views: [header, scroll, bar, separator, settings, touchIDWarning])
        vertical.orientation = .vertical
        vertical.alignment = .width
        vertical.spacing = 10
        vertical.edgeInsets = NSEdgeInsets(top: 14, left: 16, bottom: 14, right: 16)

        root.addSubview(vertical)
        vertical.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            vertical.topAnchor.constraint(equalTo: root.topAnchor),
            vertical.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            vertical.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            vertical.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])

        // Let the list expand; cap the settings area size.
        scroll.setContentHuggingPriority(.defaultLow, for: .vertical)
        scroll.setContentCompressionResistancePriority(.defaultLow, for: .vertical)

        window.contentView = root
    }

    // MARK: Refresh

    func refresh() {
        let apps = guard_.protectedApps
        let query = searchField.stringValue.lowercased()

        // Rows
        rowActionTargets.removeAll()
        for view in listStack.views {
            listStack.removeView(view)
            view.removeFromSuperview()
        }

        let filtered = apps.filter {
            query.isEmpty ||
                $0.target.name.lowercased().contains(query) ||
                $0.target.bundleIdentifier.lowercased().contains(query)
        }

        if apps.isEmpty {
            addEmptyRow("No protected apps yet. Click “Add App…” to protect one.")
        } else if filtered.isEmpty {
            addEmptyRow("No apps match “\(searchField.stringValue)”.")
        } else {
            for protected in filtered {
                addRow(protected)
            }
        }

        // Counts + buttons
        let locked = apps.filter { $0.isLocked }.count
        countLabel.stringValue = "\(apps.count) protected · \(locked) locked"
        lockAllButton.title = locked > 0 ? "Unlock All (Touch ID or Password)" : "Lock All"
        lockAllButton.isEnabled = !apps.isEmpty
        lockAllButton.tag = locked > 0 ? 1 : 0

        // Settings
        autolockCheckbox.state = guard_.store.state.autoLockOnScreenLock ? .on : .off
        loginCheckbox.state = guard_.store.state.launchAtLogin ? .on : .off
        if let minutes = guard_.store.state.idleAutoLockMinutes {
            let idx = self.idleOptionIndex(for: minutes)
            if idlePopup.indexOfSelectedItem != idx { idlePopup.selectItem(at: idx) }
        } else {
            if idlePopup.indexOfSelectedItem != 0 { idlePopup.selectItem(at: 0) }
        }

        touchIDWarning.isHidden = TouchID.isBiometricAvailable || !TouchID.isAvailable
        touchIDWarning.stringValue = "⚠ Touch ID is unavailable. AppLock will use your Mac login password instead."

        // The document view needs an explicit height. Relying only on its
        // intrinsic fitting size leaves NSScrollView with a zero-height
        // document on some macOS releases, hiding otherwise valid rows.
        let rowHeight: CGFloat = filtered.isEmpty ? 48 : 50
        listHeightConstraint.constant = max(CGFloat(filtered.count) * rowHeight + 16, 120)
        listStack.layoutSubtreeIfNeeded()
        listHost.needsLayout = true

        // Keep the focused search field working after rebuilds.
        if window.firstResponder != searchField.currentEditor() {
            window.makeFirstResponder(searchField)
        }
    }

    private func idleOptionIndex(for minutes: Int) -> Int {
        switch minutes {
        case 0: return 0
        case 1: return 1
        case 5: return 2
        case 15: return 3
        case 30: return 4
        case 60: return 5
        default: return 0
        }
    }

    private func addEmptyRow(_ text: String) {
        let label = NSTextField(wrappingLabelWithString: text)
        label.textColor = .secondaryLabelColor
        label.font = NSFont.systemFont(ofSize: 12)
        let row = NSStackView(views: [label])
        row.orientation = .horizontal
        row.edgeInsets = NSEdgeInsets(top: 12, left: 4, bottom: 12, right: 4)
        listStack.addView(row, in: .top)
    }

    private func addRow(_ protected: ProtectedApp) {
        let target = protected.target

        // Icon
        let icon = NSImageView()
        let appIcon = NSWorkspace.shared.icon(forFile: target.url.path)
        appIcon.size = NSSize(width: 32, height: 32)
        icon.image = appIcon
        icon.imageScaling = .scaleProportionallyDown
        icon.widthAnchor.constraint(equalToConstant: 32).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 32).isActive = true

        // Name + status
        let name = NSTextField(labelWithString: target.name)
        name.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        name.lineBreakMode = .byTruncatingTail

        let status = NSTextField(labelWithString: protected.isLocked ? "Locked" : "Unlocked")
        status.textColor = protected.isLocked ? .systemRed : .systemGreen
        status.font = NSFont.systemFont(ofSize: 11)

        let identifier = NSTextField(labelWithString: target.bundleIdentifier)
        identifier.textColor = .tertiaryLabelColor
        identifier.font = NSFont.systemFont(ofSize: 10)
        identifier.lineBreakMode = .byTruncatingMiddle

        let labels = NSStackView(views: [name, status, identifier])
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 2

        // Buttons
        let toggle = NSButton(title: protected.isLocked ? "Unlock (Touch ID or Password)" : "Lock",
                              target: nil, action: nil)
        toggle.bezelStyle = .rounded
        toggle.controlSize = .small
        let toggleAction = ClosureAction { [weak self] in self?.guard_.toggle(bundleIdentifier: target.bundleIdentifier, requiresAuth: protected.isLocked) }
        toggle.target = toggleAction
        toggle.action = #selector(ClosureAction.run)
        rowActionTargets.append(toggleAction)

        let remove = NSButton(image: NSImage(systemSymbolName: "trash", accessibilityDescription: "Remove")!,
                              target: nil, action: nil)
        remove.bezelStyle = .texturedRounded
        remove.isBordered = false
        remove.setAccessibilityLabel("Remove \(target.name)")
        let removeAction = ClosureAction { [weak self] in
            self?.guard_.requestRemove(bundleIdentifier: target.bundleIdentifier)
        }
        remove.target = removeAction
        remove.action = #selector(ClosureAction.run)
        rowActionTargets.append(removeAction)

        let row = NSStackView(views: [icon, labels, NSView(), toggle, remove])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        row.edgeInsets = NSEdgeInsets(top: 6, left: 4, bottom: 6, right: 4)

        listStack.addView(row, in: .top)
    }

    // MARK: Actions

    @objc private func searchChanged(_ sender: NSSearchField) { refresh() }

    @objc private func addButtonClicked(_ sender: Any) {
        (NSApp.delegate as? AppDelegate)?.beginAddApp()
    }

    @objc private func lockAllClicked(_ sender: NSButton) {
        if guard_.protectedApps.contains(where: { $0.isLocked }) {
            guard_.requestUnlockAll()
        } else {
            guard_.lockAll()
        }
    }

    @objc private func autolockToggled(_ sender: NSButton) {
        guard_.setAutoLockOnScreenLock(sender.state == .on)
        refresh()
    }

    @objc private func idleChanged(_ sender: NSPopUpButton) {
        let minutes: Int? = {
            switch sender.indexOfSelectedItem {
            case 1: return 1
            case 2: return 5
            case 3: return 15
            case 4: return 30
            case 5: return 60
            default: return nil
            }
        }()
        guard_.setIdleAutoLockMinutes(minutes)
        refresh()
    }

    @objc private func loginToggled(_ sender: NSButton) {
        guard_.setLaunchAtLogin(sender.state == .on)
        refresh()
    }
}

// Small helper so the UI stays tidy.
private extension AppGuard {
    func toggle(bundleIdentifier: String, requiresAuth: Bool) {
        if requiresAuth {
            requestUnlock(bundleIdentifier: bundleIdentifier)
        } else {
            lock(bundleIdentifier: bundleIdentifier)
        }
    }
}

// MARK: - Bootstrap

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
