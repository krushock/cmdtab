import AppKit

struct SpaceInfo: Identifiable, Equatable {
    let id: UInt64
    let displayIndex: Int
    /// Position within its display, including full-screen spaces.
    let index: Int
    let isFullscreen: Bool
    let isCurrent: Bool
}

/// Reads the Spaces (virtual desktops) of every display, which Space holds each window, and switches Spaces.
@MainActor
final class SpaceManager {
    private(set) var spacesByDisplay: [Int: [SpaceInfo]] = [:]
    private(set) var windowSpaces: [CGWindowID: UInt64] = [:]
    private(set) var displayIdentifiers: [Int: String] = [:]

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
        var identifiers: [Int: String] = [:]
        for (position, display) in displays.enumerated() {
            let identifier = display["Display Identifier"] as? String ?? ""
            let screenIndex = screenUUIDs.firstIndex(of: identifier)
                ?? (identifier == "Main" ? 0 : min(position, max(0, screens.count - 1)))
            identifiers[screenIndex] = identifier
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
        displayIdentifiers = identifiers

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

    /// Switches `display` to `space`. Returns false when the call is unavailable.
    @discardableResult
    func switchTo(space: UInt64, display: Int) -> Bool {
        guard let connection = PrivateAPI.mainConnectionID,
              let setCurrent = PrivateAPI.managedDisplaySetCurrentSpace,
              let identifier = displayIdentifiers[display] else { return false }
        setCurrent(connection(), identifier as CFString, space)
        return true
    }

    static func uuid(of screen: NSScreen) -> String {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
              let uuid = CGDisplayCreateUUIDFromDisplayID(number.uint32Value)?.takeRetainedValue() else { return "" }
        return CFUUIDCreateString(nil, uuid) as String
    }
}
