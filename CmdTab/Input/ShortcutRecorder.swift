import AppKit
import SwiftUI
import Carbon.HIToolbox

/// Shared hook so the event tap can route key presses to the recorder (and swallow them,
/// otherwise the system would act on ⌘⇥ before the recorder sees it).
@MainActor
final class ShortcutRecording {
    static let shared = ShortcutRecording()
    var handler: ((UInt16, CGEventFlags) -> Void)?
    var isRecording: Bool { handler != nil }
}

struct ShortcutRecorder: NSViewRepresentable {
    @Binding var shortcut: Shortcut?
    var allowClear: Bool = true

    func makeNSView(context: Context) -> RecorderView {
        let view = RecorderView()
        view.onChange = { shortcut = $0 }
        view.allowClear = allowClear
        view.shortcut = shortcut
        return view
    }

    func updateNSView(_ nsView: RecorderView, context: Context) {
        nsView.shortcut = shortcut
        nsView.allowClear = allowClear
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: RecorderView, context: Context) -> CGSize? {
        CGSize(width: 150, height: 26)
    }
}

final class RecorderView: NSView {
    var onChange: ((Shortcut?) -> Void)?
    var allowClear = true
    var shortcut: Shortcut? { didSet { needsDisplay = true } }
    private var isRecording = false { didSet { needsDisplay = true } }
    private var clearButtonRect: CGRect = .zero

    override var acceptsFirstResponder: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: 150, height: 26) }
    override var focusRingMaskBounds: NSRect { bounds }
    override func drawFocusRingMask() {
        NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()
    }

    // MARK: Accessibility (VoiceOver)

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .button }
    override func accessibilityLabel() -> String? { "Keyboard shortcut" }
    override func accessibilityValue() -> Any? {
        if isRecording { return "Recording, press the new shortcut" }
        return shortcut?.displayString ?? "Not set"
    }
    override func accessibilityHelp() -> String? {
        "Press Space or Return to record a new shortcut" + (allowClear ? ", Delete to clear it" : "")
    }
    override func accessibilityPerformPress() -> Bool {
        if isRecording { stopRecording() } else { startRecording() }
        return true
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
        (isRecording ? NSColor.controlAccentColor.withAlphaComponent(0.18) : NSColor.controlBackgroundColor).setFill()
        path.fill()
        (isRecording ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
        path.lineWidth = isRecording ? 1.5 : 1
        path.stroke()

        let text: String
        let color: NSColor
        if isRecording {
            text = "Type shortcut…"
            color = .secondaryLabelColor
        } else if let shortcut {
            text = shortcut.displayString
            color = .labelColor
        } else {
            text = "Click to record"
            color = .secondaryLabelColor
        }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: color,
        ]
        let size = (text as NSString).size(withAttributes: attrs)
        let origin = CGPoint(x: (bounds.width - size.width) / 2 - (showsClear ? 8 : 0), y: (bounds.height - size.height) / 2)
        (text as NSString).draw(at: origin, withAttributes: attrs)

        if showsClear {
            let r = CGRect(x: bounds.width - 20, y: (bounds.height - 14) / 2, width: 14, height: 14)
            clearButtonRect = r
            if let img = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Clear") {
                let tinted = img.withSymbolConfiguration(.init(pointSize: 12, weight: .regular))
                NSColor.tertiaryLabelColor.set()
                tinted?.draw(in: r, from: .zero, operation: .sourceOver, fraction: 0.9)
            }
        } else {
            clearButtonRect = .zero
        }
    }

    private var showsClear: Bool { allowClear && shortcut != nil && !isRecording }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if showsClear, clearButtonRect.contains(p) {
            shortcut = nil
            onChange?(nil)
            return
        }
        if isRecording {
            stopRecording()
        } else {
            window?.makeFirstResponder(self)
            startRecording()
        }
    }

    private func startRecording() {
        isRecording = true
        ShortcutRecording.shared.handler = { [weak self] keyCode, flags in
            self?.record(keyCode: keyCode, flags: flags)
        }
    }

    private func stopRecording() {
        isRecording = false
        ShortcutRecording.shared.handler = nil
    }

    override func resignFirstResponder() -> Bool {
        stopRecording()
        return super.resignFirstResponder()
    }

    override func becomeFirstResponder() -> Bool {
        needsDisplay = true
        return super.becomeFirstResponder()
    }

    override func keyDown(with event: NSEvent) {
        if isRecording {
            // Reached only when the event tap isn't running (no Accessibility permission yet).
            record(keyCode: event.keyCode, flags: Shortcut.cgFlags(from: event.modifierFlags))
            return
        }
        // Keyboard operation while focused: Space/Return start recording, Delete clears.
        let plain = event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty
        switch Int(event.keyCode) {
        case kVK_Space, kVK_Return, kVK_ANSI_KeypadEnter:
            startRecording()
        case kVK_Delete, kVK_ForwardDelete where allowClear && plain:
            shortcut = nil
            onChange?(nil)
        default:
            super.keyDown(with: event)
        }
    }

    private func record(keyCode: UInt16, flags: CGEventFlags) {
        guard isRecording else { return }
        if Int(keyCode) == kVK_Escape && flags.intersection(Shortcut.relevantMask).isEmpty {
            stopRecording()
            return
        }
        // Ignore bare modifier key codes.
        let modifierKeyCodes: Set<Int> = [kVK_Command, kVK_RightCommand, kVK_Option, kVK_RightOption,
                                          kVK_Control, kVK_RightControl, kVK_Shift, kVK_RightShift, kVK_CapsLock, kVK_Function]
        if modifierKeyCodes.contains(Int(keyCode)) { return }
        let new = Shortcut(keyCode: keyCode, flags: flags)
        shortcut = new
        onChange?(new)
        stopRecording()
    }
}
