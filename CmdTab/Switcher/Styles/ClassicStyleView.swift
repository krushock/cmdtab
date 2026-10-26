import SwiftUI

/// A row of application icons in a frosted bar, like the built-in ⌘⇥ switcher.
struct ClassicStyleView: View {
    var model: SwitcherModel
    let actions: SwitcherActions
    let size: CGSize
    @Namespace private var ns

    var body: some View {
        let count = max(1, model.items.count)
        let maxBar = size.width * 0.92 - 32
        let cell = max(56, min(136, floor(maxBar / CGFloat(count))))
        let iconSize = cell - 26

        VStack(spacing: 14) {
            HStack(spacing: 0) {
                ForEach(Array(model.items.enumerated()), id: \.element.id) { index, item in
                    ZStack {
                        if index == model.selectedIndex {
                            RoundedRectangle(cornerRadius: cell * 0.18, style: .continuous)
                                .fill(Color.primary.opacity(0.16))
                                .matchedGeometryEffect(id: "selection", in: ns)
                        }
                        cellContent(item, iconSize: iconSize)
                    }
                    .frame(width: cell, height: cell)
                    .contentShape(Rectangle())
                    .onHover { if $0 { actions.hover(index) } }
                    .onTapGesture { actions.select(index) }
                }
            }
            .padding(16)
            .background {
                MaterialBackground(material: .hudWindow)
                    .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
            }
            .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous).strokeBorder(Color.primary.opacity(0.1)))
            .shadow(color: .black.opacity(0.28), radius: 30, y: 12)

            if let selected = model.selected {
                TitleLabel(title: selected.title, subtitle: selected.subtitle, onBackdrop: false)
                    .id(selected.id)
                    .transition(.opacity)
            }
        }
        .frame(width: size.width, height: size.height)
    }

    @ViewBuilder
    private func cellContent(_ item: SwitcherItem, iconSize: CGFloat) -> some View {
        if item.isApp {
            AppIconView(icon: item.icon, size: iconSize)
        } else {
            ThumbnailCard(item: item, image: model.thumbnail(for: item),
                          size: fitSize(aspectRatio: item.aspectRatio, in: CGSize(width: iconSize, height: iconSize * 0.8)),
                          selected: false, cornerRadius: 6, badgeSize: iconSize * 0.34)
        }
    }
}
