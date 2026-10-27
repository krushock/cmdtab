import SwiftUI

/// The Exposé overlay for one display: tiles, drop-zone feedback, the drag ghost and a hint line.
struct ExposeScreenView: View {
    var model: ExposeModel
    let screenIndex: Int
    let actions: ExposeActions

    private var screen: ExposeScreen? { model.screens.first { $0.id == screenIndex } }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                MaterialBackground(material: .fullScreenUI)
                    .overlay(Color.black.opacity(0.42))
                    .allowsHitTesting(false)
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { actions.cancel() }

                if let screen {
                    zoneFeedback(screen, size: geo.size)
                    ForEach(screen.tiles) { tile in
                        tileView(tile, in: screen)
                    }
                    header(screen, width: geo.size.width)
                    hint(size: geo.size)
                    if let drag = model.drag, screen.contains(global: drag.location) {
                        ghost(drag, in: screen)
                    }
                    splitPreview(screen)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .id(model.presentation)
        }
        .ignoresSafeArea()
    }

    // MARK: Tiles

    @ViewBuilder
    private func tileView(_ tile: ExposeTile, in screen: ExposeScreen) -> some View {
        let isDragged = model.drag?.windowID == tile.id
        let hovered = model.hovered == tile.id && model.drag == nil
        let splitSide: SplitSide? = {
            if case .window(tile.id, let side)? = model.drag?.target { return side }
            return nil
        }()

        ThumbnailCard(item: tile.item, image: model.thumbnails[tile.id], size: tile.frame.size,
                      selected: hovered || splitSide != nil, cornerRadius: 8, badgeSize: min(40, tile.frame.height * 0.2))
        .frame(width: tile.frame.width, height: tile.frame.height)
        .overlay(alignment: .bottom) {
            Text(tile.item.title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(1)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Capsule().fill(.black.opacity(0.55)))
                .frame(maxWidth: tile.frame.width)
                .offset(y: 22)
                .opacity(isDragged ? 0 : 1)
        }
        .scaleEffect(hovered ? 1.03 : 1)
        .opacity(isDragged ? 0.25 : 1)
        .position(x: tile.frame.midX, y: tile.frame.midY)
        .onHover { actions.hover($0 ? tile.id : nil) }
        .gesture(
            DragGesture(minimumDistance: 6, coordinateSpace: .global)
                .onChanged { value in
                    let global = screen.globalPoint(fromPanel: value.location)
                    let grab = CGSize(width: value.startLocation.x - tile.frame.minX,
                                      height: value.startLocation.y - tile.frame.minY)
                    actions.dragChanged(tile.id, screen.id, global, grab)
                }
                .onEnded { _ in actions.dragEnded() }
        )
        .onTapGesture { actions.activate(tile.id) }
    }

    /// Above everything, including the ghost: the half of the target the dragged window will take lights up.
    @ViewBuilder
    private func splitPreview(_ screen: ExposeScreen) -> some View {
        if case .window(let id, let side)? = model.drag?.target, let tile = screen.tiles.first(where: { $0.id == id }) {
            SplitPreview(side: side)
                .frame(width: tile.frame.width, height: tile.frame.height)
                .position(x: tile.frame.midX, y: tile.frame.midY)
                .zIndex(200)
                .transition(.opacity)
        }
    }

    /// Drawn over the target tile: the half the dragged window will take lights up.
    private struct SplitPreview: View {
        let side: SplitSide
        var body: some View {
            HStack(spacing: 0) {
                half(active: side == .left)
                half(active: side == .right)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .allowsHitTesting(false)
        }
        private func half(active: Bool) -> some View {
            ZStack {
                Rectangle().fill(Color.white.opacity(active ? 0.45 : 0.08))
                if active {
                    Label("Split", systemImage: "rectangle.split.2x1")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.black.opacity(0.8))
                }
            }
        }
    }

    // MARK: Drop zones

    @ViewBuilder
    private func zoneFeedback(_ screen: ExposeScreen, size: CGSize) -> some View {
        if let target = model.drag?.target {
            switch target {
            case .zone(screen.id, let zone):
                let rect: CGRect = {
                    switch zone {
                    case .left: return CGRect(x: 12, y: 12, width: size.width / 2 - 18, height: size.height - 24)
                    case .right: return CGRect(x: size.width / 2 + 6, y: 12, width: size.width / 2 - 18, height: size.height - 24)
                    case .fill: return CGRect(x: 12, y: 12, width: size.width - 24, height: size.height - 24)
                    }
                }()
                let label = zone == .fill ? "Fill screen" : (zone == .left ? "Left half" : "Right half")
                zoneRect(rect, label: label, symbol: zone == .fill ? "rectangle" : "rectangle.split.2x1")
            case .display(screen.id):
                zoneRect(CGRect(x: 12, y: 12, width: size.width - 24, height: size.height - 24),
                         label: "Move to \(screen.name)", symbol: "display")
            default:
                EmptyView()
            }
        }
    }

    private func zoneRect(_ rect: CGRect, label: String, symbol: String) -> some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Color.white.opacity(0.14))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.8), style: StrokeStyle(lineWidth: 2, dash: [10, 8])))
            .overlay {
                Label(label, systemImage: symbol)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18).padding(.vertical, 10)
                    .background(Capsule().fill(.black.opacity(0.5)))
            }
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
            .allowsHitTesting(false)
            .transition(.opacity.combined(with: .scale(scale: 0.98)))
    }

    // MARK: Ghost, header, hint

    private func ghost(_ drag: ExposeDrag, in screen: ExposeScreen) -> some View {
        let p = screen.panelPoint(fromGlobal: drag.location)
        let origin = CGPoint(x: p.x - drag.grabOffset.width, y: p.y - drag.grabOffset.height)
        return Group {
            if let tile = model.tile(drag.windowID) {
                // Shrinks into a small placeholder while over a drop target so the target stays readable.
                ThumbnailCard(item: tile.item, image: model.thumbnails[tile.id], size: drag.tileSize,
                              selected: true, cornerRadius: 8, badgeSize: min(40, drag.tileSize.height * 0.2))
                    .scaleEffect(drag.target == nil ? 0.96 : 0.5)
                    .opacity(drag.target == nil ? 0.92 : 0.8)
                    .position(x: origin.x + drag.tileSize.width / 2, y: origin.y + drag.tileSize.height / 2)
                    .allowsHitTesting(false)
                    .zIndex(100)
            }
        }
    }

    private func header(_ screen: ExposeScreen, width: CGFloat) -> some View {
        VStack(spacing: 2) {
            Text(screen.name)
                .font(.system(size: 14, weight: .semibold))
            if screen.tiles.isEmpty {
                Text("No windows on this display").font(.system(size: 12))
            }
        }
        .foregroundStyle(.white.opacity(0.75))
        .frame(width: width)
        .padding(.top, 36)
        .allowsHitTesting(false)
    }

    private func hint(size: CGSize) -> some View {
        Text("Drag a window onto another to split the screen between them  ·  drag to an edge for a half or the whole screen  ·  click to switch  ·  ⎋ closes")
            .font(.system(size: 12))
            .foregroundStyle(.white.opacity(0.65))
            .padding(.horizontal, 14).padding(.vertical, 7)
            .background(Capsule().fill(.black.opacity(0.35)))
            .position(x: size.width / 2, y: size.height - 32)
            .allowsHitTesting(false)
    }
}
