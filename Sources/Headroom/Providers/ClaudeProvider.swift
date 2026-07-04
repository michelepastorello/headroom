import Foundation
import Security

/// Reads the official Anthropic OAuth usage endpoint with the token Claude
/// Code already stores (login keychain, or ~/.claude/.credentials.json).
/// This replaces the old LimitBar approach of scraping `claude /status`
/// through a PTY: ~300 ms instead of ~15 s, and no breakage on CLI updates.
enum ClaudeProvider {
    static func fetch(skipKeychain: Bool = false) async -> ProviderState {
        guard let credentials = loadCredentials(skipKeychain: skipKeychain) else {
            return .failed(ProviderFailure(
                message: "No Claude Code credentials found",
                fix: "Run `claude` in a terminal and sign in"
            ))
        }

        // A stale expiresAt is common (Claude Code refreshes tokens lazily),
        // so never fail on the timestamp alone: try the request and let the
        // server decide. 401/403 below still reports the expired state.
        do {
            let url = URL(string: "https://api.anthropic.com/api/oauth/usage")!
            let (json, status) = try await ProviderSupport.getJSON(url: url, headers: [
                "Authorization": "Bearer \(credentials.accessToken)",
                "anthropic-beta": "oauth-2025-04-20",
                "Accept": "application/json",
                "User-Agent": "Headroom/1.0"
            ])

            if status == 401 || status == 403 {
                return .failed(ProviderFailure(
                    message: "Claude token was rejected",
                    fix: "Open `claude` once to refresh the login"
                ))
            }
            if status == 429 {
                return .failed(ProviderFailure(
                    message: "Anthropic is rate-limiting status checks",
                    fix: "Nothing to do; it retries on the next refresh"
                ))
            }
            guard status == 200, let payload = json as? [String: Any] else {
                return .failed(ProviderFailure(
                    message: "Anthropic API returned HTTP \(status)",
                    fix: "Try again in a minute"
                ))
            }

            let windows = parseWindows(payload)
            guard !windows.isEmpty else {
                return .failed(ProviderFailure(
                    message: "Usage response had no known windows",
                    fix: "Update Headroom; the API schema may have changed"
                ))
            }

            return .loaded(ProviderSnapshot(
                provider: .claude,
                planName: credentials.planName,
                windows: windows,
                fetchedAt: Date()
            ))
        } catch {
            return .failed(ProviderFailure(
                message: "Claude request failed: \(error.localizedDescription)",
                fix: "Check your network connection"
            ))
        }
    }

    /// Raw response body for `--raw` diagnostics. Usage data only.
    static func rawResponse() async -> String {
        guard let credentials = loadCredentials(skipKeychain: false) else {
            return "(no credentials)"
        }
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("Headroom/1.0", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request) else {
            return "(request failed)"
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        return "HTTP \(status)\n" + ProviderSupport.prettyJSON(data)
    }

    // MARK: - Response parsing

    /// The modern schema carries an authoritative `limits` array whose
    /// entries have kind/percent/resets_at and an optional model scope
    /// (this is where per-model weekly caps like Fable live). Prefer it;
    /// fall back to the legacy top-level keys for older accounts.
    private static func parseWindows(_ payload: [String: Any]) -> [UsageWindow] {
        if let limits = payload["limits"] as? [[String: Any]] {
            let windows = limits.compactMap(window(fromLimit:))
            if !windows.isEmpty {
                return windows + extraUsageWindows(payload)
            }
        }
        return legacyWindows(payload)
    }

    private static func window(fromLimit dict: [String: Any]) -> UsageWindow? {
        guard let percent = ProviderSupport.double(dict["percent"]) else { return nil }
        let kind = (dict["kind"] as? String) ?? "limit"

        var label: String
        switch kind {
        case "session": label = "Session (5h)"
        case "weekly_all": label = "Week (all models)"
        case "weekly_scoped": label = "Week"
        default: label = kind.replacingOccurrences(of: "_", with: " ").capitalized
        }

        var id = "claude.\(kind)"
        if let scope = dict["scope"] as? [String: Any] {
            let scopeName = (scope["model"] as? [String: Any])?["display_name"] as? String
                ?? (scope["surface"] as? [String: Any])?["display_name"] as? String
            if let scopeName {
                label = kind == "weekly_scoped" ? "Week (\(scopeName))" : "\(label) · \(scopeName)"
                id += ".\(scopeName.lowercased())"
            }
        }

        return UsageWindow(
            id: id,
            label: label,
            usedPercent: min(100, max(0, percent)),
            resetsAt: ProviderSupport.resetDate(from: dict)
        )
    }

    /// Extra-usage credits only matter when the user has them switched on;
    /// a disabled bucket would just show a meaningless "100% left" row.
    private static func extraUsageWindows(_ payload: [String: Any]) -> [UsageWindow] {
        guard let extra = payload["extra_usage"] as? [String: Any],
              (extra["is_enabled"] as? Bool) == true,
              let utilization = ProviderSupport.double(extra["utilization"]) else {
            return []
        }
        return [UsageWindow(
            id: "claude.extra_usage",
            label: "Extra usage credits",
            usedPercent: min(100, max(0, utilization)),
            resetsAt: ProviderSupport.resetDate(from: extra)
        )]
    }

    private static let legacyKeys: [(key: String, label: String)] = [
        ("five_hour", "Session (5h)"),
        ("seven_day", "Week (all models)"),
        ("seven_day_sonnet", "Week (Sonnet)"),
        ("seven_day_opus", "Week (Opus)"),
        ("seven_day_oauth_apps", "Week (apps)")
    ]

    private static func legacyWindows(_ payload: [String: Any]) -> [UsageWindow] {
        var windows: [UsageWindow] = []
        for (key, label) in legacyKeys {
            if let window = window(from: payload[key], id: key, label: label) {
                windows.append(window)
            }
        }
        return windows
    }

    private static func window(from value: Any?, id: String, label: String) -> UsageWindow? {
        guard let dict = value as? [String: Any],
              let utilization = ProviderSupport.double(dict["utilization"]) else {
            return nil
        }
        return UsageWindow(
            id: "claude.\(id)",
            label: label,
            usedPercent: min(100, max(0, utilization)),
            resetsAt: ProviderSupport.resetDate(from: dict)
        )
    }

    // MARK: - Credentials

    private struct Credentials {
        let accessToken: String
        let expiresAt: Date?
        let planName: String?
    }

    private static func loadCredentials(skipKeychain: Bool) -> Credentials? {
        if let data = fileCredentialData(), let creds = parseCredentials(data) {
            return creds
        }
        if !skipKeychain,
           let data = keychainCredentialData(),
           let creds = parseCredentials(data) {
            return creds
        }
        return nil
    }

    private static func fileCredentialData() -> Data? {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/.credentials.json")
        return try? Data(contentsOf: url)
    }

    private static func keychainCredentialData() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else { return nil }
        return item as? Data
    }

    private static func parseCredentials(_ data: Data) -> Credentials? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = json["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String else {
            return nil
        }
        var expiresAt: Date?
        if let ms = ProviderSupport.double(oauth["expiresAt"]) {
            expiresAt = Date(timeIntervalSince1970: ms > 7_000_000_000 ? ms / 1000 : ms)
        }
        let plan = (oauth["subscriptionType"] as? String)?.capitalized
        return Credentials(accessToken: token, expiresAt: expiresAt, planName: plan)
    }
}
