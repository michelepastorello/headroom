import Foundation

enum ProviderSupport {
    static func getJSON(url: URL, headers: [String: String]) async throws -> (Any, Int) {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = try JSONSerialization.jsonObject(with: data)
        return (json, status)
    }

    static func double(_ value: Any?) -> Double? {
        if let d = value as? Double { return d }
        if let i = value as? Int { return Double(i) }
        if let s = value as? String { return Double(s) }
        return nil
    }

    /// Accepts epoch seconds, epoch milliseconds, "in N seconds" counters or ISO-8601 strings.
    static func resetDate(from window: [String: Any]) -> Date? {
        for key in ["reset_at", "resets_at", "reset_time"] {
            guard let raw = window[key] else { continue }
            if let epoch = double(raw) {
                // Anything above year ~2200 in seconds is actually milliseconds.
                return Date(timeIntervalSince1970: epoch > 7_000_000_000 ? epoch / 1000 : epoch)
            }
            if let iso = raw as? String, let date = parseISO(iso) {
                return date
            }
        }
        for key in ["reset_after_seconds", "resets_in_seconds", "remaining_seconds"] {
            if let seconds = double(window[key]) {
                return Date().addingTimeInterval(seconds)
            }
        }
        return nil
    }

    static func prettyJSON(_ data: Data) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]) else {
            return String(data: data, encoding: .utf8) ?? "(binary)"
        }
        return String(data: pretty, encoding: .utf8) ?? "(binary)"
    }

    static func parseISO(_ string: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: string) { return date }
        let plain = ISO8601DateFormatter()
        return plain.date(from: string)
    }
}
