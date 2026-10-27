import AppKit
import ApplicationServices

/// Moves and resizes other apps' windows through Accessibility. Rectangles are in the global
/// top-left coordinate space that Accessibility and ScreenCaptureKit share.
enum WindowArranger {
    /// Usable area of a screen (below the menu bar, above the Dock) in top-left coordinates.
    static func visibleArea(of screen: NSScreen) -> CGRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
        let vf = screen.visibleFrame
        return CGRect(x: vf.minX, y: primaryHeight - vf.maxY, width: vf.width, height: vf.height)
    }

    static func halves(of area: CGRect) -> (left: CGRect, right: CGRect) {
        let w = floor(area.width / 2)
        return (CGRect(x: area.minX, y: area.minY, width: w, height: area.height),
                CGRect(x: area.minX + w, y: area.minY, width: area.width - w, height: area.height))
    }

    /// A rectangle for `size` centred in `area`, shrunk to fit.
    static func centered(size: CGSize, in area: CGRect) -> CGRect {
        let w = min(size.width, area.width), h = min(size.height, area.height)
        return CGRect(x: area.midX - w / 2, y: area.midY - h / 2, width: w, height: h)
    }

    static func setFrame(_ window: WindowInfo, to rect: CGRect, axCache: AXWindowCache) {
        guard let element = WindowActivator.element(for: window, axCache: axCache) else { return }
        var minimized: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXMinimizedAttribute as CFString, &minimized) == .success,
           (minimized as? Bool) == true {
            AXUIElementSetAttributeValue(element, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        }
        var origin = rect.origin
        var size = rect.size
        guard let positionValue = AXValueCreate(.cgPoint, &origin),
              let sizeValue = AXValueCreate(.cgSize, &size) else { return }
        // Size, position, size: apps with minimum sizes or edge constraints settle correctly this way.
        AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, sizeValue)
        AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, positionValue)
        AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, sizeValue)
    }
}
