import AppKit
import Carbon.HIToolbox

struct SpaceInfo: Identifiable, Equatable {
    let id: UInt64
    let displayIndex: Int
    /// Position within its display, including full-screen spaces.
    let index: Int
    let isFullscreen: Bool
    let isCurrent: Bool
}

/// Reads the Spaces (virtual desktops) of every display and which Space holds each window.
@MainActor
final class SpaceManager {
    private(set) var spacesByDisplay: [Int: [SpaceInfo]] = [:]
    private(set) var windowSpaces: [CGWindowID: UInt64] = [:]

    var isAvailable: Bool { PrivateAPI.hasSpaces }

    func refresh(windows: [WindowInfo]) {
        guard let connection = PrivateAPI.mainConnectionID,
              let copyDisplays = PrivateAPI.copyManagedDisplaySpaces,
              let spacesForWindows = PrivateAPI.copySpacesForWindows else { return }
        let cid = connection()
        let displays = copyDisplays(cid)?.takeRetainedValue() as? [[String: Any]] ?? []
        let screens = NSScreen.screens
        let screenUUIDs = screens.map { Self.uuid(of: $0) }

        var result: [Int: [SpaceInfo]] = [:]
        for (position, display) in displays.enumerated() {
            let identifier = display["Display Identifier"] as? String ?? ""
            let screenIndex = screenUUIDs.firstIndex(of: identifier)
                ?? (identifier == "Main" ? 0 : min(position, max(0, screens.count - 1)))
            let current = display["Current Space"] as? [String: Any]
            let currentID = (current?["id64"] as? UInt64) ?? (current?["ManagedSpaceID"] as? UInt64)
            var list: [SpaceInfo] = []
            for (i, space) in (display["Spaces"] as? [[String: Any]] ?? []).enumerated() {
                guard let id = (space["id64"] as? UInt64) ?? (space["ManagedSpaceID"] as? UInt64) else { continue }
                let type = space["type"] as? Int ?? 0
                list.append(SpaceInfo(id: id, displayIndex: screenIndex, index: i, isFullscreen: type == 4, isCurrent: id == currentID))
            }
            result[screenIndex] = list
        }
        spacesByDisplay = result

        var map: [CGWindowID: UInt64] = [:]
        for w in windows {
            if let ids = spacesForWindows(cid, 7, [w.id] as CFArray)?.takeRetainedValue() as? [UInt64], let first = ids.first {
                map[w.id] = first
            }
        }
        windowSpaces = map
    }

    func spaces(forDisplay index: Int) -> [SpaceInfo] { spacesByDisplay[index] ?? [] }
    func currentSpace(forDisplay index: Int) -> SpaceInfo? { spaces(forDisplay: index).first { $0.isCurrent } }
    func space(for window: CGWindowID) -> UInt64? { windowSpaces[window] }

    static func uuid(of screen: NSScreen) -> String {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
              let uuid = CGDisplayCreateUUIDFromDisplayID(number.uint32Value)?.takeRetainedValue() else { return "" }
        return CFUUIDCreateString(nil, uuid) as String
    }
}

/// Drives Spaces through the system's own keyboard shortcuts (⌃← / ⌃→, on by default), since there
/// is no supported way for one app to switch Spaces or move another app's window between them.
enum SpaceNavigator {
    /// Switches `steps` desktops left (negative) or right (positive) on the active display.
    static func pressArrows(_ steps: Int) async {
        guard steps != 0 else { return }
        let key = CGKeyCode(steps > 0 ? kVK_RightArrow : kVK_LeftArrow)
        for _ in 0..<abs(steps) {
            postKey(key, flags: .maskControl)
            try? await Task.sleep(for: .milliseconds(550))
        }
    }

    /// Moves a window of the current Space `steps` desktops over: grabs its title bar and presses
    /// ⌃arrow while dragging, which is how macOS lets the user carry a window along.
    static func moveWindow(_ window: WindowInfo, steps: Int) async {
        guard steps != 0 else { return }
        // Just right of the traffic lights: title bar in every standard window, no toolbar controls there.
        let grab = CGPoint(x: window.frame.minX + 70, y: window.frame.minY + 11)
        postMouse(.mouseMoved, at: grab)
        try? await Task.sleep(for: .milliseconds(80))
        postMouse(.leftMouseDown, at: grab)
        try? await Task.sleep(for: .milliseconds(120))
        var p = grab
        for _ in 0..<4 {
            p.y += 2
            postMouse(.leftMouseDragged, at: p)
            try? await Task.sleep(for: .milliseconds(30))
        }
        try? await Task.sleep(for: .milliseconds(100))
        await pressArrows(steps)
        try? await Task.sleep(for: .milliseconds(150))
        postMouse(.leftMouseUp, at: p)
    }

    private static func postKey(_ key: CGKeyCode, flags: CGEventFlags) {
        for down in [true, false] {
            guard let e = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: down) else { continue }
            e.flags = flags
            e.post(tap: .cghidEventTap)
        }
    }

    private static func postMouse(_ type: CGEventType, at point: CGPoint) {
        guard let e = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left) else { return }
        e.post(tap: .cghidEventTap)
    }
}
