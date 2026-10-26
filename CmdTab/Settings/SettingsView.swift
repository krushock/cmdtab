import SwiftUI

struct SettingsView: View {
    @Bindable var settings: AppSettings
    var onPreview: () -> Void = {}
    @State private var hasAccessibility = Permissions.hasAccessibility
    @State private var hasScreenRecording = Permissions.hasScreenRecording
    @State private var launchAtLogin = false

    var body: some View {
        Form {
            Section("Shortcuts") {
                LabeledContent("Switch windows") {
                    ShortcutRecorder(shortcut: Binding(
                        get: { settings.mainShortcut },
                        set: { if let s = $0 { settings.mainShortcut = s } }), allowClear: false)
                }
                LabeledContent("Windows of current app") {
                    ShortcutRecorder(shortcut: $settings.appWindowsShortcut)
                }
                Text("Hold the modifier and press the key to cycle forward, add ⇧ to go back. Release the modifier to switch. ⎋ cancels, W closes the window, M minimizes it, Q quits the app. Setting ⌘⇥ replaces the built-in switcher.")
                    .font(.callout).foregroundStyle(.secondary)
            }

            Section("Style") {
                StylePicker(selection: $settings.style)
                HStack {
                    Button("Preview Switcher") { onPreview() }
                    Text("⇥ cycles, ↩ switches, ⎋ closes").font(.callout).foregroundStyle(.secondary)
                }
                Toggle("Dim and blur the desktop behind the switcher", isOn: $settings.dimBackground)
                    .disabled(!settings.style.usesFullScreenBackdrop)
                LabeledContent("Show after") {
                    HStack {
                        Slider(value: $settings.showDelay, in: 0...0.5, step: 0.05)
                        Text(String(format: "%.0f ms", settings.showDelay * 1000))
                            .monospacedDigit().frame(width: 60, alignment: .trailing)
                    }
                }
                Text("A quick tap switches straight to the previous window without showing the switcher.")
                    .font(.callout).foregroundStyle(.secondary)
            }

            Section("Windows") {
                Toggle("Show every window, not just apps", isOn: $settings.showAllWindows)
                Text("Each window of an app (for example several Chrome windows) gets its own entry.")
                    .font(.callout).foregroundStyle(.secondary)
                Toggle("Include minimized windows", isOn: $settings.includeMinimized)
                Toggle("Include windows from other Spaces", isOn: $settings.includeOtherSpaces)
                Toggle("Include apps without windows (app mode)", isOn: $settings.appsWithoutWindows)
            }

            Section("Displays") {
                Picker("Show the switcher on", selection: $settings.displayRule) {
                    ForEach(SwitcherDisplayRule.allCases) { Text($0.title).tag($0) }
                }
                Picker("List windows", selection: $settings.windowDisplayFilter) {
                    ForEach(WindowDisplayFilter.allCases) { Text($0.title).tag($0) }
                }
                Text("With a single display both settings make no difference.")
                    .font(.callout).foregroundStyle(.secondary)
            }

            Section("General") {
                Toggle("Launch at login", isOn: Binding(
                    get: { launchAtLogin },
                    set: { settings.launchAtLogin = $0; launchAtLogin = settings.launchAtLogin }))
                Toggle("Hide menu bar icon", isOn: $settings.hideMenuBarIcon)
                if settings.hideMenuBarIcon {
                    Text("To open Settings again, open CmdTab from Finder or Spotlight while it is running.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }

            Section("Permissions") {
                PermissionRow(name: "Accessibility", granted: hasAccessibility,
                              detail: "Needed to intercept the shortcut and to raise windows.") {
                    Permissions.requestAccessibility()
                    Permissions.openAccessibilitySettings()
                }
                PermissionRow(name: "Screen Recording", granted: hasScreenRecording,
                              detail: "Needed for window previews and titles.") {
                    Permissions.requestScreenRecording()
                    Permissions.openScreenRecordingSettings()
                }
                if !hasScreenRecording {
                    Text("If you just granted Screen Recording, quit and relaunch CmdTab for previews to appear.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 560)
        .frame(minHeight: 640)
        .task {
            launchAtLogin = settings.launchAtLogin
            while !Task.isCancelled {
                hasAccessibility = Permissions.hasAccessibility
                hasScreenRecording = Permissions.hasScreenRecording
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
}

private struct PermissionRow: View {
    let name: String
    let granted: Bool
    let detail: String
    let action: () -> Void

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: granted ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(granted ? Color.green : Color.red)
                    Text(name).fontWeight(.medium)
                }
                Text(detail).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            if !granted {
                Button("Grant…", action: action)
            }
        }
    }
}

// MARK: - Style picker with schematic previews

private struct StylePicker: View {
    @Binding var selection: SwitcherStyle

    var body: some View {
        HStack(spacing: 10) {
            ForEach(SwitcherStyle.allCases) { style in
                VStack(spacing: 6) {
                    StylePreview(style: style)
                        .frame(width: 92, height: 62)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(nsColor: .windowBackgroundColor)))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(selection == style ? Color.accentColor : Color.secondary.opacity(0.3),
                                          lineWidth: selection == style ? 2.5 : 1))
                    Text(style.title).font(.callout).fontWeight(selection == style ? .semibold : .regular)
                    Text(style.subtitle).font(.caption2).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center).frame(height: 26, alignment: .top)
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .onTapGesture { withAnimation(.snappy) { selection = style } }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct StylePreview: View {
    let style: SwitcherStyle

    var body: some View {
        let fill = Color.secondary.opacity(0.35)
        let sel = Color.accentColor
        ZStack {
            LinearGradient(colors: [Color.blue.opacity(0.35), Color.purple.opacity(0.3)], startPoint: .topLeading, endPoint: .bottomTrailing)
            switch style {
            case .classic:
                RoundedRectangle(cornerRadius: 6).fill(.ultraThinMaterial).frame(width: 84, height: 24)
                HStack(spacing: 4) {
                    ForEach(0..<5) { i in
                        RoundedRectangle(cornerRadius: 3).fill(i == 1 ? sel : fill).frame(width: 12, height: 12)
                    }
                }
            case .grid:
                VStack(spacing: 5) {
                    ForEach(0..<2) { r in
                        HStack(spacing: 5) {
                            ForEach(0..<3) { c in
                                RoundedRectangle(cornerRadius: 2).fill(r == 0 && c == 1 ? sel : fill).frame(width: 22, height: 15)
                            }
                        }
                    }
                }
            case .coverFlow:
                ZStack {
                    RoundedRectangle(cornerRadius: 2).fill(fill).frame(width: 30, height: 22)
                        .rotation3DEffect(.degrees(55), axis: (0, 1, 0), perspective: 0.6).offset(x: -30)
                    RoundedRectangle(cornerRadius: 2).fill(fill).frame(width: 30, height: 22)
                        .rotation3DEffect(.degrees(-55), axis: (0, 1, 0), perspective: 0.6).offset(x: 30)
                    RoundedRectangle(cornerRadius: 2).fill(sel).frame(width: 36, height: 26)
                }
            case .ring:
                ZStack {
                    ForEach(0..<6) { i in
                        let a = Double(i) / 6 * 2 * .pi
                        let c = cos(a), s = sin(a)
                        RoundedRectangle(cornerRadius: 2).fill(i == 0 ? sel : fill)
                            .frame(width: 14 + 12 * (c + 1) / 2, height: 10 + 8 * (c + 1) / 2)
                            .offset(x: s * 36, y: c * 11)
                            .zIndex(c)
                    }
                }
            case .filmstrip:
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 2).fill(fill).frame(width: 24, height: 16)
                    RoundedRectangle(cornerRadius: 2).fill(sel).frame(width: 30, height: 20)
                    RoundedRectangle(cornerRadius: 2).fill(fill).frame(width: 24, height: 16)
                }
            }
        }
    }
}
