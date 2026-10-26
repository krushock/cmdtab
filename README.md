# CmdTab

A small, native macOS window switcher in the spirit of [AltTab](https://alt-tab-macos.netlify.app): it replaces ⌘⇥ (or any shortcut you pick), can list every window instead of just apps, and comes with four animated styles.

Requires macOS 26 or newer. Written in Swift with AppKit + SwiftUI, no dependencies.

## Features

- **Any shortcut**, including ⌘⇥ itself. Hold the modifier and tap the key to cycle, add ⇧ to go back, release the modifier to switch. A quick tap jumps straight to the previous window without showing the UI.
- **Second shortcut** (default ⌘`) for the windows of the current app only. Pressing it while ⌘⇥ is open switches scope on the fly.
- **Windows or apps.** "Show every window" gives each Chrome window (or any other app's window) its own entry. App mode groups like the system switcher and also lists apps without windows.
- **Four styles**, all spring-animated: Classic (row of icons like macOS), Grid (previews in a grid, AltTab style), Cover Flow (3D carousel like the screenshot that started this), Filmstrip (one line of previews).
- **Live previews** of every window via ScreenCaptureKit, including minimized windows and windows on other Spaces.
- **Mouse** hover selects, click switches, click outside cancels.
- **Keys while open:** ←/→/↑/↓ move, ↩ switch, ⎋ cancel, W close window, M minimize, Q quit app.
- Menu bar item with quick style switching, launch at login, a Preview button in Settings.

## Build

```bash
./build.sh
```

That renders the app icon, generates `CmdTab.xcodeproj` with [xcodegen](https://github.com/yonaslab/XcodeGen) and builds into `build/CmdTab.app`. Or open the generated project in Xcode. Signing uses the "Apple Development" identity on this Mac; keep the signing identity stable, otherwise macOS forgets the permissions after every rebuild.

Copy `build/CmdTab.app` to `/Applications` for day-to-day use (launch at login expects a stable location).

## Permissions

CmdTab needs two grants in System Settings → Privacy & Security:

- **Accessibility** to intercept the shortcut before the system does and to raise windows.
- **Screen Recording** for window previews and titles. Without it the switcher still works with app icons.

The Settings window shows the state of both and opens the right pane. Relaunch after granting Screen Recording.

## How it works

- `Input/EventTap.swift` installs a session-level `CGEventTap`; `Switcher/SwitcherController.swift` is the state machine (open, cycle, commit on modifier release).
- `Core/WindowSource.swift` enumerates windows with `SCShareableContent` and cross-checks them against each app's Accessibility window list (`Core/AXWindowCache.swift`), which also provides the minimized state.
- `Core/ThumbnailStore.swift` captures previews with `SCScreenshotManager`, a few at a time.
- `Core/WindowActivator.swift` focuses the chosen window with the same private SkyLight calls AltTab uses (`_SLPSSetFrontProcessWithOptions`), since public activation is refused for background apps since macOS 14, then raises it via Accessibility.
- `Switcher/Styles/*` are plain SwiftUI views hosted in a borderless non-activating `NSPanel`.
