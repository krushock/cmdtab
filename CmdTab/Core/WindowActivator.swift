import AppKit
import ApplicationServices

// Private SkyLight calls, the same ones AltTab relies on. Since macOS 14 the public
// `NSRunningApplication.activate` is cooperative and is refused for a background app, so
// these are what actually bring another app's window to the front.
@_silgen_name("_SLPSSetFrontProcessWithOptions")
func _SLPSSetFrontProcessWithOptions(_ psn: UnsafeMutablePointer<ProcessSerialNumber>, _ wid: CGWindowID, _ mode: UInt32) -> CGError

@_silgen_name("SLPSPostEventRecordTo")
func SLPSPostEventRecordTo(_ psn: UnsafeMutablePointer<ProcessSerialNumber>, _ bytes: UnsafeMutablePointer<UInt8>) -> CGError

// Deprecated Carbon call that Swift hides; the symbol is still exported by HIServices.
@_silgen_name("GetProcessForPID")
func _GetProcessForPID(_ pid: pid_t, _ psn: UnsafeMutablePointer<ProcessSerialNumber>) -> OSStatus

private let kSLPSUserGenerated: UInt32 = 0x200

enum WindowActivator {
    @MainActor
    static func activate(_ item: SwitcherItem, axCache: AXWindowCache) {
        guard let app = NSRunningApplication(processIdentifier: item.pid) else { return }
        if app.isHidden { app.unhide() }

        var window: WindowInfo? = item.windows.first
        if item.isApp && !item.isMinimized {
            // App mode behaves like the system switcher: bring the app forward with its current window.
            window = item.windows.first
        }

        if let window {
            let element = element(for: window, axCache: axCache)
            if let element { unminimize(element) }
            focus(pid: item.pid, windowID: window.id)
            if let element { AXUIElementPerformAction(element, kAXRaiseAction as CFString) }
        } else {
            focus(pid: item.pid, windowID: 0)
        }
        // Public call as a complement; it is a no-op when the private path already worked.
        app.activate()
    }

    /// Makes `pid` the front process and `windowID` its key window.
    private static func focus(pid: pid_t, windowID: CGWindowID) {
        var psn = ProcessSerialNumber()
        guard _GetProcessForPID(pid, &psn) == noErr else { return }
        _ = _SLPSSetFrontProcessWithOptions(&psn, windowID, kSLPSUserGenerated)
        guard windowID != 0 else { return }
        // Post synthetic "window became key" records so the app focuses that specific window.
        for eventType: UInt8 in [0x01, 0x02] {
            var bytes = [UInt8](repeating: 0, count: 0xf8)
            bytes[0x04] = 0xf8
            bytes[0x08] = eventType
            bytes[0x3a] = 0x10
            var wid = windowID
            withUnsafeBytes(of: &wid) { raw in
                for i in 0..<4 { bytes[0x3c + i] = raw[i] }
            }
            for i in 0x20..<0x30 { bytes[i] = 0xff }
            bytes.withUnsafeMutableBufferPointer { buf in
                _ = SLPSPostEventRecordTo(&psn, buf.baseAddress!)
            }
        }
    }

    static func element(for w: WindowInfo, axCache: AXWindowCache) -> AXUIElement? {
        if let e = axCache.entry(for: w.id, pid: w.pid)?.element { return e }
        return AXWindowCache.query(pid: w.pid)?[w.id]?.element
    }

    private static func unminimize(_ element: AXUIElement) {
        var minimized: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXMinimizedAttribute as CFString, &minimized) == .success,
           (minimized as? Bool) == true {
            AXUIElementSetAttributeValue(element, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        }
    }

    static func close(_ w: WindowInfo, axCache: AXWindowCache) {
        guard let element = element(for: w, axCache: axCache) else { return }
        var button: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXCloseButtonAttribute as CFString, &button) == .success, let button {
            AXUIElementPerformAction(button as! AXUIElement, kAXPressAction as CFString)
        }
    }

    static func minimize(_ w: WindowInfo, axCache: AXWindowCache) {
        guard let element = element(for: w, axCache: axCache) else { return }
        AXUIElementSetAttributeValue(element, kAXMinimizedAttribute as CFString, kCFBooleanTrue)
    }
}
