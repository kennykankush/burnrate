# burnrate

A menu bar tracker for Claude Code and Codex usage, costs, and limits — the bits Anthropic ships native, plus the bits nobody surfaces.

Live OAuth windows. Per-session quality grades. Cache-hit savings. 38 pattern cards including chronotype, anxiety meter, plugin marketplace popularity, beta gate timeline, codename collector. Reads everything in `~/.claude` you can read, plus `/api/oauth/usage`.

[burnrate.fyi](https://burnrate.fyi)

## Install

### Direct download

Grab the latest `.zip` from [Releases](https://github.com/kennykankush/burnrate/releases), unzip, and drag `burnrate.app` into `/Applications`.

> **First-launch quirk** — burnrate is signed with an Apple Development certificate (not yet notarised), so on first launch macOS will say "burnrate.app cannot be opened because the developer cannot be verified."
>
> Fix: **right-click** `burnrate.app` in `/Applications`, choose **Open**, then click **Open** in the warning dialog. macOS remembers the choice.

### Homebrew

```bash
brew tap kennykankush/burnrate https://github.com/kennykankush/burnrate
brew install --cask burnrate
```

Same first-launch right-click step applies until burnrate is properly notarised.

## What it shows

Click the menu bar icon. The Claude Code tab includes:

- **Live windows** — `fiveHour`, `sevenDay`, `sevenDayOpus`, `sevenDaySonnet` straight from Anthropic's OAuth `/api/oauth/usage` endpoint, with exact reset timestamps
- **Plan tier** — Pro / Max 5× / Max 20× detected from your `extra_usage.monthly_limit`
- **Advisor card** — health, primary driver, $/min burn, cache hit %
- **Today rich card** — hourly sparkline (current hour highlighted), language pills, lines/commits chips
- **Aggregate** — Day N · streak · sessions · longest
- **38 pattern cards** — anxiety meter (slash-command frequency), plugin popularity, beta-gate timeline, burnstar sign, achievements, monthly wrap, cost-per-commit, idle-session reclaim, and 30 more
- **Health row** — OAuth · Stalls · MCP · Limits · Compaction age · Context %

## What it reads

| Surface | Path |
| --- | --- |
| Pre-aggregated stats | `~/.claude/stats-cache.json` |
| Per-session quant | `~/.claude/usage-data/session-meta/*.json` |
| Per-session quality | `~/.claude/usage-data/facets/*.json` |
| Active session | `~/.claude/projects/<encoded-cwd>/<sessionId>.jsonl` |
| Live rate-limit windows | `https://api.anthropic.com/api/oauth/usage` |
| Marketplace popularity | `~/.claude/plugins/install-counts-cache.json` |
| Slash-command history | `~/.claude/history.jsonl` |
| Telemetry events | `~/.claude/telemetry/1p_failed_events.*.json` |
| Beta gates | `anthropic-beta` header from telemetry |

Everything runs locally. No data leaves your machine.

## Privacy

burnrate does not phone home. The only network call it makes is to `https://api.anthropic.com/api/oauth/usage` using the OAuth credential `claude` already has in your Keychain — same endpoint Anthropic's own `/status` command uses.

## Development

```bash
swift build
bash scripts/run.sh                  # debug build, sign, launch
bash scripts/release.sh 0.1.0        # release build, zip, ready to ship
```

Code-signing setup (one-time, prevents repeated keychain prompts during development):

```bash
bash scripts/setup-codesigning.sh
```

Uses your Apple Development cert if you have one (Xcode signs you up automatically); falls back to a self-signed identity called "Burnrate Dev" otherwise.

## Releasing

```bash
bash scripts/release.sh 0.2.0        # bumps Info.plist, builds, signs, zips
gh release create v0.2.0 dist/burnrate-0.2.0.zip --generate-notes
# update Casks/burnrate.rb with the new version + sha256
git add Casks/burnrate.rb && git commit -m "Cask: bump to 0.2.0" && git push
```

When you push a `v*` tag, the GitHub Actions workflow at `.github/workflows/release.yml` rebuilds and attaches the artifact automatically.

## License

MIT — see [LICENSE](./LICENSE).
