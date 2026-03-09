# AI Usage App

# burnrate

Local file reader prototype for Codex and Claude usage data on macOS.

## What it reads

- `~/.codex/sessions/**/*.jsonl`
- `~/.claude/stats-cache.json`

## What it outputs

A normalized JSON snapshot with:

- time window
- Codex live local rate-limit windows, resets, and token totals
- Claude local session/message/tool-call counts
- source/confidence notes for each provider

## Run

```bash
swift build
./.build/debug/ai-usage-app --days 7
```

Optional overrides:

```bash
./.build/debug/ai-usage-app \
  --days 14 \
  --codex-dir /custom/path/.codex \
  --claude-stats /custom/path/stats-cache.json \
  --history-path /custom/path/history.jsonl \
  --retention-days 180
```

Disable history writes:

```bash
./.build/debug/ai-usage-app --days 7 --no-history
```

## History

By default each run appends a snapshot to:

`~/.ai-usage-app/history.jsonl`

This is the data a future menu bar app or widget can use for:

- current bar fill
- 7 day / 30 day trends
- last refresh timestamp
- simple historical charts

## Caveat

This is a local activity reader, not an official quota API client.
Claude snapshots are marked as `estimated` because they are derived from local files rather than vendor-reported remaining allowance.
Codex rate-limit windows come from local session telemetry, which is much closer to the app UI than the old SQLite totals.

## Widget note

To render this as a real macOS widget, the next step is an Xcode project with:

- a macOS host app or menu bar app
- a WidgetKit extension
- a shared App Group store that reads or mirrors `history.jsonl`

That project now exists at:

`Runway.xcodeproj`

## Open in Xcode

1. Open `Runway.xcodeproj`
2. Select the `Runway` scheme
3. Build and run on `My Mac`
4. Launch the app once so it writes the latest shared snapshot
5. Add the `Runway` widget from the macOS widget gallery

## What the app does

- reads Codex session telemetry from `~/.codex/sessions/**/*.jsonl`
- reads local Claude activity from `~/.claude/stats-cache.json`
- refreshes on launch and on a timer
- stores the latest widget snapshot in shared defaults
- writes longer history to `~/Library/Application Support/Runway/history.jsonl`

## Current display model

Because this is a local file reader, the display mixes direct local telemetry with user-configured budgets:

- Codex: live 5 hour and 7 day rate-limit bars from local session logs
- Claude Code: weekly message budget

The app still lets you edit the Claude budget so that bar remains meaningful without an official vendor quota API.
