import AppKit
import ScreenCaptureKit

/// Enumerates real, user-facing windows using ScreenCaptureKit (which lists windows on every Space,
/// including minimized ones) cross-checked against the Accessibility window list of each app.
@MainActor
final class WindowSource {
    private(set) var windows: [WindowInfo] = []
    private(set) var scWindows: [CGWindowID: SCWindow] = [:]
    private(set) var lastRefresh: Date = .distantPast
    let axCache = AXWindowCache()
    private var refreshTask: Task<Void, Never>?

    var isStale: Bool { Date().timeIntervalSince(lastRefresh) > 1.0 }

    func scWindow(for id: CGWindowID) -> SCWindow? { scWindows[id] }

    /// Refresh; concurrent callers share one in-flight refresh.
    func refresh() async {
        if let refreshTask {
            await refreshTask.value
            return
        }
        let task = Task { await performRefresh() }
        refreshTask = task
        await task.value
        refreshTask = nil
    }

    private func performRefresh() async {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        var candidates: [WindowInfo] = []
        var map: [CGWindowID: SCWindow] = [:]

        if let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false) {
            for w in content.windows {
                guard let owner = w.owningApplication, owner.processID != ownPID, w.windowLayer == 0 else { continue }
                guard w.frame.width >= 80, w.frame.height >= 40 else { continue }
                guard let app = NSRunningApplication(processIdentifier: owner.processID),
                      app.activationPolicy == .regular else { continue }
                map[w.windowID] = w
                candidates.append(WindowInfo(
                    id: w.windowID, pid: owner.processID, title: w.title ?? "", frame: w.frame,
                    isOnScreen: w.isOnScreen, isMinimized: false,
                    appName: app.localizedName ?? owner.applicationName,
                    bundleID: owner.bundleIdentifier))
            }
        } else {
            // No screen-recording permission yet: fall back to the window list of the current Space.
            candidates = Self.cgWindowList(excludingPID: ownPID)
        }

        // Cross-check with Accessibility: real windows show up in the app's AX window list and that is
        // also where the minimized state lives.
        let pids = Array(Set(candidates.map(\.pid)))
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            axCache.refresh(pids: pids) { cont.resume() }
        }

        var result: [WindowInfo] = []
        for var w in candidates {
            if let entries = axCache.entries(for: w.pid) {
                guard let entry = entries[w.id] else { continue }
                w.isMinimized = entry.isMinimized
            }
            result.append(w)
        }
        windows = result
        scWindows = map
        lastRefresh = Date()
    }

    private static func cgWindowList(excludingPID ownPID: pid_t) -> [WindowInfo] {
        guard let list = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        var out: [WindowInfo] = []
        for info in list {
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t, pid != ownPID,
                  let id = info[kCGWindowNumber as String] as? CGWindowID,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict),
                  bounds.width >= 80, bounds.height >= 40,
                  let app = NSRunningApplication(processIdentifier: pid), app.activationPolicy == .regular
            else { continue }
            let alpha = info[kCGWindowAlpha as String] as? Double ?? 1
            guard alpha > 0.05 else { continue }
            let onScreen = (info[kCGWindowIsOnscreen as String] as? Bool) ?? false
            out.append(WindowInfo(id: id, pid: pid, title: info[kCGWindowName as String] as? String ?? "",
                                  frame: bounds, isOnScreen: onScreen, isMinimized: false,
                                  appName: app.localizedName ?? (info[kCGWindowOwnerName as String] as? String ?? ""),
                                  bundleID: app.bundleIdentifier ?? ""))
        }
        return out
    }
}
