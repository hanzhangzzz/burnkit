# Changelog

## BurnKit v0.1.0

First unified release of the BurnKit toolset.

### Added

- `bin/burnkit` release entry point for guided setup, doctor checks, router launch, and Burn AI command forwarding.
- `scripts/e2e-install-verify.sh` for dry-run and real local install verification, including router `config.env` preservation checks.
- Claude Provider Router as the provider and Agent Team routing layer.
- iTerm2 Tab Color as the idle-session pressure layer for Claude Code and Codex CLI.
- Burn AI as the local Claude Code / Codex plan usage and burn-rate layer.
- README launch narrative for the path from more tabs, to human bottleneck, to agent harness.

### Install

```bash
git clone https://github.com/doingdd/iterm2-claude-tab-color.git burnkit
cd burnkit
bin/burnkit doctor
bin/burnkit install router
pip3 install iterm2
bin/burnkit install tabs
bin/burnkit install burn
```

### Safety

- Root-level `install.sh` / `uninstall.sh` are intentionally not provided.
- `bin/burnkit` only orchestrates setup; each tool keeps its own real installer and uninstall path.
- Burn AI does not manage login state or credentials.
- Provider tokens stay in `tools/claude-provider-router/config.env`, which must not be committed.
