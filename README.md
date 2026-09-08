# Anthropic Usage Menu Bar

macOS menu bar widget that tracks Anthropic Claude and OpenAI / Codex subscription usage.

## Build

Requires Xcode 15+ and macOS 14+.

```bash
cd /home/neilw/Projects/AnthropicUsageMenuBar
swift build
```

For Xcode project, open the folder and create a new macOS App target, then add the Sources files.

## Setup

1. Open the menu bar icon → Settings
2. Anthropic Admin API Key: get from platform.claude.com → Organization → API Keys → Admin API key `sk-ant-admin01-...`
3. Set monthly limit USD
4. Optional OpenAI API Key for Codex tracking
5. Refresh interval

Keys are stored in Keychain.

## Anthropic API

Uses `GET https://api.anthropic.com/v1/organizations/usage_report/messages` with headers:
- `x-api-key`
- `anthropic-version: 2023-06-01`

Polls monthly usage, sums cost.

## Notes

OpenAI usage endpoint is stubbed – provide manual limits for now. Replace `OpenAIService` with actual usage API when available.
