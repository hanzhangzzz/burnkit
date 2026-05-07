#!/usr/bin/env bash
# Demo 录制脚本 — 造假 state 文件，模拟三色 tab 切换场景
# 用法：bash demo_record.sh
# 清理：bash demo_record.sh clean

set -euo pipefail

STATE_DIR="$HOME/.claude/idle_state"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/config.sh"
BACKUP_DIR="$STATE_DIR/_demo_backup"

# 加载配置获取阈值
source "$CONFIG_FILE"

now=$(date +%s)
green_ts=$now                           # 刚空闲
yellow_ts=$((now - THRESHOLD_YELLOW * 60 - 60))   # 超过黄色阈值 1 分钟
red_ts=$((now - THRESHOLD_RED * 60 - 60))         # 超过红色阈值 1 分钟

info()  { echo -e "\033[36m[DEMO]\033[0m $*"; }
warn()  { echo -e "\033[33m[DEMO]\033[0m $*"; }

# ── 清理 ──────────────────────────────────────
demo_clean() {
  info "清理 demo state 文件..."
  for f in demo-green demo-yellow demo-red; do
    rm -f "$STATE_DIR/$f.json"
  done
  # 恢复备份的真实 state 文件
  if [[ -d "$BACKUP_DIR" ]]; then
    local count
    count=$(find "$BACKUP_DIR" -name '*.json' 2>/dev/null | wc -l | tr -d ' ')
    if [[ "$count" -gt 0 ]]; then
      info "恢复 $count 个备份的 state 文件..."
      cp "$BACKUP_DIR"/*.json "$STATE_DIR/" 2>/dev/null || true
    fi
    rm -rf "$BACKUP_DIR"
  fi
  info "清理完成。daemon 会在下一个 cycle 恢复正常颜色。"
  exit 0
}

if [[ "${1:-}" == "clean" ]]; then
  demo_clean
fi

# ── 前置检查 ──────────────────────────────────
if [[ -z "${ITERM_SESSION_ID:-}" ]]; then
  warn "未检测到 ITERM_SESSION_ID，请在 iTerm2 中运行此脚本。"
  exit 1
fi

# 检查 daemon 是否在跑
if ! launchctl list 2>/dev/null | grep -q tab-color-daemon; then
  warn "daemon 未运行，请先启动: launchctl kickstart -k gui/$(id -u)/com.duying.tab-color-daemon"
  exit 1
fi

# ── 备份现有 state 文件 ──────────────────────
mkdir -p "$BACKUP_DIR"
existing_count=$(find "$STATE_DIR" -maxdepth 1 -name '*.json' 2>/dev/null | wc -l | tr -d ' ')
if [[ "$existing_count" -gt 0 ]]; then
  info "备份 $existing_count 个现有 state 文件到 $BACKUP_DIR"
  cp "$STATE_DIR"/*.json "$BACKUP_DIR/" 2>/dev/null || true
  # 删掉真实的 state 文件，避免干扰 demo
  for f in "$STATE_DIR"/*.json; do
    [[ -f "$f" ]] && rm "$f"
  done
fi

# ── 生成假 state 文件 ────────────────────────
# 需要用户在 3 个 tab 里分别运行本脚本（或手动粘贴 ITERM_SESSION_ID）
# 这里用当前 session 的 UUID 做为 demo-green 的参照

# 尝试读取当前 tab 的其他 pane session（如果只有 1 个 tab 就用当前 session）
current_session="$ITERM_SESSION_ID"

info "当前 ITERM_SESSION_ID: $current_session"
info ""
info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
info "  录制步骤"
info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
info ""
info "这个脚本需要你在 3 个 iTerm2 tab 里各运行一次。"
info "每次运行会自动识别当前 tab，生成对应颜色的 state 文件。"
info ""
info "准备工作："
info "  1. 打开 iTerm2，新建 3 个 tab"
info "  2. 每个 tab 设置 Profile Name: Demo-A / Demo-B / Demo-C"
info "     (iTerm2 → Preferences → Profiles → 选中 → General → Name)"
info "  3. 每个 tab 进入本项目目录"
info "  4. 设置 tab 标题不显示路径："
info "     Preferences → Profiles → General → Title → 选 'Profile Name'"
info ""
info "开始录制："
info "  ① 在 Tab A (Demo-A) 运行:  bash demo_record.sh green"
info "  ② 在 Tab B (Demo-B) 运行:  bash demo_record.sh yellow"
info "  ③ 在 Tab C (Demo-C) 运行:  bash demo_record.sh red"
info "  ④ 等 2 秒，daemon 会上色"
info "  ⑤ 用 Cmd+Shift+1/2/3 切换 tab，录制切换过程"
info "  ⑥ 录完后运行: bash demo_record.sh clean"
info ""
info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
info ""

# ── 单个 tab 上色模式 ─────────────────────────
create_state() {
  local color="$1"
  local session_id="$ITERM_SESSION_ID"
  local ts

  case "$color" in
    green)
      ts=$green_ts
      info "创建 🟢 GREEN state (刚空闲)"
      ;;
    yellow)
      ts=$yellow_ts
      info "创建 🟡 YELLOW state (空闲 $(( (now - yellow_ts) / 60 )) 分钟)"
      ;;
    red)
      ts=$red_ts
      info "创建 🔴 RED state (空闲 $(( (now - red_ts) / 60 )) 分钟)"
      ;;
    *)
      warn "未知颜色: $color，请用 green/yellow/red"
      exit 1
      ;;
  esac

  cat > "$STATE_DIR/demo-${color}.json" << EOF
{
  "iterm2_session": "${session_id}",
  "claude_session": "demo-${color}",
  "idle_since": ${ts},
  "color_stage": "${color}"
}
EOF

  # 同时写一个 ANSI escape 即时设色（不需要等 daemon）
  # 直接写到当前 tty
  local tty_dev
  tty_dev=$(find_claude_tty 2>/dev/null || tty 2>/dev/null || echo "")
  if [[ -n "$tty_dev" && -w "$tty_dev" ]]; then
    case "$color" in
      green)  printf '\033]6;1;bg;red;brightness;30\033\\' > "$tty_dev"
              printf '\033]6;1;bg;green;brightness;180\033\\' > "$tty_dev"
              printf '\033]6;1;bg;blue;brightness;30\033\\' > "$tty_dev" ;;
      yellow) printf '\033]6;1;bg;red;brightness;220\033\\' > "$tty_dev"
              printf '\033]6;1;bg;green;brightness;160\033\\' > "$tty_dev"
              printf '\033]6;1;bg;blue;brightness;0\033\\' > "$tty_dev" ;;
      red)    printf '\033]6;1;bg;red;brightness;200\033\\' > "$tty_dev"
              printf '\033]6;1;bg;green;brightness;40\033\\' > "$tty_dev"
              printf '\033]6;1;bg;blue;brightness;40\033\\' > "$tty_dev" ;;
    esac
    info "ANSI escape 即时设色完成"
  fi

  info "state 文件已写入: $STATE_DIR/demo-${color}.json"
  info "daemon 会在 500ms 内确认颜色。"
}

# find_claude_tty — 从 hook 脚本复制的逻辑，找到真实 tty
find_claude_tty() {
  local pid=$$
  for _ in $(seq 1 20); do
    if [[ -r "/proc/$pid/fd/1" ]]; then
      local link
      link=$(readlink "/proc/$pid/fd/1" 2>/dev/null || true)
      if [[ "$link" == /dev/ttys* ]]; then
        echo "$link"
        return
      fi
    fi
    # macOS: 用 lsof
    local tty_candidate
    tty_candidate=$(lsof -p "$pid" -a -d 1 -Fn 2>/dev/null | grep '^n/dev/ttys' | head -1 | sed 's/^n//')
    if [[ -n "$tty_candidate" ]]; then
      echo "$tty_candidate"
      return
    fi
    local ppid
    ppid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
    [[ -z "$ppid" || "$ppid" == "0" || "$ppid" == "$pid" ]] && break
    pid=$ppid
  done
}

# ── 入口 ──────────────────────────────────────
if [[ -n "${1:-}" && "$1" != "clean" ]]; then
  create_state "$1"
fi
