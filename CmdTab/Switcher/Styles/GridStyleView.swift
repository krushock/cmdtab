import SwiftUI

/// Window previews laid out in a grid (AltTab-like).
struct GridStyleView: View {
    var model: SwitcherModel
    let actions: SwitcherActions
    let size: CGSize

    var body: some View {
        let count = max(1, model.items.count)
        let cols = GridLayout.columns(for: count)
        let rows = Int(ceil(Double(count) / Double(cols)))
        let spacing: CGFloat = 18
        let maxW = size.width * 0.9
        let maxH = size.height * 0.86
        let cellW = min(340, (maxW - spacing * CGFloat(cols - 1)) / CGFloat(cols))
        let thumbH = max(60, min(cellW * 0.62, (maxH - spacing * CGFloat(rows - 1)) / CGFloat(rows) - 56))
        let thumbBox = CGSize(width: cellW - 20, height: thumbH)

        VStack {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(cellW), spacing: spacing), count: cols), spacing: spacing) {
                ForEach(Array(model.items.enumerated()), id: \.element.id) { index, item in
                    let selected = index == model.selectedIndex
                    VStack(spacing: 10) {
                        ThumbnailCard(item: item, image: model.thumbnail(for: item),
                                      size: fitSize(aspectRatio: item.aspectRatio, in: thumbBox),
                                      selected: selected, cornerRadius: 8, badgeSize: 30)
                            .frame(width: thumbBox.width, height: thumbBox.height)
                        Text(item.title)
                            .font(.system(size: 13, weight: selected ? .semibold : .medium))
                            .lineLimit(1)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                    }
                    .padding(10)
                    .frame(width: cellW)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(selected ? 0.18 : 0)))
                    .contentShape(Rectangle())
                    .onHover { if $0 { actions.hover(index) } }
                    .onTapGesture { actions.select(index) }
                }
            }
            .padding(24)
            .background {
                VisualEffectView(material: .hudWindow)
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            }
            .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(Color.white.opacity(0.12)))
            .shadow(color: .black.opacity(0.3), radius: 30, y: 12)
        }
        .frame(width: size.width, height: size.height)
    }
}
