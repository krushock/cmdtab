import SwiftUI

/// One horizontal line of window previews, the selected one enlarged in the middle.
struct FilmstripStyleView: View {
    var model: SwitcherModel
    let actions: SwitcherActions
    let size: CGSize

    var body: some View {
        let cellW = min(380, size.width * 0.24)
        let cellH = min(260, size.height * 0.3)
        let gap: CGFloat = 28
        let visible = Int(size.width / (cellW + gap)) / 2 + 2

        ZStack {
            ForEach(Array(model.items.enumerated()), id: \.element.id) { index, item in
                let d = CGFloat(index - model.selectedIndex)
                let selected = d == 0
                let thumb = fitSize(aspectRatio: item.aspectRatio, in: CGSize(width: cellW, height: cellH))
                ThumbnailCard(item: item, image: model.thumbnail(for: item), size: thumb,
                              selected: selected, cornerRadius: 10, badgeSize: 34)
                    .scaleEffect(selected ? 1.14 : 0.9)
                    .offset(x: d * (cellW + gap))
                    .opacity(abs(d) > CGFloat(visible) ? 0 : 1)
                    .zIndex(selected ? 10 : 0)
                    .onHover { if $0 { actions.hover(index) } }
                    .onTapGesture { actions.select(index) }
            }
        }
        .frame(width: size.width, height: size.height)
        .overlay(alignment: .bottom) {
            if let selected = model.selected {
                TitleLabel(title: selected.title, subtitle: selected.subtitle)
                    .padding(.bottom, size.height * 0.5 - cellH * 0.6 - 60)
                    .id(selected.id)
                    .transition(.opacity)
            }
        }
    }
}
