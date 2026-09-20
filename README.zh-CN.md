# BurnKit

BurnKit 现在是三个独立工具的项目导航页。它们面向并行 AI 编程工作流，但实现、发布、Issue 和安装生命周期均由各自仓库独立维护。

| 项目 | 用途 | 安装 |
|---|---|---|
| [Claude Lanes](https://github.com/hanzhangzzz/claude-lanes) | 把每个 Claude Code 窗口明确固定到指定 Provider 或 Team 路由 | `npm install -g claude-lanes` |
| [Coding Usage Bar](https://github.com/hanzhangzzz/coding-usage-bar) | 在 macOS 菜单栏显示 Coding Plan 用量和燃烧节奏 | `npx coding-usage-bar install` |
| [iTerm2 AI Tab Color](https://github.com/hanzhangzzz/iterm2-ai-tab-color) | 按待处理状态为 Claude Code / Codex 的 iTerm2 tab 着色 | clone 仓库后执行 `./install.sh` |

## BurnKit CLI

保留的 CLI 只做只读导航和本机诊断：

```bash
git clone https://github.com/hanzhangzzz/burnkit.git
cd burnkit
./bin/burnkit projects
./bin/burnkit doctor
```

当前 npm 的 `burnkit@latest` 仍是旧的整合工具包（截至 2026-09-20 为 `0.1.2`），不包含这里的只读导航 CLI。请不要从 npm 安装 BurnKit；使用上面的仓库入口，并按各独立项目自己的命令安装。

BurnKit 不再打包、安装、卸载或代理这三个工具。请使用各独立项目自己的命令和文档。

## License

BurnKit 自身代码与文档使用 [MIT License](LICENSE)。三个独立项目分别声明自己的源码与素材授权边界。
