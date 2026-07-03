import SwiftUI

struct DashboardView: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var preferences: Preferences
    var openSettings: () -> Void = {}
    /// ImageRenderer can't rasterize ScrollView content or button controls;
    /// snapshot mode swaps them for static equivalents.
    var isSnapshot = false

    var body: some View {
        VStack(spacing: 0) {
            header
            HairlineDivider()
            // No summary strip and no ScrollView on purpose: every window is
            // already visible at a glance, so the popover grows to fit.
            providerStack
        }
        .frame(width: Theme.popoverWidth)
    }

    private var hudVisibleBinding: Binding<Bool> {
        Binding(
            get: { preferences.hudVisible },
            set: {
                preferences.hudVisible = $0
                store.menuBarPreferenceChanged()
            }
        )
    }

    private var providerStack: some View {
        VStack(spacing: 0) {
            ForEach(Array(ProviderID.allCases.enumerated()), id: \.element) { index, provider in
                if index > 0 {
                    HairlineDivider()
                        .padding(.horizontal, 12)
                }
                ProviderSection(
                    provider: provider,
                    state: store.states[provider] ?? .loading,
                    store: store,
                    preferences: preferences
                )
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "gauge.with.needle")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("Headroom")
                .font(.system(size: 13, weight: .semibold))

            Spacer()

            if let last = store.lastRefresh {
                Text(last, style: .relative)
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
            }

            if isSnapshot {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            } else {
                Button {
                    store.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .semibold))
                        .rotationEffect(.degrees(store.isRefreshing ? 360 : 0))
                        .animation(
                            store.isRefreshing
                                ? .linear(duration: 0.9).repeatForever(autoreverses: false)
                                : .default,
                            value: store.isRefreshing
                        )
                }
                .buttonStyle(.borderless)
                .help("Refresh now (⌘R)")
                .keyboardShortcut("r", modifiers: .command)

                Menu {
                    Toggle("Floating HUD", isOn: hudVisibleBinding)
                        .keyboardShortcut("j", modifiers: [.control, .option])
                    Menu("HUD position") {
                        ForEach(HUDPosition.allCases) { position in
                            Button(position.label) {
                                store.applyHUDPosition(position.rawValue)
                            }
                        }
                    }
                    Divider()
                    Button("Settings…") { openSettings() }
                        .keyboardShortcut(",", modifiers: .command)
                    Button("Quit Headroom") { NSApp.terminate(nil) }
                        .keyboardShortcut("q", modifiers: .command)
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.borderless)
                .menuIndicator(.hidden)
                .fixedSize()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

}

// MARK: - Provider section

struct ProviderSection: View {
    let provider: ProviderID
    let state: ProviderState
    let store: UsageStore
    @ObservedObject var preferences: Preferences

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader
            content
        }
        .padding(12)
    }

    private var sectionHeader: some View {
        HStack(spacing: 7) {
            Image(systemName: provider.symbolName)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(provider.identityTint)
                .frame(width: 18, height: 18)
                .background(provider.identityTint.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))

            Text(provider.displayName)
                .font(.system(size: 13, weight: .semibold))

            if let plan = state.snapshot?.planName, !plan.isEmpty {
                Text(plan)
                    .font(.system(size: 9, weight: .semibold))
                    .textCase(.uppercase)
                    .kerning(0.4)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(.quaternary.opacity(0.6), in: Capsule())
            }

            Spacer()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .loading:
            VStack(spacing: 12) {
                SkeletonRow()
                SkeletonRow()
            }
        case .failed(let failure):
            FailureRow(failure: failure)
        case .loaded(let snapshot):
            windowRows(snapshot)
        case .stale(let snapshot, let failure):
            VStack(alignment: .leading, spacing: 12) {
                StaleNotice(snapshot: snapshot, failure: failure)
                windowRows(snapshot)
            }
        }
    }

    private func windowRows(_ snapshot: ProviderSnapshot) -> some View {
        VStack(spacing: 12) {
            ForEach(snapshot.windows) { window in
                WindowRow(
                    window: window,
                    severity: store.severity(for: window),
                    tint: provider.identityTint,
                    warnAt: preferences.warnThreshold,
                    criticalAt: preferences.criticalThreshold
                )
            }
        }
    }
}

/// Values stay on screen; this quiet line says how old they are and why.
struct StaleNotice: View {
    let snapshot: ProviderSnapshot
    let failure: ProviderFailure

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 10))
            Text("Not updated · last reading \(Formatters.clock.string(from: snapshot.fetchedAt)) · \(failure.message)")
                .font(.system(size: 10.5))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .foregroundStyle(.secondary)
    }
}

// MARK: - Rows

struct WindowRow: View {
    let window: UsageWindow
    let severity: UsageSeverity
    let tint: Color
    let warnAt: Double
    let criticalAt: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(window.label)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(window.leftPercent.rounded()))%")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(severity == .ok ? Color.primary : Theme.tint(for: severity))
                Text("left")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            GaugeBar(
                usedPercent: window.usedPercent,
                severity: severity,
                tint: tint,
                warnAt: warnAt,
                criticalAt: criticalAt
            )

            if let reset = window.resetsAt {
                Text("resets in \(Formatters.countdown(to: reset)) · \(Formatters.clock.string(from: reset))")
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

struct FailureRow: View {
    let failure: ProviderFailure

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.warning)
                Text(failure.message)
                    .font(.system(size: 12, weight: .medium))
            }
            Text(failure.fix)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(.leading, 17)
        }
        .padding(.vertical, 2)
    }
}

struct SkeletonRow: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                RoundedRectangle(cornerRadius: 3)
                    .fill(.quaternary)
                    .frame(width: 90, height: 10)
                Spacer()
                RoundedRectangle(cornerRadius: 3)
                    .fill(.quaternary)
                    .frame(width: 42, height: 12)
            }
            Capsule()
                .fill(.quaternary.opacity(0.6))
                .frame(height: 5)
            RoundedRectangle(cornerRadius: 3)
                .fill(.quaternary.opacity(0.7))
                .frame(width: 130, height: 8)
        }
        .redacted(reason: .placeholder)
    }
}

struct HairlineDivider: View {
    var body: some View {
        Rectangle()
            .fill(.separator)
            .frame(height: 1)
            .opacity(0.6)
    }
}
