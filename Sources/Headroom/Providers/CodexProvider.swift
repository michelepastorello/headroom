import Foundation

/// Reads the official Codex usage endpoint with the token the Codex CLI
/// already keeps in ~/.codex/auth.json. Same data `codex` shows in /status.
enum CodexProvider {
    static func fetch() async -> ProviderState {
        guard let token = accessToken() else {
            return .failed(ProviderFailure(
                message: "No Codex credentials found",
                fix: "Run `codex` in a terminal and sign in"
            ))
        }

        do {
            let url = URL(string: "https://chatgpt.com/backend-api/wham/usage")!
            let (json, status) = try await ProviderSupport.getJSON(url: url, headers: [
                "Authorization": "Bearer \(token)",
                "Accept": "application/json",
                "User-Agent": "Headroom/1.0"
            ])

            if status == 401 || status == 403 {
                return .failed(ProviderFailure(
                    message: "Codex session expired",
                    fix: "Run `codex` once to refresh the login"
                ))
            }
            guard status == 200, let payload = json as? [String: Any] else {
                return .failed(ProviderFailure(
                    message: "Codex API returned HTTP \(status)",
                    fix: "Try again in a minute"
                ))
            }

            var windows: [UsageWindow] = []
            if let rateLimit = payload["rate_limit"] as? [String: Any] {
                windows.append(contentsOf: parse(rateLimit: rateLimit, idPrefix: "codex.general", labelPrefix: ""))
            }
            if let additional = payload["additional_rate_limits"] as? [[String: Any]] {
                for extra in additional {
                    guard let rateLimit = extra["rate_limit"] as? [String: Any] else { continue }
                    let name = (extra["limit_name"] as? String) ?? "Extra"
                    // "GPT-5.3-Codex-Spark" and friends are model SKUs; the
                    // last word is the human name ("Spark").
                    let shortName = name.split(separator: "-").last.map(String.init) ?? name
                    windows.append(contentsOf: parse(
                        rateLimit: rateLimit,
                        idPrefix: "codex.\(name.lowercased())",
                        labelPrefix: "\(shortName) · "
                    ))
                }
            }

            guard !windows.isEmpty else {
                return .failed(ProviderFailure(
                    message: "Codex returned no rate-limit data",
                    fix: "Check your plan on chatgpt.com"
                ))
            }

            let plan = (payload["plan_type"] as? String)?
                .replacingOccurrences(of: "_", with: " ")
                .capitalized
            return .loaded(ProviderSnapshot(
                provider: .codex,
                planName: plan,
                windows: windows,
                fetchedAt: Date()
            ))
        } catch {
            return .failed(ProviderFailure(
                message: "Codex request failed: \(error.localizedDescription)",
                fix: "Check your network connection"
            ))
        }
    }

    /// Raw response body for `--raw` diagnostics. Usage data only.
    static func rawResponse() async -> String {
        guard let token = accessToken() else { return "(no credentials)" }
        var request = URLRequest(url: URL(string: "https://chatgpt.com/backend-api/wham/usage")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("Headroom/1.0", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request) else {
            return "(request failed)"
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        return "HTTP \(status)\n" + ProviderSupport.prettyJSON(data)
    }

    private static func parse(rateLimit: [String: Any], idPrefix: String, labelPrefix: String) -> [UsageWindow] {
        var windows: [UsageWindow] = []
        if let primary = rateLimit["primary_window"] as? [String: Any],
           let used = ProviderSupport.double(primary["used_percent"]) {
            windows.append(UsageWindow(
                id: "\(idPrefix).5h",
                label: "\(labelPrefix)Session (5h)",
                usedPercent: min(100, max(0, used)),
                resetsAt: ProviderSupport.resetDate(from: primary)
            ))
        }
        if let secondary = rateLimit["secondary_window"] as? [String: Any],
           let used = ProviderSupport.double(secondary["used_percent"]) {
            windows.append(UsageWindow(
                id: "\(idPrefix).week",
                label: "\(labelPrefix)Week",
                usedPercent: min(100, max(0, used)),
                resetsAt: ProviderSupport.resetDate(from: secondary)
            ))
        }
        return windows
    }

    private static func accessToken() -> String? {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/auth.json")
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if let token = json["access_token"] as? String { return token }
        if let tokens = json["tokens"] as? [String: Any],
           let token = tokens["access_token"] as? String {
            return token
        }
        return nil
    }
}
