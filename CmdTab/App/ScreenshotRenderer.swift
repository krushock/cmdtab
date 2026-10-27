import AppKit
import SwiftUI

/// Renders README screenshots of every style from synthetic data: system app icons, made-up titles and
/// drawn placeholder window contents. Nothing from the user's real screen is used.
@MainActor
enum ScreenshotRenderer {
    static let size = CGSize(width: 1440, height: 900)

    private struct Sample {
        let bundleID: String
        let name: String
        let title: String
        let tint: NSColor
        let aspect: CGFloat
    }

    private static let samples: [Sample] = [
        Sample(bundleID: "com.apple.Safari", name: "Safari", title: "Swift.org — Welcome to Swift", tint: .systemBlue, aspect: 1.6),
        Sample(bundleID: "com.apple.Notes", name: "Notes", title: "Project notes", tint: .systemYellow, aspect: 1.3),
        Sample(bundleID: "com.apple.mail", name: "Mail", title: "Inbox – 3 messages", tint: .systemIndigo, aspect: 1.5),
        Sample(bundleID: "com.apple.Terminal", name: "Terminal", title: "zsh — 80×24", tint: .systemGreen, aspect: 1.4),
        Sample(bundleID: "com.apple.iCal", name: "Calendar", title: "October 2026", tint: .systemRed, aspect: 1.55),
        Sample(bundleID: "com.apple.dt.Xcode", name: "Xcode", title: "CmdTab — SwitcherController.swift", tint: .systemTeal, aspect: 1.7),
        Sample(bundleID: "com.apple.Music", name: "Music", title: "Now Playing", tint: .systemPink, aspect: 1.2),
    ]

    static func render(to dir: URL) {
        ScreenshotMode.enabled = true
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let windows = samples.enumerated().map { i, s in
            WindowInfo(id: CGWindowID(100 + i), pid: pid_t(1000 + i), title: s.title,
                       frame: CGRect(x: 0, y: 0, width: 1200, height: 1200 / s.aspect),
                       isOnScreen: true, isMinimized: i == 5, appName: s.name, bundleID: s.bundleID)
        }
        let items = zip(samples, windows).map { s, w in
            SwitcherItem(id: "win-\(w.id)", pid: w.pid, appName: s.name, title: s.title, subtitle: s.name,
                         icon: icon(for: s.bundleID), windows: [w], isApp: false)
        }
        let appItems = zip(samples, windows).map { s, w in
            SwitcherItem(id: "app-\(w.pid)", pid: w.pid, appName: s.name, title: s.name, subtitle: s.title,
                         icon: icon(for: s.bundleID), windows: [w], isApp: true)
        }
        var thumbs: [CGWindowID: CGImage] = [:]
        for (s, w) in zip(samples, windows) { thumbs[w.id] = placeholderWindow(tint: s.tint, size: w.frame.size, seed: Int(w.id)) }

        let model = SwitcherModel()
        model.thumbnails = thumbs
        model.dimBackground = true
        model.selectedIndex = 1
        let actions = SwitcherActions(hover: { _ in }, select: { _ in }, cancel: {})

        for style in SwitcherStyle.allCases {
            model.style = style
            model.scope = style == .classic ? .apps : .windows
            model.items = style == .classic ? appItems : items
            model.columns = GridLayout.columns(for: model.items.count)
            let view = ZStack {
                Wallpaper()
                SwitcherRootView(model: model, actions: actions)
            }
            .frame(width: size.width, height: size.height)
            write(view, to: dir.appendingPathComponent("\(style.rawValue).jpg"))
        }
        // Exposé with a drag in progress over another window.
        let exposeModel = ExposeModel()
        exposeModel.thumbnails = thumbs
        let shown = Array(windows.prefix(6)).map { w in
            WindowInfo(id: w.id, pid: w.pid, title: w.title,
                       frame: CGRect(x: 0, y: 0, width: w.frame.width * 0.9, height: w.frame.height * 0.9),
                       isOnScreen: true, isMinimized: false, appName: w.appName, bundleID: w.bundleID)
        }
        let area = CGRect(x: 70, y: 80, width: size.width - 140, height: size.height - 170)
        let frames = ExposeLayout.layout(shown, in: area)
        let tiles = zip(shown, items).map { w, item in ExposeTile(id: w.id, window: w, item: item, frame: frames[w.id] ?? .zero) }
        let screenFrame = CGRect(origin: .zero, size: size)
        exposeModel.screens = [ExposeScreen(id: 0, name: "Built-in Display", frame: screenFrame, tiles: tiles)]
        if let dragged = tiles.last, let target = tiles.first {
            let grab = CGSize(width: dragged.frame.width * 0.5, height: dragged.frame.height * 0.4)
            let panelPoint = CGPoint(x: target.frame.midX + target.frame.width * 0.3, y: target.frame.midY)
            exposeModel.drag = ExposeDrag(windowID: dragged.id, sourceScreen: 0, grabOffset: grab, tileSize: dragged.frame.size,
                                          location: exposeModel.screens[0].globalPoint(fromPanel: panelPoint),
                                          target: .window(target.id, .right))
        }
        let exposeActions = ExposeActions(hover: { _ in }, activate: { _ in }, dragChanged: { _, _, _, _ in }, dragEnded: {}, cancel: {})
        let exposeView = ZStack {
            Wallpaper()
            ExposeScreenView(model: exposeModel, screenIndex: 0, actions: exposeActions)
        }
        .frame(width: size.width, height: size.height)
        write(exposeView, to: dir.appendingPathComponent("expose.jpg"))

        print("wrote \(SwitcherStyle.allCases.count + 1) screenshots to \(dir.path)")
    }

    private static func write<V: View>(_ view: V, to url: URL) {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1.5
        guard let cg = renderer.cgImage else { print("render failed: \(url.lastPathComponent)"); return }
        let rep = NSBitmapImageRep(cgImage: cg)
        guard let data = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.82]) else { return }
        try? data.write(to: url)
    }

    private static func icon(for bundleID: String) -> NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return NSWorkspace.shared.icon(for: .application)
        }
        let img = NSWorkspace.shared.icon(forFile: url.path)
        img.size = NSSize(width: 256, height: 256)
        return img
    }

    /// A generic window: title bar with traffic lights, a sidebar and some text-like bars.
    private static func placeholderWindow(tint: NSColor, size: CGSize, seed: Int) -> CGImage? {
        let img = NSImage(size: size)
        img.lockFocus()
        NSColor(calibratedWhite: 0.96, alpha: 1).setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
        let barH: CGFloat = 52
        NSColor(calibratedWhite: 0.88, alpha: 1).setFill()
        NSBezierPath(rect: NSRect(x: 0, y: size.height - barH, width: size.width, height: barH)).fill()
        for (i, c) in [NSColor.systemRed, .systemYellow, .systemGreen].enumerated() {
            c.setFill()
            NSBezierPath(ovalIn: NSRect(x: 20 + CGFloat(i) * 28, y: size.height - barH / 2 - 9, width: 18, height: 18)).fill()
        }
        let sidebarW = size.width * 0.24
        tint.withAlphaComponent(0.12).setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: sidebarW, height: size.height - barH)).fill()
        var rng = seed * 7919 + 13
        func next() -> CGFloat { rng = (rng &* 1103515245 &+ 12345) & 0x7fffffff; return CGFloat(rng % 1000) / 1000 }
        tint.withAlphaComponent(0.5).setFill()
        var y = size.height - barH - 40
        for _ in 0..<8 {
            NSBezierPath(roundedRect: NSRect(x: 24, y: y, width: sidebarW * (0.4 + 0.5 * next()), height: 14), xRadius: 7, yRadius: 7).fill()
            y -= 34
        }
        NSColor(calibratedWhite: 0.78, alpha: 1).setFill()
        y = size.height - barH - 50
        while y > 30 {
            let w = (size.width - sidebarW - 80) * (0.35 + 0.65 * next())
            NSBezierPath(roundedRect: NSRect(x: sidebarW + 40, y: y, width: w, height: 16), xRadius: 8, yRadius: 8).fill()
            y -= 40
        }
        tint.withAlphaComponent(0.85).setFill()
        NSBezierPath(roundedRect: NSRect(x: sidebarW + 40, y: size.height - barH - 110, width: 160, height: 36), xRadius: 8, yRadius: 8).fill()
        img.unlockFocus()
        return img.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }
}

/// A synthetic desktop background so the screenshots show nothing from the real desktop.
private struct Wallpaper: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.16, green: 0.32, blue: 0.62), Color(red: 0.42, green: 0.18, blue: 0.52)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Circle().fill(Color(red: 0.95, green: 0.55, blue: 0.35).opacity(0.55)).frame(width: 700).blur(radius: 120).offset(x: -380, y: 260)
            Circle().fill(Color(red: 0.35, green: 0.85, blue: 0.85).opacity(0.5)).frame(width: 600).blur(radius: 110).offset(x: 420, y: -240)
        }
    }
}
