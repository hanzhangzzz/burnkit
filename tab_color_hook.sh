#!/bin/bash
# ============================================================
# iTerm2 Tab Color - AI CLI Hook 脚本
# 同时处理 Stop 和 PreToolUse 两个事件
#
# Stop 事件：AI CLI 完成回复，tab 变绿 + 写时间戳
# PreToolUse 事件：用户开始提问，tab 恢复默认 + 清除时间戳
# ============================================================

AGENT="${TAB_COLOR_AGENT:-claude}"
if [ "$1" = "--agent" ] && [ -n "$2" ]; then
    AGENT="$2"
fi

case "$AGENT" in
    claude|codex) ;;
    *) exit 0 ;;
esac

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

# ---- 找到 agent 进程对应的 tty，写 escape 码到真实终端 ----
# Hook 执行时 stdout 可能是管道（不是 tty），必须找到父进程链
# 中 agent 所在的 tty 设备直接写入。

find_agent_tty() {
    # 从当前进程向上找，直到找到 tty 不是 '?' 的进程
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
TTY_DEV="$(find_agent_tty)"

write_escape() {
    local seq="$1"
    if [ -n "$TTY_DEV" ] && [ -w "$TTY_DEV" ]; then
        printf "%s" "$seq" > "$TTY_DEV"
    fi
    # stdout 可能被 hook runtime 解析；只有真实终端才直接输出控制码。
    if [ -t 1 ]; then
        printf "%s" "$seq"
    fi
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
AGENT_SESSION=$(HOOK_JSON="$HOOK_JSON" AGENT="$AGENT" ITERM_SESSION_ID="${ITERM_SESSION_ID:-}" python3 - <<'PY' 2>/dev/null
import hashlib
import json
import os

payload = json.loads(os.environ.get("HOOK_JSON", "{}") or "{}")
session = (
    payload.get("session_id")
    or payload.get("conversation_id")
    or payload.get("thread_id")
    or payload.get("id")
    or (payload.get("session") or {}).get("id")
)
if not session:
    raw = "|".join([
        os.environ.get("AGENT", ""),
        os.environ.get("ITERM_SESSION_ID", ""),
        os.getcwd(),
    ])
    session = hashlib.sha1(raw.encode()).hexdigest()[:24]
print(session)
PY
)
STATE_BASENAME=$(AGENT="$AGENT" AGENT_SESSION="$AGENT_SESSION" python3 - <<'PY'
import os
import re

agent = os.environ["AGENT"]
session = os.environ["AGENT_SESSION"]
safe_session = re.sub(r"[^A-Za-z0-9_.-]", "_", session)
print(safe_session if agent == "claude" else f"{agent}-{safe_session}")
PY
)

# 不在 iTerm2 里（无 ITERM_SESSION_ID）且找不到 tty，直接退出
if [ -z "$ITERM_SESSION_ID" ] && [ -z "$TTY_DEV" ]; then
    exit 0
fi

# ---- Stop 事件：agent 回复完成 → 变绿 + 写时间戳 ----
if [ "$HOOK_EVENT" = "Stop" ]; then
    set_tab_color "$COLOR_GREEN_R" "$COLOR_GREEN_G" "$COLOR_GREEN_B"

    mkdir -p "$IDLE_STATE_DIR"
    TIMESTAMP=$(date +%s)
    STATE_FILE="$IDLE_STATE_DIR/${STATE_BASENAME}.json"
    python3 - <<EOF
import json

data = {
    "schema_version": 2,
    "agent": "$AGENT",
    "iterm2_session": "$ITERM_SESSION_ID",
    "agent_session": "$AGENT_SESSION",
    "idle_since": $TIMESTAMP,
    "color_stage": "green"
}
if "$AGENT" == "claude":
    data["claude_session"] = "$AGENT_SESSION"
with open("$STATE_FILE", "w") as f:
    json.dump(data, f)
EOF

# ---- 用户继续操作 → 重置颜色 + 清除时间戳 ----
elif [ "$HOOK_EVENT" = "PreToolUse" ] || [ "$HOOK_EVENT" = "UserPromptSubmit" ]; then
    reset_tab_color

    STATE_FILE="$IDLE_STATE_DIR/${STATE_BASENAME}.json"
    if [ -f "$STATE_FILE" ]; then
        rm -f "$STATE_FILE"
        # 立即通过 API 重置整个 tab（包括分屏 pane），不等 daemon 轮询
        SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
        "$SCRIPT_DIR/reset_tab.py" "$ITERM_SESSION_ID" 2>/dev/null &
    fi
fi

exit 0
