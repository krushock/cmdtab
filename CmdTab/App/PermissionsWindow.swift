import AppKit
import SwiftUI

/// Shown at launch while a permission is missing. Nothing else in the app runs until both are granted.
@MainActor
final class PermissionsWindowController: NSObject, NSWindowDelegate {
    private let window: NSWindow
    private let onGranted: () -> Void

    init(onGranted: @escaping () -> Void) {
        self.onGranted = onGranted
        let hosting = NSHostingController(rootView: PermissionsView(onGranted: onGranted))
        let window = NSWindow(contentViewController: hosting)
        window.title = "CmdTab"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 480, height: 400))
        window.center()
        self.window = window
        super.init()
        window.delegate = self
    }

    func show() {
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    func close() {
        window.delegate = nil
        window.close()
    }

    /// Closing the window before the grants exist means the app cannot do anything, so it quits.
    func windowWillClose(_ notification: Notification) {
        NSApp.terminate(nil)
    }
}

private struct PermissionsView: View {
    let onGranted: () -> Void
    @State private var hasAccessibility = Permissions.hasAccessibility
    @State private var hasScreenRecording = Permissions.hasScreenRecording

    var body: some View {
        VStack(spacing: 20) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 72, height: 72)
            VStack(spacing: 6) {
                Text("CmdTab needs two permissions")
                    .font(.title2.weight(.semibold))
                Text("The switcher stays off until both are granted. Grant them in System Settings, then come back here.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 12) {
                PermissionCard(
                    name: "Accessibility",
                    detail: "Intercepts the shortcut before macOS does and raises the chosen window.",
                    granted: hasAccessibility
                ) {
                    Permissions.requestAccessibility()
                    Permissions.openAccessibilitySettings()
                }
                PermissionCard(
                    name: "Screen Recording",
                    detail: "Reads window titles and renders the window previews.",
                    granted: hasScreenRecording
                ) {
                    Permissions.requestScreenRecording()
                    Permissions.openScreenRecordingSettings()
                }
            }

            HStack {
                Button("Quit") { NSApp.terminate(nil) }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Text(hasAccessibility && hasScreenRecording ? "Starting…" : "Waiting for permissions…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(28)
        .frame(width: 480)
        .task {
            while !Task.isCancelled {
                hasAccessibility = Permissions.hasAccessibility
                hasScreenRecording = Permissions.hasScreenRecording
                if hasAccessibility && hasScreenRecording {
                    try? await Task.sleep(for: .milliseconds(400))
                    onGranted()
                    return
                }
                try? await Task.sleep(for: .milliseconds(700))
            }
        }
    }
}

private struct PermissionCard: View {
    let name: String
    let detail: String
    let granted: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: granted ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 24))
                .foregroundStyle(granted ? Color.green : Color.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).fontWeight(.medium)
                Text(detail).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if granted {
                Text("Granted").font(.callout).foregroundStyle(.secondary)
            } else {
                Button("Open System Settings…", action: action)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.secondary.opacity(0.2)))
    }
}
