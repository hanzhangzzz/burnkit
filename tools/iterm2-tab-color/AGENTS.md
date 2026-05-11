# iTerm2 Tab Color

本目录维护 Claude Code / Codex CLI idle hook 和 iTerm2 tab color daemon。目标是在 iTerm2 多 tab / split pane 并行使用 AI CLI 时，用 tab 颜色提示哪些 session 已完成回复并等待人处理。

本文件是给后续 AI/维护者的操作手册。修改本工具前先读完本文件，再读 `README.md`、`README.zh-CN.md` 和相关源码。

## 目录迁移边界

目录迁移阶段只做目录整理和路径适配，不能混入功能修复。

行为基准：

- `tools/iterm2-tab-color/` 的功能行为必须等同于仓库 HEAD `0ba4914 feat: improve codex install and idle cleanup` 的根目录实现。
- 允许修改：文件移动后的相对路径解析、安装脚本生成的 hook 安装目标、launchd plist 中的 daemon 脚本路径、README/测试命令中的路径。
- 禁止修改：hook 事件语义、state 文件生命周期、颜色状态机、活跃 tab 判断、同 tab 聚合、进程检测、daemon 调度逻辑。

如果发现功能 bug，先暂停迁移，单独提出 bugfix 计划并 review。不要把目录迁移和行为修复混在一个 diff 里。

## 基本用法

从仓库根目录安装：

```bash
pip3 install iterm2
bin/burnkit install tabs
```

从仓库根目录卸载：

```bash
bin/burnkit uninstall tabs
```

卸载默认保留 `~/.claude/idle_state` 和 daemon log。如需一起清理：

```bash
bin/burnkit uninstall tabs --purge-state
```

预演安装，不写文件、不启动服务：

```bash
bin/burnkit install tabs --dry-run
```

根目录不保留 `install.sh` / `uninstall.sh` 兼容入口。对用户可见的安装、卸载统一走 `bin/burnkit install tabs` / `bin/burnkit uninstall tabs`。本目录的 `install.sh` / `uninstall.sh` 只作为兼容 wrapper；真实逻辑维护在 `install-core.sh` / `uninstall-core.sh`，并由 `bin/burnkit` 直接调用。

## 运行时文件

安装后会涉及这些用户目录文件：

| 路径 | 作用 |
|------|------|
| `~/.claude/hooks/tab_color_hook.sh` | Claude hook 脚本副本 |
| `~/.codex/hooks/tab_color_hook.sh` | Codex hook 脚本副本 |
| `~/.claude/settings.json` | Claude Code hook 注册位置 |
| `~/.codex/hooks.json` | Codex hook 注册位置 |
| `~/.claude/idle_state/*.json` | 每个 idle AI session 的 state 文件 |
| `~/.claude/idle_state/daemon.log` | daemon stdout/stderr 日志 |
| `~/Library/LaunchAgents/com.duying.tab-color-daemon.plist` | launchd plist 真实文件 |

安装脚本会在修改 JSON 配置前创建 `.bak.YYYYmmdd-HHMMSS` 备份。

LaunchAgent plist 必须是 `~/Library/LaunchAgents/` 下的真实文件。不要把它安装成指向仓库目录的软链；登录自动加载和 `KeepAlive` 兜底都依赖当前用户 launchd domain 中存在真实 job。

## 重启与排查

查看 daemon 是否注册：

```bash
launchctl list | grep tab-color
```

查看更详细的 launchd 状态：

```bash
launchctl print gui/$(id -u)/com.duying.tab-color-daemon
```

重启 daemon：

```bash
launchctl kickstart -k gui/$(id -u)/com.duying.tab-color-daemon
```

查看日志：

```bash
tail -f ~/.claude/idle_state/daemon.log
```

修改 `config.sh` 后必须重启 daemon，hook 脚本下次触发会重新读取配置，daemon 不会自动热加载配置。

## 颜色规则

| 颜色 | 含义 | 触发条件 |
|------|------|----------|
| 白色 | 活跃、处理中，或没有 idle state | 当前活跃 tab、用户提交新输入、工具调用开始、state 全部清空 |
| 绿色 | AI CLI 刚完成，正在等人 | `Stop` hook 写入 state，`color_stage=green` |
| 黄色 | 等待时间较长 | idle 时间达到 `THRESHOLD_YELLOW` |
| 红色 | 等待太久，需要优先处理 | idle 时间达到 `THRESHOLD_RED` |

默认 RGB：

| Stage | RGB |
|-------|-----|
| `green` | `30, 180, 30` |
| `yellow` | `220, 160, 0` |
| `red` | `200, 40, 40` |

关键规则：

- 颜色是 tab 级别，不是 pane 级别。同一个 iTerm2 tab 内所有 pane 使用同一 tab color。
- 当前活跃 tab 始终显示白色，因为用户已经在看它。
- 非活跃 tab 才用绿/黄/红作为通知徽章。
- 同 tab 多个 idle session 取最严重颜色：`red > yellow > green`。
- 某个 pane 开始新请求时，只清理这个 pane/session 对应的 state；同 tab 其他 pane 的 idle state 必须保留。
- 当同一个 tab 内所有 AI session 都恢复活跃、处理中、关闭或回到 shell 后，tab 才恢复白色。

## 状态模型

每个 idle AI session 在 `IDLE_STATE_DIR` 下对应一个 JSON 文件，默认目录是 `~/.claude/idle_state`。

典型 state：

```json
{
  "schema_version": 2,
  "agent": "claude",
  "iterm2_session": "w0t1p2:UUID",
  "agent_session": "session-id",
  "claude_session": "session-id",
  "idle_since": 1778136768,
  "color_stage": "green"
}
```

字段说明：

| 字段 | 说明 |
|------|------|
| `agent` | `claude` 或 `codex`；旧 state 缺失时按 `claude` 兼容 |
| `iterm2_session` | iTerm2 pane id，常见格式是 `w0t1p2:UUID` |
| `agent_session` | Claude/Codex 的 session id；缺失时 hook 用 agent、iTerm session、cwd 生成稳定 hash |
| `claude_session` | 兼容旧 Claude state 的字段，仅 Claude 写入 |
| `idle_since` | Unix timestamp，Stop hook 写入 |
| `color_stage` | `green`、`yellow`、`red` |

`iterm2_session` 解析规则：

- `extract_uuid("w0t1p2:UUID") -> "UUID"`，iTerm2 API 查询 session 时只用 UUID。
- `extract_tab_prefix("w0t1p2:UUID") -> "w0t1"`，用于判断同一个 tab。

## 状态转换

```text
无 state / active / processing
        |
        | Stop hook
        v
green idle state
        |
        | idle >= THRESHOLD_YELLOW
        v
yellow idle state
        |
        | idle >= THRESHOLD_RED
        v
red idle state
        |
        | PreToolUse / UserPromptSubmit / pane 回到 shell / session 消失
        v
无 state / white
```

更具体的转换责任：

| 事件 | 责任组件 | 结果 |
|------|----------|------|
| `Stop` | `tab_color_hook.sh` | 立即用 escape sequence 把当前 pane 设绿，写入 `color_stage=green` state |
| `PreToolUse` | `tab_color_hook.sh` | 重置当前 tab 颜色，删除当前 session state，后台调用 `reset_tab.py` |
| `UserPromptSubmit` | `tab_color_hook.sh` | Codex 用户提交输入时执行，与 `PreToolUse` 一样清理当前 session state |
| watch 500ms | `tab_color_daemon.py` | 读取 state，清理已回 shell 的 pane，按 tab 聚合并通过 iTerm2 API 写颜色 |
| poll `POLL_INTERVAL` | `tab_color_daemon.py` | 清理孤儿 state，检查 agent 进程，升级 `green -> yellow -> red`，只写 state 元数据 |

设计原则：daemon 的 watch loop 是 iTerm2 API 颜色写入者；poller 只改 state 文件元数据。不要新增第二个长期颜色写入循环。

## 架构设计

```text
Claude Code / Codex hook event
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

组件职责：

| 文件 | 职责 |
|------|------|
| `config.sh` | 用户配置：阈值、颜色、轮询间隔、state 目录、并发提示 |
| `tab_color_hook.sh` | Claude/Codex hook 入口；处理 Stop、PreToolUse、UserPromptSubmit |
| `tab_color_daemon.py` | launchd 托管 daemon；读取 state、聚合 tab、升级颜色、清理孤儿 |
| `reset_tab.py` | hook 后台调用，通过 iTerm2 API 快速重置整个 tab |
| `install-core.sh` | 内部安装实现：复制 hook、JSON hook 注册、launchd plist |
| `uninstall-core.sh` | 内部卸载实现：停止 launchd、删除 hook 文件、移除 JSON hook 条目，可选删除 state/log |
| `install.sh` | 兼容 wrapper，提示使用 `bin/burnkit install tabs` 后转发到 `install-core.sh` |
| `uninstall.sh` | 兼容 wrapper，提示使用 `bin/burnkit uninstall tabs` 后转发到 `uninstall-core.sh` |
| `test_daemon.py` | daemon 行为单元测试，使用 mock iTerm2 API |

两个设色机制都需要保留：

- hook 用 terminal escape sequence 快速设绿/重置，反馈快但主要作用于当前终端。
- daemon 用 iTerm2 Python API 给整个 tab 的所有 pane 统一设色，覆盖 split pane 场景。

daemon 入口必须使用 `iterm2.run_forever(main, retry=True)`，这样 iTerm2 重启、升级或 websocket 断开后，Python API 会尝试自动重连。

## 配置

配置文件：`tools/iterm2-tab-color/config.sh`。

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `THRESHOLD_YELLOW` | `10` | idle 多少分钟后升级为黄色 |
| `THRESHOLD_RED` | `20` | idle 多少分钟后升级为红色 |
| `COLOR_GREEN_R/G/B` | `30/180/30` | 绿色 RGB |
| `COLOR_YELLOW_R/G/B` | `220/160/0` | 黄色 RGB |
| `COLOR_RED_R/G/B` | `200/40/40` | 红色 RGB |
| `POLL_INTERVAL` | `30` | poller 重型扫描间隔，单位秒 |
| `IDLE_STATE_DIR` | `$HOME/.claude/idle_state` | state 文件目录 |
| `CONCURRENT_TARGET` | `3` | 日志提示用，不强制限制并发 |

`POLL_INTERVAL` 影响黄/红升级延迟和重型进程扫描频率。watch loop 固定约 500ms，用于快速响应 state 文件变化和 active tab 切换。

## 测试规范

修改本目录后至少运行：

```bash
bash -n tools/iterm2-tab-color/install-core.sh tools/iterm2-tab-color/uninstall-core.sh tools/iterm2-tab-color/install.sh tools/iterm2-tab-color/uninstall.sh tools/iterm2-tab-color/tab_color_hook.sh
python3 -m py_compile tools/iterm2-tab-color/tab_color_daemon.py tools/iterm2-tab-color/reset_tab.py tools/iterm2-tab-color/test_daemon.py
python3 -m unittest tools/iterm2-tab-color/test_daemon.py
```

如果当前工作目录已经是 `tools/iterm2-tab-color/`，等价命令是：

```bash
bash -n install-core.sh uninstall-core.sh install.sh uninstall.sh tab_color_hook.sh
python3 -m py_compile tab_color_daemon.py reset_tab.py test_daemon.py
python3 -m unittest test_daemon.py
```

测试覆盖重点：

- `compute_color_stage` 的绿/黄/红阈值边界。
- `extract_uuid` 和 `extract_tab_prefix` 的 iTerm2 session id 解析。
- active tab 上色跳过，reset 不跳过。
- 同 tab 多 state 使用最高严重级别。
- pane 回到 shell 或 iTerm2 session 消失时清理 state。
- agent 进程检测失败时保守保留 state。
- Codex/Claude 进程 marker 分流。

新增功能性变更时必须先补测试；纯文档变更不需要跑单元测试，但最终迁移收口仍需执行完整验证。

## 常见坑

- 不要在 hook 里按 tab 前缀删除同 tab 所有 state。开始新请求只能清理当前 session state，否则同 tab 其他等待中的 pane 会丢失 yellow/red 状态。
- 不要让 poller 直接写 iTerm2 tab color。长期颜色写入者只能有一个，否则会产生白/绿/黄/红互相覆盖。
- 不要只给当前 pane 设色。iTerm2 tab color 应该覆盖同 tab 的所有 pane。
- 不要把 Codex hook 的 stdout 写出 escape sequence 或普通文本。Codex Stop hook 会校验 stdout，安装脚本使用静默命令是必要的。
- 不要假设 `ITERM_SESSION_ID` 可以直接传给 `app.get_session_by_id()`；必须取冒号后的 UUID。
- 不要依赖 `readlink -f`，macOS 默认 `readlink` 不支持该参数；路径解析要兼容 macOS。
- 不要把 LaunchAgent plist 安装成软链。plist 应写入 `~/Library/LaunchAgents/com.duying.tab-color-daemon.plist` 真实文件，再执行 `launchctl bootstrap`。
- 不要把 daemon 入口退回 `iterm2.run_forever(main)` 默认参数；默认 `retry=False`，iTerm2 重启或升级后 websocket 断开会导致 daemon 不再处理黄/红升级和 active tab 清色。
- 不要默认删除 `~/.claude/idle_state` 和日志。卸载默认保留，只有 `--purge-state` 才删除。
- 不要提交 `tools/claude-provider-router/config.env`；这是另一个工具的敏感本地配置。
