#!/bin/bash
# ============================================================
# iTerm2 Tab Color - 安装脚本
# 建立软链 + 注册 Claude/Codex hooks + 配置 launchd 守护进程
# ============================================================
set -e

TOOLS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_SRC="$TOOLS_DIR/tab_color_hook.sh"
DAEMON_SRC="$TOOLS_DIR/tab_color_daemon.py"
PLIST_SRC="$TOOLS_DIR/com.duying.tab-color-daemon.plist"

CLAUDE_HOOK_LINK="$HOME/.claude/hooks/tab_color_hook.sh"
CODEX_HOOK_LINK="$HOME/.codex/hooks/tab_color_hook.sh"
PLIST_LINK="$HOME/Library/LaunchAgents/com.duying.tab-color-daemon.plist"

CLAUDE_SETTINGS_FILE="$HOME/.claude/settings.json"
CODEX_HOOKS_FILE="$HOME/.codex/hooks.json"
PYTHON3="$(which python3)"

echo "📦 iTerm2 Tab Color 安装程序"
echo "================================"
echo "源目录: $TOOLS_DIR"
echo "Python:  $PYTHON3"
echo ""

# ---- 1. 检查源文件 ----
for f in "$HOOK_SRC" "$DAEMON_SRC" "$TOOLS_DIR/config.sh"; do
    if [ ! -f "$f" ]; then
        echo "❌ 缺少文件: $f"
        exit 1
    fi
done

# 检查 iterm2 Python 模块
if ! "$PYTHON3" -c "import iterm2" 2>/dev/null; then
    echo "❌ iterm2 Python 模块未安装，请先执行："
    echo "   pip3 install iterm2"
    exit 1
fi
echo "✅ 源文件 & iterm2 模块检查通过"

# ---- 2. 创建必要目录 ----
mkdir -p "$HOME/.claude/hooks"
mkdir -p "$HOME/.codex/hooks"
mkdir -p "$HOME/.claude/idle_state"
mkdir -p "$HOME/Library/LaunchAgents"
echo "✅ 目录创建完成"

# ---- 3. 生成 launchd plist 文件 ----
# 动态写入真实的 Python 路径和脚本路径
DAEMON_LOG="$HOME/.claude/idle_state/daemon.log"
cat > "$PLIST_SRC" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.duying.tab-color-daemon</string>

    <key>ProgramArguments</key>
    <array>
        <string>$PYTHON3</string>
        <string>$DAEMON_SRC</string>
    </array>

    <!-- 登录后自动启动 -->
    <key>RunAtLoad</key>
    <true/>

    <!-- 退出后始终自动重启 -->
    <key>KeepAlive</key>
    <true/>

    <!-- 日志 -->
    <key>StandardOutPath</key>
    <string>$DAEMON_LOG</string>
    <key>StandardErrorPath</key>
    <string>$DAEMON_LOG</string>

    <!-- 需要 iTerm2 已运行，延迟 5s 启动避免连接失败 -->
    <key>ThrottleInterval</key>
    <integer>10</integer>
</dict>
</plist>
PLIST
echo "✅ launchd plist 已生成: $PLIST_SRC"

# ---- 4. 建立软链 ----

# Hook 脚本软链
if [ -L "$CLAUDE_HOOK_LINK" ]; then
    rm "$CLAUDE_HOOK_LINK"
fi
ln -s "$HOOK_SRC" "$CLAUDE_HOOK_LINK"

if [ -L "$CODEX_HOOK_LINK" ]; then
    rm "$CODEX_HOOK_LINK"
fi
ln -s "$HOOK_SRC" "$CODEX_HOOK_LINK"

chmod +x "$HOOK_SRC"
echo "✅ Claude Hook 软链: $CLAUDE_HOOK_LINK"
echo "                    → $HOOK_SRC"
echo "✅ Codex Hook 软链:  $CODEX_HOOK_LINK"
echo "               → $HOOK_SRC"

# plist 软链
if [ -L "$PLIST_LINK" ]; then
    launchctl unload "$PLIST_LINK" 2>/dev/null || true
    rm "$PLIST_LINK"
fi
ln -s "$PLIST_SRC" "$PLIST_LINK"
echo "✅ plist 软链:  $PLIST_LINK"
echo "               → $PLIST_SRC"

# ---- 5. 注册 Claude Code Hooks ----
echo ""
echo "🔧 注册 Claude Code Hooks..."

if [ -f "$CLAUDE_SETTINGS_FILE" ]; then
    "$PYTHON3" - <<PYEOF
import json

settings_path = "$CLAUDE_SETTINGS_FILE"
hook_cmd = "$CLAUDE_HOOK_LINK"

with open(settings_path) as f:
    cfg = json.load(f)

hooks = cfg.setdefault("hooks", {})

def ensure_hook(event_name, matcher, command):
    event_hooks = hooks.setdefault(event_name, [])
    target_group = None
    for group in event_hooks:
        if group.get("matcher") == matcher:
            target_group = group
            break
    if target_group is None:
        target_group = {"matcher": matcher, "hooks": []}
        event_hooks.append(target_group)
    for h in target_group["hooks"]:
        if h.get("command") == command:
            print(f"   （已存在，跳过）: {event_name}/{matcher}")
            return
    target_group["hooks"].append({"type": "command", "command": command})
    print(f"   ✅ 已注册: {event_name}/{matcher}")

ensure_hook("Stop", "*", hook_cmd)
ensure_hook("PreToolUse", "*", hook_cmd)

with open(settings_path, "w") as f:
    json.dump(cfg, f, indent=2, ensure_ascii=False)

print("✅ settings.json 更新完成")
PYEOF
else
    echo "⚠️  未找到 $CLAUDE_SETTINGS_FILE，跳过 Claude hook 注册"
fi

# ---- 5b. 注册 Codex Hooks ----
echo ""
echo "🔧 注册 Codex Hooks..."

if [ -f "$CODEX_HOOKS_FILE" ]; then
    "$PYTHON3" - <<PYEOF
import json

hooks_path = "$CODEX_HOOKS_FILE"
hook_cmd = "'$CODEX_HOOK_LINK' --agent codex"

with open(hooks_path) as f:
    cfg = json.load(f)

hooks = cfg.setdefault("hooks", {})
events = ["Stop", "PreToolUse", "UserPromptSubmit"]

for event_name in events:
    for group in hooks.get(event_name, []):
        group["hooks"] = [
            h for h in group.get("hooks", [])
            if "tab_color_hook.sh" not in h.get("command", "") or "--agent codex" in h.get("command", "")
        ]

def ensure_hook(event_name, matcher, command):
    event_hooks = hooks.setdefault(event_name, [])
    target_group = None
    for group in event_hooks:
        if group.get("matcher") == matcher:
            target_group = group
            break
    if target_group is None:
        target_group = {"matcher": matcher, "hooks": []}
        event_hooks.append(target_group)
    for h in target_group["hooks"]:
        if h.get("command") == command:
            print(f"   （已存在，跳过）: {event_name}/{matcher}")
            return
    target_group["hooks"].append({"type": "command", "command": command})
    print(f"   ✅ 已注册: {event_name}/{matcher}")

for event_name in events:
    ensure_hook(event_name, "*", hook_cmd)

with open(hooks_path, "w") as f:
    json.dump(cfg, f, indent=2, ensure_ascii=False)

print("✅ hooks.json 更新完成")
PYEOF
else
    echo "⚠️  未找到 $CODEX_HOOKS_FILE，跳过 Codex hook 注册"
fi

# ---- 6. 加载 launchd 守护进程 ----
echo ""
echo "🚀 加载守护进程..."
launchctl load "$PLIST_LINK"
sleep 1

# 检查是否成功运行
if launchctl list | grep -q "com.duying.tab-color-daemon"; then
    echo "✅ 守护进程已启动（launchd 管理，登录自动运行）"
else
    echo "⚠️  守护进程加载完成，但可能在等待 iTerm2 启动后才能连接"
    echo "   日志: $DAEMON_LOG"
fi

# ---- 7. 完成 ----
echo ""
echo "================================"
echo "🎉 安装完成！"
echo ""
echo "验证："
echo "  launchctl list | grep tab-color      # 查看守护进程状态"
echo "  tail -f $DAEMON_LOG  # 查看实时日志"
echo ""
echo "修改配置："
echo "  编辑 $TOOLS_DIR/config.sh 即可调整时间阈值和颜色"
echo "  改完后执行: launchctl kickstart -k gui/\$(id -u)/com.duying.tab-color-daemon"
echo ""
echo "卸载："
echo "  launchctl unload '$PLIST_LINK'"
echo "  rm '$CLAUDE_HOOK_LINK' '$CODEX_HOOK_LINK' '$PLIST_LINK'"
