import AppKit

struct WindowInfo: Identifiable, Hashable {
    let id: CGWindowID
    let pid: pid_t
    let title: String
    let frame: CGRect
    let isOnScreen: Bool
    var isMinimized: Bool
    let appName: String
    let bundleID: String

    var aspectRatio: CGFloat {
        guard frame.height > 0 else { return 1.6 }
        return max(0.3, min(4, frame.width / frame.height))
    }
}

enum SwitcherScope: Equatable {
    /// One entry per running application (like the system switcher).
    case apps
    /// One entry per window, all applications.
    case windows
    /// One entry per window of the frontmost application.
    case appWindows
}

/// One cell in the switcher: an app (with all its windows) or a single window.
struct SwitcherItem: Identifiable, Equatable {
    let id: String
    let pid: pid_t
    let appName: String
    let title: String
    let subtitle: String?
    let icon: NSImage?
    let windows: [WindowInfo]
    let isApp: Bool

    var primaryWindow: WindowInfo? { windows.first }
    var primaryWindowID: CGWindowID? { windows.first?.id }
    var isMinimized: Bool { !windows.isEmpty && windows.allSatisfy { $0.isMinimized } }
    var aspectRatio: CGFloat { windows.first?.aspectRatio ?? 1.6 }

    static func == (lhs: SwitcherItem, rhs: SwitcherItem) -> Bool {
        lhs.id == rhs.id && lhs.title == rhs.title && lhs.windows == rhs.windows
    }

    static func app(pid: pid_t, app: NSRunningApplication?, windows: [WindowInfo]) -> SwitcherItem {
        let name = app?.localizedName ?? windows.first?.appName ?? "App"
        let count = windows.count
        let subtitle: String? = count > 1 ? "\(count) windows" : windows.first.map { $0.title.isEmpty ? nil : $0.title } ?? nil
        return SwitcherItem(id: "app-\(pid)", pid: pid, appName: name, title: name, subtitle: subtitle,
                            icon: app?.icon, windows: windows, isApp: true)
    }

    static func window(_ w: WindowInfo, app: NSRunningApplication?) -> SwitcherItem {
        let name = app?.localizedName ?? w.appName
        let title = w.title.isEmpty ? name : w.title
        return SwitcherItem(id: "win-\(w.id)", pid: w.pid, appName: name, title: title,
                            subtitle: w.title.isEmpty ? nil : name, icon: app?.icon, windows: [w], isApp: false)
    }
}
