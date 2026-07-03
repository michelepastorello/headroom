import SwiftUI

enum Theme {
    /// Calm teal for healthy usage; system orange/red past the thresholds.
    static let ok = Color(red: 0.20, green: 0.55, blue: 0.53)
    static let warning = Color.orange
    static let critical = Color.red

    static func tint(for severity: UsageSeverity) -> Color {
        switch severity {
        case .ok: ok
        case .warning: warning
        case .critical: critical
        }
    }

    static let popoverWidth: CGFloat = 340
}
