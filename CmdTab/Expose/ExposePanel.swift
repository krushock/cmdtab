import AppKit
import SwiftUI

/// One full-screen, non-activating panel per display for Exposé.
@MainActor
final class ExposePanel: NSPanel {
    private var generation = 0

    init(model: ExposeModel, screenIndex: Int, actions: ExposeActions) {
        let hosting = NSHostingView(rootView: ExposeScreenView(model: model, screenIndex: screenIndex, actions: actions))
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
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().alphaValue = 1
        }
    }

    func hide() {
        guard isVisible else { return }
        generation += 1
        let gen = generation
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.16
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
