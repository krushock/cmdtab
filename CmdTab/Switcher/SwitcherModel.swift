import AppKit
import Observation

@MainActor
@Observable
final class SwitcherModel {
    var items: [SwitcherItem] = []
    var selectedIndex = 0
    var style: SwitcherStyle = .classic
    var scope: SwitcherScope = .apps
    var thumbnails: [CGWindowID: CGImage] = [:]
    var dimBackground = true
    var columns = 1
    /// Incremented every time the panel is shown so SwiftUI state (entry animation) resets.
    var presentation = 0

    var selected: SwitcherItem? {
        items.indices.contains(selectedIndex) ? items[selectedIndex] : nil
    }

    func thumbnail(for item: SwitcherItem) -> CGImage? {
        guard let id = item.primaryWindowID else { return nil }
        return thumbnails[id]
    }
}

struct SwitcherActions {
    var hover: (Int) -> Void
    var select: (Int) -> Void
    var cancel: () -> Void
}
