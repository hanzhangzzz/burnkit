#!/bin/bash
# Production installer for iTerm2 Tab Color.
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
DAEMON_SRC="$SCRIPT_DIR/tab_color_daemon.py"
RESET_SRC="$SCRIPT_DIR/reset_tab.py"
CONFIG_SRC="$SCRIPT_DIR/config.sh"
CLAUDE_HOOK_LINK="$HOME/.claude/hooks/tab_color_hook.sh"
CODEX_HOOK_LINK="$HOME/.codex/hooks/tab_color_hook.sh"
PLIST_LINK="$HOME/Library/LaunchAgents/$LABEL.plist"

CLAUDE_SETTINGS_FILE="$HOME/.claude/settings.json"
CODEX_HOOKS_FILE="$HOME/.codex/hooks.json"
IDLE_STATE_DIR="$HOME/.claude/idle_state"
DAEMON_LOG="$IDLE_STATE_DIR/daemon.log"

DRY_RUN=0
INSTALL_CLAUDE=1
INSTALL_CODEX=1
INSTALL_LAUNCHD=1
CHECK_PYTHON=1

usage() {
    cat <<EOF
iTerm2 Tab Color 安装器

用法:
  bash tools/iterm2-tab-color/install.sh [选项]

选项:
  --dry-run            只打印将要执行的变更，不写文件、不启动服务
  --no-claude          不修改 ~/.claude/settings.json
  --no-codex           不修改 ~/.codex/hooks.json
  --no-launchd         不安装/启动 launchd daemon
  --skip-python-check  跳过 iterm2 Python 包检查
  -h, --help           显示帮助

会执行的变更:
  1. 创建/更新 ~/.claude/hooks/tab_color_hook.sh -> $HOOK_SRC
  2. 创建/更新 ~/.codex/hooks/tab_color_hook.sh -> $HOOK_SRC
  3. 生成 launchd plist: $PLIST_LINK
  4. 注册并启动 launchd daemon
  5. 注册 Claude hooks: Stop, PreToolUse
  6. 注册 Codex hooks: Stop, PreToolUse, UserPromptSubmit
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

require_file() {
    if [ ! -f "$1" ]; then
        log "错误：缺少文件 $1"
        exit 1
    fi
}

backup_file() {
    local path="$1"
    if [ ! -e "$path" ]; then
        return 0
    fi
    local backup="$path.bak.$TIMESTAMP"
    if [ "$DRY_RUN" -eq 1 ]; then
        log "[dry-run] 备份 $path -> $backup"
    else
        cp -p "$path" "$backup"
        log "已备份: $backup"
    fi
}

ensure_dir() {
    local path="$1"
    if [ "$DRY_RUN" -eq 1 ]; then
        log "[dry-run] mkdir -p $path"
    else
        mkdir -p "$path"
    fi
}

install_symlink() {
    local source="$1"
    local link="$2"
    local label="$3"

    if [ -L "$link" ]; then
        local current
        current="$(readlink "$link")"
        if [ "$current" = "$source" ]; then
            log "$label 已是正确软链: $link -> $source"
            return 0
        fi
        log "$label 软链将更新: $link"
        log "  旧目标: $current"
        log "  新目标: $source"
        run_cmd rm "$link"
    elif [ -e "$link" ]; then
        log "$label 已存在但不是软链，将先备份再替换: $link"
        backup_file "$link"
        run_cmd rm "$link"
    else
        log "$label 将创建: $link -> $source"
    fi

    run_cmd ln -s "$source" "$link"
}

find_python3() {
    local candidates candidate fallback seen
    candidates="$(command -v python3 2>/dev/null || true)
$(which -a python3 2>/dev/null || true)
/Users/duying/.pyenv/shims/python3
/opt/homebrew/bin/python3
/usr/local/bin/python3
/usr/bin/python3"
    fallback=""
    seen=":"

    while IFS= read -r candidate; do
        [ -n "$candidate" ] || continue
        [ -x "$candidate" ] || continue
        case "$seen" in
            *:"$candidate":*) continue ;;
        esac
        seen="$seen$candidate:"
        [ -n "$fallback" ] || fallback="$candidate"

        if [ "$CHECK_PYTHON" -eq 0 ]; then
            printf '%s\n' "$candidate"
            return 0
        fi

        if "$candidate" -c "import iterm2" >/dev/null 2>&1; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done <<EOF
$candidates
EOF

    if [ "$CHECK_PYTHON" -eq 1 ]; then
        log "错误：未找到已安装 iterm2 Python 包的 python3"
        log "安装命令: pip3 install iterm2"
        log "或使用 --skip-python-check 跳过检查"
        exit 1
    fi

    if [ -n "$fallback" ]; then
        printf '%s\n' "$fallback"
        return 0
    fi

    log "错误：未找到 python3"
    exit 1
}

write_plist() {
    section "生成 launchd plist"
    log "plist: $PLIST_LINK"
    log "daemon: $DAEMON_SRC"
    log "log: $DAEMON_LOG"

    if [ -L "$PLIST_LINK" ]; then
        log "launchd plist 当前是软链，将替换为真实文件: $PLIST_LINK -> $(readlink "$PLIST_LINK")"
        run_cmd rm "$PLIST_LINK"
    elif [ -e "$PLIST_LINK" ]; then
        log "launchd plist 已存在，将先备份再替换: $PLIST_LINK"
        backup_file "$PLIST_LINK"
        run_cmd rm "$PLIST_LINK"
    fi

    if [ "$DRY_RUN" -eq 1 ]; then
        log "[dry-run] 写入 $PLIST_LINK"
        return 0
    fi

    PYTHON3="$PYTHON3" \
    PLIST_LINK="$PLIST_LINK" \
    DAEMON_SRC="$DAEMON_SRC" \
    DAEMON_LOG="$DAEMON_LOG" \
    LABEL="$LABEL" \
    "$PYTHON3" - <<'PY'
import os
import plistlib

data = {
    "Label": os.environ["LABEL"],
    "ProgramArguments": [os.environ["PYTHON3"], os.environ["DAEMON_SRC"]],
    "RunAtLoad": True,
    "KeepAlive": True,
    "StandardOutPath": os.environ["DAEMON_LOG"],
    "StandardErrorPath": os.environ["DAEMON_LOG"],
    "ThrottleInterval": 10,
}

with open(os.environ["PLIST_LINK"], "wb") as f:
    plistlib.dump(data, f, sort_keys=False)
PY
}

update_claude_settings() {
    [ "$INSTALL_CLAUDE" -eq 1 ] || {
        log "跳过 Claude settings 更新"
        return 0
    }

    section "注册 Claude Code hooks"
    log "settings: $CLAUDE_SETTINGS_FILE"
    log "hook: $CLAUDE_HOOK_LINK"

    if [ -f "$CLAUDE_SETTINGS_FILE" ]; then
        backup_file "$CLAUDE_SETTINGS_FILE"
    elif [ "$DRY_RUN" -eq 1 ]; then
        log "[dry-run] 将创建 $CLAUDE_SETTINGS_FILE"
    fi

    DRY_RUN="$DRY_RUN" \
    SETTINGS_PATH="$CLAUDE_SETTINGS_FILE" \
    HOOK_COMMAND="$CLAUDE_HOOK_LINK" \
    "$PYTHON3" - <<'PY'
import json
import os
from pathlib import Path

dry_run = os.environ["DRY_RUN"] == "1"
settings_path = Path(os.environ["SETTINGS_PATH"])
hook_command = os.environ["HOOK_COMMAND"]

if settings_path.exists():
    with settings_path.open() as f:
        cfg = json.load(f)
else:
    cfg = {}

hooks = cfg.setdefault("hooks", {})
events = ["Stop", "PreToolUse"]
changed = False
removed = 0

for event_name in events:
    groups = hooks.setdefault(event_name, [])
    for group in groups:
        before = list(group.get("hooks", []))
        group["hooks"] = [
            h for h in before
            if "tab_color_hook.sh" not in h.get("command", "")
        ]
        removed += len(before) - len(group["hooks"])
        changed = changed or group["hooks"] != before

if removed:
    print(f"{'[dry-run] 将移除' if dry_run else '已移除'} {removed} 个旧 tab_color_hook.sh hook")

def ensure_hook(event_name, matcher, command):
    global changed
    groups = hooks.setdefault(event_name, [])
    target = None
    for group in groups:
        if group.get("matcher") == matcher:
            target = group
            break
    if target is None:
        target = {"matcher": matcher, "hooks": []}
        groups.append(target)
        changed = True
    item = {"type": "command", "command": command}
    if item not in target["hooks"]:
        target["hooks"].append(item)
        changed = True
        print(f"{'[dry-run] 将注册' if dry_run else '已注册'}: {event_name}/{matcher}")
    else:
        print(f"已存在: {event_name}/{matcher}")

ensure_hook("Stop", "*", hook_command)
ensure_hook("PreToolUse", "*", hook_command)

if changed:
    if dry_run:
        print(f"[dry-run] 将写入 {settings_path}")
    else:
        settings_path.parent.mkdir(parents=True, exist_ok=True)
        with settings_path.open("w") as f:
            json.dump(cfg, f, indent=2, ensure_ascii=False)
            f.write("\n")
        print(f"已更新: {settings_path}")
else:
    print("无需变更")
PY
}

update_codex_hooks() {
    [ "$INSTALL_CODEX" -eq 1 ] || {
        log "跳过 Codex hooks 更新"
        return 0
    }

    section "注册 Codex hooks"
    log "hooks: $CODEX_HOOKS_FILE"
    log "hook: $CODEX_HOOK_LINK"

    if [ -f "$CODEX_HOOKS_FILE" ]; then
        backup_file "$CODEX_HOOKS_FILE"
    elif [ "$DRY_RUN" -eq 1 ]; then
        log "[dry-run] 将创建 $CODEX_HOOKS_FILE"
    fi

    DRY_RUN="$DRY_RUN" \
    HOOKS_PATH="$CODEX_HOOKS_FILE" \
    HOOK_COMMAND="'$CODEX_HOOK_LINK' --agent codex >/dev/null 2>&1 || true" \
    "$PYTHON3" - <<'PY'
import json
import os
from pathlib import Path

dry_run = os.environ["DRY_RUN"] == "1"
hooks_path = Path(os.environ["HOOKS_PATH"])
hook_command = os.environ["HOOK_COMMAND"]

if hooks_path.exists():
    with hooks_path.open() as f:
        cfg = json.load(f)
else:
    cfg = {"hooks": {}}

hooks = cfg.setdefault("hooks", {})
events = ["Stop", "PreToolUse", "UserPromptSubmit"]
changed = False
removed = 0

for event_name in events:
    groups = hooks.setdefault(event_name, [])
    for group in groups:
        before = list(group.get("hooks", []))
        group["hooks"] = [
            h for h in before
            if "tab_color_hook.sh" not in h.get("command", "")
        ]
        removed += len(before) - len(group["hooks"])
        changed = changed or group["hooks"] != before

if removed:
    print(f"{'[dry-run] 将移除' if dry_run else '已移除'} {removed} 个旧 tab_color_hook.sh hook")

def ensure_hook(event_name, matcher, command):
    global changed
    groups = hooks.setdefault(event_name, [])
    target = None
    for group in groups:
        if group.get("matcher") == matcher:
            target = group
            break
    if target is None:
        target = {"matcher": matcher, "hooks": []}
        groups.append(target)
        changed = True
    item = {"type": "command", "command": command}
    if item not in target["hooks"]:
        target["hooks"].append(item)
        changed = True
        print(f"{'[dry-run] 将注册' if dry_run else '已注册'}: {event_name}/{matcher}")
    else:
        print(f"已存在: {event_name}/{matcher}")

for event_name in events:
    ensure_hook(event_name, "*", hook_command)

if changed:
    if dry_run:
        print(f"[dry-run] 将写入 {hooks_path}")
    else:
        hooks_path.parent.mkdir(parents=True, exist_ok=True)
        with hooks_path.open("w") as f:
            json.dump(cfg, f, indent=2, ensure_ascii=False)
            f.write("\n")
        print(f"已更新: {hooks_path}")
else:
    print("无需变更")
PY
}

restart_launchd() {
    [ "$INSTALL_LAUNCHD" -eq 1 ] || {
        log "跳过 launchd 安装"
        return 0
    }

    section "安装并启动 launchd daemon"

    if [ "$DRY_RUN" -eq 1 ]; then
        log "[dry-run] launchctl bootout gui/$(id -u)/$LABEL"
        log "[dry-run] launchctl bootstrap gui/$(id -u) $PLIST_LINK"
        log "[dry-run] launchctl kickstart -k gui/$(id -u)/$LABEL"
        return 0
    fi

    launchctl bootout "gui/$(id -u)/$LABEL" >/dev/null 2>&1 || true
    launchctl unload "$PLIST_LINK" >/dev/null 2>&1 || true
    launchctl bootstrap "gui/$(id -u)" "$PLIST_LINK" >/dev/null 2>&1 || launchctl load "$PLIST_LINK"
    launchctl kickstart -k "gui/$(id -u)/$LABEL" >/dev/null 2>&1 || true

    if launchctl print "gui/$(id -u)/$LABEL" >/dev/null 2>&1; then
        log "daemon 已注册: gui/$(id -u)/$LABEL"
    else
        log "警告：daemon 未能确认注册，请查看日志: $DAEMON_LOG"
    fi
}

parse_args() {
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --dry-run) DRY_RUN=1 ;;
            --no-claude) INSTALL_CLAUDE=0 ;;
            --no-codex) INSTALL_CODEX=0 ;;
            --no-launchd) INSTALL_LAUNCHD=0 ;;
            --skip-python-check) CHECK_PYTHON=0 ;;
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

    section "iTerm2 Tab Color 安装"
    log "工具目录: $SCRIPT_DIR"
    log "仓库目录: $REPO_ROOT"
    [ "$DRY_RUN" -eq 1 ] && log "模式: dry-run，不会写入任何文件"

    require_file "$HOOK_SRC"
    require_file "$DAEMON_SRC"
    require_file "$RESET_SRC"
    require_file "$CONFIG_SRC"

    PYTHON3="$(find_python3)"
    log "Python: $PYTHON3"

    if [ "$CHECK_PYTHON" -eq 1 ] && ! "$PYTHON3" -c "import iterm2" >/dev/null 2>&1; then
        log "错误：未安装 iterm2 Python 包"
        log "安装命令: pip3 install iterm2"
        exit 1
    fi

    section "创建运行目录"
    ensure_dir "$HOME/.claude/hooks"
    ensure_dir "$HOME/.codex/hooks"
    ensure_dir "$IDLE_STATE_DIR"
    ensure_dir "$HOME/Library/LaunchAgents"

    section "安装 hook 软链"
    run_cmd chmod +x "$HOOK_SRC" "$DAEMON_SRC" "$RESET_SRC"
    install_symlink "$HOOK_SRC" "$CLAUDE_HOOK_LINK" "Claude hook"
    install_symlink "$HOOK_SRC" "$CODEX_HOOK_LINK" "Codex hook"

    write_plist
    update_claude_settings
    update_codex_hooks
    restart_launchd

    section "安装完成"
    log "已配置:"
    [ "$INSTALL_CLAUDE" -eq 1 ] && log "  Claude hooks -> $CLAUDE_HOOK_LINK"
    [ "$INSTALL_CODEX" -eq 1 ] && log "  Codex hooks  -> $CODEX_HOOK_LINK"
    [ "$INSTALL_LAUNCHD" -eq 1 ] && log "  launchd      -> $PLIST_LINK"
    log ""
    log "验证命令:"
    log "  launchctl print gui/$(id -u)/$LABEL"
    log "  tail -f $DAEMON_LOG"
    log ""
    log "卸载命令:"
    log "  bash $SCRIPT_DIR/uninstall.sh"
}

main "$@"
