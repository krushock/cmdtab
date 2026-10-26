import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {
    private let window: NSWindow

    init(settings: AppSettings, onPreview: @escaping () -> Void) {
        let hosting = NSHostingController(rootView: SettingsView(settings: settings, onPreview: onPreview))
        let window = NSWindow(contentViewController: hosting)
        window.title = "CmdTab Settings"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 560, height: 720))
        window.center()
        self.window = window
    }

    func show() {
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }
}
