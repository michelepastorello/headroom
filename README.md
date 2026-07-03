# Headroom

Native macOS menu-bar app that shows how much of your AI coding-tool rate
limits is left — Codex (OpenAI) and Claude Code (Anthropic) — when each window
resets, and warns you before a long run dies at 99%.

**[headroom.michelepastorello.ai](https://headroom.michelepastorello.ai)** ·
built by [Michele Pastorello](https://michelepastorello.ai) · MIT license.

Evolution of the LimitBar prototype. What changed:

| | LimitBar (prototype) | Headroom |
|---|---|---|
| Claude data | PTY-scrapes `claude /status` (~15 s, breaks on CLI updates) | Official Anthropic OAuth usage API (~300 ms) |
| Codex data | Official API | Official API + dynamic extra windows (Spark, …) |
| Menu bar | Static icon | Live % of your tightest window, orange/red past thresholds |
| Refresh | Manual only | Auto-refresh (1–15 min) + manual + refresh-on-open |
| Alerts | None | Native notifications at configurable thresholds |
| Login item | None | Launch at login (SMAppService) |
| Appearance | Forced dark | Native, adaptive light/dark, popover material |
| Structure | Single 1000-line main.swift | Modular Swift package, provider layer, testable |
| Extras | — | `--check`/`--raw` diagnostics, `--snapshot [--hud]` renderer, onboarding, app icon |
| Widgets | — | Floating always-on-top HUD + optional per-provider menu bar items |
| Shortcut | — | Global ⌃⌥H opens the popover from anywhere |

## Build

Requires macOS 14+ and Xcode Command Line Tools (Swift 6).

```sh
./build-app.sh     # builds, generates the icon, bundles and signs Headroom.app
open Headroom.app
```

## Terminal diagnostics

```sh
.build/release/Headroom --check              # prints every window as text
.build/release/Headroom --check --no-keychain  # skip the keychain (file creds only)
```

## Snapshots

```sh
.build/release/Headroom --snapshot out.png          # light appearance, demo data
.build/release/Headroom --snapshot out.png --dark   # dark appearance
```

## First launch notes

- Claude Code stores its login in the macOS keychain; Headroom asks for read
  access once. Click **Always Allow**. Denying it just marks Claude as
  unavailable — everything else keeps working.
- The app is ad-hoc signed. For distribution, sign with a Developer ID and
  notarize (`xcrun notarytool`).

## Privacy

Local-first by architecture: Headroom reads the tokens your CLIs already
store and calls only the vendors' own usage endpoints. No telemetry, no
account, no middleman server. Credentials never leave this Mac.

## Layout

```
Sources/Headroom/
  HeadroomApp.swift      entry point, status item, windows, --check, --snapshot
  UsageStore.swift       refresh orchestration, alerts, timers
  Models.swift           providers, windows, severity
  Preferences.swift      user settings (UserDefaults)
  DemoData.swift         fixed data for snapshots
  Providers/             one small file per provider + shared HTTP/parsing
  Views/                 dashboard, settings, onboarding, gauge, theme
scripts/make-icon.swift  draws the app icon with CoreGraphics
```

Not affiliated with OpenAI, Anthropic or SessionWatcher.
