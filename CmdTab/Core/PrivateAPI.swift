import ApplicationServices
import Darwin

/// Private and deprecated system calls, looked up at runtime so a future macOS that drops one of them
/// degrades CmdTab (window focusing becomes best-effort) instead of crashing it at launch.
enum PrivateAPI {
    typealias SetFrontProcess = @convention(c) (UnsafeMutablePointer<ProcessSerialNumber>, CGWindowID, UInt32) -> CGError
    typealias PostEventRecord = @convention(c) (UnsafeMutablePointer<ProcessSerialNumber>, UnsafeMutablePointer<UInt8>) -> CGError
    typealias GetProcessForPID = @convention(c) (pid_t, UnsafeMutablePointer<ProcessSerialNumber>) -> OSStatus
    typealias AXGetWindow = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError

    /// SkyLight: makes a process the front process with a given window as key. Public `activate()` is
    /// cooperative since macOS 14 and may be refused for a background app, so this is the reliable path.
    static let setFrontProcess: SetFrontProcess? = load("_SLPSSetFrontProcessWithOptions", from: skyLight)
    /// SkyLight: posts "window became key" records so the app focuses one specific window.
    static let postEventRecord: PostEventRecord? = load("SLPSPostEventRecordTo", from: skyLight)
    /// Carbon, deprecated: pid → process serial number, needed by the SkyLight calls.
    static let getProcessForPID: GetProcessForPID? = load("GetProcessForPID", from: hiServices)
    /// Accessibility: AX window element → window number. No public equivalent exists.
    static let axGetWindow: AXGetWindow? = load("_AXUIElementGetWindow", from: hiServices)

    static var canFocusWindows: Bool { setFrontProcess != nil && getProcessForPID != nil }

    private static let skyLight: UnsafeMutableRawPointer? =
        dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)
    private static let hiServices: UnsafeMutableRawPointer? =
        dlopen("/System/Library/Frameworks/ApplicationServices.framework/Frameworks/HIServices.framework/HIServices", RTLD_LAZY)

    private static func load<T>(_ name: String, from handle: UnsafeMutableRawPointer?) -> T? {
        // Fall back to the global namespace if the explicit framework could not be opened.
        let searchHandle = handle ?? UnsafeMutableRawPointer(bitPattern: -2)  // RTLD_DEFAULT
        guard let symbol = dlsym(searchHandle, name) else {
            NSLog("CmdTab: symbol \(name) not found; falling back to public APIs")
            return nil
        }
        return unsafeBitCast(symbol, to: T.self)
    }
}
