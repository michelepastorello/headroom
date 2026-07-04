import SwiftUI

/// Compact always-on-top readout of every usage window, one row per window.
struct HUDView: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var preferences: Preferences

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "gauge.with.needle")
                    .font(.system(size: 9, weight: .bold))
                Text("HEADROOM")
                    .font(.system(size: 9, weight: .bold))
                    .kerning(0.8)
                Spacer()
                Button {
                    preferences.hudVisible = false
                    store.menuBarPreferenceChanged()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                }
                .buttonStyle(.borderless)
                .help("Hide HUD")
            }
            .foregroundStyle(.secondary)

            ForEach(rows, id: \.window.id) { row in
                HUDRow(
                    provider: row.provider,
                    window: row.window,
                    severity: store.severity(for: row.window)
                )
            }

            if let next = nextReset {
                Text("next reset: \(next.window.shortLabel(providerShort: next.provider.shortName)) in \(Formatters.countdown(to: next.window.resetsAt ?? Date()))")
                    .font(.system(size: 9))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
                    .padding(.top, 1)
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
        .frame(width: 304)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 13))
        .overlay(
            RoundedRectangle(cornerRadius: 13)
                .strokeBorder(.separator.opacity(0.5), lineWidth: 1)
        )
        .padding(6)
    }

    private var rows: [(provider: ProviderID, window: UsageWindow)] {
        var result: [(ProviderID, UsageWindow)] = []
        for provider in ProviderID.allCases {
            guard let snapshot = store.states[provider]?.snapshot else { continue }
            for window in snapshot.windows {
                result.append((provider, window))
            }
        }
        return result
    }

    private var nextReset: (provider: ProviderID, window: UsageWindow)? {
        var best: (ProviderID, UsageWindow)?
        for provider in ProviderID.allCases {
            guard let snapshot = store.states[provider]?.snapshot else { continue }
            for window in snapshot.windows {
                guard let reset = window.resetsAt, reset > Date() else { continue }
                if best == nil || reset < best!.1.resetsAt! {
                    best = (provider, window)
                }
            }
        }
        return best
    }
}

private struct HUDRow: View {
    let provider: ProviderID
    let window: UsageWindow
    let severity: UsageSeverity

    private var tint: Color {
        severity == .ok ? provider.identityTint : Theme.tint(for: severity)
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(provider.glyph)
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(tint)
                .frame(width: 14)
            Text(window.shortLabel(providerShort: provider.shortName))
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .frame(width: 66, alignment: .leading)
                .lineLimit(1)
            GaugeBar(usedPercent: window.usedPercent, severity: severity, tint: provider.identityTint)
            Text("\(Int(window.leftPercent.rounded()))%")
                .font(.system(size: 11.5, weight: .bold))
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(severity == .ok ? Color.primary : tint)
                .frame(width: 40, alignment: .trailing)
        }
    }
}
