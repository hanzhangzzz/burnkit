#!/bin/bash
# ============================================================
# iTerm2 Tab Color - Claude Code Hook 脚本
# 同时处理 Stop 和 PreToolUse 两个事件
#
# Stop 事件：Claude 完成回复，tab 变绿 + 写时间戳
# PreToolUse 事件：用户开始提问，tab 恢复默认 + 清除时间戳
# ============================================================

# 加载配置（软链后路径仍指向 tools 目录的 config.sh）
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/config.sh"

if [ ! -f "$CONFIG_FILE" ]; then
    THRESHOLD_YELLOW=10
    THRESHOLD_RED=20
    COLOR_GREEN_R=30;  COLOR_GREEN_G=180; COLOR_GREEN_B=30
    COLOR_YELLOW_R=220; COLOR_YELLOW_G=160; COLOR_YELLOW_B=0
    COLOR_RED_R=200;   COLOR_RED_G=40;    COLOR_RED_B=40
    IDLE_STATE_DIR="$HOME/.claude/idle_state"
else
    source "$CONFIG_FILE"
fi

# ---- 找到 Claude 进程对应的 tty，写 escape 码到真实终端 ----
# Claude Code 执行 hook 时 stdout 是管道（不是 tty），
# 必须找到父进程链中 claude 所在的 tty 设备直接写入。

find_claude_tty() {
    # 从当前进程向上找，直到找到 tty 不是 '?' 的 claude/node 进程
    local pid=$$
    local tty_dev=""
    for _ in $(seq 1 10); do
        local ppid tty comm
        read -r ppid tty comm < <(ps -p "$pid" -o ppid=,tty=,comm= 2>/dev/null | tr -s ' ')
        if [ -n "$tty" ] && [ "$tty" != "?" ] && [ "$tty" != "??" ]; then
            tty_dev="/dev/$tty"
            break
        fi
        [ -z "$ppid" ] || [ "$ppid" -eq 1 ] && break
        pid="$ppid"
    done
    echo "$tty_dev"
}

# 获取 tty 路径，写 escape 码的函数
TTY_DEV="$(find_claude_tty)"

write_escape() {
    local seq="$1"
    if [ -n "$TTY_DEV" ] && [ -w "$TTY_DEV" ]; then
        printf "%s" "$seq" > "$TTY_DEV"
    fi
    # 同时输出到 stdout（在真实终端环境下也能生效）
    printf "%s" "$seq"
}

set_tab_color() {
    local r=$1 g=$2 b=$3
    write_escape "$(printf '\033]6;1;bg;red;brightness;%s\a'   "$r")"
    write_escape "$(printf '\033]6;1;bg;green;brightness;%s\a' "$g")"
    write_escape "$(printf '\033]6;1;bg;blue;brightness;%s\a'  "$b")"
}

reset_tab_color() {
    write_escape "$(printf '\033]6;1;bg;*;default\a')"
}

# ---- 读取 hook 事件 ----
HOOK_JSON=$(cat)
HOOK_EVENT=$(echo "$HOOK_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('hook_event_name',''))" 2>/dev/null)
CLAUDE_SESSION=$(echo "$HOOK_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('session_id',''))" 2>/dev/null)

# 不在 iTerm2 里（无 ITERM_SESSION_ID）且找不到 tty，直接退出
if [ -z "$ITERM_SESSION_ID" ] && [ -z "$TTY_DEV" ]; then
    exit 0
fi

# ---- Stop 事件：Claude 回复完成 → 变绿 + 写时间戳 ----
if [ "$HOOK_EVENT" = "Stop" ]; then
    set_tab_color "$COLOR_GREEN_R" "$COLOR_GREEN_G" "$COLOR_GREEN_B"

    mkdir -p "$IDLE_STATE_DIR"
    TIMESTAMP=$(date +%s)
    STATE_FILE="$IDLE_STATE_DIR/${CLAUDE_SESSION}.json"
    python3 - <<EOF
import json, glob, os

data = {
    "iterm2_session": "$ITERM_SESSION_ID",
    "claude_session": "$CLAUDE_SESSION",
    "idle_since": $TIMESTAMP,
    "color_stage": "green"
}
with open("$STATE_FILE", "w") as f:
    json.dump(data, f)

# 清理同 tab 的旧 state 文件（--resume 后旧 pane 残留）
# ITERM_SESSION_ID 格式: w0t0p0:UUID → 提取 tab 前缀 "w0t"
cur_session = "$ITERM_SESSION_ID"
if ":" in cur_session:
    tab_prefix = cur_session.split(":")[0].rsplit("p", 1)[0]  # "w0t0p0" → "w0t0"
else:
    tab_prefix = ""

if tab_prefix:
    state_dir = "$IDLE_STATE_DIR"
    for f in glob.glob(os.path.join(state_dir, "*.json")):
        if f == "$STATE_FILE":
            continue
        try:
            with open(f) as fp:
                d = json.load(fp)
            other_session = d.get("iterm2_session", "")
            # 同 tab = 同 wXtY 前缀
            if other_session and tab_prefix in other_session:
                os.unlink(f)
        except (json.JSONDecodeError, OSError):
            pass
EOF

# ---- PreToolUse 事件：用户开始输入 → 重置颜色 + 清除时间戳 ----
elif [ "$HOOK_EVENT" = "PreToolUse" ]; then
    reset_tab_color

    STATE_FILE="$IDLE_STATE_DIR/${CLAUDE_SESSION}.json"
    if [ -f "$STATE_FILE" ]; then
        rm -f "$STATE_FILE"
        # 立即通过 API 重置整个 tab（包括分屏 pane），不等 daemon 轮询
        SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
        "$SCRIPT_DIR/reset_tab.py" "$ITERM_SESSION_ID" 2>/dev/null &
    fi
fi

exit 0
