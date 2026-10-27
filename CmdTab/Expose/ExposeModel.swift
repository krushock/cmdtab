import AppKit
import Observation

enum SplitSide: Equatable { case left, right }
enum DropZone: Equatable { case left, right, fill }

/// Where a dragged window will land when released.
enum DropTarget: Equatable {
    /// Split the screen between the dragged window and this one; the dragged window takes `SplitSide`.
    case window(CGWindowID, SplitSide)
    /// Tile the dragged window into a zone of the screen with this index.
    case zone(Int, DropZone)
    /// Move the dragged window to the screen with this index, keeping its size.
    case display(Int)
}

struct ExposeTile: Identifiable, Equatable {
    let id: CGWindowID
    let window: WindowInfo
    let item: SwitcherItem
    /// In the screen panel's coordinates (points, top-left origin).
    var frame: CGRect

    static func == (lhs: ExposeTile, rhs: ExposeTile) -> Bool {
        lhs.id == rhs.id && lhs.window == rhs.window && lhs.frame == rhs.frame
    }
}

struct ExposeScreen: Identifiable, Equatable {
    let id: Int
    let name: String
    /// AppKit global frame (bottom-left origin).
    let frame: CGRect
    var tiles: [ExposeTile]

    var size: CGSize { frame.size }

    func contains(global point: CGPoint) -> Bool { frame.contains(point) }

    /// Global AppKit point → this panel's top-left point space.
    func panelPoint(fromGlobal p: CGPoint) -> CGPoint {
        CGPoint(x: p.x - frame.minX, y: frame.maxY - p.y)
    }

    /// Panel point → global AppKit point.
    func globalPoint(fromPanel p: CGPoint) -> CGPoint {
        CGPoint(x: frame.minX + p.x, y: frame.maxY - p.y)
    }
}

struct ExposeDrag: Equatable {
    let windowID: CGWindowID
    let sourceScreen: Int
    /// From the tile's top-left corner to the grab point, in panel points.
    let grabOffset: CGSize
    let tileSize: CGSize
    var location: CGPoint   // global AppKit point
    var target: DropTarget?
}

@MainActor
@Observable
final class ExposeModel {
    var screens: [ExposeScreen] = []
    var thumbnails: [CGWindowID: CGImage] = [:]
    var hovered: CGWindowID?
    var drag: ExposeDrag?
    var presentation = 0

    var allTiles: [ExposeTile] { screens.flatMap(\.tiles) }

    func tile(_ id: CGWindowID) -> ExposeTile? {
        for s in screens { if let t = s.tiles.first(where: { $0.id == id }) { return t } }
        return nil
    }

    func screen(containing global: CGPoint) -> ExposeScreen? {
        screens.first { $0.contains(global: global) }
    }

    func screen(withTile id: CGWindowID) -> ExposeScreen? {
        screens.first { $0.tiles.contains { $0.id == id } }
    }
}

struct ExposeActions {
    var hover: (CGWindowID?) -> Void
    var activate: (CGWindowID) -> Void
    var dragChanged: (_ id: CGWindowID, _ screen: Int, _ global: CGPoint, _ grabOffset: CGSize) -> Void
    var dragEnded: () -> Void
    var cancel: () -> Void
}
