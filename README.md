# iTerm2 Claude Tab Color 🚦

> Visual idle monitoring for Claude Code sessions in iTerm2.

When you run multiple Claude Code sessions across iTerm2 tabs, it's hard to track which ones are waiting for your input and how long they've been idle. This tool automatically colors your tabs so you know **at a glance** where Claude needs you.

![demo](assets/demo.gif)

## How It Works

| Tab Color | Meaning | Trigger |
|-----------|---------|---------|
| 🟢 **Green** | Claude just finished, waiting for you | Immediately after Claude stops |
| 🟡 **Yellow** | Idle for a while, check soon | After `THRESHOLD_YELLOW` minutes (default: 10) |
| 🔴 **Red** | Idle too long, needs attention | After `THRESHOLD_RED` minutes (default: 20) |
| ⬜ **White** | Active / processing | You're on this tab, or Claude is working |

**Only tabs you're NOT looking at get colored.** Your active tab stays white — you always know where you are.

![split pane](assets/split-pane.png)

## Features

- **One-command install** — `bash install.sh` does everything
- **Split pane support** — colors apply to the entire tab, not just one pane
- **Active tab awareness** — current tab stays white, colored tabs act as notification badges
- **Fully configurable** — time thresholds, colors, poll intervals
- **Auto-restart** — managed by macOS launchd, survives crashes and reboots
- **Concurrent session hints** — logs remind you when you can open more sessions

## Quick Start

### Prerequisites

- macOS + [iTerm2](https://iterm2.com/)
- Python 3.10+
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) CLI

### Install

```bash
pip3 install iterm2
git clone https://github.com/doingdd/iterm2-claude-tab-color.git
cd iterm2-claude-tab-color
bash install.sh
```

That's it. The installer will:
- Create symlinks for hooks and launchd plist
- Register Claude Code hooks (`Stop` + `PreToolUse`)
- Start the background daemon (auto-launches on login)

### Verify

```bash
launchctl list | grep tab-color
tail -f ~/.claude/idle_state/daemon.log
```

Open a Claude Code session, ask it something, wait for it to finish — your tab should turn green.

## Configuration

Edit `config.sh` (the only file you need to touch):

```bash
# Time thresholds (minutes)
THRESHOLD_YELLOW=10    # Idle → yellow
THRESHOLD_RED=20       # Idle → red

# Tab colors (RGB 0-255)
COLOR_GREEN_R=30;   COLOR_GREEN_G=180;  COLOR_GREEN_B=30
COLOR_YELLOW_R=220; COLOR_YELLOW_G=160; COLOR_YELLOW_B=0
COLOR_RED_R=200;    COLOR_RED_G=40;     COLOR_RED_B=40

# Poll interval (seconds)
POLL_INTERVAL=30

# Concurrent session target (optional hint in logs)
CONCURRENT_TARGET=3
```

After editing, restart the daemon:

```bash
launchctl kickstart -k gui/$(id -u)/com.duying.tab-color-daemon
```

## Architecture

```
┌─────────────────┐       ┌──────────────────┐       ┌─────────────────┐
│  Claude Code     │       │  Hook Script      │       │  Daemon Process │
│                  │ Stop  │  tab_color_hook   │ files  │  tab_color_     │
│  hook events ────►──────►  .sh              │───────►  daemon.py     │
│                  │ Pre   │                   │ watch  │                 │
│                  │ Tool  │  + ANSI escape    │ dir    │  + iTerm2 API   │
│                  │ Use   │  instant feedback │        │  + color upgrade│
└─────────────────┘       └──────────────────┘        └─────────────────┘
```

Three components work together:

1. **Hook script** (`tab_color_hook.sh`) — triggered by Claude Code's Stop/PreToolUse events
   - **Stop**: sets green via ANSI escape (instant feedback on active pane), writes timestamp file
   - **PreToolUse**: resets color, deletes timestamp file, calls API to reset entire tab in background

2. **Daemon** (`tab_color_daemon.py`) — background process managed by launchd (single-writer architecture)
   - **Watch loop (500ms)**: the ONLY loop that writes colors via iTerm2 API. Reads state files + active tab status → applies correct color per session
   - **Poller (30s)**: only updates state file metadata (orphan cleanup, same-tab dedup, color stage upgrade green→yellow→red). Never touches iTerm2 API
   - Tracks active tab: colors only non-active tabs (notification badge pattern)
   - Supports split panes: colors all panes in the same tab uniformly

3. **Reset script** (`reset_tab.py`) — called by PreToolUse hook in background for instant full-tab reset

## File Structure

```
iterm2-claude-tab-color/
├── config.sh         # User configuration (edit this)
├── install.sh        # One-command installer
├── tab_color_hook.sh # Claude Code hook script
├── tab_color_daemon.py  # Background daemon (launchd)
├── reset_tab.py      # Fast API reset (called by hook)
├── test_daemon.py    # Unit tests (41 tests, no iTerm2 dependency)
├── LICENSE           # MIT
└── README.md
```

Runtime files:
- `~/.claude/hooks/tab_color_hook.sh` → symlink to source
- `~/.claude/idle_state/*.json` → per-session idle state
- `~/.claude/idle_state/daemon.log` → daemon log

## Commands

```bash
# Check daemon status
launchctl list | grep tab-color

# View live log
tail -f ~/.claude/idle_state/daemon.log

# Restart daemon (after config change)
launchctl kickstart -k gui/$(id -u)/com.duying.tab-color-daemon

# Uninstall
launchctl unload ~/Library/LaunchAgents/com.duying.tab-color-daemon.plist
rm ~/.claude/hooks/tab_color_hook.sh
rm ~/Library/LaunchAgents/com.duying.tab-color-daemon.plist
# Then remove tab_color_hook entries from ~/.claude/settings.json
```

## Technical Notes

**Two color-setting mechanisms**: ANSI escape codes (instant, but only active pane) + iTerm2 Python API (covers all panes, ~1s delay). They work together: hooks give instant feedback, daemon ensures split-pane consistency.

**Active tab stays white**: Colors are notification badges — you don't need a badge on the tab you're already looking at.

**ITERM_SESSION_ID format**: Environment variable is `w0t1p2:UUID`, but iTerm2 API only accepts pure UUID. The daemon strips the prefix via `extract_uuid()`.

**TTY detection in hooks**: Claude Code pipes hook stdout, so hooks can't write ANSI escapes to stdout directly. `find_claude_tty()` walks the parent process chain to find the real tty device and writes to `/dev/ttysXXX` directly.

## License

[MIT](LICENSE)

---

## 中文说明

用 tab 颜色告诉你哪些 Claude Code session 在等你。

### 解决什么问题

开多个 iTerm2 tab 跑 Claude Code 时，不知道哪个 tab 的 Claude 已经回复完在等你、等了多久。这个工具让 tab 颜色自动反映空闲状态，一眼就知道该切到哪个 tab。

### 颜色规则

| 颜色 | 含义 | 触发条件 |
|------|------|----------|
| **绿色** | Claude 刚回复完，等你输入 | Claude Stop 后立即生效 |
| **黄色** | 等了一会儿了，该去看看了 | 超过 10 分钟（可配置） |
| **红色** | 等很久了，赶紧去处理 | 超过 20 分钟（可配置） |
| **白色** | 正常状态（活跃 / 处理中） | 你正在这个 tab，或 Claude 在处理 |

**只有你不在的 tab 才上色。** 当前活跃的 tab 始终是白色 — 你永远知道自己在哪。

### 安装

```bash
pip3 install iterm2
git clone https://github.com/doingdd/iterm2-claude-tab-color.git
cd iterm2-claude-tab-color
bash install.sh
```

### 配置

编辑 `config.sh`，修改时间阈值和颜色。改完后重启：

```bash
launchctl kickstart -k gui/$(id -u)/com.duying.tab-color-daemon
```

### 卸载

```bash
launchctl unload ~/Library/LaunchAgents/com.duying.tab-color-daemon.plist
rm ~/.claude/hooks/tab_color_hook.sh
rm ~/Library/LaunchAgents/com.duying.tab-color-daemon.plist
# 然后手动从 ~/.claude/settings.json 的 hooks 中移除 tab_color_hook 相关条目
```

详细技术说明见上方英文部分。
