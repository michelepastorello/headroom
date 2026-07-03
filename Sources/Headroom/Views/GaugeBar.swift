import SwiftUI

/// 5 pt fuel-gauge track. Fill = percent used, in the provider's identity
/// color while healthy, orange/red past the thresholds.
/// Hairline ticks mark the warn and critical thresholds.
struct GaugeBar: View {
    let usedPercent: Double
    let severity: UsageSeverity
    let tint: Color
    var warnAt: Double = 75
    var criticalAt: Double = 90

    private var fillColor: Color {
        severity == .ok ? tint : Theme.tint(for: severity)
    }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.quaternary.opacity(0.6))

                Capsule()
                    .fill(fillColor)
                    .frame(width: max(usedPercent > 0 ? 5 : 0, width * usedPercent / 100))

                tick(at: warnAt, in: width)
                tick(at: criticalAt, in: width)
            }
        }
        .frame(height: 5)
        .accessibilityElement()
        .accessibilityLabel("\(Int(usedPercent)) percent used")
    }

    @ViewBuilder
    private func tick(at percent: Double, in width: CGFloat) -> some View {
        if usedPercent < percent {
            Rectangle()
                .fill(.tertiary)
                .frame(width: 1, height: 5)
                .offset(x: width * percent / 100)
        }
    }
}
