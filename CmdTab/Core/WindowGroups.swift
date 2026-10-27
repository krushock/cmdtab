import CoreGraphics
import Foundation

/// A pair of windows that CmdTab tiled side by side. The group lives as long as both windows keep
/// the frames they were given; moving, resizing, closing or minimizing either dissolves it.
struct WindowGroup: Identifiable, Equatable {
    struct Member: Equatable {
        let id: CGWindowID
        let frame: CGRect
    }

    let id: UUID
    /// Activation order: the last member ends up focused.
    var members: [Member]

    var ids: [CGWindowID] { members.map(\.id) }
}

@MainActor
final class WindowGroupStore {
    private(set) var groups: [WindowGroup] = []

    func add(_ windows: [WindowInfo]) {
        let ids = Set(windows.map(\.id))
        groups.removeAll { !Set($0.ids).isDisjoint(with: ids) }
        groups.append(WindowGroup(id: UUID(), members: windows.map { .init(id: $0.id, frame: $0.frame) }))
    }

    func group(containing id: CGWindowID) -> WindowGroup? {
        groups.first { $0.ids.contains(id) }
    }

    /// Drops every group whose members are gone, hidden, or no longer where the group put them.
    func prune(with windows: [WindowInfo]) {
        let byID = Dictionary(uniqueKeysWithValues: windows.map { ($0.id, $0) })
        groups.removeAll { group in
            !group.members.allSatisfy { m in
                guard let w = byID[m.id], w.isOnScreen, !w.isMinimized else { return false }
                return Self.roughlyEqual(w.frame, m.frame)
            }
        }
    }

    private static func roughlyEqual(_ a: CGRect, _ b: CGRect, tolerance: CGFloat = 6) -> Bool {
        abs(a.minX - b.minX) < tolerance && abs(a.minY - b.minY) < tolerance &&
        abs(a.width - b.width) < tolerance && abs(a.height - b.height) < tolerance
    }
}
