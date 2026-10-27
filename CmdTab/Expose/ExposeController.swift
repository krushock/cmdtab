import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Exposé: every window of every display spread out, a Spaces bar per display, and
/// drag-and-drop arranging. Pairs tiled here are remembered as groups.
@MainActor
final class ExposeController {
    let settings: AppSettings
    let model = ExposeModel()

    private let source: WindowSource
    private let thumbnails: ThumbnailStore
    private let groups: WindowGroupStore
    private let spaces = SpaceManager()
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
            switchSpace: { [weak self] screen, space in self?.switchSpace(display: screen, id: space) },
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

    // MARK: - Screens, tiles, spaces

    private func rebuildScreens(animated: Bool) {
        let screens = NSScreen.screens
        let primaryHeight = screens.first?.frame.height ?? 0
        groups.prune(with: source.windows)
        if spaces.isAvailable { spaces.refresh(windows: source.windows) }
        let visible = source.windows.filter { $0.isOnScreen || (settings.exposeIncludeMinimized && $0.isMinimized) }

        var result: [ExposeScreen] = []
        for (index, screen) in screens.enumerated() {
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

            let spaceTiles = spaceTiles(forDisplay: index)
            let size = screen.frame.size
            let top: CGFloat = spaceTiles.isEmpty ? 80 : SpacesBarLayout.totalHeight + 36
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
                                       topLeftOrigin: topLeftOrigin, tiles: tiles, spaces: spaceTiles))
        }
        if animated {
            withAnimation(.spring(duration: 0.4, bounce: 0.15)) { model.screens = result }
        } else {
            model.screens = result
        }
    }

    private func spaceTiles(forDisplay index: Int) -> [SpaceTile] {
        let list = spaces.spaces(forDisplay: index)
        guard list.count > 1 || list.contains(where: \.isFullscreen) else { return [] }
        var desktopNumber = 0
        return list.map { space in
            let windows = sortWindows(source.windows.filter {
                spaces.space(for: $0.id) == space.id && !$0.isMinimized && Self.screenIndex(forWindowFrame: $0.frame) == index
            })
            let name: String
            if space.isFullscreen {
                name = windows.first?.appName ?? "Full Screen"
            } else {
                desktopNumber += 1
                name = "Desktop \(desktopNumber)"
            }
            return SpaceTile(id: space.id, index: space.index, name: name, isCurrent: space.isCurrent,
                             isFullscreen: space.isFullscreen, windows: windows)
        }
    }

    /// Index of the screen holding the centre of a window frame (top-left coordinates).
    static func screenIndex(forWindowFrame frame: CGRect) -> Int {
        guard let primary = NSScreen.screens.first else { return 0 }
        let center = CGPoint(x: frame.midX, y: primary.frame.height - frame.midY)
        return NSScreen.screens.firstIndex { $0.frame.contains(center) } ?? 0
    }

    /// Previews for the tiles first, then for the windows shown inside the Space cards.
    private func captureVisible() async {
        var seen = Set<CGWindowID>()
        var list: [WindowInfo] = []
        for w in model.allTiles.flatMap(\.members) + model.screens.flatMap { $0.spaces.flatMap(\.windows) } {
            if seen.insert(w.id).inserted { list.append(w) }
        }
        await thumbnails.captureAll(list, source: source) { [weak self] id, image in
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

    private func switchSpace(display: Int, id: UInt64) {
        guard let target = spaces.spaces(forDisplay: display).first(where: { $0.id == id }) else { return }
        close()
        guard !target.isCurrent else { return }
        let switched = spaces.switchTo(space: id, display: display)
        // Give the most recent window there focus once the switch has happened.
        if let w = sortWindows(source.windows.filter { spaces.space(for: $0.id) == id }).first {
            let activate = onActivate
            Task {
                if switched { try? await Task.sleep(for: .milliseconds(350)) }
                activate(w)
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
        for (spaceID, frame) in SpacesBarLayout.cardFrames(for: screen.spaces, screenSize: screen.size)
        where frame.insetBy(dx: -8, dy: -8).contains(p) {
            if let space = screen.spaces.first(where: { $0.id == spaceID }), !space.isFullscreen, !space.isCurrent {
                return .space(screen.id, spaceID)
            }
            return nil
        }
        let edge: CGFloat = 56
        if p.y < edge && screen.spaces.isEmpty { return .zone(screen.id, .fill) }
        if p.x < edge { return .zone(screen.id, .left) }
        if p.x > screen.size.width - edge { return .zone(screen.id, .right) }
        if p.y > screen.size.height - edge { return .zone(screen.id, .fill) }
        for tile in screen.tiles where tile.id != id && !tile.isGroup {
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

        case .display(let screenID):
            guard let nsScreen = nsScreen(for: screenID) else { return }
            let area = WindowArranger.visibleArea(of: nsScreen)
            WindowArranger.setFrame(window, to: WindowArranger.centered(size: window.frame.size, in: area), axCache: axCache)

        case .space(let screenID, let spaceID):
            guard let screen = model.screens.first(where: { $0.id == screenID }),
                  let space = screen.spaces.first(where: { $0.id == spaceID }),
                  let nsScreen = nsScreen(for: screenID),
                  spaces.space(for: window.id) != spaceID else { return }
            close()
            let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
            let frame = CGRect(x: nsScreen.frame.minX, y: primaryHeight - nsScreen.frame.maxY,
                               width: nsScreen.frame.width, height: nsScreen.frame.height)
            Task {
                try? await Task.sleep(for: .milliseconds(250))   // overlay fade-out first
                let ok = await MissionControl.move(window, toSpaceTitled: space.name, screenFrame: frame)
                if !ok { NSLog("CmdTab: could not move window \(window.id) to \(space.name) via Mission Control") }
            }
            return
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
