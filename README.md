# 卷死你三件套

> The Human Bottleneck Kit for AI coding workflows. The AI is not slow. You are.

[中文说明](README.zh-CN.md)

This is a tiny, slightly unhinged toolset for developers who run too many AI coding sessions at once and still want more throughput.

Claude Code finishes. Codex finishes. Another tab turns idle. You do not notice, because your human brain is busy staring at the wrong terminal like a productivity tax with a pulse.

So this repo does one thing very honestly: it makes your bottleneck visible.

![Six AI coding sessions across terminal tabs, color-coded by idle pressure](assets/readme/hero-ai-tabs.png)

## Why This Exists

AI agents are getting faster. Your attention is not.

If you run one session, you can babysit it. If you run five, you need traffic control. If you run ten, you need a shame machine with colors.

This project is that machine.

- Switch Claude Code providers without spelunking through config files.
- Split leader and teammate traffic in Agent Team workflows.
- Color idle iTerm2 tabs so waiting sessions start yelling silently.
- Watch Claude Code and Codex plan usage so 5h windows do not idle while the 7d budget still has room.

## The Real Height

This is not a tool for manually feeding AI forever.

First, it squeezes you: your idle time, your context switching, your confidence that you can keep ten AI sessions moving by sheer will. At some point, you hit the wall. You cannot open more windows. You cannot switch more tabs. You cannot answer another "should I continue?" without wondering why you are still the scheduler.

Then the right questions appear:

```text
Why does it keep asking me?
Why can't it decide the next step?
Why am I still the human event loop?
Why can't these sessions queue, split work, verify, and ship?
```

Exactly. You start harnessing.

The colors push the human operator to the limit. The next layer removes the human from the loop. That is the real point of this kit: not to make you feed AI harder, but to make it obvious that the next productivity jump is not more terminal tabs. It is a more autonomous agent harness.

![Progression from more terminal windows, to human bottleneck, to autonomous agent harness](assets/readme/harness-evolution.png)

## The Three Tools

| Tool | Status | What It Does | Why You Care |
|------|--------|--------------|--------------|
| Claude Provider Router | Available | Starts Claude Code through `c`, switches providers by number, and routes Team traffic by role | Burn the right quota on the right job instead of manually juggling endpoints |
| iTerm2 Tab Color | Available | Turns inactive AI CLI tabs green, yellow, or red when Claude Code or Codex is waiting for you | Your terminal becomes a cockpit instead of a graveyard of forgotten prompts |
| Burn AI | Early | Tracks local Claude Code and Codex coding plan usage, then warns when your burn pace is too slow, too fast, or close to a limit | Stop wasting expensive plan windows without blindly maxing every 5h cycle |

![Three-tool kit overview: provider routing, tab color pressure, and plan usage pacing](assets/readme/toolkit-overview.png)

## The Attention Abuse Protocol

| Color | Meaning | Emotional Damage |
|-------|---------|------------------|
| Green | The AI just finished and is waiting | "Nice, go collect the result." |
| Yellow | It has been waiting for a while | "You are losing the parallelism game." |
| Red | It has been waiting too long | "The machine is ready. The bottleneck has a keyboard." |
| White | Active tab, processing, or clean state | "Nothing is screaming here." |

Only inactive tabs get colored. The tab you are looking at stays white because notifications should point at what you are missing, not decorate what you already see.

![Tab color escalation from white to green to yellow to red, then back to white after response](assets/readme/tab-color-escalation.png)

## Quick Start

Clone the repo:

```bash
git clone https://github.com/doingdd/iterm2-claude-tab-color.git
cd iterm2-claude-tab-color
```

Use the Claude Provider Router:

```bash
cd tools/claude-provider-router
cp config.env.example config.env
chmod 600 config.env
./c 0
```

Install iTerm2 Tab Color:

```bash
pip3 install iterm2
bash tools/iterm2-tab-color/install.sh
```

Then open several Claude Code or Codex CLI sessions, ask them to do real work, and stop pretending you can remember which tab needs you.

## What It Feels Like

Before:

```text
tab 1: probably done?
tab 2: maybe still running?
tab 3: forgot this existed
tab 4: why is my fan loud?
tab 5: oh no
```

After:

```text
green  -> collect now
yellow -> aging badly
red    -> stop cosplaying as a scheduler
white  -> currently active or clean
```

## Repository Layout

```text
.
├── tools/
│   ├── claude-provider-router/
│   ├── iterm2-tab-color/
│   └── burn-ai/
├── assets/
├── AGENTS.md
├── CLAUDE.md
├── README.md
└── README.zh-CN.md
```

Root-level `install.sh` and `uninstall.sh` are intentionally not provided. Each tool owns its own install and uninstall path.

## Tool Docs

- [Claude Provider Router](tools/claude-provider-router/README.md)
- [iTerm2 Tab Color](tools/iterm2-tab-color/README.md)
- [iTerm2 Tab Color Chinese README](tools/iterm2-tab-color/README.zh-CN.md)
- [Burn AI](tools/burn-ai/README.md)

## Safety Notes

- Do not commit `tools/claude-provider-router/config.env`; use `config.env.example` as the template.
- Burn AI does not manage login state or credentials; it only reads local usage data already produced by Claude Code and Codex.
- Changes to tab color behavior, state cleanup, process detection, or hook semantics should be reviewed as behavior changes, not bundled into directory work.

## Development Checks

For iTerm2 Tab Color changes:

```bash
bash -n tools/iterm2-tab-color/install.sh tools/iterm2-tab-color/uninstall.sh tools/iterm2-tab-color/tab_color_hook.sh
python3 -m py_compile tools/iterm2-tab-color/tab_color_daemon.py tools/iterm2-tab-color/reset_tab.py tools/iterm2-tab-color/test_daemon.py
python3 -m unittest tools/iterm2-tab-color/test_daemon.py
```

## License

[MIT](LICENSE)
