import SwiftUI

/// 3D carousel: the selected window faces the viewer, the rest recede on either side.
struct CoverFlowStyleView: View {
    var model: SwitcherModel
    let actions: SwitcherActions
    let size: CGSize

    var body: some View {
        let w = size.width, h = size.height
        let box = CGSize(width: min(w * 0.46, 1000), height: h * 0.5)

        ZStack {
            ForEach(Array(model.items.enumerated()), id: \.element.id) { index, item in
                let d = CGFloat(index - model.selectedIndex)
                let absd = abs(d)
                let sign: CGFloat = d < 0 ? -1 : 1
                let cardSize = fitSize(aspectRatio: item.aspectRatio, in: box)
                let x: CGFloat = d == 0 ? 0 : sign * (box.width * 0.5 + 40 + (absd - 1) * box.width * 0.17)
                let rot: Double = d == 0 ? 0 : Double(-sign) * 54
                let scale: CGFloat = d == 0 ? 1 : max(0.5, 0.8 - 0.05 * (absd - 1))

                ThumbnailCard(item: item, image: model.thumbnail(for: item), size: cardSize,
                              selected: d == 0, cornerRadius: 12, badgeSize: 44, showReflection: true)
                    .scaleEffect(scale)
                    .rotation3DEffect(.degrees(rot), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
                    .offset(x: x, y: 0)
                    .opacity(absd > 7 ? 0 : 1)
                    .zIndex(Double(1000 - absd))
                    .onHover { if $0 { actions.hover(index) } }
                    .onTapGesture { actions.select(index) }
            }
        }
        .frame(width: w, height: h)
        .offset(y: h * 0.06)
        .overlay(alignment: .top) {
            if let selected = model.selected {
                TitleLabel(title: selected.title, subtitle: selected.subtitle)
                    .padding(.top, h * 0.08)
                    .id(selected.id)
                    .transition(.opacity)
            }
        }
    }
}
