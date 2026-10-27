import AppKit
import ApplicationServices

/// Drives the real Mission Control to move a window to another Space, the one thing macOS offers no
/// API for: it opens Mission Control, finds the window's thumbnail and the desktop button in the
/// WindowManager process's Accessibility tree, and drags one onto the other with synthetic mouse input.
@MainActor
enum MissionControl {
    struct Thumbnail {
        let bundleID: String
        let title: String
        let center: CGPoint
    }

    struct SpaceButton {
        let title: String
        let center: CGPoint
    }

    static func toggle() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        p.arguments = ["-a", "Mission Control"]
        try? p.run()
    }

    private static var windowManager: AXUIElement? {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.WindowManager").first else { return nil }
        let root = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 1.0)
        return root
    }

    /// Window thumbnails and desktop buttons currently shown, in top-left global coordinates.
    static func contents() -> (thumbnails: [Thumbnail], spaces: [SpaceButton]) {
        guard let root = windowManager else { return ([], []) }
        var thumbnails: [Thumbnail] = []
        var spaces: [SpaceButton] = []
        func walk(_ e: AXUIElement, depth: Int, inSpacesBar: Bool) {
            guard depth < 8 else { return }
            let role = string(e, kAXRoleAttribute) ?? ""
            let ident = string(e, "AXIdentifier") ?? ""
            if role == "AXButton", let center = center(of: e) {
                if inSpacesBar {
                    if let title = string(e, kAXTitleAttribute), !title.isEmpty {
                        spaces.append(SpaceButton(title: title, center: center))
                    }
                } else if let range = ident.range(of: ".space.") {
                    thumbnails.append(Thumbnail(bundleID: String(ident[..<range.lowerBound]),
                                                title: string(e, kAXTitleAttribute) ?? "", center: center))
                }
            }
            var kids: CFTypeRef?
            guard AXUIElementCopyAttributeValue(e, kAXChildrenAttribute as CFString, &kids) == .success,
                  let children = kids as? [AXUIElement] else { return }
            for k in children.prefix(80) { walk(k, depth: depth + 1, inSpacesBar: inSpacesBar || ident == "mc.spaces") }
        }
        walk(root, depth: 0, inSpacesBar: false)
        return (thumbnails, spaces)
    }

    static var isOpen: Bool { !contents().spaces.isEmpty }

    /// Moves `window` to the desktop titled `spaceTitle` (for example "Desktop 2") on the screen whose
    /// top-left-coordinate frame is `screenFrame`. The user stays on the current Space, like in Mission Control.
    static func move(_ window: WindowInfo, toSpaceTitled spaceTitle: String, screenFrame: CGRect) async -> Bool {
        toggle()
        var opened = false
        for _ in 0..<25 {
            try? await Task.sleep(for: .milliseconds(100))
            if isOpen { opened = true; break }
        }
        guard opened else { return false }
        try? await Task.sleep(for: .milliseconds(450))   // let the layout animation finish

        let shown = contents()
        let thumbs = shown.thumbnails.filter { screenFrame.contains($0.center) }
        let thumb = thumbs.first { $0.bundleID == window.bundleID && $0.title == window.title }
            ?? thumbs.first { $0.bundleID == window.bundleID && window.title.isEmpty }
        guard let thumb, let target = shown.spaces.first(where: { $0.title == spaceTitle && screenFrame.contains($0.center) }) else {
            toggle()
            return false
        }

        let source = CGEventSource(stateID: .hidSystemState)
        func mouse(_ type: CGEventType, _ p: CGPoint) {
            CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
        }
        var p = thumb.center
        mouse(.mouseMoved, p)
        try? await Task.sleep(for: .milliseconds(120))
        mouse(.leftMouseDown, p)
        try? await Task.sleep(for: .milliseconds(150))
        let steps = 24
        let dx = (target.center.x - p.x) / CGFloat(steps), dy = (target.center.y - p.y) / CGFloat(steps)
        for _ in 0..<steps {
            p.x += dx; p.y += dy
            mouse(.leftMouseDragged, p)
            try? await Task.sleep(for: .milliseconds(16))
        }
        try? await Task.sleep(for: .milliseconds(350))   // the Spaces bar reacts to the hover
        mouse(.leftMouseUp, p)
        try? await Task.sleep(for: .milliseconds(700))
        if isOpen { toggle() }
        return true
    }

    private static func string(_ e: AXUIElement, _ attribute: String) -> String? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(e, attribute as CFString, &v) == .success else { return nil }
        return v as? String
    }

    private static func center(of e: AXUIElement) -> CGPoint? {
        var posV: CFTypeRef?, sizeV: CFTypeRef?
        guard AXUIElementCopyAttributeValue(e, kAXPositionAttribute as CFString, &posV) == .success,
              AXUIElementCopyAttributeValue(e, kAXSizeAttribute as CFString, &sizeV) == .success,
              let posV, let sizeV, CFGetTypeID(posV) == AXValueGetTypeID(), CFGetTypeID(sizeV) == AXValueGetTypeID() else { return nil }
        var p = CGPoint.zero, s = CGSize.zero
        guard AXValueGetValue(posV as! AXValue, .cgPoint, &p), AXValueGetValue(sizeV as! AXValue, .cgSize, &s) else { return nil }
        return CGPoint(x: p.x + s.width / 2, y: p.y + s.height / 2)
    }
}
