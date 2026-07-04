import SwiftUI
import ServiceManagement

/// Single-page grouped settings, sized to fit without scrolling.
struct SettingsView: View {
    @ObservedObject var preferences: Preferences
    let store: UsageStore
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginItemError: String?

    var body: some View {
        Form {
            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        updateLoginItem(enabled)
                    }
                if let loginItemError {
                    Text(loginItemError)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Toggle(isOn: $preferences.hotkeyEnabled) {
                    Text("Global shortcuts")
                    Text("⌃⌥H opens Headroom · ⌃⌥J toggles the HUD")
                }
                .onChange(of: preferences.hotkeyEnabled) { _, enabled in
                    if enabled {
                        HotKeyManager.shared.register()
                    } else {
                        HotKeyManager.shared.unregister()
                    }
                }

                Picker("Check usage every", selection: $preferences.refreshMinutes) {
                    Text("1 minute").tag(1)
                    Text("2 minutes").tag(2)
                    Text("5 minutes").tag(5)
                    Text("10 minutes").tag(10)
                    Text("15 minutes").tag(15)
                }
                .onChange(of: preferences.refreshMinutes) {
                    store.rescheduleTimer()
                }
            }

            Section("Menu bar") {
                Picker("Layout", selection: layoutBinding) {
                    Text("One value (tightest limit)").tag("single")
                    Text("Both providers, one item").tag("both")
                }
                .onChange(of: preferences.menuBarLayoutRaw) {
                    store.menuBarPreferenceChanged()
                }

                Picker("Show", selection: menuBarBinding) {
                    ForEach(MenuBarStyle.allCases) { style in
                        Text(style.label).tag(style)
                    }
                }

                Picker("Percentage tracks", selection: $preferences.menuBarSourceRaw) {
                    Text("Tightest of all providers").tag("auto")
                    ForEach(ProviderID.allCases, id: \.rawValue) { provider in
                        Text(provider.displayName).tag(provider.rawValue)
                    }
                }
                .onChange(of: preferences.menuBarSourceRaw) {
                    store.menuBarPreferenceChanged()
                }
            }

            Section("Floating HUD") {
                Toggle("Show HUD", isOn: $preferences.hudVisible)
                    .onChange(of: preferences.hudVisible) {
                        store.menuBarPreferenceChanged()
                    }

                Picker("Position", selection: $preferences.hudPositionRaw) {
                    ForEach(HUDPosition.allCases) { position in
                        Text(position.label).tag(position.rawValue)
                    }
                }
                .disabled(!preferences.hudVisible)
                .onChange(of: preferences.hudPositionRaw) { _, raw in
                    store.applyHUDPosition(raw)
                }
            }

            Section {
                Toggle("Notify when a window fills up", isOn: $preferences.alertsEnabled)

                LabeledContent("Heads-up at") {
                    Stepper(
                        "\(Int(preferences.warnThreshold))% used",
                        value: $preferences.warnThreshold,
                        in: 50...90,
                        step: 5
                    )
                    .monospacedDigit()
                }
                .disabled(!preferences.alertsEnabled)

                LabeledContent("Critical at") {
                    Stepper(
                        "\(Int(preferences.criticalThreshold))% used",
                        value: $preferences.criticalThreshold,
                        in: 80...99,
                        step: 1
                    )
                    .monospacedDigit()
                }
                .disabled(!preferences.alertsEnabled)
            } header: {
                Text("Alerts")
            } footer: {
                Text("Headroom reads the official Codex and Anthropic usage APIs with the logins your CLIs already have. Nothing leaves this Mac.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// Maps the legacy "perProvider" value onto "both".
    private var layoutBinding: Binding<String> {
        Binding(
            get: { preferences.menuBarLayoutRaw == "single" ? "single" : "both" },
            set: { preferences.menuBarLayoutRaw = $0 }
        )
    }

    private var menuBarBinding: Binding<MenuBarStyle> {
        Binding(
            get: { preferences.menuBarStyle },
            set: { preferences.menuBarStyle = $0 }
        )
    }

    private func updateLoginItem(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginItemError = nil
        } catch {
            loginItemError = "Couldn't update login item: \(error.localizedDescription)"
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
