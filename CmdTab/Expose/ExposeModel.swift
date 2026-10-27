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
    /// Move the dragged window to this Space of the display with this index.
    case space(Int, UInt64)
}

/// One cell of the overview: a single window, or a group of windows CmdTab tiled together.
struct ExposeTile: Identifiable, Equatable {
    let id: CGWindowID
    let members: [WindowInfo]
    let items: [SwitcherItem]
    let groupID: UUID?
    /// In the screen panel's coordinates (points, top-left origin).
    var frame: CGRect

    var isGroup: Bool { members.count > 1 }
    var window: WindowInfo { members[0] }
    var item: SwitcherItem { items[0] }
    var title: String { isGroup ? items.map(\.appName).joined(separator: " + ") : items[0].title }

    /// Smallest rectangle around every member, in window (top-left global) coordinates.
    var unionFrame: CGRect { members.dropFirst().reduce(members[0].frame) { $0.union($1.frame) } }

    /// Member frames relative to `unionFrame`, each component in 0...1.
    var memberRects: [CGRect] {
        let u = unionFrame
        guard u.width > 0, u.height > 0 else { return members.map { _ in CGRect(x: 0, y: 0, width: 1, height: 1) } }
        return members.map {
            CGRect(x: ($0.frame.minX - u.minX) / u.width, y: ($0.frame.minY - u.minY) / u.height,
                   width: $0.frame.width / u.width, height: $0.frame.height / u.height)
        }
    }

    static func == (lhs: ExposeTile, rhs: ExposeTile) -> Bool {
        lhs.id == rhs.id && lhs.members == rhs.members && lhs.frame == rhs.frame && lhs.groupID == rhs.groupID
    }
}

/// A Space (desktop or full-screen app) shown in the bar at the top of a display's overlay.
struct SpaceTile: Identifiable, Equatable {
    let id: UInt64
    let index: Int
    let name: String
    let isCurrent: Bool
    let isFullscreen: Bool
    let windows: [WindowInfo]
}

struct ExposeScreen: Identifiable, Equatable {
    let id: Int
    let name: String
    /// AppKit global frame (bottom-left origin).
    let frame: CGRect
    /// The same screen's origin in window (top-left global) coordinates.
    let topLeftOrigin: CGPoint
    var tiles: [ExposeTile]
    var spaces: [SpaceTile]

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

    /// Window frame (top-left global) → rectangle in this panel's points.
    func panelRect(fromWindowFrame f: CGRect) -> CGRect {
        CGRect(x: f.minX - topLeftOrigin.x, y: f.minY - topLeftOrigin.y, width: f.width, height: f.height)
    }
}

/// Geometry of the Spaces bar, shared by the view (drawing) and the controller (hit testing).
enum SpacesBarLayout {
    static let top: CGFloat = 54
    static let cardHeight: CGFloat = 84
    static let spacing: CGFloat = 18
    static let labelHeight: CGFloat = 22

    static var totalHeight: CGFloat { top + cardHeight + labelHeight }

    static func cardFrames(for spaces: [SpaceTile], screenSize: CGSize) -> [UInt64: CGRect] {
        guard !spaces.isEmpty, screenSize.height > 0 else { return [:] }
        let width = cardHeight * (screenSize.width / screenSize.height)
        let total = CGFloat(spaces.count) * width + CGFloat(spaces.count - 1) * spacing
        var x = (screenSize.width - total) / 2
        var frames: [UInt64: CGRect] = [:]
        for space in spaces {
            frames[space.id] = CGRect(x: x, y: top, width: width, height: cardHeight)
            x += width + spacing
        }
        return frames
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
    var switchSpace: (_ screen: Int, _ space: UInt64) -> Void
    var dragChanged: (_ id: CGWindowID, _ screen: Int, _ global: CGPoint, _ grabOffset: CGSize) -> Void
    var dragEnded: () -> Void
    var cancel: () -> Void
}
