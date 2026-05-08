# iTerm2 AI CLI Tab Color

> Visual idle monitoring for Claude Code and Codex CLI sessions in iTerm2.

[中文说明](README.zh-CN.md)

When you run multiple Claude Code or Codex CLI sessions across iTerm2 tabs, it is hard to tell which ones are waiting for your input and how long they have been idle. This tool colors iTerm2 tabs automatically so you can see where attention is needed.

![demo](../../assets/demo.gif)

## Behavior

| Tab Color | Meaning | Trigger |
|-----------|---------|---------|
| Green | AI CLI just finished and is waiting for you | `Stop` hook writes an idle state |
| Yellow | Waiting for a while | Idle time exceeds `THRESHOLD_YELLOW` (default: 10 minutes) |
| Red | Waiting too long | Idle time exceeds `THRESHOLD_RED` (default: 20 minutes) |
| White | Active, processing, or no idle state | Active tab, prompt/tool activity, or all idle states cleared |

Important rules:

- Only inactive tabs get colored. The currently focused tab stays white because you are already looking at it.
- Colors are tab-level, not pane-level. If a tab has multiple panes, all panes in that tab share the same tab color.
- Same-tab aggregation is conservative. If several AI sessions in the same tab are idle, the tab uses the most severe color among them: red over yellow over green.
- Starting work in one pane clears that pane/session state only. If another pane in the same tab still has an idle red state, the tab remains red.
- When all AI CLI sessions in a tab are processing, active, closed, or back at the shell, the tab returns to white.

## Features

- One-command install with `bash tools/iterm2-tab-color/install.sh` from the repo root
- Production uninstall with `bash tools/iterm2-tab-color/uninstall.sh`
- Claude Code and Codex CLI support through the same hook script
- Split-pane support: one consistent color per iTerm2 tab
- Active-tab awareness: colors work as notification badges
- Fast exit cleanup: panes that return to `zsh`/`bash` are pruned quickly without increasing heavy process scans
- Configurable thresholds, colors, poll interval, and concurrency hint
- macOS launchd daemon with login auto-launch, KeepAlive, and iTerm2 reconnect support

## Quick Start

### Prerequisites

- macOS + [iTerm2](https://iterm2.com/)
- Python 3.10+
- `iterm2` Python package
- Claude Code CLI and/or Codex CLI

### Install

```bash
pip3 install iterm2
git clone https://github.com/doingdd/iterm2-claude-tab-color.git
cd iterm2-claude-tab-color
bash tools/iterm2-tab-color/install.sh
```

The installer will:

- Create symlinks for Claude/Codex hooks
- Write a real launchd plist to `~/Library/LaunchAgents/com.duying.tab-color-daemon.plist`
- Register Claude Code hooks: `Stop` and `PreToolUse`
- Create/update `~/.codex/hooks.json` and register silent Codex hooks: `Stop`, `PreToolUse`, and `UserPromptSubmit`
- Start the background daemon and enable auto-launch on login
- Back up JSON settings before writing `.bak.YYYYmmdd-HHMMSS` files
- Print each created, updated, backed up, and started item

Preview without writing:

```bash
bash tools/iterm2-tab-color/install.sh --dry-run
```

Uninstall:

```bash
bash tools/iterm2-tab-color/uninstall.sh
```

The uninstaller keeps `~/.claude/idle_state` and daemon logs by default. To remove them:

```bash
bash tools/iterm2-tab-color/uninstall.sh --purge-state
```

### Verify

```bash
launchctl list | grep tab-color
tail -f ~/.claude/idle_state/daemon.log
```

Open a Claude Code or Codex CLI session, ask it something, and wait for it to finish. The tab should turn green when the session becomes idle.

## Configuration

Edit `tools/iterm2-tab-color/config.sh`:

```bash
# Time thresholds in minutes
THRESHOLD_YELLOW=10
THRESHOLD_RED=20

# Tab colors, RGB 0-255
COLOR_GREEN_R=30;   COLOR_GREEN_G=180;  COLOR_GREEN_B=30
COLOR_YELLOW_R=220; COLOR_YELLOW_G=160; COLOR_YELLOW_B=0
COLOR_RED_R=200;    COLOR_RED_G=40;     COLOR_RED_B=40

# Heavy process scan interval in seconds
POLL_INTERVAL=30

# Optional log hint
CONCURRENT_TARGET=3
```

After editing, restart the daemon:

```bash
launchctl kickstart -k gui/$(id -u)/com.duying.tab-color-daemon
```

## Architecture

```text
Claude / Codex hook events
        |
        v
tab_color_hook.sh
        |
        | writes ~/.claude/idle_state/*.json
        v
tab_color_daemon.py
        |
        | iTerm2 Python API
        v
iTerm2 tab color
```

### Hook Script

`tab_color_hook.sh` handles both Claude Code and Codex CLI.

- `Stop`: sets green quickly through terminal escape sequences and writes an idle state file.
- `PreToolUse` / `UserPromptSubmit`: resets the tab, removes that session state file, and starts `reset_tab.py` in the background for a fast full-tab reset.
- Codex hooks are registered as silent commands because Codex Stop hooks validate stdout as JSON.

### Daemon

`tab_color_daemon.py` is managed by launchd and is the single writer for iTerm2 API color changes.
It starts the iTerm2 Python API with retry enabled, so iTerm2 restarts, upgrades, or websocket disconnects can reconnect instead of leaving idle states unprocessed.

- Watch loop, every 500ms: reads state files, does lightweight cleanup for panes that returned to shell, applies tab colors, and resets tabs whose last state disappeared.
- Fast exit cleanup, every 1s at most: uses iTerm2 `jobName` only, so it does not increase `ps`/`pgrep` process-scan load.
- Poller, every `POLL_INTERVAL` seconds: performs heavier orphan cleanup, checks actual Claude/Codex process presence, upgrades green to yellow/red, and writes metadata only.

### State Model

Each idle AI session has one JSON file under `~/.claude/idle_state/`.

State files include:

- `agent`: `claude` or `codex`
- `iterm2_session`: iTerm2 pane id, usually `w0t1p2:UUID`
- `agent_session`: agent session id
- `idle_since`: Unix timestamp
- `color_stage`: `green`, `yellow`, or `red`

The daemon groups state by iTerm2 tab. A tab is white only when it is active or when no idle state remains for that tab.

## Runtime Files

- `~/.claude/hooks/tab_color_hook.sh` -> symlink to this tool directory
- `~/.codex/hooks/tab_color_hook.sh` -> symlink to this tool directory
- `~/.claude/idle_state/*.json` -> per-session idle state
- `~/.claude/idle_state/daemon.log` -> daemon log
- `~/Library/LaunchAgents/com.duying.tab-color-daemon.plist` -> generated launchd plist file

## Commands

```bash
# Check daemon status
launchctl list | grep tab-color

# View daemon log
tail -f ~/.claude/idle_state/daemon.log

# Restart daemon
launchctl kickstart -k gui/$(id -u)/com.duying.tab-color-daemon

# Remove runtime files
launchctl unload ~/Library/LaunchAgents/com.duying.tab-color-daemon.plist
rm ~/.claude/hooks/tab_color_hook.sh
rm ~/.codex/hooks/tab_color_hook.sh
rm ~/Library/LaunchAgents/com.duying.tab-color-daemon.plist
```

After uninstalling, remove `tab_color_hook.sh` entries from `~/.claude/settings.json` and `~/.codex/hooks.json` if needed.

## Development

```bash
bash -n install.sh uninstall.sh tab_color_hook.sh
python3 -m py_compile tab_color_daemon.py reset_tab.py test_daemon.py
python3 -m unittest test_daemon.py
```

Run these commands from `tools/iterm2-tab-color/`.

## License

[MIT](../../LICENSE)
