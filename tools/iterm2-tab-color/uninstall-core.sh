#!/bin/bash
# Production uninstaller for iTerm2 Tab Color.
set -euo pipefail

LABEL="com.duying.tab-color-daemon"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"

resolve_path() {
    local source="$1"
    while [ -L "$source" ]; do
        local dir target
        dir="$(cd "$(dirname "$source")" && pwd)"
        target="$(readlink "$source")"
        case "$target" in
            /*) source="$target" ;;
            *) source="$dir/$target" ;;
        esac
    done
    cd "$(dirname "$source")" && pwd
}

SCRIPT_DIR="$(resolve_path "${BASH_SOURCE[0]}")"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HOOK_SRC="$SCRIPT_DIR/tab_color_hook.sh"
CLAUDE_HOOK_LINK="$HOME/.claude/hooks/tab_color_hook.sh"
CODEX_HOOK_LINK="$HOME/.codex/hooks/tab_color_hook.sh"
PLIST_LINK="$HOME/Library/LaunchAgents/$LABEL.plist"

CLAUDE_SETTINGS_FILE="$HOME/.claude/settings.json"
CODEX_HOOKS_FILE="$HOME/.codex/hooks.json"
IDLE_STATE_DIR="$HOME/.claude/idle_state"
DAEMON_LOG="$IDLE_STATE_DIR/daemon.log"

DRY_RUN=0
PURGE_STATE=0
REMOVE_CLAUDE=1
REMOVE_CODEX=1
REMOVE_LAUNCHD=1

usage() {
    cat <<EOF
iTerm2 Tab Color 卸载器

用法:
  bin/burnkit uninstall tabs [选项]

选项:
  --dry-run       只打印将要执行的变更，不写文件
  --keep-claude   不修改 ~/.claude/settings.json，不删除 Claude hook 文件
  --keep-codex    不修改 ~/.codex/hooks.json，不删除 Codex hook 文件
  --keep-launchd  不停止/移除 launchd daemon
  --purge-state   删除 ~/.claude/idle_state 下本工具 state 文件和 daemon.log
  -h, --help      显示帮助

默认会执行:
  1. 停止 launchd daemon
  2. 删除 ~/.claude/hooks/tab_color_hook.sh
  3. 删除 ~/.codex/hooks/tab_color_hook.sh
  4. 删除 ~/Library/LaunchAgents/$LABEL.plist
  5. 从 Claude/Codex JSON 配置中移除 tab_color_hook.sh hook

默认保留:
  - $IDLE_STATE_DIR
  - $DAEMON_LOG
EOF
}

log() {
    printf '%s\n' "$*"
}

section() {
    printf '\n%s\n' "$1"
    printf '%s\n' "----------------------------------------"
}

run_cmd() {
    if [ "$DRY_RUN" -eq 1 ]; then
        printf '[dry-run] %q' "$1"
        shift || true
        for arg in "$@"; do
            printf ' %q' "$arg"
        done
        printf '\n'
    else
        "$@"
    fi
}

find_python3() {
    if ! command -v python3 >/dev/null 2>&1; then
        log "错误：未找到 python3"
        exit 1
    fi
    command -v python3
}

backup_file() {
    local path="$1"
    [ -f "$path" ] || return 0
    local backup="$path.bak.$TIMESTAMP"
    if [ "$DRY_RUN" -eq 1 ]; then
        log "[dry-run] 备份 $path -> $backup"
    else
        cp -p "$path" "$backup"
        log "已备份: $backup"
    fi
}

remove_hook_file() {
    local path="$1"
    local label="$2"

    if [ -L "$path" ]; then
        if [ "$DRY_RUN" -eq 1 ]; then
            log "将删除 $label 软链: $path -> $(readlink "$path")"
        else
            log "删除 $label 软链: $path -> $(readlink "$path")"
        fi
        run_cmd rm "$path"
    elif [ -f "$path" ]; then
        if [ "$DRY_RUN" -eq 1 ]; then
            log "将删除 $label 文件: $path"
        else
            log "删除 $label 文件: $path"
        fi
        run_cmd rm "$path"
    elif [ -e "$path" ]; then
        log "跳过 $label：$path 存在但不是普通文件或软链，未删除"
    else
        log "$label 不存在: $path"
    fi
}

remove_generated_file_if_present() {
    local path="$1"
    local label="$2"

    if [ -L "$path" ]; then
        if [ "$DRY_RUN" -eq 1 ]; then
            log "将删除 $label 软链: $path -> $(readlink "$path")"
        else
            log "删除 $label 软链: $path -> $(readlink "$path")"
        fi
        run_cmd rm "$path"
    elif [ -f "$path" ]; then
        log "删除 $label 文件: $path"
        run_cmd rm "$path"
    elif [ -e "$path" ]; then
        log "跳过 $label：$path 存在但不是普通文件或软链，未删除"
    else
        log "$label 不存在: $path"
    fi
}

remove_hook_entries() {
    local path="$1"
    local label="$2"

    [ -f "$path" ] || {
        log "$label 配置不存在: $path"
        return 0
    }

    backup_file "$path"

    DRY_RUN="$DRY_RUN" CONFIG_PATH="$path" LABEL_NAME="$label" "$PYTHON3" - <<'PY'
import json
import os
from pathlib import Path

dry_run = os.environ["DRY_RUN"] == "1"
path = Path(os.environ["CONFIG_PATH"])
label = os.environ["LABEL_NAME"]

with path.open() as f:
    cfg = json.load(f)

hooks = cfg.get("hooks", {})
removed = 0

for groups in hooks.values():
    if not isinstance(groups, list):
        continue
    for group in groups:
        before = list(group.get("hooks", []))
        group["hooks"] = [
            h for h in before
            if "tab_color_hook.sh" not in h.get("command", "")
        ]
        removed += len(before) - len(group["hooks"])

if removed == 0:
    print(f"{label}: 无需移除 hook")
elif dry_run:
    print(f"[dry-run] {label}: 将移除 {removed} 个 tab_color_hook.sh hook")
else:
    with path.open("w") as f:
        json.dump(cfg, f, indent=2, ensure_ascii=False)
        f.write("\n")
    print(f"{label}: 已移除 {removed} 个 tab_color_hook.sh hook")
PY
}

stop_launchd() {
    [ "$REMOVE_LAUNCHD" -eq 1 ] || {
        log "跳过 launchd 卸载"
        return 0
    }

    section "停止并移除 launchd daemon"
    if [ "$DRY_RUN" -eq 1 ]; then
        log "[dry-run] launchctl bootout gui/$(id -u)/$LABEL"
    else
        launchctl bootout "gui/$(id -u)/$LABEL" >/dev/null 2>&1 || true
        launchctl unload "$PLIST_LINK" >/dev/null 2>&1 || true
    fi
    remove_generated_file_if_present "$PLIST_LINK" "launchd plist"
}

purge_state() {
    [ "$PURGE_STATE" -eq 1 ] || {
        log "保留 state/log: $IDLE_STATE_DIR"
        return 0
    }

    section "删除 state/log"
    if [ ! -d "$IDLE_STATE_DIR" ]; then
        log "state 目录不存在: $IDLE_STATE_DIR"
        return 0
    fi

    if [ "$DRY_RUN" -eq 1 ]; then
        log "[dry-run] 删除 $IDLE_STATE_DIR/*.json"
        log "[dry-run] 删除 $DAEMON_LOG"
    else
        find "$IDLE_STATE_DIR" -maxdepth 1 -name '*.json' -delete
        rm -f "$DAEMON_LOG"
    fi
}

parse_args() {
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --dry-run) DRY_RUN=1 ;;
            --keep-claude) REMOVE_CLAUDE=0 ;;
            --keep-codex) REMOVE_CODEX=0 ;;
            --keep-launchd) REMOVE_LAUNCHD=0 ;;
            --purge-state) PURGE_STATE=1 ;;
            -h|--help) usage; exit 0 ;;
            *)
                log "错误：未知参数 $1"
                usage
                exit 1
                ;;
        esac
        shift
    done
}

main() {
    parse_args "$@"

    section "iTerm2 Tab Color 卸载"
    log "工具目录: $SCRIPT_DIR"
    [ "$DRY_RUN" -eq 1 ] && log "模式: dry-run，不会写入任何文件"

    PYTHON3="$(find_python3)"

    stop_launchd

    section "移除 hook 文件"
    if [ "$REMOVE_CLAUDE" -eq 1 ]; then
        remove_hook_file "$CLAUDE_HOOK_LINK" "Claude hook"
    else
        log "跳过 Claude hook 文件"
    fi
    if [ "$REMOVE_CODEX" -eq 1 ]; then
        remove_hook_file "$CODEX_HOOK_LINK" "Codex hook"
    else
        log "跳过 Codex hook 文件"
    fi

    section "清理 JSON hook 配置"
    [ "$REMOVE_CLAUDE" -eq 1 ] && remove_hook_entries "$CLAUDE_SETTINGS_FILE" "Claude"
    [ "$REMOVE_CODEX" -eq 1 ] && remove_hook_entries "$CODEX_HOOKS_FILE" "Codex"

    purge_state

    section "卸载完成"
    log "已处理:"
    [ "$REMOVE_LAUNCHD" -eq 1 ] && log "  launchd daemon: $LABEL"
    [ "$REMOVE_CLAUDE" -eq 1 ] && log "  Claude hook: $CLAUDE_HOOK_LINK"
    [ "$REMOVE_CODEX" -eq 1 ] && log "  Codex hook: $CODEX_HOOK_LINK"
    [ "$PURGE_STATE" -eq 0 ] && log "  state/log 已保留，可用 --purge-state 删除"
    log ""
    log "重新安装:"
    log "  $REPO_ROOT/bin/burnkit install tabs"
}

main "$@"
