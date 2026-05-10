# BurnKit

> Overclock the human. Then build the harness.

[中文说明](README.zh-CN.md)

BurnKit is a three-tool kit for developers running Claude Code and Codex in parallel. It routes work to the right provider, colors idle terminal tabs when AI is waiting for you, and tracks plan burn before expensive windows quietly evaporate.

Chinese spirit name: `卷死你三件套`.

This is not about going productivity-crazy, and it is not about making you go crazy either.

BurnKit exposes the awkward truth inside AI coding: models keep getting faster, but the workflow still jams around the human operator. You think you need a stronger model. Then you notice the real drag: provider choice, idle sessions, context switching, wasted plan windows, and the person who keeps answering "should I continue?"

BurnKit turns those hidden costs into signals. When the signals become too many to handle manually, the next question becomes obvious: how do you make AI ask less, queue work, split tasks, verify results, and ship without constant babysitting?

That is the harness entrance.

![burnkit status — real-time plan usage and burn pace](assets/demo-status.gif)

## What You Get

| Tool | Command | Job | Why It Exists |
|------|---------|-----|---------------|
| Claude Provider Router | `burnkit router 0` | Start Claude Code through numbered providers and route Agent Team leader/teammate traffic | Put the right job on the right model, endpoint, and quota |
| iTerm2 Tab Color | `burnkit install tabs` | Color inactive Claude Code / Codex tabs when they are waiting for you | Turn forgotten prompts into visible pressure |
| Burn AI | `burnkit status --refresh` | Track local Claude Code / Codex plan usage and burn pace | Stop wasting expensive windows without blindly maxing every cycle |

![SwiftBar menubar — Codex and Claude burn pace at a glance](assets/menubar-screenshot.png)

![burnkit install all --dry-run](assets/demo-install.gif)

## Let Your Agent Install It

Copy this into your AI coding agent and let it handle the install:

```text
Install BurnKit for me in this repo.

Rules:
- First run `scripts/e2e-install-verify.sh --dry-run`.
- Run `bin/burnkit doctor`.
- Dry-run each installer before any real install:
  - `bin/burnkit install router --dry-run`
  - `bin/burnkit install tabs --dry-run --skip-python-check`
  - `bin/burnkit install burn --dry-run`
- Do not overwrite `tools/claude-provider-router/config.env`. If it already exists, preserve it byte-for-byte.
- Before real install, tell me exactly what files and system state will be changed, then wait for my explicit confirmation.
- After I confirm, run the real install and verify it with `scripts/e2e-install-verify.sh --real`.
```

The important part: `config.env` contains provider tokens. A correct agent must preserve it if it already exists.

## Install

```bash
npx burnkit install all
```

Or from source:

```bash
git clone https://github.com/hanzhangzzz/burnkit.git
cd burnkit
bin/burnkit install all
```

Then edit your provider config:

```bash
$EDITOR tools/claude-provider-router/config.env
```

Run Claude Code through BurnKit:

```bash
burnkit router 0
burnkit router team 7 0
```

Check plan burn:

```bash
burnkit status --refresh
```

Uninstall everything:

```bash
burnkit uninstall all
```

## The Loop It Creates

```text
1. Start more AI sessions.
2. Watch idle tabs turn green, yellow, and red.
3. Use Burn AI to see whether your 5h / 7d plan windows are being wasted.
4. Hit the human scheduling limit.
5. Start designing a real agent harness.
```

This is the point. BurnKit is not a forever-babysitting tool. It is a pressure rig. It squeezes your idle time, your context switching, and your confidence that one human can keep ten agent sessions moving by hand.

At the limit, the useful questions stop being motivational and start being architectural:

```text
Why does it keep asking me?
Why can't it decide the next step?
Why am I still the human event loop?
Why can't these sessions queue, split work, verify, and ship?
```

Exactly. You start harnessing.

## Command Map

| Command | Purpose |
|---------|---------|
| `burnkit doctor` | Check local prerequisites and tool readiness |
| `burnkit install router` | Create `tools/claude-provider-router/config.env` from the template when missing |
| `burnkit install tabs` | Run the iTerm2 Tab Color installer |
| `burnkit install burn` | Install/build Burn AI, then run `burn-ai install` |
| `burnkit install all` | Install CLI shim, router, tab color, and Burn AI in order |
| `burnkit uninstall all` | Uninstall tab color, Burn AI, and CLI shim |
| `burnkit router 0` | Start Claude Code through provider config `0` |
| `burnkit router team 7 0` | Start Agent Team routing: leader on `7`, teammate on `0` |
| `burnkit burn doctor` | Forward to Burn AI CLI |
| `burnkit status --refresh` | Refresh and print plan usage state |

Each tool still owns its own runtime files, safety checks, and uninstall path.

## Tab Pressure

| Color | Meaning | Operator Signal |
|-------|---------|-----------------|
| Green | AI just finished and is waiting | Collect the result now |
| Yellow | It has waited for a while | Your parallelism is leaking |
| Red | It has waited too long | The machine is ready; the human is late |
| White | Active tab, processing, or clean state | No attention needed here |

Only inactive tabs get colored. The tab you are looking at stays white because notifications should point at what you are missing.

![iTerm2 tab colors — green, yellow, red idle indicators](assets/demo-tab-color.gif)

## Repository Layout

```text
.
├── bin/
│   └── burnkit
├── tools/
│   ├── claude-provider-router/
│   ├── iterm2-tab-color/
│   └── burn-ai/
├── assets/
├── package.json
├── AGENTS.md
├── CLAUDE.md
├── README.md
└── README.zh-CN.md
```

## Tool Docs

- [Claude Provider Router](tools/claude-provider-router/README.md)
- [iTerm2 Tab Color](tools/iterm2-tab-color/README.md)
- [iTerm2 Tab Color Chinese README](tools/iterm2-tab-color/README.zh-CN.md)
- [Burn AI](tools/burn-ai/README.md)

## Safety Notes

- `tools/claude-provider-router/config.env` contains tokens and must not be committed.
- Burn AI does not manage login state, credentials, or private usage APIs. It reads local usage data already produced by Claude Code and Codex.
- Burn AI does not overwrite existing Claude Code status line scripts. If one exists, it prints an ingest snippet for manual integration.
- Tab color behavior, state cleanup, process detection, hook events, and daemon scheduling are behavior changes. Do not bundle them with docs or release polish.

## Development Checks

For the release entry point:

```bash
bash -n bin/burnkit
bin/burnkit --help
bin/burnkit doctor
scripts/e2e-install-verify.sh --dry-run
```

For real install verification on a local machine:

```bash
scripts/e2e-install-verify.sh --real
```

The e2e verifier includes a sentinel test that proves an existing `tools/claude-provider-router/config.env` is preserved instead of overwritten.

For iTerm2 Tab Color changes:

```bash
bash -n tools/iterm2-tab-color/install.sh tools/iterm2-tab-color/uninstall.sh tools/iterm2-tab-color/tab_color_hook.sh
python3 -m py_compile tools/iterm2-tab-color/tab_color_daemon.py tools/iterm2-tab-color/reset_tab.py tools/iterm2-tab-color/test_daemon.py
python3 -m unittest tools/iterm2-tab-color/test_daemon.py
```

For Burn AI changes:

```bash
cd tools/burn-ai
npm ci
npm test
npm run build
npx --no-install burn-ai install
burn-ai install
npx --no-install burn-ai doctor --dry-run
npx --no-install burn-ai status --fixtures
npx --no-install burn-ai menubar render
git diff --check
```

## License

[MIT](LICENSE)
