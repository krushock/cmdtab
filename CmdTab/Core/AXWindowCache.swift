import AppKit
import ApplicationServices

@_silgen_name("_AXUIElementGetWindow")
func _AXUIElementGetWindow(_ element: AXUIElement, _ identifier: UnsafeMutablePointer<CGWindowID>) -> AXError

/// Accessibility window elements per application, queried off the main thread with short timeouts
/// so an unresponsive app can never stall the switcher.
final class AXWindowCache: @unchecked Sendable {
    struct Entry {
        let element: AXUIElement
        let isMinimized: Bool
    }

    private let queue = DispatchQueue(label: "com.valeryburtsev.CmdTab.ax", qos: .userInitiated, attributes: .concurrent)
    private let lock = NSLock()
    private var byPID: [pid_t: [CGWindowID: Entry]] = [:]

    func entries(for pid: pid_t) -> [CGWindowID: Entry]? {
        lock.lock(); defer { lock.unlock() }
        return byPID[pid]
    }

    func entry(for windowID: CGWindowID, pid: pid_t) -> Entry? {
        entries(for: pid)?[windowID]
    }

    /// Refresh the cache for the given processes concurrently; `completion` runs on the main thread.
    func refresh(pids: [pid_t], completion: @escaping @Sendable () -> Void) {
        let group = DispatchGroup()
        for pid in Set(pids) {
            group.enter()
            queue.async {
                let result = AXWindowCache.query(pid: pid)
                self.lock.lock()
                if let result { self.byPID[pid] = result } else { self.byPID.removeValue(forKey: pid) }
                self.lock.unlock()
                group.leave()
            }
        }
        group.notify(queue: .main, execute: completion)
    }

    func forget(pid: pid_t) {
        lock.lock(); defer { lock.unlock() }
        byPID.removeValue(forKey: pid)
    }

    static func query(pid: pid_t) -> [CGWindowID: Entry]? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.25)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else {
            return nil
        }
        var out: [CGWindowID: Entry] = [:]
        for w in windows {
            var id: CGWindowID = 0
            guard _AXUIElementGetWindow(w, &id) == .success, id != 0 else { continue }
            var minimized: CFTypeRef?
            let isMin = AXUIElementCopyAttributeValue(w, kAXMinimizedAttribute as CFString, &minimized) == .success
                && ((minimized as? Bool) ?? false)
            out[id] = Entry(element: w, isMinimized: isMin)
        }
        return out
    }

    static func focusedWindowID(pid: pid_t) -> CGWindowID? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.25)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        let element = value as! AXUIElement
        var id: CGWindowID = 0
        guard _AXUIElementGetWindow(element, &id) == .success, id != 0 else { return nil }
        return id
    }
}
