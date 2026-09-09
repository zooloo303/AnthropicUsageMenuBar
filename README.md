# Usage Menu Bar

A native macOS menu bar app that shows Claude and Codex **subscription usage** together: percent used, session and weekly windows, and reset times. Click the chart icon in the menu bar to open it.

## Build and run

Requires macOS 14+ and a Swift 6+ toolchain (Xcode or current Apple Command Line Tools).

```sh
./scripts/build-app.sh
open "dist/Usage Menu Bar.app"
```

For regular use, move the app to `~/Applications` or `/Applications`, launch that copy, and enable **Launch at login** in Settings if desired. The build is signed locally with an ad hoc signature; distribution to other Macs would need Developer ID signing and notarization.

## Connections

- **Claude:** open **Settings → Connect Claude**, sign in on Claude's website, and click **Save connection**. The app remembers this connection in its own persistent WebKit browser store across restarts and updates. Refresh never opens a Claude Keychain password dialog. Claude can still expire or revoke a web session; reconnect if that happens. Until a web connection is saved, the app can reuse a silently accessible Claude Code sign-in as a compatibility fallback. It never prompts for that Keychain entry or refreshes/rewrites Claude Code's credentials.
- **Codex:** sign in to your local Codex client with ChatGPT. The app locates Codex in common CLI, desktop, VS Code, and Zed installations. If needed, choose its executable in Settings. It uses the documented `account/rateLimits/read` app-server method over a short-lived local stdio connection; it never sends prompts or starts agent tasks.

The Claude integration reads the web usage endpoint at `https://claude.ai/api/organizations/{id}/usage`, or the OAuth usage endpoint for the silent Claude Code fallback. These are **internal endpoints**, not supported public API contracts, and may change. Failures are shown explicitly, with a link to the provider's usage page. No API admin keys or manually entered dollar budgets are required.

The app does not display API billing, dollar spend, or ChatGPT chat usage. These are subscription quota readings for Claude and Codex. Percentages and window durations come from the providers; missing data is never represented as zero.

## Behavior

- Refreshes on launch and in the background, even while the panel is closed; checks again after waking from sleep.
- Default polling is every five minutes; Settings offers 5, 10, 15, or 30 minutes.
- Manual refresh requests are at least one minute apart. Errors back off; Claude HTTP 429 responses respect a retry delay.
- Shows last successful readings and an explicit error if a refresh fails. Past reset times say that a fresh reading is needed.
- Supports extra model-specific quota windows when reported.
- Optional menu bar percentages: `C` for Claude and `O` for OpenAI Codex, using each provider's first returned window.
- Settings opens in its own window and stays open while you use controls or connection dialogs. Changes apply only after Save; Cancel or closing the window discards the draft.
- Stores only preferences in UserDefaults. Claude web sign-in cookies stay in the app’s persistent WebKit store. Claude Code tokens and usage snapshots stay in memory. Credentials are never logged. There is no telemetry.

## Development and checks

```sh
./scripts/test.sh
swift run UsageProbe             # Live read-only check of both providers
swift run UsageProbe codex       # Or claude
open "dist/Usage Menu Bar.app" --args --preview
```

Preview mode uses clearly labeled sample data and makes no provider requests. `UsageProbe` prints usage summaries and safe errors, never credentials. Tests cover response shapes, missing/malformed data, legacy and multiple Codex buckets, fragmented RPC messages, errors, process exit, and timeouts. They require no account or network connection.

Code is split into `Sources/Core` (connections and parsing), `Sources/App` (SwiftUI and polling), `Sources/Probe` (live diagnostics), and `Tests`.

Reference: [Codex app-server protocol](https://learn.chatgpt.com/docs/app-server).
