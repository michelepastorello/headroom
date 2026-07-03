import SwiftUI

/// Case order is display order: Claude Code first.
enum ProviderID: String, CaseIterable, Sendable, Codable {
    case claude
    case codex

    var displayName: String {
        switch self {
        case .codex: "Codex"
        case .claude: "Claude Code"
        }
    }

    var shortName: String {
        switch self {
        case .codex: "Codex"
        case .claude: "Claude"
        }
    }

    /// Text glyph for surfaces where SF Symbols can't carry color
    /// (status-item titles, HUD rows).
    var glyph: String {
        switch self {
        case .codex: "{}"
        case .claude: "✳"
        }
    }

    var symbolName: String {
        switch self {
        case .codex: "curlybraces"
        case .claude: "asterisk"
        }
    }

    /// Identity color, also used as the gauge fill while usage is healthy:
    /// Codex sky blue, Claude coral orange.
    var identityTint: Color {
        switch self {
        case .codex: Color(red: 0.33, green: 0.62, blue: 0.86)
        case .claude: Color(red: 0.85, green: 0.44, blue: 0.30)
        }
    }
}

struct UsageWindow: Identifiable, Sendable, Codable {
    let id: String
    let label: String
    /// 0...100, percent of the window already consumed.
    let usedPercent: Double
    let resetsAt: Date?

    var leftPercent: Double { max(0, 100 - usedPercent) }

    /// Compact name for tight surfaces (summary strip, HUD):
    /// "Week (Fable)" → "Fable wk", "Session (5h)" → "Claude 5h",
    /// "Spark · Week" → "Spark wk".
    func shortLabel(providerShort: String) -> String {
        var base = label
        var owner = providerShort
        if let dot = base.range(of: " · ") {
            owner = String(base[..<dot.lowerBound])
            base = String(base[dot.upperBound...])
        }
        if base.hasPrefix("Session") { return "\(owner) 5h" }
        if base == "Week" || base == "Week (all models)" { return "\(owner) wk" }
        if base.hasPrefix("Week ("), base.hasSuffix(")") {
            return "\(base.dropFirst(6).dropLast()) wk"
        }
        return "\(owner) \(base)"
    }
}

struct ProviderSnapshot: Sendable, Codable {
    let provider: ProviderID
    let planName: String?
    let windows: [UsageWindow]
    let fetchedAt: Date
}

struct ProviderFailure: Error, Sendable {
    /// What went wrong, one line.
    let message: String
    /// The exact command or action that fixes it.
    let fix: String
}

enum ProviderState: Sendable {
    case loading
    case loaded(ProviderSnapshot)
    /// Last good reading kept on screen while refreshes fail.
    case stale(ProviderSnapshot, ProviderFailure)
    case failed(ProviderFailure)

    var snapshot: ProviderSnapshot? {
        switch self {
        case .loaded(let snapshot): snapshot
        case .stale(let snapshot, _): snapshot
        case .loading, .failed: nil
        }
    }
}

/// The single most binding constraint across every provider window.
struct TightestWindow: Sendable {
    let provider: ProviderID
    let window: UsageWindow
}

enum UsageSeverity: Sendable {
    case ok
    case warning
    case critical

    static func of(usedPercent: Double, warnAt: Double, criticalAt: Double) -> UsageSeverity {
        if usedPercent >= criticalAt { return .critical }
        if usedPercent >= warnAt { return .warning }
        return .ok
    }
}
