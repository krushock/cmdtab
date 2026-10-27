import SwiftUI

/// The Exposé overlay for one display: tiles, drop-zone feedback, drag ghost and hint.
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
        let isTarget: Bool = {
            if case .window(tile.id, _)? = model.drag?.target { return true }
            return false
        }()

        Group {
            if tile.isGroup {
                GroupCard(tile: tile, thumbnails: model.thumbnails, selected: hovered)
            } else {
                ThumbnailCard(item: tile.item, image: model.thumbnails[tile.id], size: tile.frame.size,
                              selected: hovered || isTarget, cornerRadius: 8, badgeSize: min(40, tile.frame.height * 0.2))
            }
        }
        .frame(width: tile.frame.width, height: tile.frame.height)
        .overlay(alignment: .bottom) {
            Label {
                Text(tile.title)
            } icon: {
                if tile.isGroup { Image(systemName: "rectangle.split.2x1.fill") }
            }
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
                    guard !tile.isGroup else { return }
                    let global = screen.globalPoint(fromPanel: value.location)
                    let grab = CGSize(width: value.startLocation.x - tile.frame.minX,
                                      height: value.startLocation.y - tile.frame.minY)
                    actions.dragChanged(tile.id, screen.id, global, grab)
                }
                .onEnded { _ in actions.dragEnded() }
        )
        .onTapGesture { actions.activate(tile.id) }
    }

    /// Two windows CmdTab tiled together, drawn at their real relative positions inside one card.
    private struct GroupCard: View {
        let tile: ExposeTile
        let thumbnails: [CGWindowID: CGImage]
        let selected: Bool

        var body: some View {
            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.06))
                    ForEach(Array(zip(tile.members, tile.memberRects).enumerated()), id: \.element.0.id) { index, pair in
                        let (window, rel) = pair
                        let rect = CGRect(x: rel.minX * geo.size.width, y: rel.minY * geo.size.height,
                                          width: rel.width * geo.size.width, height: rel.height * geo.size.height)
                        ThumbnailCard(item: tile.items[index], image: thumbnails[window.id], size: rect.size,
                                      selected: false, cornerRadius: 6, badgeSize: min(32, rect.height * 0.2))
                            .position(x: rect.midX, y: rect.midY)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .shadow(color: .white.opacity(selected ? 0.55 : 0), radius: 26)
            .shadow(color: .white.opacity(selected ? 0.35 : 0), radius: 8)
        }
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
            let top: CGFloat = 12
            switch target {
            case .zone(screen.id, let zone):
                let rect: CGRect = {
                    switch zone {
                    case .left: return CGRect(x: 12, y: top, width: size.width / 2 - 18, height: size.height - top - 12)
                    case .right: return CGRect(x: size.width / 2 + 6, y: top, width: size.width / 2 - 18, height: size.height - top - 12)
                    case .fill: return CGRect(x: 12, y: top, width: size.width - 24, height: size.height - top - 12)
                    }
                }()
                let label = zone == .fill ? "Fill screen" : (zone == .left ? "Left half" : "Right half")
                zoneRect(rect, label: label, symbol: zone == .fill ? "rectangle" : "rectangle.split.2x1")
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
                Text("No windows on this desktop").font(.system(size: 12))
            }
        }
        .foregroundStyle(.white.opacity(0.75))
        .frame(width: width)
        .padding(.top, 36)
        .allowsHitTesting(false)
    }

    private func hint(size: CGSize) -> some View {
        Text("Drag a window onto another to split the screen between them  ·  drag to a side edge for a half, to the top or bottom for the whole screen  ·  click to switch  ·  ⎋ closes")
            .font(.system(size: 12))
            .foregroundStyle(.white.opacity(0.65))
            .padding(.horizontal, 14).padding(.vertical, 7)
            .background(Capsule().fill(.black.opacity(0.35)))
            .position(x: size.width / 2, y: size.height - 32)
            .allowsHitTesting(false)
    }
}
