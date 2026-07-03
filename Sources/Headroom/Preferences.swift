import Foundation
import SwiftUI

enum MenuBarStyle: String, CaseIterable, Identifiable {
    case iconOnly
    case percentLeft
    case percentUsed

    var id: String { rawValue }

    var label: String {
        switch self {
        case .iconOnly: "Icon only"
        case .percentLeft: "Icon + % left"
        case .percentUsed: "Icon + % used"
        }
    }
}

/// All user preferences, backed by UserDefaults via @AppStorage-compatible keys.
@MainActor
final class Preferences: ObservableObject {
    static let shared = Preferences()

    @AppStorage("menuBarStyle") var menuBarStyleRaw: String = MenuBarStyle.percentLeft.rawValue
    /// "auto" (tightest across providers) or a ProviderID rawValue.
    @AppStorage("menuBarSource") var menuBarSourceRaw: String = "auto"
    /// "single" (one gauge item) or "perProvider" (one item per provider).
    @AppStorage("menuBarLayout") var menuBarLayoutRaw: String = "single"
    @AppStorage("hotkeyEnabled") var hotkeyEnabled: Bool = true
    @AppStorage("hudVisible") var hudVisible: Bool = false
    /// One of HUDPosition's raw values; applied when chosen, dragging wins after.
    @AppStorage("hudPosition") var hudPositionRaw: String = "topRight"
    @AppStorage("refreshMinutes") var refreshMinutes: Int = 5
    @AppStorage("alertsEnabled") var alertsEnabled: Bool = true
    @AppStorage("warnThreshold") var warnThreshold: Double = 75
    @AppStorage("criticalThreshold") var criticalThreshold: Double = 90
    @AppStorage("hasCompletedWelcome") var hasCompletedWelcome: Bool = false

    var menuBarStyle: MenuBarStyle {
        get { MenuBarStyle(rawValue: menuBarStyleRaw) ?? .percentLeft }
        set { menuBarStyleRaw = newValue.rawValue }
    }
}
