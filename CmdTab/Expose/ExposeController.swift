import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Exposé: every window of every display spread out, with drag-and-drop arranging.
@MainActor
final class ExposeController {
    let settings: AppSettings
    let model = ExposeModel()

    private let source: WindowSource
    private let thumbnails: ThumbnailStore
    private let onActivate: (WindowInfo) -> Void
    private var panels: [Int: ExposePanel] = [:]
    private var loadTask: Task<Void, Never>?
    private(set) var isOpen = false

    /// Layout margins inside each screen: room for the display name above and the hint below.
    private static let insets = NSEdgeInsets(top: 80, left: 70, bottom: 90, right: 70)

    init(settings: AppSettings, source: WindowSource, thumbnails: ThumbnailStore, onActivate: @escaping (WindowInfo) -> Void) {
        self.settings = settings
        self.source = source
        self.thumbnails = thumbnails
        self.onActivate = onActivate
    }

    private var actions: ExposeActions {
        ExposeActions(
            hover: { [weak self] id in self?.hover(id) },
            activate: { [weak self] id in self?.activate(id) },
            dragChanged: { [weak self] id, screen, global, grab in self?.dragChanged(id, screen: screen, global: global, grab: grab) },
            dragEnded: { [weak self] in self?.dragEnded() },
            cancel: { [weak self] in self?.close() })
    }

    // MARK: - Open / close

    func toggle() {
        if isOpen { close() } else { open() }
    }

    func open() {
        guard !isOpen else { return }
        isOpen = true
        model.presentation += 1
        model.drag = nil
        model.hovered = nil
        rebuildScreens(animated: false)
        showPanels()
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            guard let self else { return }
            await self.source.refresh()
            guard self.isOpen, !Task.isCancelled else { return }
            self.rebuildScreens(animated: true)
            await self.capture(self.model.allTiles.map(\.window))
        }
    }

    func close() {
        guard isOpen else { return }
        isOpen = false
        loadTask?.cancel()
        model.drag = nil
        for panel in panels.values { panel.hide() }
    }

    private func showPanels() {
        let screens = NSScreen.screens
        for (index, screen) in screens.enumerated() {
            let panel = panels[index] ?? ExposePanel(model: model, screenIndex: index, actions: actions)
            panels[index] = panel
            panel.show(on: screen)
        }
        for (index, panel) in panels where index >= screens.count {
            panel.orderOut(nil)
            panels[index] = nil
        }
    }

    // MARK: - Screens and tiles

    private func rebuildScreens(animated: Bool) {
        let screens = NSScreen.screens
        let windows = source.windows.filter { $0.isOnScreen || (settings.exposeIncludeMinimized && $0.isMinimized) }
        var result: [ExposeScreen] = []
        for (index, screen) in screens.enumerated() {
            let mine = windows.filter { Self.screenIndex(forWindowFrame: $0.frame) == index }
            let size = screen.frame.size
            let area = CGRect(x: Self.insets.left, y: Self.insets.top,
                              width: size.width - Self.insets.left - Self.insets.right,
                              height: size.height - Self.insets.top - Self.insets.bottom)
            let frames = ExposeLayout.layout(mine, in: area)
            let tiles = mine.map { w in
                ExposeTile(id: w.id, window: w,
                           item: SwitcherItem.window(w, app: NSRunningApplication(processIdentifier: w.pid)),
                           frame: frames[w.id] ?? .zero)
            }
            result.append(ExposeScreen(id: index, name: screen.localizedName, frame: screen.frame, tiles: tiles))
        }
        if animated {
            withAnimation(.spring(duration: 0.4, bounce: 0.15)) { model.screens = result }
        } else {
            model.screens = result
        }
    }

    /// Index of the screen holding the centre of a window frame (top-left coordinates).
    static func screenIndex(forWindowFrame frame: CGRect) -> Int {
        guard let primary = NSScreen.screens.first else { return 0 }
        let center = CGPoint(x: frame.midX, y: primary.frame.height - frame.midY)
        return NSScreen.screens.firstIndex { $0.frame.contains(center) } ?? 0
    }

    private func capture(_ windows: [WindowInfo]) async {
        await thumbnails.captureAll(windows, source: source) { [weak self] id, image in
            self?.model.thumbnails[id] = image
        }
    }

    // MARK: - Keyboard

    /// Handles a key while Exposé is open. Everything is swallowed; this decides what it does.
    func handleKey(keyCode: UInt16, flags: CGEventFlags) {
        switch Int(keyCode) {
        case kVK_Escape:
            close()
        case kVK_Return, kVK_ANSI_KeypadEnter, kVK_Space:
            if let id = model.hovered ?? model.allTiles.first?.id { activate(id) }
        case kVK_LeftArrow, kVK_UpArrow:
            moveSelection(-1)
        case kVK_RightArrow, kVK_DownArrow, kVK_Tab:
            moveSelection(1)
        default:
            break
        }
    }

    private func moveSelection(_ delta: Int) {
        let tiles = model.allTiles
        guard !tiles.isEmpty else { return }
        let current = tiles.firstIndex { $0.id == model.hovered } ?? (delta > 0 ? -1 : 0)
        let next = ((current + delta) % tiles.count + tiles.count) % tiles.count
        withAnimation(.snappy) { model.hovered = tiles[next].id }
    }

    // MARK: - Mouse

    private func hover(_ id: CGWindowID?) {
        guard model.drag == nil else { return }
        if id == nil && model.hovered != nil && NSEvent.pressedMouseButtons != 0 { return }
        withAnimation(.snappy(duration: 0.18)) { model.hovered = id }
    }

    private func activate(_ id: CGWindowID) {
        guard let window = model.tile(id)?.window else { return }
        close()
        onActivate(window)
    }

    private func dragChanged(_ id: CGWindowID, screen: Int, global: CGPoint, grab: CGSize) {
        if model.drag == nil {
            guard let tile = model.tile(id) else { return }
            model.hovered = nil
            model.drag = ExposeDrag(windowID: id, sourceScreen: screen, grabOffset: grab,
                                    tileSize: tile.frame.size, location: global, target: nil)
        }
        model.drag?.location = global
        let target = dropTarget(at: global, dragging: id, from: screen)
        if target != model.drag?.target {
            withAnimation(.snappy(duration: 0.2)) { model.drag?.target = target }
        }
    }

    private func dropTarget(at global: CGPoint, dragging id: CGWindowID, from sourceScreen: Int) -> DropTarget? {
        guard let screen = model.screen(containing: global) else { return nil }
        let p = screen.panelPoint(fromGlobal: global)
        let edge: CGFloat = 56
        if p.y < edge { return .zone(screen.id, .fill) }
        if p.x < edge { return .zone(screen.id, .left) }
        if p.x > screen.size.width - edge { return .zone(screen.id, .right) }
        for tile in screen.tiles where tile.id != id {
            if tile.frame.insetBy(dx: -10, dy: -10).contains(p) {
                return .window(tile.id, p.x < tile.frame.midX ? .left : .right)
            }
        }
        if screen.id != sourceScreen { return .display(screen.id) }
        return nil
    }

    private func dragEnded() {
        guard let drag = model.drag else { return }
        withAnimation(.spring(duration: 0.35, bounce: 0.2)) { model.drag = nil }
        guard let target = drag.target,
              let window = source.windows.first(where: { $0.id == drag.windowID }) else { return }
        let axCache = source.axCache
        /// Windows to bring forward afterwards, last one gets focus.
        var focus: [WindowInfo] = [window]

        switch target {
        case .window(let otherID, let side):
            guard let other = source.windows.first(where: { $0.id == otherID }),
                  let screen = model.screen(withTile: otherID),
                  let nsScreen = nsScreen(for: screen.id) else { return }
            let halves = WindowArranger.halves(of: WindowArranger.visibleArea(of: nsScreen))
            WindowArranger.setFrame(window, to: side == .left ? halves.left : halves.right, axCache: axCache)
            WindowArranger.setFrame(other, to: side == .left ? halves.right : halves.left, axCache: axCache)
            focus.insert(other, at: 0)

        case .zone(let screenID, let zone):
            guard let nsScreen = nsScreen(for: screenID) else { return }
            let area = WindowArranger.visibleArea(of: nsScreen)
            let halves = WindowArranger.halves(of: area)
            let rect: CGRect
            switch zone {
            case .left: rect = halves.left
            case .right: rect = halves.right
            case .fill: rect = area
            }
            WindowArranger.setFrame(window, to: rect, axCache: axCache)

        case .display(let screenID):
            guard let nsScreen = nsScreen(for: screenID) else { return }
            let area = WindowArranger.visibleArea(of: nsScreen)
            WindowArranger.setFrame(window, to: WindowArranger.centered(size: window.frame.size, in: area), axCache: axCache)
        }

        // A drop ends the arranging: leave the overview and bring the arranged windows forward,
        // the dragged one last so it ends up focused.
        close()
        Task { [weak self] in
            for (i, w) in focus.enumerated() {
                if i > 0 { try? await Task.sleep(for: .milliseconds(120)) }
                self?.onActivate(w)
            }
        }
    }

    private func nsScreen(for index: Int) -> NSScreen? {
        NSScreen.screens.indices.contains(index) ? NSScreen.screens[index] : nil
    }
}
