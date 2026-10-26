import Foundation
import Observation
import ServiceManagement

enum SwitcherStyle: String, Codable, CaseIterable, Identifiable {
    case classic, grid, coverFlow, ring, filmstrip

    var id: String { rawValue }

    var title: String {
        switch self {
        case .classic: return "Classic"
        case .grid: return "Grid"
        case .coverFlow: return "Cover Flow"
        case .ring: return "Ring"
        case .filmstrip: return "Filmstrip"
        }
    }

    var subtitle: String {
        switch self {
        case .classic: return "Row of icons, like macOS"
        case .grid: return "Window previews in a grid"
        case .coverFlow: return "3D carousel of windows"
        case .ring: return "Windows on a spinning 3D ring"
        case .filmstrip: return "One line of window previews"
        }
    }

    /// Whether this style draws a full-screen blurred backdrop.
    var usesFullScreenBackdrop: Bool { self != .classic }

    /// Only the static layouts select on hover; in the moving ones (Cover Flow, Ring, Filmstrip)
    /// cards slide under the cursor, so there a click is needed.
    var selectsOnHover: Bool { self == .classic || self == .grid }
}

/// Which display the switcher appears on.
enum SwitcherDisplayRule: String, Codable, CaseIterable, Identifiable {
    case activeWindow, mouse, primary
    var id: String { rawValue }
    var title: String {
        switch self {
        case .activeWindow: return "Display of the active window"
        case .mouse: return "Display under the mouse"
        case .primary: return "Primary display"
        }
    }
}

/// Which windows the switcher lists.
enum WindowDisplayFilter: String, Codable, CaseIterable, Identifiable {
    case allDisplays, switcherDisplay
    var id: String { rawValue }
    var title: String {
        switch self {
        case .allDisplays: return "From all displays"
        case .switcherDisplay: return "Only from the switcher's display"
        }
    }
}

struct SettingsData: Codable, Equatable {
    var mainShortcut: Shortcut = .cmdTab
    var appWindowsShortcut: Shortcut? = .cmdGrave
    var style: SwitcherStyle = .classic
    var showAllWindows: Bool = true
    var includeMinimized: Bool = true
    var includeOtherSpaces: Bool = true
    var showDelay: Double = 0.1
    var dimBackground: Bool = true
    var appsWithoutWindows: Bool = true
    var hideMenuBarIcon: Bool = false
    var displayRule: SwitcherDisplayRule = .mouse
    var windowDisplayFilter: WindowDisplayFilter = .allDisplays

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mainShortcut = try c.decodeIfPresent(Shortcut.self, forKey: .mainShortcut) ?? .cmdTab
        appWindowsShortcut = try c.decodeIfPresent(Shortcut?.self, forKey: .appWindowsShortcut) ?? nil
        style = try c.decodeIfPresent(SwitcherStyle.self, forKey: .style) ?? .classic
        showAllWindows = try c.decodeIfPresent(Bool.self, forKey: .showAllWindows) ?? true
        includeMinimized = try c.decodeIfPresent(Bool.self, forKey: .includeMinimized) ?? true
        includeOtherSpaces = try c.decodeIfPresent(Bool.self, forKey: .includeOtherSpaces) ?? true
        showDelay = try c.decodeIfPresent(Double.self, forKey: .showDelay) ?? 0.1
        dimBackground = try c.decodeIfPresent(Bool.self, forKey: .dimBackground) ?? true
        appsWithoutWindows = try c.decodeIfPresent(Bool.self, forKey: .appsWithoutWindows) ?? true
        hideMenuBarIcon = try c.decodeIfPresent(Bool.self, forKey: .hideMenuBarIcon) ?? false
        displayRule = try c.decodeIfPresent(SwitcherDisplayRule.self, forKey: .displayRule) ?? .mouse
        windowDisplayFilter = try c.decodeIfPresent(WindowDisplayFilter.self, forKey: .windowDisplayFilter) ?? .allDisplays
    }
}

@MainActor
@Observable
final class AppSettings {
    static let shared = AppSettings()

    private static let key = "com.valeryburtsev.CmdTab.settings"

    private(set) var data: SettingsData {
        didSet { save() }
    }

    private init() {
        if let raw = UserDefaults.standard.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode(SettingsData.self, from: raw) {
            data = decoded
        } else {
            data = SettingsData()
        }
    }

    private func save() {
        if let raw = try? JSONEncoder().encode(data) {
            UserDefaults.standard.set(raw, forKey: Self.key)
        }
    }

    var mainShortcut: Shortcut {
        get { data.mainShortcut }
        set { data.mainShortcut = newValue }
    }
    var appWindowsShortcut: Shortcut? {
        get { data.appWindowsShortcut }
        set { data.appWindowsShortcut = newValue }
    }
    var style: SwitcherStyle {
        get { data.style }
        set { data.style = newValue }
    }
    var showAllWindows: Bool {
        get { data.showAllWindows }
        set { data.showAllWindows = newValue }
    }
    var includeMinimized: Bool {
        get { data.includeMinimized }
        set { data.includeMinimized = newValue }
    }
    var includeOtherSpaces: Bool {
        get { data.includeOtherSpaces }
        set { data.includeOtherSpaces = newValue }
    }
    var showDelay: Double {
        get { data.showDelay }
        set { data.showDelay = newValue }
    }
    var dimBackground: Bool {
        get { data.dimBackground }
        set { data.dimBackground = newValue }
    }
    var appsWithoutWindows: Bool {
        get { data.appsWithoutWindows }
        set { data.appsWithoutWindows = newValue }
    }
    var hideMenuBarIcon: Bool {
        get { data.hideMenuBarIcon }
        set { data.hideMenuBarIcon = newValue }
    }
    var displayRule: SwitcherDisplayRule {
        get { data.displayRule }
        set { data.displayRule = newValue }
    }
    var windowDisplayFilter: WindowDisplayFilter {
        get { data.windowDisplayFilter }
        set { data.windowDisplayFilter = newValue }
    }

    // MARK: Launch at login (not persisted by us; the system owns this state)

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                NSLog("CmdTab: launch at login change failed: \(error)")
            }
        }
    }
}
