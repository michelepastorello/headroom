import SwiftUI

struct DetectedCLI: Identifiable {
    let id: String
    let name: String
    let path: String?
    var isInstalled: Bool { path != nil }
}

enum CLIDetector {
    static func detect() -> [DetectedCLI] {
        [
            find(id: "codex", name: "Codex CLI", binary: "codex"),
            find(id: "claude", name: "Claude Code", binary: "claude")
        ]
    }

    private static func find(id: String, name: String, binary: String) -> DetectedCLI {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let fallbacks = ["\(home)/.local/bin", "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"]
        let paths = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":").map(String.init) + fallbacks
        for path in paths {
            let candidate = "\(path)/\(binary)"
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return DetectedCLI(id: id, name: name, path: candidate)
            }
        }
        return DetectedCLI(id: id, name: name, path: nil)
    }
}

struct WelcomeView: View {
    let clis: [DetectedCLI]
    var done: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: "gauge.with.needle")
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(Theme.ok)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Headroom is in your menu bar")
                        .font(.system(size: 17, weight: .semibold))
                    Text("Click the gauge to see how much of your AI limits is left.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(20)

            HairlineDivider()

            VStack(alignment: .leading, spacing: 10) {
                Text("Detected on this Mac")
                    .font(.system(size: 11, weight: .semibold))
                    .textCase(.uppercase)
                    .kerning(0.4)
                    .foregroundStyle(.tertiary)

                ForEach(clis) { cli in
                    HStack(spacing: 8) {
                        Image(systemName: cli.isInstalled ? "checkmark.circle.fill" : "circle.dashed")
                            .font(.system(size: 13))
                            .foregroundStyle(cli.isInstalled ? Theme.ok : Color.secondary)
                        Text(cli.name)
                            .font(.system(size: 12, weight: .medium))
                        Text(cli.path ?? "not found — sign in once from a terminal")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 0)
                    }
                }

                Text("Headroom reads the logins these CLIs already have. Credentials stay on this Mac; the app only calls the vendors' own usage endpoints.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
                    .padding(.top, 4)
            }
            .padding(20)

            HairlineDivider()

            HStack {
                Spacer()
                Button("Start monitoring") { done() }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.ok)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 440)
    }
}
