# 卷死你三件套

> 面向高并发 AI 编程工作流的小工具集，让 Provider 路由、窗口可见性和人工接管提示更清晰。

[English README](README.md)

本仓库现在是工具集，而不是单一的 iTerm2 tab color 项目。

## 工具列表

| 工具 | 路径 | 状态 | 解决的问题 |
|------|------|------|------------|
| Claude Provider Router | `tools/claude-provider-router/` | 可用 | 用 `c` 快速切换 Claude Code Provider，并支持 Agent Team 的 leader/teammate 分流 |
| iTerm2 Tab Color | `tools/iterm2-tab-color/` | 可用 | 多个 Claude Code / Codex CLI tab 并行时，用颜色提示哪个 session 已经等人太久 |
| 第三件工具 | 待定 | 预留 | 范围明确前只保留占位，不做推测性实现 |

## 目录结构

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

根目录不提供 `install.sh` / `uninstall.sh`。每个工具从自己的目录或文档路径执行安装、卸载。

## 快速使用

Claude Provider Router：

```bash
cd tools/claude-provider-router
cp config.env.example config.env
chmod 600 config.env
./c 0
```

iTerm2 Tab Color：

```bash
pip3 install iterm2
bash tools/iterm2-tab-color/install.sh
```

详细说明见各工具 README：

- `tools/claude-provider-router/README.md`
- `tools/iterm2-tab-color/README.md`
- `tools/iterm2-tab-color/README.zh-CN.md`

## 维护规则

- 第三个工具未明确前只保留占位，不做推测性实现。
- 不提交 `tools/claude-provider-router/config.env`；仓库只维护 `config.env.example`。
- 目录迁移期间保持 `tools/iterm2-tab-color/` 行为稳定。允许路径修正；颜色/state 行为变更必须单独计划。
- 完整项目基准见 `AGENTS.md`。

## 验证

修改 iTerm2 Tab Color 后至少运行：

```bash
bash -n tools/iterm2-tab-color/install.sh tools/iterm2-tab-color/uninstall.sh tools/iterm2-tab-color/tab_color_hook.sh
python3 -m py_compile tools/iterm2-tab-color/tab_color_daemon.py tools/iterm2-tab-color/reset_tab.py tools/iterm2-tab-color/test_daemon.py
python3 -m unittest tools/iterm2-tab-color/test_daemon.py
```

## License

[MIT](LICENSE)
