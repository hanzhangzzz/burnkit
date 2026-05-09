# Burn AI

Burn AI is BurnKit's plan-burn layer. It monitors local Claude Code and Codex coding plan usage, then tells you whether your current pace is under-burning, on track, over-burning, or close to a limit.

It does not manage login state, credentials, or API keys. It only reads usage data already produced by local Claude Code and Codex tooling.

## Quick Start

From the BurnKit repo root:

```bash
bin/burnkit install burn
bin/burnkit status --refresh
```

Direct package flow:

```bash
npx burn-ai install
burn-ai doctor
burn-ai status
```

`install` creates a local runtime at `~/.burn-ai/app`, a user-level CLI shim at `~/.local/bin/burn-ai`, a launchd agent, a default config file, and a SwiftBar menu bar plugin. Make sure `~/.local/bin` is in your `PATH`.

## Commands

| Command | Purpose |
|---------|---------|
| `burn-ai install` | Install runtime, launchd checker, SwiftBar host/plugin, and Claude ingest when safe |
| `burn-ai uninstall` | Remove Burn AI managed launchd/status line/plugin config |
| `burn-ai doctor` | Check local Codex/Claude usage sources and notification backend |
| `burn-ai status` | Print 5h/7d usage and burn state from `~/.burn-ai/status.json` |
| `burn-ai status --json` | Print the same status snapshot written to `~/.burn-ai/status.json` |
| `burn-ai status --refresh` | Re-collect local usage before printing status |
| `burn-ai menubar render` | Print SwiftBar-compatible menu text from `~/.burn-ai/status.json` |
| `burn-ai menubar install` | Install the SwiftBar plugin wrapper |
| `burn-ai menubar uninstall` | Remove the Burn AI managed SwiftBar plugin |
| `burn-ai ingest claude-statusline` | Read Claude Code status line JSON from stdin and cache usage |

## Install Behavior

`burn-ai install` is designed to be repeatable.

- From `npx burn-ai install` or `npx --no-install burn-ai install`, it copies the current package into `~/.burn-ai/app` through a temporary directory, then restarts launchd.
- From the installed shim `burn-ai install`, it detects that it is already running from `~/.burn-ai/app`, skips runtime self-copy, and still refreshes the CLI shim, SwiftBar plugin, and launchd agent.
- The launchd job runs `~/.burn-ai/app/dist/cli.js daemon --once` every 300 seconds.
- The installer does not overwrite user-managed Claude Code status line scripts.

## Claude Code Status Line

If you do not have a Claude Code status line, `burn-ai install` can create a minimal one.

If you already have one, Burn AI will not overwrite it. Add this near the top of your own script:

```bash
input="$(cat)"
printf "%s" "$input" | node "$HOME/.burn-ai/app/dist/cli.js" ingest claude-statusline >/dev/null

# Make the rest of your script read from "$input" instead of stdin.
```

## Codex

Burn AI reads Codex `payload.rate_limits` from local `~/.codex` JSONL session data. If no such data exists, run Codex CLI or Codex App once and complete a normal interaction.

## Profiles

Set `BURN_AI_PROFILE=high` for the more aggressive profile. The default is `low`.

```bash
BURN_AI_PROFILE=high burn-ai status
```

Both profiles are constrained by the 7d budget. Burn AI does not treat "fill every 5h window" as the goal.

## Provider Config

`burn-ai install` creates `~/.burn-ai/config.json`:

```json
{
  "providers": ["codex", "claude"]
}
```

Remove a provider from this list if you do not want Burn AI to monitor it. For one-off runs, `BURN_AI_PROVIDERS=codex burn-ai status --refresh` also works.

## Menu Bar

The first menu bar implementation uses SwiftBar as a thin host. Burn AI still owns collection and state; the SwiftBar plugin only runs `burn-ai menubar render` and reads `~/.burn-ai/status.json`.

`burn-ai install` checks for SwiftBar and installs it with Homebrew cask when it is missing. It installs the Burn AI plugin into SwiftBar's configured `PluginDirectory`, not blindly into a hardcoded default directory, then opens SwiftBar.

```bash
burn-ai menubar install
```

If SwiftBar is not installed, `burn-ai doctor` will report it. If SwiftBar already has a custom plugin folder, Burn AI uses that folder.

The menu bar title shows the highest-priority provider state, including both 5h and 7d usage:

```text
Burn OK Codex 5h 4% / 7d 36%
```

The dropdown stays read-only and shows usage, reset time, target range, data age, and warnings. SwiftBar is a host dependency; `burn-ai uninstall` removes the Burn AI plugin but does not uninstall SwiftBar itself.

## Runtime Files

| Path | Purpose |
|------|---------|
| `~/.burn-ai/app/` | Stable runtime copy used by launchd, Claude ingest hints, and SwiftBar |
| `~/.burn-ai/config.json` | Provider selection, default `["codex", "claude"]` |
| `~/.burn-ai/status.json` | Stable display-layer entry point |
| `~/.burn-ai/codex/latest.json` | Latest normalized Codex usage |
| `~/.burn-ai/claude/latest.json` | Latest normalized Claude usage after status line ingest |
| `~/.local/bin/burn-ai` | CLI shim pointing at the stable runtime |
| `~/Library/LaunchAgents/com.duying.burn-ai.plist` | macOS launchd agent |
| SwiftBar `PluginDirectory` / `burn-ai.1m.js` | Menu bar plugin wrapper |

## Notifications

On macOS, Burn AI uses `terminal-notifier` when available and attaches a dynamic data card as the notification content image.

The card shows provider, 5h used percentage, state label, target range, and reset countdown. This avoids asking users to infer meaning from a red/yellow icon.

If `terminal-notifier` is unavailable, Burn AI falls back to `osascript display notification`, which uses the system default notification appearance.

See [plan.md](plan.md) for the current product and technical baseline.
