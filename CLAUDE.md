# iTerm2 Claude Tab Color

用 tab 颜色实时反映 Claude Code session 的空闲状态。

## 项目结构

| 文件 | 职责 |
|------|------|
| `tab_color_daemon.py` | 后台守护进程，launchd 管理。监听 state 文件 + 轮询升级颜色 |
| `tab_color_hook.sh` | Claude Code hook，Stop 写 state + 设绿色，PreToolUse 删 state + 重置颜色 |
| `reset_tab.py` | PreToolUse hook 后台调用，通过 iTerm2 API 重置整个 tab 颜色 |
| `config.sh` | 用户配置（阈值、颜色、轮询间隔） |
| `install.sh` | 一键安装（symlink hooks + launchd plist） |
| `com.duying.tab-color-daemon.plist` | launchd 配置 |

## 运行机制

1. **Stop hook** → ANSI escape 即时设绿 + 写 `~/.claude/idle_state/{session}.json`
2. **daemon watch_idle_dir** → 每 500ms 扫描目录，统一应用颜色（活跃→白，非活跃→色阶色）
3. **daemon color_poller** → 每 30s 轮询，升级颜色（绿→黄→红），清理孤儿/去重
4. **PreToolUse hook** → 删 state 文件 + `reset_tab.py` 后台重置整个 tab

## 踩过的坑

### 1. 分屏 pane 颜色不同步

**现象**：Claude session pane 变绿了，切到同 tab 的 zsh pane 颜色没变。

**原因**：`apply_tab_color` 只给当前 session 设颜色，没遍历同 tab 下所有 pane。

**修复**：通过 `session.tab.sessions` 获取同 tab 所有 session，逐一设色。

### 2. 活跃 tab 识别困难

**现象**：所有 tab 都有颜色，分不清哪个是自己正在看的。

**修复**：只给非活跃 tab 上色（通知徽章模式）。`is_active_tab()` 通过 `session.tab.window.current_tab` 判断。活跃 tab 始终保持白色。

### 3. 颜色闪烁（red↔yellow 来回跳）

**现象**：tab 颜色在红色和黄色之间来回切换。

**根因有两个**：

**(a) 两个守护进程同时运行**
- launchd 版本（本项目安装的）和 iTerm2 AutoLaunch 版本（`~/.config/iterm2/AppSupport/Scripts/AutoLaunch/` 下的 symlink）同时运行
- 两者用不同的配置阈值读写同一个 state 文件，互相覆盖 `color_stage`
- **修复**：删除 AutoLaunch 下的 symlink，只保留 launchd 管理的一个实例

**(b) active_tab_watcher 与 color_poller 竞争**
- `active_tab_watcher` 每 0.5s 切换 tab 颜色（切走补色、切入去色）
- `color_poller` 每 30s 升级颜色
- 两者交叉执行导致颜色在两个值之间震荡
- **修复**：移除 `active_tab_watcher`，把活跃 tab 检测合并到 `color_poller` 里（30s 周期足够稳定）

### 4. TTY 检测（hook 脚本）

**现象**：hook 中写 ANSI escape 到 stdout 无效。

**原因**：Claude Code pipe 了 hook 的 stdout，不是直接写到终端。

**修复**：hook 脚本中的 `find_claude_tty()` 沿父进程链找到真实的 tty 设备（`/dev/ttysXXX`），直接写。

### 5. ITERM_SESSION_ID 格式

**现象**：`app.get_session_by_id()` 找不到 session。

**原因**：环境变量 `ITERM_SESSION_ID` 格式是 `w0t1p2:UUID`，但 iTerm2 API 只接受纯 UUID。

**修复**：`extract_uuid()` 去掉前缀。

### 6. claude --resume 导致旧 state 文件残留

**现象**：resume 后 tab 颜色异常——切走后变红（应该绿），或切回来再切走保持白色。

**根因**：
- `claude --resume` 创建新 session_id + 新 iTerm2 pane（`w0t0p0` → `w0t0p1`）
- 旧 state 文件指向旧 pane，新 state 文件指向新 pane，但两者在**同一个 tab**
- PreToolUse hook 只删当前 session 的 state 文件，旧 session 的文件无人清理
- daemon 孤儿清理检测到旧 pane 仍存在（不删），同 tab 去重只在两个 state 文件并存时触发

**修复**：两层防御：
1. **Hook 层**：Stop hook 写新 state 文件后，按 `wXtY` tab 前缀匹配并删除同 tab 旧 state 文件
2. **Daemon 层**：`apply_tab_color` 接受外部传入的 `app`/`session` 对象，避免重复获取导致过期数据（"切走后保持白色"的根因）

### 7. 双写入者竞争（切走不变绿的根因）

**现象**：切走 tab 后应该变绿但保持白色，或者切回来后应该变白却保持绿色。

**根因**：`watch_idle_dir` 和 `color_poller` 两个循环都调用 `apply_tab_color` 写颜色：
- watch 1s 周期：检测文件消失 → 重置颜色，但不处理"非活跃 tab 重新上色"
- poller 30s 周期：处理活跃/非活跃切换 + 颜色升级
- 两者交叉执行，状态互相覆盖 → 颜色在两个值之间震荡，或某个方向被吞掉

**修复**：单写入者架构。`watch_idle_dir`（500ms）是**唯一**调用 iTerm2 API 设色的循环，统一处理"活跃→白/非活跃→色阶色"。`color_poller`（30s）只改 state 文件元数据（色阶升级、孤儿清理、同 tab 去重），绝不碰颜色。

### 8. 不需要复杂的自动重连

最初考虑了 API 连接断开后的自动重连逻辑。实际上 `iterm2.run_forever(main)` + launchd `KeepAlive=true` 就够了——连接断开时进程退出，launchd 自动重启。**简单就是最好的。**

## 关键设计决策

| 决策 | 原因 |
|------|------|
| 两种设色机制并用 | ANSI escape 即时但只覆盖当前 pane；iTerm2 API 覆盖全 tab 但有 ~1s 延迟 |
| 只给非活跃 tab 上色 | 颜色是通知徽章，不是状态标签。用户已经在看的 tab 不需要通知 |
| 关系列表只在一侧声明 | 减少维护负担，Obsidian 反向链接自动补全另一侧 |
| 状态文件用 JSON 不用空文件 | 需要存 `iterm2_session` 和 `idle_since`，空文件不够 |
| watch 500ms + poll 30s | watch 保证即时响应（新 session / 活跃切换），poll 负责升级和去重 |
