import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Exposé: the windows of the display under the mouse spread out, with drag-and-drop arranging.
/// Pairs tiled here are remembered as groups.
@MainActor
final class ExposeController {
    let settings: AppSettings
    let model = ExposeModel()

    private let source: WindowSource
    private let thumbnails: ThumbnailStore
    private let groups: WindowGroupStore
    private let sortWindows: ([WindowInfo]) -> [WindowInfo]
    private let onActivate: (WindowInfo) -> Void
    private var panels: [Int: ExposePanel] = [:]
    private var loadTask: Task<Void, Never>?
    private(set) var isOpen = false

    private static let sideInset: CGFloat = 70
    private static let bottomInset: CGFloat = 90

    init(settings: AppSettings, source: WindowSource, thumbnails: ThumbnailStore, groups: WindowGroupStore,
         sortWindows: @escaping ([WindowInfo]) -> [WindowInfo], onActivate: @escaping (WindowInfo) -> Void) {
        self.settings = settings
        self.source = source
        self.thumbnails = thumbnails
        self.groups = groups
        self.sortWindows = sortWindows
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
        targetScreenIndex = Self.screenIndexUnderMouse()
        rebuildScreens(animated: false)
        showPanels()
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            guard let self else { return }
            await self.source.refresh()
            guard self.isOpen, !Task.isCancelled else { return }
            self.rebuildScreens(animated: true)
            await self.captureVisible()
        }
    }

    func close() {
        guard isOpen else { return }
        isOpen = false
        loadTask?.cancel()
        model.drag = nil
        for panel in panels.values { panel.hide() }
    }

    /// The display under the mouse when Exposé was invoked.
    private var targetScreenIndex = 0

    private func showPanels() {
        let screens = NSScreen.screens
        guard screens.indices.contains(targetScreenIndex) else { return }
        let panel = panels[targetScreenIndex] ?? ExposePanel(model: model, screenIndex: targetScreenIndex, actions: actions)
        panels[targetScreenIndex] = panel
        panel.show(on: screens[targetScreenIndex])
        for (index, other) in panels where index != targetScreenIndex {
            other.orderOut(nil)
        }
    }

    private static func screenIndexUnderMouse() -> Int {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.firstIndex { $0.frame.contains(mouse) } ?? 0
    }

    // MARK: - Screen and tiles

    private func rebuildScreens(animated: Bool) {
        let screens = NSScreen.screens
        let primaryHeight = screens.first?.frame.height ?? 0
        groups.prune(with: source.windows)
        // Only the current desktop's windows of the chosen display: what Mission Control would show there.
        let visible = source.windows.filter { $0.isOnScreen || (settings.exposeIncludeMinimized && $0.isMinimized) }

        var result: [ExposeScreen] = []
        for (index, screen) in screens.enumerated() where index == targetScreenIndex {
            let mine = visible.filter { Self.screenIndex(forWindowFrame: $0.frame) == index }

            // Group members become one entry; everything else is a single-window entry.
            var entries: [[WindowInfo]] = []
            var consumed = Set<CGWindowID>()
            for w in mine where !consumed.contains(w.id) {
                if let g = groups.group(containing: w.id) {
                    let members = g.ids.compactMap { id in mine.first { $0.id == id } }
                    if members.count == g.ids.count {
                        entries.append(members)
                        consumed.formUnion(g.ids)
                        continue
                    }
                }
                entries.append([w])
                consumed.insert(w.id)
            }

            let size = screen.frame.size
            let top: CGFloat = 80
            let area = CGRect(x: Self.sideInset, y: top, width: size.width - 2 * Self.sideInset,
                              height: size.height - top - Self.bottomInset)
            let unions = entries.map { ms in ms.dropFirst().reduce(ms[0].frame) { $0.union($1.frame) } }
            let layoutEntries = zip(entries, unions).map { ExposeLayout.Entry(id: $0[0].id, size: $1.size) }
            let frames = ExposeLayout.layout(layoutEntries, in: area)
            let tiles = entries.map { members in
                ExposeTile(id: members[0].id, members: members,
                           items: members.map { SwitcherItem.window($0, app: NSRunningApplication(processIdentifier: $0.pid)) },
                           groupID: members.count > 1 ? groups.group(containing: members[0].id)?.id : nil,
                           frame: frames[members[0].id] ?? .zero)
            }
            let topLeftOrigin = CGPoint(x: screen.frame.minX, y: primaryHeight - screen.frame.maxY)
            result.append(ExposeScreen(id: index, name: screen.localizedName, frame: screen.frame,
                                       topLeftOrigin: topLeftOrigin, tiles: tiles))
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

    private func captureVisible() async {
        await thumbnails.captureAll(model.allTiles.flatMap(\.members), source: source) { [weak self] id, image in
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

    /// Switches to a window, or brings a whole group forward with its last member focused.
    private func activate(_ id: CGWindowID) {
        guard let tile = model.tile(id) else { return }
        close()
        bringForward(tile.members)
    }

    private func bringForward(_ windows: [WindowInfo]) {
        Task { [weak self] in
            for (i, w) in windows.enumerated() {
                if i > 0 { try? await Task.sleep(for: .milliseconds(120)) }
                self?.onActivate(w)
            }
        }
    }

    // MARK: - Drag and drop

    private func dragChanged(_ id: CGWindowID, screen: Int, global: CGPoint, grab: CGSize) {
        if model.drag == nil {
            guard let tile = model.tile(id), !tile.isGroup else { return }
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
        if p.y < edge || p.y > screen.size.height - edge { return .zone(screen.id, .fill) }
        if p.x < edge { return .zone(screen.id, .left) }
        if p.x > screen.size.width - edge { return .zone(screen.id, .right) }
        for tile in screen.tiles where tile.id != id && !tile.isGroup {
            if tile.frame.insetBy(dx: -10, dy: -10).contains(p) {
                return .window(tile.id, p.x < tile.frame.midX ? .left : .right)
            }
        }
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
        var newGroup: [WindowInfo]? = nil

        switch target {
        case .window(let otherID, let side):
            guard let other = source.windows.first(where: { $0.id == otherID }),
                  let screen = model.screen(withTile: otherID),
                  let nsScreen = nsScreen(for: screen.id) else { return }
            let halves = WindowArranger.halves(of: WindowArranger.visibleArea(of: nsScreen))
            WindowArranger.setFrame(window, to: side == .left ? halves.left : halves.right, axCache: axCache)
            WindowArranger.setFrame(other, to: side == .left ? halves.right : halves.left, axCache: axCache)
            focus.insert(other, at: 0)
            newGroup = focus

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

        }

        // A drop ends the arranging: leave the overview and bring the arranged windows forward,
        // the dragged one last so it ends up focused.
        close()
        bringForward(focus)

        if let newGroup {
            // Remember the pair with the frames the apps actually settled on.
            Task { [weak self, source, groups] in
                try? await Task.sleep(for: .milliseconds(450))
                await source.refresh()
                let settled = newGroup.compactMap { m in source.windows.first { $0.id == m.id } }
                guard settled.count == newGroup.count, self != nil else { return }
                groups.add(settled)
            }
        }
    }

    private func nsScreen(for index: Int) -> NSScreen? {
        NSScreen.screens.indices.contains(index) ? NSScreen.screens[index] : nil
    }
}
