import Foundation

/// Fixed demo snapshots for `--snapshot` renders and marketing material.
enum DemoData {
    static func snapshots(now: Date = Date()) -> [ProviderID: ProviderState] {
        [
            .codex: .loaded(ProviderSnapshot(
                provider: .codex,
                planName: "Plus",
                windows: [
                    UsageWindow(
                        id: "codex.general.5h",
                        label: "Session (5h)",
                        usedPercent: 34,
                        resetsAt: now.addingTimeInterval(2 * 3600 + 40 * 60)
                    ),
                    UsageWindow(
                        id: "codex.general.week",
                        label: "Week",
                        usedPercent: 58,
                        resetsAt: now.addingTimeInterval(3 * 86_400 + 5 * 3600)
                    )
                ],
                fetchedAt: now
            )),
            .claude: .loaded(ProviderSnapshot(
                provider: .claude,
                planName: "Max",
                windows: [
                    UsageWindow(
                        id: "claude.five_hour",
                        label: "Session (5h)",
                        usedPercent: 62,
                        resetsAt: now.addingTimeInterval(1 * 3600 + 12 * 60)
                    ),
                    UsageWindow(
                        id: "claude.seven_day",
                        label: "Week (all models)",
                        usedPercent: 41,
                        resetsAt: now.addingTimeInterval(4 * 86_400 + 9 * 3600)
                    ),
                    UsageWindow(
                        id: "claude.weekly_scoped.fable",
                        label: "Week (Fable)",
                        usedPercent: 81,
                        resetsAt: now.addingTimeInterval(4 * 86_400 + 9 * 3600)
                    )
                ],
                fetchedAt: now
            ))
        ]
    }
}
