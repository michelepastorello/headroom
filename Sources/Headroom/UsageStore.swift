import Foundation
import SwiftUI
import UserNotifications

@MainActor
final class UsageStore: ObservableObject {
    @Published private(set) var states: [ProviderID: ProviderState] = [:]
    @Published private(set) var lastRefresh: Date?
    @Published private(set) var isRefreshing = false

    /// Fired after every refresh so the status item can redraw.
    var onUpdate: (() -> Void)?

    private let preferences: Preferences
    private var timer: Timer?
    private var refreshTask: Task<Void, Never>?
    /// window id + reset epoch → highest severity already notified.
    private var notifiedKeys: Set<String> = []
    private var notificationsConfigured = false

    init(preferences: Preferences = .shared) {
        self.preferences = preferences
        for provider in ProviderID.allCases {
            // Restore the last persisted reading so values are on screen
            // from the very first frame, even before the first refresh
            // (and even if that refresh fails).
            if let snapshot = Self.loadPersistedSnapshot(for: provider) {
                states[provider] = .stale(snapshot, ProviderFailure(
                    message: "Restored last reading",
                    fix: "Refreshing…"
                ))
            } else {
                states[provider] = .loading
            }
        }
    }

    // MARK: - Derived

    var tightest: TightestWindow? {
        tightestWindow(in: ProviderID.allCases)
    }

    /// What the status item tracks: the overall tightest window, or the
    /// tightest of the provider chosen in Settings.
    var menuBarWindow: TightestWindow? {
        if let provider = ProviderID(rawValue: preferences.menuBarSourceRaw) {
            return tightestWindow(in: [provider])
        }
        return tightest
    }

    func tightest(of provider: ProviderID) -> TightestWindow? {
        tightestWindow(in: [provider])
    }

    func menuBarPreferenceChanged() {
        onUpdate?()
    }

    /// Set by the app delegate; snaps the HUD panel to an anchor.
    var onApplyHUDPosition: ((String) -> Void)?

    func applyHUDPosition(_ raw: String) {
        preferences.hudPositionRaw = raw
        preferences.hudVisible = true
        onApplyHUDPosition?(raw)
        onUpdate?()
    }

    private func tightestWindow(in providers: [ProviderID]) -> TightestWindow? {
        var best: TightestWindow?
        for provider in providers {
            guard let snapshot = states[provider]?.snapshot else { continue }
            for window in snapshot.windows {
                if best == nil || window.usedPercent > best!.window.usedPercent {
                    best = TightestWindow(provider: provider, window: window)
                }
            }
        }
        return best
    }

    func severity(for window: UsageWindow) -> UsageSeverity {
        .of(
            usedPercent: window.usedPercent,
            warnAt: preferences.warnThreshold,
            criticalAt: preferences.criticalThreshold
        )
    }

    // MARK: - Refresh

    func start() {
        refresh()
        rescheduleTimer()
    }

    func rescheduleTimer() {
        timer?.invalidate()
        let interval = TimeInterval(max(1, preferences.refreshMinutes)) * 60
        let timer = Timer(timeInterval: interval, repeats: true) { _ in
            Task { @MainActor in
                UsageStoreRegistry.shared?.refresh()
            }
        }
        timer.tolerance = 10
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func refreshIfStale(olderThan seconds: TimeInterval = 60) {
        guard let last = lastRefresh else { return refresh() }
        if Date().timeIntervalSince(last) > seconds { refresh() }
    }

    func refresh() {
        guard refreshTask == nil else { return }
        isRefreshing = true

        refreshTask = Task { @MainActor in
            async let codex = CodexProvider.fetch()
            async let claude = ClaudeProvider.fetch()
            let results: [(ProviderID, ProviderState)] = [
                (.codex, await codex),
                (.claude, await claude)
            ]
            for (provider, state) in results {
                withAnimation(.easeOut(duration: 0.2)) {
                    states[provider] = reconciled(old: states[provider], new: state)
                }
            }
            lastRefresh = Date()
            isRefreshing = false
            refreshTask = nil
            onUpdate?()
            checkAlerts()
        }
    }

    /// A failed refresh must never wipe values off the screen: keep the last
    /// good snapshot, whatever its age, and carry the failure alongside so
    /// the UI can flag the reading as not updated.
    private func reconciled(old: ProviderState?, new: ProviderState) -> ProviderState {
        if case .failed(let failure) = new, let snapshot = old?.snapshot {
            return .stale(snapshot, failure)
        }
        if case .loaded(let snapshot) = new {
            Self.persistSnapshot(snapshot)
        }
        return new
    }

    // MARK: - Snapshot persistence (survives restarts)

    private static func persistenceKey(for provider: ProviderID) -> String {
        "lastSnapshot.\(provider.rawValue)"
    }

    private static func persistSnapshot(_ snapshot: ProviderSnapshot) {
        if let data = try? JSONEncoder().encode(snapshot) {
            UserDefaults.standard.set(data, forKey: persistenceKey(for: snapshot.provider))
        }
    }

    private static func loadPersistedSnapshot(for provider: ProviderID) -> ProviderSnapshot? {
        guard let data = UserDefaults.standard.data(forKey: persistenceKey(for: provider)) else {
            return nil
        }
        return try? JSONDecoder().decode(ProviderSnapshot.self, from: data)
    }

    /// Snapshot mode: fixed demo data, no network, no timers.
    func injectDemo() {
        states = DemoData.snapshots()
        lastRefresh = Date().addingTimeInterval(-12)
    }

    // MARK: - Alerts

    private func checkAlerts() {
        guard preferences.alertsEnabled, Bundle.main.bundleIdentifier != nil else { return }

        var pending: [(window: UsageWindow, provider: ProviderID, severity: UsageSeverity, key: String)] = []
        for provider in ProviderID.allCases {
            guard let snapshot = states[provider]?.snapshot else { continue }
            for window in snapshot.windows {
                let severity = severity(for: window)
                guard severity != .ok else { continue }
                let resetEpoch = Int(window.resetsAt?.timeIntervalSince1970 ?? 0)
                let level = severity == .critical ? "critical" : "warn"
                let key = "\(window.id).\(resetEpoch).\(level)"
                guard !notifiedKeys.contains(key) else { continue }
                pending.append((window, provider, severity, key))
            }
        }
        guard !pending.isEmpty else { return }

        Task { @MainActor in
            await configureNotificationsIfNeeded()
            let center = UNUserNotificationCenter.current()
            for item in pending {
                notifiedKeys.insert(item.key)
                let content = UNMutableNotificationContent()
                content.title = item.severity == .critical
                    ? "\(item.provider.displayName): limit almost reached"
                    : "\(item.provider.displayName): heads up"
                var body = "\(item.window.label) is \(Int(item.window.usedPercent))% used."
                if let reset = item.window.resetsAt {
                    body += " Resets \(Formatters.clock.string(from: reset))."
                }
                content.body = body
                content.sound = item.severity == .critical ? .default : nil
                let request = UNNotificationRequest(
                    identifier: item.key,
                    content: content,
                    trigger: nil
                )
                try? await center.add(request)
            }
        }
    }

    private func configureNotificationsIfNeeded() async {
        guard !notificationsConfigured else { return }
        notificationsConfigured = true
        let center = UNUserNotificationCenter.current()
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }
}

/// Weak registry so the repeating Timer never retains the store.
@MainActor
enum UsageStoreRegistry {
    weak static var shared: UsageStore?
}

enum Formatters {
    static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    private static let weekdayClock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEE HH:mm")
        return formatter
    }()

    /// "at 11:40" within the day, "Mon 11:00" beyond it.
    static func compactReset(_ date: Date) -> String {
        if date.timeIntervalSinceNow < 22 * 3600 {
            return "at \(clock.string(from: date))"
        }
        return weekdayClock.string(from: date)
    }

    static func countdown(to date: Date, from now: Date = Date()) -> String {
        let seconds = max(0, Int(date.timeIntervalSince(now)))
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(max(1, minutes))m"
    }
}
