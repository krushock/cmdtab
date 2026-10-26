import SwiftUI

struct SwitcherRootView: View {
    var model: SwitcherModel
    let actions: SwitcherActions

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if model.style.usesFullScreenBackdrop && model.dimBackground {
                    VisualEffectView(material: .fullScreenUI, blendingMode: .behindWindow)
                        .overlay(Color.black.opacity(0.38))
                        .allowsHitTesting(false)
                }
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { actions.cancel() }
                SwitcherContent(model: model, actions: actions, size: geo.size)
                    .id(model.presentation)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
    }
}

private struct SwitcherContent: View {
    var model: SwitcherModel
    let actions: SwitcherActions
    let size: CGSize
    @State private var appeared = false

    var body: some View {
        Group {
            switch model.style {
            case .classic: ClassicStyleView(model: model, actions: actions, size: size)
            case .grid: GridStyleView(model: model, actions: actions, size: size)
            case .coverFlow: CoverFlowStyleView(model: model, actions: actions, size: size)
            case .ring: RingStyleView(model: model, actions: actions, size: size)
            case .filmstrip: FilmstripStyleView(model: model, actions: actions, size: size)
            }
        }
        .frame(width: size.width, height: size.height)
        .scaleEffect(appeared ? 1 : 0.94)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(.spring(duration: 0.3, bounce: 0.22)) { appeared = true }
        }
    }
}

// MARK: - Shared pieces

struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = blendingMode
        v.state = .active
        return v
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

struct AppIconView: View {
    let icon: NSImage?
    let size: CGFloat

    var body: some View {
        Group {
            if let icon {
                Image(nsImage: icon).resizable().interpolation(.high)
            } else {
                Image(systemName: "app.dashed").resizable().foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.3), radius: size * 0.06, y: size * 0.03)
    }
}

/// A window preview with rounded corners, selection ring and app-icon badge.
struct ThumbnailCard: View {
    let item: SwitcherItem
    let image: CGImage?
    let size: CGSize
    let selected: Bool
    var cornerRadius: CGFloat = 12
    var badgeSize: CGFloat = 40
    var showReflection = false

    var body: some View {
        if showReflection {
            VStack(spacing: 2) {
                card(plain: false)
                card(plain: true)
                    .scaleEffect(y: -1)
                    .mask(LinearGradient(colors: [.white.opacity(0.28), .clear], startPoint: .top, endPoint: .bottom))
                    .frame(height: size.height * 0.4, alignment: .top)
                    .clipped()
                    .allowsHitTesting(false)
            }
        } else {
            card(plain: false)
        }
    }

    @ViewBuilder
    private func card(plain: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        ZStack {
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
            } else {
                shape.fill(Color.white.opacity(0.10))
                AppIconView(icon: item.icon, size: min(size.width, size.height) * 0.45)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(shape)
        // Drop shadow for depth, plus a soft white glow around the selected window (no border).
        .shadow(color: .black.opacity(plain ? 0 : 0.4), radius: plain ? 0 : 16, y: plain ? 0 : 10)
        .shadow(color: .white.opacity(plain || !selected ? 0 : 0.55), radius: 26)
        .shadow(color: .white.opacity(plain || !selected ? 0 : 0.35), radius: 8)
        .overlay(alignment: .bottomTrailing) {
            if !plain {
                AppIconView(icon: item.icon, size: badgeSize)
                    .offset(x: badgeSize * 0.22, y: badgeSize * 0.22)
            }
        }
        .overlay(alignment: .topLeading) {
            if !plain && item.isMinimized {
                Label("Minimized", systemImage: "arrow.down.right.and.arrow.up.left")
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Capsule().fill(.black.opacity(0.55)))
                    .foregroundStyle(.white)
                    .padding(8)
            }
        }
    }
}

/// Title + subtitle label rendered over the backdrop.
struct TitleLabel: View {
    let title: String
    let subtitle: String?
    var onBackdrop = true

    var body: some View {
        VStack(spacing: 3) {
            Text(title)
                .font(.system(size: onBackdrop ? 22 : 15, weight: .medium))
                .lineLimit(1)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: onBackdrop ? 14 : 12))
                    .opacity(0.7)
                    .lineLimit(1)
            }
        }
        .foregroundStyle(onBackdrop ? Color.white : Color.primary)
        .shadow(color: .black.opacity(onBackdrop ? 0.5 : 0), radius: 6, y: 2)
        .padding(.horizontal, onBackdrop ? 0 : 16)
        .padding(.vertical, onBackdrop ? 0 : 8)
        .background {
            if !onBackdrop {
                VisualEffectView(material: .hudWindow).clipShape(Capsule())
            }
        }
        .frame(maxWidth: 700)
    }
}

enum GridLayout {
    static func columns(for count: Int) -> Int {
        max(1, min(count, Int(ceil(sqrt(Double(count) * 1.7)))))
    }
}

func fitSize(aspectRatio: CGFloat, in box: CGSize) -> CGSize {
    guard box.width > 0, box.height > 0 else { return .zero }
    let w = min(box.width, box.height * aspectRatio)
    return CGSize(width: w, height: w / aspectRatio)
}
