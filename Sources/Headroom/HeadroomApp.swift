import AppKit
import SwiftUI

@main
@MainActor
enum HeadroomMain {
    static func main() {
        let arguments = CommandLine.arguments
        if let index = arguments.firstIndex(of: "--snapshot"), index + 1 < arguments.count {
            let appearance = arguments.contains("--dark") ? NSAppearance.Name.darkAqua : .aqua
            SnapshotRenderer.render(to: arguments[index + 1], appearance: appearance, hud: arguments.contains("--hud"))
            return
        }
        if arguments.contains("--check") {
            HealthCheck.run(skipKeychain: arguments.contains("--no-keychain"))
            return
        }
        if arguments.contains("--raw") {
            HealthCheck.dumpRaw()
            return
        }

        let delegate = AppDelegate()
        let app = NSApplication.shared
        app.delegate = delegate
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let preferences = Preferences.shared
    private let store = UsageStore()
    private let hud = HUDPanelController()
    private var statusItems: [String: NSStatusItem] = [:]
    private var popover: NSPopover?
    private var settingsWindow: NSWindow?
    private var welcomeWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        UsageStoreRegistry.shared = store
        store.onUpdate = { [weak self] in self?.syncUI() }

        createPopover()
        syncUI()
        store.start()

        HotKeyManager.shared.onToggleDashboard = { [weak self] in self?.toggleFromHotKey() }
        HotKeyManager.shared.onToggleHUD = { [weak self] in
            guard let self else { return }
            self.preferences.hudVisible.toggle()
            self.syncUI()
        }
        store.onApplyHUDPosition = { [weak self] raw in
            guard let self else { return }
            self.hud.apply(positionRaw: raw, store: self.store, preferences: self.preferences)
        }
        if preferences.hotkeyEnabled {
            HotKeyManager.shared.register()
        }

        if !preferences.hasCompletedWelcome {
            showWelcome()
        }
    }

    // MARK: - Popover

    private func createPopover() {
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        let controller = NSHostingController(
            rootView: DashboardView(
                store: store,
                preferences: preferences,
                openSettings: { [weak self] in self?.showSettings() }
            )
        )
        // Keep NSPopover in sync with SwiftUI's intrinsic size: without this
        // the popover keeps the height measured at show time (the small
        // skeleton state) and the grown content spills past the menu bar.
        controller.sizingOptions = [.preferredContentSize]
        popover.contentViewController = controller
        self.popover = popover
    }

    // MARK: - UI sync (status item + HUD)

    /// One status item, always. The layout preference only decides what its
    /// title shows: the single tightest value, or both providers combined
    /// (iStat Menus-style). One item, one popover.
    private func syncUI() {
        createStatusItemIfNeeded()
        updateStatusItemContent()
        hud.setVisible(preferences.hudVisible, store: store, preferences: preferences)
    }

    private var showsBothProviders: Bool {
        // "perProvider" is the legacy value from the short-lived two-item mode.
        preferences.menuBarLayoutRaw == "both" || preferences.menuBarLayoutRaw == "perProvider"
    }

    private func createStatusItemIfNeeded() {
        guard statusItems["main"] == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = "HeadroomStatusItem"
        item.behavior = .removalAllowed
        if let button = item.button {
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.toolTip = "Headroom — AI usage limits"
        }
        statusItems["main"] = item
    }

    private func updateStatusItemContent() {
        guard let button = statusItems["main"]?.button else { return }
        if showsBothProviders {
            button.image = nil
            button.attributedTitle = combinedTitle()
        } else {
            if button.image == nil {
                button.image = NSImage(
                    systemSymbolName: "gauge.with.needle",
                    accessibilityDescription: "Headroom"
                )?.withSymbolConfiguration(.init(pointSize: 13.5, weight: .medium))
                button.image?.isTemplate = true
                button.imagePosition = .imageLeft
            }
            button.attributedTitle = mainTitle()
        }
    }

    private func combinedTitle() -> NSAttributedString {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        let result = NSMutableAttributedString()
        for (index, provider) in ProviderID.allCases.enumerated() {
            if index > 0 {
                result.append(NSAttributedString(string: "  ", attributes: [.font: font]))
            }
            result.append(perProviderTitle(for: provider))
        }
        return result
    }

    private func mainTitle() -> NSAttributedString {
        guard preferences.menuBarStyle != .iconOnly, let tightest = store.menuBarWindow else {
            return NSAttributedString(string: "")
        }
        let value = preferences.menuBarStyle == .percentUsed
            ? Int(tightest.window.usedPercent.rounded())
            : Int(tightest.window.leftPercent.rounded())
        let font = NSFont.monospacedDigitSystemFont(ofSize: 12.5, weight: .medium)
        var attributes: [NSAttributedString.Key: Any] = [.font: font]
        switch store.severity(for: tightest.window) {
        case .ok: break
        case .warning: attributes[.foregroundColor] = NSColor.systemOrange
        case .critical: attributes[.foregroundColor] = NSColor.systemRed
        }
        return NSAttributedString(string: " \(value)%", attributes: attributes)
    }

    private func perProviderTitle(for provider: ProviderID) -> NSAttributedString {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        guard let tightest = store.tightest(of: provider) else {
            return NSAttributedString(string: "\(provider.glyph) –", attributes: [
                .font: font,
                .foregroundColor: NSColor.tertiaryLabelColor
            ])
        }
        let value = preferences.menuBarStyle == .percentUsed
            ? Int(tightest.window.usedPercent.rounded())
            : Int(tightest.window.leftPercent.rounded())
        let color: NSColor
        switch store.severity(for: tightest.window) {
        case .ok: color = NSColor(provider.identityTint)
        case .warning: color = .systemOrange
        case .critical: color = .systemRed
        }
        return NSAttributedString(string: "\(provider.glyph) \(value)%", attributes: [
            .font: font,
            .foregroundColor: color
        ])
    }

    // MARK: - Popover toggling

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        togglePopover(anchoredTo: sender)
    }

    private func toggleFromHotKey() {
        guard let anchor = statusItems["main"]?.button else { return }
        togglePopover(anchoredTo: anchor)
    }

    private func togglePopover(anchoredTo button: NSStatusBarButton) {
        guard let popover else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            store.refreshIfStale()
            syncUI()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    // MARK: - Windows

    private func showSettings() {
        popover?.performClose(nil)
        if settingsWindow == nil {
            let controller = NSHostingController(
                rootView: SettingsView(preferences: preferences, store: store)
            )
            let window = NSWindow(contentViewController: controller)
            window.title = "Headroom Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            // Center on the very first open; afterwards the window keeps
            // wherever the user moved it, across launches too.
            if !window.setFrameUsingName("HeadroomSettings") {
                window.center()
            }
            window.setFrameAutosaveName("HeadroomSettings")
            settingsWindow = window
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func showWelcome() {
        if welcomeWindow == nil {
            let controller = NSHostingController(
                rootView: WelcomeView(clis: CLIDetector.detect()) { [weak self] in
                    self?.preferences.hasCompletedWelcome = true
                    self?.welcomeWindow?.close()
                    self?.toggleFromHotKey()
                }
            )
            let window = NSWindow(contentViewController: controller)
            window.title = "Welcome to Headroom"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            welcomeWindow = window
        }
        welcomeWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - Health check (`Headroom --check`)

/// Terminal diagnostics: fetches every provider and prints percentages only.
/// Never prints tokens or credentials.
enum HealthCheck {
    static func run(skipKeychain: Bool) {
        let semaphore = DispatchSemaphore(value: 0)

        // Detached: the main thread parks on the semaphore below, so this
        // must not inherit any actor isolation.
        Task.detached {
            for provider in ProviderID.allCases {
                let state = provider == .codex
                    ? await CodexProvider.fetch()
                    : await ClaudeProvider.fetch(skipKeychain: skipKeychain)
                switch state {
                case .loaded(let snapshot):
                    let plan = snapshot.planName.map { " (\($0))" } ?? ""
                    print("✓ \(provider.displayName)\(plan)")
                    for window in snapshot.windows {
                        var line = "    \(window.label): \(Int(window.usedPercent))% used"
                        if let reset = window.resetsAt {
                            line += ", resets in \(Formatters.countdown(to: reset))"
                        }
                        print(line)
                    }
                case .stale(let snapshot, let failure):
                    print("⚠ \(provider.displayName): stale since \(Formatters.clock.string(from: snapshot.fetchedAt)) (\(failure.message))")
                case .failed(let failure):
                    print("✗ \(provider.displayName): \(failure.message)")
                    print("    fix: \(failure.fix)")
                case .loading:
                    break
                }
            }
            semaphore.signal()
        }

        // Park the main thread while the async work runs on the cooperative pool.
        _ = semaphore.wait(timeout: .now() + 30)
    }

    /// Prints the raw usage responses (usage data only, never credentials)
    /// so schema changes can be diagnosed without guessing.
    static func dumpRaw() {
        let semaphore = DispatchSemaphore(value: 0)
        Task.detached {
            print("── Claude (api.anthropic.com/api/oauth/usage)")
            print(await ClaudeProvider.rawResponse())
            print("── Codex (chatgpt.com/backend-api/wham/usage)")
            print(await CodexProvider.rawResponse())
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 30)
    }
}

// MARK: - Snapshot renderer (design verification & marketing renders)

@MainActor
enum SnapshotRenderer {
    static func render(to path: String, appearance: NSAppearance.Name, hud: Bool = false) {
        NSApplication.shared.appearance = NSAppearance(named: appearance)

        let store = UsageStore()
        store.injectDemo()

        let colorScheme: ColorScheme = appearance == .darkAqua ? .dark : .light
        let view = Group {
            if hud {
                HUDView(store: store, preferences: .shared)
            } else {
                DashboardView(store: store, preferences: .shared, isSnapshot: true)
                    .background(Color(nsColor: .windowBackgroundColor))
            }
        }
        .environment(\.colorScheme, colorScheme)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 2.0

        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            FileHandle.standardError.write(Data("snapshot: render failed\n".utf8))
            exit(1)
        }

        do {
            try png.write(to: URL(fileURLWithPath: path))
            print("snapshot written: \(path)")
        } catch {
            FileHandle.standardError.write(Data("snapshot: \(error)\n".utf8))
            exit(1)
        }
    }
}
