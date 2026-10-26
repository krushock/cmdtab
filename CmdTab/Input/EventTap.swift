import CoreGraphics
import Foundation

/// A session-level CGEvent tap for keyboard events. The handler returns `true` to swallow an event.
final class EventTap {
    typealias Handler = (CGEventType, CGEvent) -> Bool

    private var port: CFMachPort?
    private var source: CFRunLoopSource?
    private let handler: Handler

    init(handler: @escaping Handler) {
        self.handler = handler
    }

    var isRunning: Bool { port != nil }

    @discardableResult
    func start() -> Bool {
        if port != nil { return true }
        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue)
        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: eventTapCallback,
            userInfo: userInfo
        ) else {
            return false
        }
        self.port = port
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        self.source = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        return true
    }

    func stop() {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let port { CGEvent.tapEnable(tap: port, enable: false) }
        source = nil
        port = nil
    }

    fileprivate func reenable() {
        if let port { CGEvent.tapEnable(tap: port, enable: true) }
    }

    fileprivate func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        handler(type, event)
    }
}

private func eventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let tap = Unmanaged<EventTap>.fromOpaque(userInfo).takeUnretainedValue()
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        tap.reenable()
        return Unmanaged.passUnretained(event)
    }
    return tap.handle(type, event) ? nil : Unmanaged.passUnretained(event)
}
