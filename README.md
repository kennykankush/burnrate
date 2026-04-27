<div align="center">
  <img src="assets/header.png" alt="burnrate" width="100%" />
</div>

# burnrate

**Nope. Not a `/status` wrapper, hehe.**

burnrate is a macOS menu bar app that turns months of Claude Code usage into chronotypes, burnstar signs, achievements, leaderboards, and a deck of pattern cards. Live OAuth windows, plan tier, $/min burn, and cache hit are in there too. They're just not the point.

`/usage` shows you a snapshot. burnrate shows you the story.

> **Codex too.** burnrate includes Codex coverage today, with Claude Code the heavier of the two. Deeper Codex parity is in progress.

## Install

### Homebrew

```bash
brew tap kennykankush/burnrate https://github.com/kennykankush/burnrate
brew install --cask burnrate
```

### Direct download

Grab the latest `.zip` from [Releases](https://github.com/kennykankush/burnrate/releases), unzip, drag `burnrate.app` into `/Applications`.

### First launch

burnrate is signed with an Apple Development certificate (notarisation in progress). On first launch macOS shows: *"Apple could not verify burnrate is free of malware."*

1. Click **Done** on the dialog (do not move to trash)
2. **System Settings → Privacy & Security**, scroll down to the burnrate entry
3. Click **Open Anyway** → authenticate → **Open**

macOS remembers the choice. Future launches are silent.

## What you get

Three things, in the order you'll use them.

### The Advisor: what to do right now

The card you'll look at every time you open the menu. A live diagnostic that reads your current session and tells you, in plain English, whether you're healthy, what's eating your window, and how long you've got.

- **Health verdict.** Green / yellow / red, with the reason in one sentence.
- **Recommendation.** *"You're fine for the next hour."* *"That last turn ate 18% of your window."* *"Slow down on Opus or you'll cool down before reset."*
- **Primary driver.** The model, project, or tool burning you down right now, with the supporting detail.
- **Forecast.** Where you'll land before reset, projected turns remaining, what happens if you keep the current pace.
- **Live burn.** $/min and tokens/min, updated continuously.

Dashboard warning light plus a mechanic who actually explains it. The answer to *can I keep coding right now?*

### Pattern cards

Stories built from data nobody else reads. A handful of them, just to set the tone:

| Card | What it surfaces |
|---|---|
| `chronotype` | When you actually code, classified into a profile that reads back like a personality |
| `anxietyMeter` | How often you mash slash-commands per session, derived from `history.jsonl` |
| `burnstarSign` | Your Claude horoscope, computed from burn rate, model mix, and tool bias |
| `monthlyWrap` | Spotify-Wrapped for your last month: top project, top tool, longest streak, biggest single turn |
| `codenameCollector` | Every release codename you have passed through, scraped from `anthropic-beta` headers |
| `pluginPopularity` | Marketplace install counts for the plugins you actually have installed |
| `mostExpensiveTurn` | Your single most expensive turn ever, with the exact prompt timestamp |
| `firstPromptEver` | The first thing you ever asked Claude Code |
| `achievements` | Unlockable badges as you cross milestones |

A few more, named without descriptions: `betaTimeline`, `costPerCommit`, `idleReclaim`, `wrongPath`, `anniversary`, `weekendWarrior`, and leaderboards for bash, MCP, and skills.

The rest are earned by using it.

### The gauges

Live windows (`fiveHour`, `sevenDay`, `sevenDayOpus`, `sevenDaySonnet`) with exact reset timestamps. Plan tier (Pro / Max 5x / Max 20x) detected automatically. A Today panel with hourly sparkline, language pills, and lines and commits chips. Aggregate stats: Day N, streak, sessions, longest. A health row covering OAuth, stalls, MCP, limits, compaction age, and context %.

The bits every Claude usage tool ships. They're here, they work, they're not the reason you'd install this.

## What it reads

burnrate reads local files Claude Code writes under `~/.claude/`. One network call, `GET /api/oauth/usage` on `api.anthropic.com`, for the live rate-limit windows. Same endpoint Claude Code's own `/usage` slash command uses. Nothing else leaves your machine. No telemetry, no analytics, no third-party servers.

## Privacy and Anthropic policy

burnrate touches Keychain and one Anthropic endpoint. Both are explained in detail because vagueness in this category breeds paranoia.

### The single network call

The only outbound request burnrate makes is:

```
GET https://api.anthropic.com/api/oauth/usage
Authorization: Bearer <OAuth token from Keychain item "Claude Code-credentials">
```

This is the same endpoint Claude Code's own `/usage` slash command hits. It returns the live `fiveHour`, `sevenDay`, `sevenDayOpus`, `sevenDaySonnet` windows and reset timestamps. Metadata only. No tokens are consumed, no model is invoked, no completions are made.

burnrate cannot be used to call Claude models. It does not proxy inference, does not spoof the Claude Code harness, and does not route prompts. The implementation is in [`Sources/BurnrateCore/ClaudeOAuth.swift`](Sources/BurnrateCore/ClaudeOAuth.swift). One URL, one `GET`, one `Authorization` header.

### Anthropic's third-party tool policy

In January 2026 Anthropic clarified its Consumer Terms of Service to ban third-party tools from using subscription OAuth tokens to call Claude models. See [The Register](https://www.theregister.com/2026/02/20/anthropic_clarifies_ban_third_party_claude_access/). Server-side enforcement targets tools that proxy inference (the OpenCode case).

burnrate is not in that category. It hits a read-only meta endpoint, identical to what `/usage` does. As of this writing, every menu bar tool in this space (CodexBar, ClaudeUsageBar, claude-usage-systray, ClaudeMeter, and others) does the same with no enforcement action.

If Anthropic ever extends enforcement to read-only endpoints, burnrate's live-windows half goes dark. Every other field continues to work from local files. The pattern cards do not depend on the network call.

### Keychain

burnrate reads one Keychain item: `Claude Code-credentials`, the same one the Claude Code CLI writes when you sign in. burnrate does not write to Keychain. To stop the macOS access prompt on every launch:

1. Open **Keychain Access**, search for `Claude Code-credentials`
2. Open the item → **Access Control** → add `burnrate.app` under "Always allow access by these applications"
3. Relaunch burnrate

Prefer adding burnrate specifically over "allow all applications."

### What burnrate does not do

- No telemetry, no crash reporting, no anonymous analytics
- No filesystem scanning. Only reads the explicit paths used by features you have on
- No Screen Recording, no Accessibility, no Automation entitlements
- No password storage, no secondary accounts

## Development

```bash
swift build
bash scripts/run.sh                  # debug build, sign, launch
```

One-time code-signing setup (prevents repeated Keychain prompts during dev):

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

Pushing a `v*` tag triggers `.github/workflows/release.yml` to rebuild and attach the artifact automatically.

## Credits

Inspired by [ccusage](https://github.com/ryoppippi/ccusage) (MIT, ryoppippi) for proving the local-files-first approach, and by [CodexBar](https://github.com/steipete/CodexBar) (MIT, steipete) for the menu bar pattern in this category.

## License

MIT. See [LICENSE](./LICENSE).
