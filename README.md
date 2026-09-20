# BurnKit

BurnKit is the directory for three standalone tools built for parallel AI coding workflows. The implementations, releases, issues, and install lifecycle now live entirely in their own repositories.

| Project | What it does | Install |
|---|---|---|
| [Claude Lanes](https://github.com/hanzhangzzz/claude-lanes) | Pins each Claude Code window to an explicit provider or team route | `npm install -g claude-lanes` |
| [Coding Usage Bar](https://github.com/hanzhangzzz/coding-usage-bar) | Shows coding-plan usage and burn pace in the macOS menu bar | `npx coding-usage-bar install` |
| [iTerm2 AI Tab Color](https://github.com/hanzhangzzz/iterm2-ai-tab-color) | Colors Claude Code and Codex tabs by attention state | Clone the repository and run `./install.sh` |

## BurnKit CLI

The remaining CLI is intentionally read-only:

```bash
git clone https://github.com/hanzhangzzz/burnkit.git
cd burnkit
./bin/burnkit projects
./bin/burnkit doctor
```

The npm `burnkit@latest` package is still the old bundled toolkit (`0.1.2` as of 2026-09-20) and does not contain this read-only directory CLI. Do not install BurnKit from npm; use the repository entry above and install each standalone project with its own command.

BurnKit no longer bundles, installs, uninstalls, or proxies the three tools. Use each standalone project's own commands and documentation.

中文说明见 [README.zh-CN.md](README.zh-CN.md)。

## License

BurnKit's own code and documentation are released under the [MIT License](LICENSE). Each standalone project defines its own source and asset licensing terms.
