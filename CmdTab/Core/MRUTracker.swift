import AppKit

/// Keeps windows in most-recently-focused order: observes app activations and records our own switches.
@MainActor
final class MRUTracker {
    private(set) var order: [CGWindowID] = []
    private var observer: Any?

    init() {
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            let pid = app.processIdentifier
            DispatchQueue.global(qos: .utility).async {
                let id = AXWindowCache.focusedWindowID(pid: pid)
                DispatchQueue.main.async {
                    if let id { self?.bump(id) }
                }
            }
        }
    }

    func bump(_ id: CGWindowID) {
        order.removeAll { $0 == id }
        order.insert(id, at: 0)
        if order.count > 200 { order.removeLast(order.count - 200) }
    }

    func rank(of id: CGWindowID) -> Int? {
        order.firstIndex(of: id)
    }

    /// Stable sort: tracked windows by recency first, then on-screen windows, then the rest.
    func sorted(_ windows: [WindowInfo]) -> [WindowInfo] {
        let indexed = windows.enumerated().map { ($0.offset, $0.element) }
        return indexed.sorted { a, b in
            let ra = rank(of: a.1.id), rb = rank(of: b.1.id)
            switch (ra, rb) {
            case let (x?, y?): return x < y
            case (_?, nil): return true
            case (nil, _?): return false
            default:
                if a.1.isOnScreen != b.1.isOnScreen { return a.1.isOnScreen }
                return a.0 < b.0
            }
        }.map(\.1)
    }
}
