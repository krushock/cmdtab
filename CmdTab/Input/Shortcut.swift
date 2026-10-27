import AppKit
import Carbon.HIToolbox

/// A keyboard shortcut: a key code plus the modifier flags that must be held.
struct Shortcut: Codable, Equatable, Hashable {
    var keyCode: UInt16
    var modifierFlags: UInt64

    static let relevantMask: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift]
    /// Modifiers that can be "held" to keep the switcher open.
    static let holdMask: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl]

    init(keyCode: UInt16, flags: CGEventFlags) {
        self.keyCode = keyCode
        self.modifierFlags = flags.intersection(Self.relevantMask).rawValue
    }

    init?(event: NSEvent) {
        guard event.type == .keyDown else { return nil }
        self.init(keyCode: event.keyCode, flags: Shortcut.cgFlags(from: event.modifierFlags))
    }

    var flags: CGEventFlags { CGEventFlags(rawValue: modifierFlags) }
    var holdFlags: CGEventFlags { flags.intersection(Self.holdMask) }

    /// Hold-style shortcuts (⌘⇥ etc.) keep the switcher open while the modifier is down.
    /// Shortcuts without ⌘/⌥/⌃ (e.g. F18) toggle the switcher and need ↩ to confirm.
    var isHoldStyle: Bool { !holdFlags.isEmpty }

    static let cmdTab = Shortcut(keyCode: UInt16(kVK_Tab), flags: .maskCommand)
    static let cmdGrave = Shortcut(keyCode: UInt16(kVK_ANSI_Grave), flags: .maskCommand)
    /// The Mission Control key (F3 on Apple keyboards) arrives as key code 160.
    static let missionControl = Shortcut(keyCode: 160, flags: [])

    func matches(keyCode: UInt16, flags: CGEventFlags) -> Bool {
        keyCode == self.keyCode && flags.intersection(Self.relevantMask) == self.flags
    }

    /// Same key with an extra ⇧ cycles backwards.
    func matchesReverse(keyCode: UInt16, flags: CGEventFlags) -> Bool {
        guard !self.flags.contains(.maskShift) else { return false }
        return keyCode == self.keyCode && flags.intersection(Self.relevantMask) == self.flags.union(.maskShift)
    }

    var displayString: String {
        var s = ""
        if flags.contains(.maskControl) { s += "⌃" }
        if flags.contains(.maskAlternate) { s += "⌥" }
        if flags.contains(.maskShift) { s += "⇧" }
        if flags.contains(.maskCommand) { s += "⌘" }
        return s + KeyNames.name(for: keyCode)
    }

    static func cgFlags(from flags: NSEvent.ModifierFlags) -> CGEventFlags {
        var out: CGEventFlags = []
        if flags.contains(.command) { out.insert(.maskCommand) }
        if flags.contains(.option) { out.insert(.maskAlternate) }
        if flags.contains(.control) { out.insert(.maskControl) }
        if flags.contains(.shift) { out.insert(.maskShift) }
        return out
    }
}

enum KeyNames {
    private static let special: [Int: String] = [
        kVK_Tab: "⇥", kVK_Space: "Space", kVK_Return: "↩", kVK_Escape: "⎋",
        kVK_Delete: "⌫", kVK_ForwardDelete: "⌦", kVK_LeftArrow: "←", kVK_RightArrow: "→",
        kVK_UpArrow: "↑", kVK_DownArrow: "↓", kVK_Home: "↖", kVK_End: "↘",
        kVK_PageUp: "⇞", kVK_PageDown: "⇟", kVK_ANSI_Grave: "`", kVK_Help: "?⃝",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15", kVK_F16: "F16", kVK_F17: "F17",
        kVK_F18: "F18", kVK_F19: "F19", kVK_F20: "F20",
        kVK_ANSI_KeypadEnter: "⌤", kVK_ANSI_KeypadClear: "⌧",
        160: "Mission Control (F3)", 131: "Launchpad (F4)",
    ]

    static func name(for keyCode: UInt16) -> String {
        if let s = special[Int(keyCode)] { return s }
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let layoutPtr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return "Key \(keyCode)"
        }
        let data = Unmanaged<CFData>.fromOpaque(layoutPtr).takeUnretainedValue() as Data
        var deadKeyState: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length = 0
        let status = data.withUnsafeBytes { raw -> OSStatus in
            guard let base = raw.baseAddress else { return -1 }
            let layout = base.assumingMemoryBound(to: UCKeyboardLayout.self)
            return UCKeyTranslate(layout, keyCode, UInt16(kUCKeyActionDisplay), 0,
                                  UInt32(LMGetKbdType()), UInt32(kUCKeyTranslateNoDeadKeysMask),
                                  &deadKeyState, chars.count, &length, &chars)
        }
        guard status == noErr, length > 0 else { return "Key \(keyCode)" }
        return String(utf16CodeUnits: chars, count: length).uppercased()
    }
}
