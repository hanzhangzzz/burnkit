# 卷死你三件套

> Tools for running high-concurrency AI coding workflows with clearer routing, visibility, and operator feedback.

[中文说明](README.zh-CN.md)

This repository is a toolset, not a single iTerm2 tab color project.

## Tools

| Tool | Path | Status | Purpose |
|------|------|--------|---------|
| Claude Provider Router | `tools/claude-provider-router/` | Available | Switch Claude Code providers with `c`, and route leader/teammate traffic in Agent Team workflows |
| iTerm2 Tab Color | `tools/iterm2-tab-color/` | Available | Color inactive iTerm2 tabs when Claude Code or Codex CLI sessions are idle and waiting for input |
| Third tool | TBD | Reserved | Keep as a placeholder until the scope is clear |

## Repository Layout

```text
.
├── tools/
│   ├── claude-provider-router/
│   └── iterm2-tab-color/
├── assets/
├── AGENTS.md
├── CLAUDE.md
├── README.md
└── README.zh-CN.md
```

Root-level `install.sh` and `uninstall.sh` are intentionally not provided. Run each tool from its own directory or documented path.

## Quick Start

Claude Provider Router:

```bash
cd tools/claude-provider-router
cp config.env.example config.env
chmod 600 config.env
./c 0
```

iTerm2 Tab Color:

```bash
pip3 install iterm2
bash tools/iterm2-tab-color/install.sh
```

For details, read each tool README:

- `tools/claude-provider-router/README.md`
- `tools/iterm2-tab-color/README.md`
- `tools/iterm2-tab-color/README.zh-CN.md`

## Maintenance Rules

- Do not implement the third tool until its scope is explicit.
- Do not commit `tools/claude-provider-router/config.env`; only `config.env.example` belongs in the repo.
- Keep `tools/iterm2-tab-color/` behavior stable during directory migration. Path fixes are allowed; color/state behavior changes need a separate plan.
- See `AGENTS.md` for the full project baseline.

## Verification

For iTerm2 Tab Color changes:

```bash
bash -n tools/iterm2-tab-color/install.sh tools/iterm2-tab-color/uninstall.sh tools/iterm2-tab-color/tab_color_hook.sh
python3 -m py_compile tools/iterm2-tab-color/tab_color_daemon.py tools/iterm2-tab-color/reset_tab.py tools/iterm2-tab-color/test_daemon.py
python3 -m unittest tools/iterm2-tab-color/test_daemon.py
```

## License

[MIT](LICENSE)
