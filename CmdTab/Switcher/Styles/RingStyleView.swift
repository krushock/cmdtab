import SwiftUI

/// Windows placed on a 3D ring viewed from slightly above. The selected window sits at the front;
/// cycling spins the whole ring.
struct RingStyleView: View {
    var model: SwitcherModel
    let actions: SwitcherActions
    let size: CGSize

    /// Shortest signed distance around the ring, so the spin always takes the short way.
    private static func ringDistance(_ delta: Int, count: Int) -> Double {
        let d = Double(delta)
        return d - Double(count) * (d / Double(count)).rounded()
    }

    var body: some View {
        let w = size.width, h = size.height
        let n = max(1, model.items.count)
        // Never spread fewer than six slots around the ring, so small lists still look like a ring.
        let slots = Double(max(n, 6))
        let radiusX = min(w * 0.4, 1100.0)
        let radiusY = h * 0.17
        let box = CGSize(width: min(w * 0.34, 760), height: h * 0.4)

        ZStack {
            ForEach(Array(model.items.enumerated()), id: \.element.id) { index, item in
                let d = Self.ringDistance(index - model.selectedIndex, count: n)
                let theta = d / slots * 2 * .pi
                let c = cos(theta), s = sin(theta)
                let depth = (c + 1) / 2                     // 1 at the front, 0 at the back
                let scale = 0.42 + 0.58 * depth
                let cardSize = fitSize(aspectRatio: item.aspectRatio, in: box)

                ThumbnailCard(item: item, image: model.thumbnail(for: item), size: cardSize,
                              selected: index == model.selectedIndex, cornerRadius: 12, badgeSize: 44,
                              showReflection: true)
                    .scaleEffect(scale)
                    .rotation3DEffect(.degrees(-s * 30), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
                    .offset(x: s * radiusX, y: c * radiusY)
                    .opacity(0.45 + 0.55 * depth)
                    .zIndex(depth * 100)
                    .onHover { if $0 { actions.hover(index) } }
                    .onTapGesture { actions.select(index) }
            }
        }
        .frame(width: w, height: h)
        .offset(y: h * 0.02)
        .overlay(alignment: .top) {
            if let selected = model.selected {
                TitleLabel(title: selected.title, subtitle: selected.subtitle)
                    .padding(.top, h * 0.07)
                    .id(selected.id)
                    .transition(.opacity)
            }
        }
    }
}
