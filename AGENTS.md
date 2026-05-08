# 卷死你三件套

本仓库按工具集维护，不再按单一 iTerm2 tab color 项目维护。

## 项目结构基准

| 路径 | 职责 |
|------|------|
| `tools/claude-provider-router/` | 第一件工具：`c` 启动器、Provider 配置、Team 路由代理、Claude Code status line |
| `tools/iterm2-tab-color/` | 第二件工具：Claude Code / Codex CLI idle hook、iTerm2 tab color daemon |
| `assets/` | 演示图、发布素材 |
| `raw_think.md` | 本地想法草稿，不作为产品承诺 |

根目录不保留 `install.sh` / `uninstall.sh` 兼容入口。每个工具的安装、卸载入口必须放在各自 `tools/<tool>/` 目录内。

## 目录迁移基准

- 目录迁移只做目录整理，不做功能层面的代码修改。
- `tools/iterm2-tab-color/` 的行为基准是当前 HEAD `0ba4914 feat: improve codex install and idle cleanup` 下的根目录实现。
- 允许改动的代码范围仅限路径适配：脚本相对路径、launchd plist 生成路径、hook 软链目标、README 中的命令路径。
- 禁止在目录迁移中引入新的 state 清理策略、颜色聚合策略、进程检测逻辑、hook 事件语义或 daemon 调度逻辑。
- 如果必须修改功能代码，必须暂停迁移，单独提出 bugfix 计划并先 review。

## 维护原则

- 第三个工具未明确前只保留占位，不做推测性实现。
- `tools/claude-provider-router/config.env` 是敏感本地配置，不能提交；只维护 `config.env.example`。
- `tools/iterm2-tab-color/install.sh` 依赖同目录脚本相对路径，移动文件时必须同步安装文档和测试命令。
- `tools/iterm2-tab-color/uninstall.sh` 必须与 install 行为对称：停止 launchd、删除 hook 软链和 launchd plist、清理 JSON hook 条目，并默认保留 state/log。
- `tools/iterm2-tab-color/` 的 LaunchAgent plist 必须安装为 `~/Library/LaunchAgents/com.duying.tab-color-daemon.plist` 真实文件，不能依赖指向仓库的软链。
- `tools/iterm2-tab-color/tab_color_daemon.py` 必须启用 iTerm2 Python API retry；iTerm2 重启或升级导致 websocket 断开时，daemon 应自动重连。
- 修改脚本后至少运行 `bash -n`、`py_compile` 和 tab color 单元测试。

## 验证命令

目录迁移完成后至少运行：

```bash
bash -n tools/iterm2-tab-color/install.sh tools/iterm2-tab-color/uninstall.sh tools/iterm2-tab-color/tab_color_hook.sh
python3 -m py_compile tools/iterm2-tab-color/tab_color_daemon.py tools/iterm2-tab-color/reset_tab.py tools/iterm2-tab-color/test_daemon.py
python3 -m unittest tools/iterm2-tab-color/test_daemon.py
```

如果修改 `tools/claude-provider-router/`，还要对该目录的 shell/Python 文件执行对应语法检查。
