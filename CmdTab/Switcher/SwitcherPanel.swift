import AppKit
import SwiftUI

/// Borderless, non-activating, full-screen panel that hosts the SwiftUI switcher.
/// It can become key so hover and clicks work, but the previously active app stays active.
@MainActor
final class SwitcherPanel: NSPanel {
    private let hosting: NSHostingView<SwitcherRootView>
    private var generation = 0

    init(model: SwitcherModel, actions: SwitcherActions) {
        hosting = NSHostingView(rootView: SwitcherRootView(model: model, actions: actions))
        hosting.sizingOptions = []
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .popUpMenu
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        animationBehavior = .none
        isMovable = false
        isExcludedFromWindowsMenu = true
        contentView = hosting
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func show(on screen: NSScreen) {
        generation += 1
        setFrame(screen.frame, display: true)
        if !isVisible { alphaValue = 0 }
        makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.16
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().alphaValue = 1
        }
    }

    func hide() {
        guard isVisible else { return }
        generation += 1
        let gen = generation
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.14
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.generation == gen else { return }
                self.orderOut(nil)
            }
        })
    }
}
