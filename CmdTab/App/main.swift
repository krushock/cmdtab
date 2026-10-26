import AppKit

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let args = CommandLine.arguments
    if let i = args.firstIndex(of: "--screenshots"), i + 1 < args.count {
        // Developer mode: render README screenshots with synthetic windows, then exit.
        app.setActivationPolicy(.prohibited)
        ScreenshotRenderer.render(to: URL(fileURLWithPath: args[i + 1]))
        exit(0)
    }
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
