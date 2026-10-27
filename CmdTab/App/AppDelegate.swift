import AppKit
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var controller: SwitcherController?
    private var settingsWindow: SettingsWindowController?
    private var permissionsWindow: PermissionsWindowController?
    private var screenRecordingMissingAtLaunch = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        if Permissions.hasAccessibility && Permissions.hasScreenRecording {
            startApp()
        } else {
            screenRecordingMissingAtLaunch = !Permissions.hasScreenRecording
            let window = PermissionsWindowController { [weak self] in self?.permissionsGranted() }
            permissionsWindow = window
            window.show()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller?.stop()
    }

    /// Opening the app while it is running (Finder, Spotlight) opens Settings. This is the way in
    /// when the menu bar icon is hidden.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if controller != nil {
            showSettings()
        } else {
            permissionsWindow?.show()
        }
        return false
    }

    // MARK: - Startup

    private func permissionsGranted() {
        permissionsWindow?.close()
        permissionsWindow = nil
        if screenRecordingMissingAtLaunch {
            // ScreenCaptureKit only honours a Screen Recording grant from the next launch on.
            relaunch()
        } else {
            startApp()
        }
    }

    /// Everything that actually does something lives here, so nothing runs before the grants exist.
    private func startApp() {
        guard controller == nil else { return }
        let controller = SwitcherController(settings: AppSettings.shared)
        self.controller = controller
        updateStatusItem()
        observeMenuBarSetting()
        if !controller.start() {
            // Permission was revoked in the meantime; fall back to the permissions window.
            controller.stop()
            self.controller = nil
            if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
            statusItem = nil
            screenRecordingMissingAtLaunch = false
            let window = PermissionsWindowController { [weak self] in self?.permissionsGranted() }
            permissionsWindow = window
            window.show()
        }
    }

    private func relaunch() {
        let path = Bundle.main.bundlePath
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 0.5; /usr/bin/open -n \"\(path)\""]
        try? task.run()
        NSApp.terminate(nil)
    }

    // MARK: - Status item

    private func observeMenuBarSetting() {
        withObservationTracking {
            _ = AppSettings.shared.hideMenuBarIcon
        } onChange: {
            Task { @MainActor [weak self] in
                self?.updateStatusItem()
                self?.observeMenuBarSetting()
            }
        }
    }

    private func updateStatusItem() {
        if AppSettings.shared.hideMenuBarIcon {
            if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
            statusItem = nil
        } else if statusItem == nil {
            setupStatusItem()
        }
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "rectangle.2.swap", accessibilityDescription: "CmdTab")
        item.button?.image?.isTemplate = true
        item.button?.toolTip = "CmdTab"
        item.menu = buildMenu()
        statusItem = item
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self

        let settings = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())

        let styleMenu = NSMenu()
        for style in SwitcherStyle.allCases {
            let mi = NSMenuItem(title: style.title, action: #selector(selectStyle(_:)), keyEquivalent: "")
            mi.target = self
            mi.representedObject = style.rawValue
            styleMenu.addItem(mi)
        }
        let styleItem = NSMenuItem(title: "Switcher Style", action: nil, keyEquivalent: "")
        styleItem.submenu = styleMenu
        menu.addItem(styleItem)

        let windows = NSMenuItem(title: "Show All Windows", action: #selector(toggleWindows), keyEquivalent: "")
        windows.target = self
        menu.addItem(windows)
        menu.addItem(.separator())

        let about = NSMenuItem(title: "About CmdTab", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)
        let quit = NSMenuItem(title: "Quit CmdTab", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
        return menu
    }

    @objc func showSettings() {
        if settingsWindow == nil {
            settingsWindow = SettingsWindowController(
                settings: AppSettings.shared,
                onPreview: { [weak self] in self?.controller?.preview() },
                onPreviewExpose: { [weak self] in self?.controller?.previewExpose() })
        }
        settingsWindow?.show()
    }

    @objc private func selectStyle(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let style = SwitcherStyle(rawValue: raw) else { return }
        AppSettings.shared.style = style
    }

    @objc private func toggleWindows() {
        AppSettings.shared.showAllWindows.toggle()
    }

    @objc private func showAbout() {
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(nil)
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        let settings = AppSettings.shared
        for item in menu.items {
            if item.title == "Show All Windows" {
                item.state = settings.showAllWindows ? .on : .off
            }
            if let sub = item.submenu {
                for mi in sub.items {
                    mi.state = (mi.representedObject as? String) == settings.style.rawValue ? .on : .off
                }
            }
        }
    }
}
