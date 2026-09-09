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

- **Claude:** sign in to Claude Code with your Claude subscription. The app reads Claude Code's `Claude Code-credentials` Keychain item, with `.claude/.credentials.json` as a fallback. macOS may ask you to allow that Keychain access. After a session expires, sign in again in Claude Code, then refresh. The app never refreshes or rewrites Claude's credentials itself.
- **Codex:** sign in to your local Codex client with ChatGPT. The app locates Codex in common CLI, desktop, VS Code, and Zed installations. If needed, choose its executable in Settings. It uses the documented `account/rateLimits/read` app-server method over a short-lived local stdio connection; it never sends prompts or starts agent tasks.

The Claude integration reads `https://api.anthropic.com/api/oauth/usage` using the existing Claude Code OAuth token. This is an **internal endpoint**, not a supported public API contract, and may change. Failures are shown explicitly, with a link to the provider's usage page. No API admin keys or manually entered dollar budgets are required.

The app does not display API billing, dollar spend, or ChatGPT chat usage. These are subscription quota readings for Claude and Codex. Percentages and window durations come from the providers; missing data is never represented as zero.

## Behavior

- Refreshes on launch and in the background, even while the panel is closed; checks again after waking from sleep.
- Default polling is every five minutes; Settings offers 5, 10, 15, or 30 minutes.
- Manual refresh requests are at least one minute apart. Errors back off; Claude HTTP 429 responses respect a retry delay.
- Shows last successful readings and an explicit error if a refresh fails. Past reset times say that a fresh reading is needed.
- Supports extra model-specific quota windows when reported.
- Optional menu bar percentages: `C` for Claude and `O` for OpenAI Codex, using each provider's first returned window.
- Settings changes apply only after Save; Cancel discards the draft.
- Stores only preferences in UserDefaults. Credentials are not copied or logged, and usage snapshots stay in memory. There is no telemetry.

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
