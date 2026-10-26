import AppKit
import Carbon.HIToolbox
import SwiftUI

/// State machine behind the switcher: listens to the event tap, builds the item list, drives the panel
/// and activates the chosen window.
@MainActor
final class SwitcherController {
    let settings: AppSettings
    let model = SwitcherModel()

    private let source = WindowSource()
    private let thumbnails = ThumbnailStore()
    private let mru = MRUTracker()
    private var tap: EventTap?
    private lazy var panel: SwitcherPanel = {
        SwitcherPanel(model: model, actions: SwitcherActions(
            hover: { [weak self] i in self?.hover(i) },
            select: { [weak self] i in self?.select(i) },
            cancel: { [weak self] in self?.cancel() }))
    }()

    private(set) var isOpen = false
    private var activeShortcut: Shortcut?
    private var showTask: Task<Void, Never>?
    private var loadTask: Task<Void, Never>?
    private var swallowedKeys = Set<UInt16>()
    private var interacted = false
    private var mouseAtShow = CGPoint.zero
    /// Display the switcher is (or will be) shown on for the current open.
    private var currentScreen: NSScreen?
    private var previewTask: Task<Void, Never>?

    init(settings: AppSettings) {
        self.settings = settings
        Task { await source.refresh() }
    }

    var isRunning: Bool { tap?.isRunning ?? false }

    @discardableResult
    func start() -> Bool {
        if tap == nil {
            tap = EventTap { [weak self] type, event in
                MainActor.assumeIsolated { self?.handle(type, event) ?? false }
            }
        }
        return tap?.start() ?? false
    }

    func stop() {
        tap?.stop()
        if isOpen { cancel() }
    }

    // MARK: - Event handling

    private var configuredShortcuts: [(Shortcut, SwitcherScope)] {
        var list: [(Shortcut, SwitcherScope)] = [(settings.mainShortcut, settings.showAllWindows ? .windows : .apps)]
        if let s = settings.appWindowsShortcut { list.append((s, .appWindows)) }
        return list
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        switch type {
        case .keyDown:
            let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
            let flags = event.flags.intersection(Shortcut.relevantMask)
            if let recorder = ShortcutRecording.shared.handler {
                swallowedKeys.insert(keyCode)
                recorder(keyCode, flags)
                return true
            }
            if isOpen {
                swallowedKeys.insert(keyCode)
                handleKeyWhileOpen(keyCode: keyCode, flags: flags)
                return true
            }
            for (shortcut, scope) in configuredShortcuts {
                if shortcut.matches(keyCode: keyCode, flags: flags) {
                    swallowedKeys.insert(keyCode)
                    open(scope: scope, shortcut: shortcut, backward: false)
                    return true
                }
                if shortcut.matchesReverse(keyCode: keyCode, flags: flags) {
                    swallowedKeys.insert(keyCode)
                    open(scope: scope, shortcut: shortcut, backward: true)
                    return true
                }
            }
            return false

        case .keyUp:
            let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
            if swallowedKeys.remove(keyCode) != nil { return true }
            return isOpen

        case .flagsChanged:
            if isOpen, let shortcut = activeShortcut, shortcut.isHoldStyle {
                let held = event.flags.intersection(Shortcut.holdMask)
                if !held.isSuperset(of: shortcut.holdFlags) {
                    commit()
                }
            }
            return false

        default:
            return false
        }
    }

    private func handleKeyWhileOpen(keyCode: UInt16, flags: CGEventFlags) {
        if let shortcut = activeShortcut {
            if shortcut.matches(keyCode: keyCode, flags: flags) { move(1); return }
            if shortcut.matchesReverse(keyCode: keyCode, flags: flags) { move(-1); return }

            // Pressing the other configured shortcut while holding the modifier switches scope
            // (e.g. ⌘` while in ⌘⇥ shows the current app's windows).
            for (other, scope) in configuredShortcuts where other != shortcut {
                if other.keyCode == keyCode, other.holdFlags == shortcut.holdFlags, scope != model.scope {
                    switchScope(to: scope, shortcut: other)
                    return
                }
                if other.keyCode == keyCode, other.holdFlags == shortcut.holdFlags {
                    move(-1)
                    return
                }
            }
        } else if Int(keyCode) == kVK_Tab {
            // Preview mode: ⇥ / ⇧⇥ cycle.
            move(flags.contains(.maskShift) ? -1 : 1)
            return
        }

        let vertical = model.style == .grid ? model.columns : 1
        switch Int(keyCode) {
        case kVK_LeftArrow: move(-1)
        case kVK_RightArrow: move(1)
        case kVK_UpArrow: move(-vertical)
        case kVK_DownArrow: move(vertical)
        case kVK_Home: setSelection(0)
        case kVK_End: setSelection(max(0, model.items.count - 1))
        case kVK_Escape: cancel()
        case kVK_Return, kVK_ANSI_KeypadEnter, kVK_Space: commit()
        case kVK_ANSI_W: closeSelectedWindow()
        case kVK_ANSI_M: minimizeSelectedWindow()
        case kVK_ANSI_Q: quitSelectedApp()
        default: break
        }
    }

    // MARK: - Opening / closing

    /// Shows the switcher without a shortcut being held: ⇥ cycles, ↩ or a click switches, ⎋ dismisses.
    func preview() {
        if isOpen { cancel() }
        open(scope: settings.showAllWindows ? .windows : .apps, shortcut: nil, backward: false)
        previewTask?.cancel()
        previewTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard let self, self.isOpen, self.activeShortcut == nil, !Task.isCancelled else { return }
            self.cancel()
        }
    }

    private func open(scope: SwitcherScope, shortcut: Shortcut?, backward: Bool) {
        isOpen = true
        interacted = false
        activeShortcut = shortcut
        model.scope = scope
        model.style = settings.style
        model.dimBackground = settings.dimBackground

        noteFrontmostWindow()
        currentScreen = targetScreen()
        rebuildItems(preservingSelection: false)
        guard !model.items.isEmpty else { close(); return }
        let n = model.items.count
        model.selectedIndex = n > 1 ? (backward ? n - 1 : 1) : 0

        let delay = (shortcut?.isHoldStyle ?? false) ? settings.showDelay : 0
        showTask?.cancel()
        showTask = Task { [weak self] in
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            guard let self, self.isOpen, !Task.isCancelled else { return }
            self.showPanel()
        }

        loadTask?.cancel()
        loadTask = Task { [weak self] in
            guard let self else { return }
            await self.source.refresh()
            guard self.isOpen, !Task.isCancelled else { return }
            self.rebuildItems(preservingSelection: true)
            await self.captureThumbnails()
        }
    }

    private func switchScope(to scope: SwitcherScope, shortcut: Shortcut) {
        activeShortcut = shortcut
        model.scope = scope
        rebuildItems(preservingSelection: false)
        guard !model.items.isEmpty else { close(); return }
        setSelection(min(1, model.items.count - 1))
        loadTask?.cancel()
        loadTask = Task { [weak self] in await self?.captureThumbnails() }
    }

    private func showPanel() {
        model.presentation += 1
        mouseAtShow = NSEvent.mouseLocation
        panel.show(on: currentScreen ?? targetScreen())
    }

    private func targetScreen() -> NSScreen {
        let fallback = NSScreen.main ?? NSScreen.screens[0]
        switch settings.displayRule {
        case .primary:
            return NSScreen.screens.first ?? fallback
        case .mouse:
            return screenUnderMouse() ?? fallback
        case .activeWindow:
            if let frame = mru.sorted(source.windows).first?.frame, let s = Self.screen(containing: frame) { return s }
            return screenUnderMouse() ?? fallback
        }
    }

    private func screenUnderMouse() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { $0.frame.contains(mouse) })
    }

    /// Display containing the centre of a window frame given in ScreenCaptureKit's top-left coordinates.
    private static func screen(containing frame: CGRect) -> NSScreen? {
        guard let primary = NSScreen.screens.first else { return nil }
        let flippedCenter = CGPoint(x: frame.midX, y: primary.frame.height - frame.midY)
        return NSScreen.screens.first(where: { $0.frame.contains(flippedCenter) })
    }

    private func close() {
        isOpen = false
        activeShortcut = nil
        interacted = false
        showTask?.cancel()
        loadTask?.cancel()
        previewTask?.cancel()
        panel.hide()
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            await self?.source.refresh()
            self?.pruneThumbnails()
        }
    }

    func cancel() {
        guard isOpen else { return }
        close()
    }

    func commit() {
        guard isOpen else { return }
        let item = model.selected
        close()
        guard let item else { return }
        if let id = item.primaryWindowID { mru.bump(id) }
        // Leave the event-tap callback before doing Accessibility IPC.
        let axCache = source.axCache
        DispatchQueue.main.async {
            WindowActivator.activate(item, axCache: axCache)
        }
    }

    // MARK: - Selection

    private func move(_ delta: Int) {
        let n = model.items.count
        guard n > 0 else { return }
        interacted = true
        setSelection(((model.selectedIndex + delta) % n + n) % n)
    }

    private func setSelection(_ index: Int) {
        guard model.items.indices.contains(index) else { return }
        // Cards animate under a resting cursor; hover must not count until the mouse itself moves again.
        mouseAtShow = NSEvent.mouseLocation
        withAnimation(.spring(duration: 0.32, bounce: 0.18)) {
            model.selectedIndex = index
        }
    }

    private func hover(_ index: Int) {
        guard isOpen, model.style.selectsOnHover, index != model.selectedIndex else { return }
        // Only react when the mouse really moved since the panel appeared or the selection last changed.
        let m = NSEvent.mouseLocation
        guard hypot(m.x - mouseAtShow.x, m.y - mouseAtShow.y) > 6 else { return }
        interacted = true
        setSelection(index)
    }

    /// A click highlights the window; the switcher stays open while the modifier is held.
    /// Clicking the already highlighted window switches to it (also the way to confirm without a modifier).
    private func select(_ index: Int) {
        guard isOpen, model.items.indices.contains(index) else { return }
        if index == model.selectedIndex {
            commit()
        } else {
            interacted = true
            setSelection(index)
        }
    }

    // MARK: - Window actions

    private func closeSelectedWindow() {
        guard let item = model.selected, let w = item.primaryWindow else { return }
        WindowActivator.close(w, axCache: source.axCache)
        refreshAfterAction()
    }

    private func minimizeSelectedWindow() {
        guard let item = model.selected, let w = item.primaryWindow else { return }
        WindowActivator.minimize(w, axCache: source.axCache)
        refreshAfterAction()
    }

    private func quitSelectedApp() {
        guard let item = model.selected else { return }
        NSRunningApplication(processIdentifier: item.pid)?.terminate()
        refreshAfterAction()
    }

    private func refreshAfterAction() {
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .milliseconds(250))
            await self.source.refresh()
            guard self.isOpen, !Task.isCancelled else { return }
            self.rebuildItems(preservingSelection: true)
            if self.model.items.isEmpty { self.close() }
            await self.captureThumbnails()
        }
    }

    // MARK: - Items

    private func noteFrontmostWindow() {
        guard let front = NSWorkspace.shared.frontmostApplication,
              front.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        let pid = front.processIdentifier
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            guard let id = AXWindowCache.focusedWindowID(pid: pid) else { return }
            DispatchQueue.main.async {
                guard let self else { return }
                self.mru.bump(id)
                if self.isOpen && !self.interacted { self.rebuildItems(preservingSelection: true) }
            }
        }
    }

    private func rebuildItems(preservingSelection: Bool) {
        let newItems = buildItems()
        guard newItems != model.items else { return }
        let selectedID = model.selected?.id
        model.items = newItems
        model.columns = GridLayout.columns(for: newItems.count)
        if preservingSelection && interacted, let selectedID, let idx = newItems.firstIndex(where: { $0.id == selectedID }) {
            model.selectedIndex = idx
        } else if preservingSelection && !interacted {
            model.selectedIndex = newItems.count > 1 ? min(model.selectedIndex, newItems.count - 1) : 0
        } else {
            model.selectedIndex = min(model.selectedIndex, max(0, newItems.count - 1))
        }
    }

    private func buildItems() -> [SwitcherItem] {
        var windows = mru.sorted(source.windows)
        if settings.windowDisplayFilter == .switcherDisplay, let screen = currentScreen, NSScreen.screens.count > 1 {
            windows.removeAll { Self.screen(containing: $0.frame) != screen }
        }
        if !settings.includeMinimized { windows.removeAll(where: \.isMinimized) }
        if !settings.includeOtherSpaces { windows.removeAll { !$0.isOnScreen && !$0.isMinimized } }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let front = NSWorkspace.shared.frontmostApplication

        switch model.scope {
        case .apps:
            var byPID: [pid_t: [WindowInfo]] = [:]
            var order: [pid_t] = []
            for w in windows {
                if byPID[w.pid] == nil { order.append(w.pid) }
                byPID[w.pid, default: []].append(w)
            }
            var items = order.map {
                SwitcherItem.app(pid: $0, app: NSRunningApplication(processIdentifier: $0), windows: byPID[$0] ?? [])
            }
            if settings.appsWithoutWindows {
                let rest = NSWorkspace.shared.runningApplications.filter {
                    $0.activationPolicy == .regular && $0.processIdentifier != ownPID && byPID[$0.processIdentifier] == nil
                }
                items += rest.map { SwitcherItem.app(pid: $0.processIdentifier, app: $0, windows: []) }
            }
            if let front, let idx = items.firstIndex(where: { $0.pid == front.processIdentifier }), idx != 0 {
                let item = items.remove(at: idx)
                items.insert(item, at: 0)
            }
            return items

        case .windows:
            return windows.map { SwitcherItem.window($0, app: NSRunningApplication(processIdentifier: $0.pid)) }

        case .appWindows:
            guard let front else { return [] }
            return windows.filter { $0.pid == front.processIdentifier }
                .map { SwitcherItem.window($0, app: front) }
        }
    }

    // MARK: - Thumbnails

    private func captureThumbnails() async {
        let windows = model.items.compactMap(\.primaryWindow)
        await thumbnails.captureAll(windows, source: source) { [weak self] id, image in
            self?.model.thumbnails[id] = image
        }
    }

    private func pruneThumbnails() {
        let live = Set(source.windows.map(\.id))
        model.thumbnails = model.thumbnails.filter { live.contains($0.key) }
    }
}
