#!/usr/bin/env python3
"""
iTerm2 Tab Color Daemon
======================
守护进程脚本，通过 launchd 在登录时自动启动。

职责：
  - 监听 ~/.claude/idle_state/ 目录变化，有新文件立即响应
  - 新状态文件出现（Stop hook 写入）→ 立即用 API 设绿色
  - 每 POLL_INTERVAL 秒轮询，根据空闲时长升级颜色：黄 → 红
  - 状态文件被删除（PreToolUse hook）→ 立即恢复默认色
  - launchd KeepAlive=true 保证退出后自动重启

配置：同目录 config.sh
"""

import asyncio
import json
import os
import time
from pathlib import Path

import iterm2

# ------------------------------------------------------------------ #
#  配置加载
# ------------------------------------------------------------------ #

def load_config() -> dict:
    defaults = {
        "THRESHOLD_YELLOW": 10,
        "THRESHOLD_RED": 20,
        "COLOR_GREEN_R": 30,    "COLOR_GREEN_G": 180, "COLOR_GREEN_B": 30,
        "COLOR_YELLOW_R": 220,  "COLOR_YELLOW_G": 160, "COLOR_YELLOW_B": 0,
        "COLOR_RED_R": 200,     "COLOR_RED_G": 40,    "COLOR_RED_B": 40,
        "POLL_INTERVAL": 30,
        "IDLE_STATE_DIR": str(Path.home() / ".claude" / "idle_state"),
        "CONCURRENT_TARGET": 3,
    }
    script_path = Path(os.path.realpath(__file__))
    config_path = script_path.parent / "config.sh"
    if not config_path.exists():
        return defaults
    cfg = dict(defaults)
    with open(config_path) as f:
        for line in f:
            line = line.strip()
            if line.startswith("#") or "=" not in line:
                continue
            key, _, val = line.partition("=")
            key = key.strip()
            val = val.split("#")[0].strip().strip('"').strip("'")
            val = val.replace("$HOME", str(Path.home()))
            if key in cfg:
                try:
                    cfg[key] = int(val)
                except ValueError:
                    cfg[key] = val
    return cfg


CFG = load_config()

THRESHOLD_YELLOW_SEC = CFG["THRESHOLD_YELLOW"] * 60
THRESHOLD_RED_SEC    = CFG["THRESHOLD_RED"] * 60
POLL_INTERVAL        = CFG["POLL_INTERVAL"]
IDLE_STATE_DIR       = Path(CFG["IDLE_STATE_DIR"])
CONCURRENT_TARGET    = CFG["CONCURRENT_TARGET"]

COLOR_GREEN  = iterm2.Color(CFG["COLOR_GREEN_R"],  CFG["COLOR_GREEN_G"],  CFG["COLOR_GREEN_B"])
COLOR_YELLOW = iterm2.Color(CFG["COLOR_YELLOW_R"], CFG["COLOR_YELLOW_G"], CFG["COLOR_YELLOW_B"])
COLOR_RED    = iterm2.Color(CFG["COLOR_RED_R"],    CFG["COLOR_RED_G"],    CFG["COLOR_RED_B"])


# ------------------------------------------------------------------ #
#  辅助函数
# ------------------------------------------------------------------ #

def log(msg: str):
    ts = time.strftime("%Y-%m-%d %H:%M:%S")
    print(f"[tab-color-daemon] {ts}  {msg}", flush=True)


def extract_uuid(iterm2_session_id: str) -> str:
    """'w0t1p2:UUID' → 'UUID'，纯 UUID 原样返回。"""
    return iterm2_session_id.split(":")[-1] if ":" in iterm2_session_id else iterm2_session_id


def is_active_tab(app, session) -> bool:
    """判断 session 所在 tab 是否为当前活跃 tab。"""
    try:
        window = session.tab.window if session.tab else None
        if window is None:
            return False
        active_tab = window.current_tab
        return active_tab is not None and active_tab.tab_id == session.tab.tab_id
    except Exception:
        return False


async def apply_tab_color(connection, iterm2_session_id: str, color: iterm2.Color | None):
    """
    给同一 tab 下所有 pane 都设 tab color。
    活跃 tab 不上色（保持白色），切走后再着色 → 一眼看出当前 tab。
    color=None 表示重置（恢复活跃/关闭），无论是否活跃都执行。
    """
    uuid = extract_uuid(iterm2_session_id)
    app = await iterm2.async_get_app(connection)
    session = app.get_session_by_id(uuid)
    if session is None:
        return

    # 设色时跳过活跃 tab（用户已经在这了，不需要通知）
    if color is not None and is_active_tab(app, session):
        return

    # 找到目标 session 所在 tab 的所有 session（包括分屏 pane）
    target_tab = session.tab
    if target_tab is None:
        target_sessions = [session]
    else:
        target_sessions = list(target_tab.sessions)

    for s in target_sessions:
        change = iterm2.LocalWriteOnlyProfile()
        if color is None:
            change.set_use_tab_color(False)
        else:
            change.set_tab_color(color)
            change.set_use_tab_color(True)
        await s.async_set_profile_properties(change)


def compute_color_stage(idle_seconds: float) -> str:
    if idle_seconds >= THRESHOLD_RED_SEC:
        return "red"
    elif idle_seconds >= THRESHOLD_YELLOW_SEC:
        return "yellow"
    else:
        return "green"


def color_for_stage(stage: str) -> iterm2.Color:
    return {"green": COLOR_GREEN, "yellow": COLOR_YELLOW, "red": COLOR_RED}[stage]


def read_state_files() -> dict[str, dict]:
    """读取所有 idle_state/*.json，返回 {文件路径: state_dict}。"""
    result = {}
    if not IDLE_STATE_DIR.exists():
        return result
    for f in IDLE_STATE_DIR.glob("*.json"):
        try:
            result[str(f)] = json.loads(f.read_text())
        except (json.JSONDecodeError, OSError):
            pass
    return result


def update_stage_file(path: str, state: dict, stage: str):
    state["color_stage"] = stage
    try:
        Path(path).write_text(json.dumps(state))
    except OSError:
        pass


# ------------------------------------------------------------------ #
#  目录监听：用轮询检测新增/删除文件，立即响应
# ------------------------------------------------------------------ #

async def watch_idle_dir(connection):
    """
    每秒扫描 idle_state 目录：
    - 启动时对所有已有文件按当前空闲时长立即设色
    - 新文件（Stop hook 刚写入）→ 立即设绿
    - 文件消失（PreToolUse hook 删除）→ 立即重置
    """
    known: dict[str, dict] = {}

    # 启动时强制刷新所有已有文件
    now = time.time()
    for path, state in read_state_files().items():
        sid = state.get("iterm2_session", "")
        if not sid:
            continue
        idle_seconds = now - state.get("idle_since", now)
        stage = compute_color_stage(idle_seconds)
        log(f"启动恢复: session {extract_uuid(sid)[:8]}… "
            f"idle {idle_seconds/60:.1f}min → {stage}")
        await apply_tab_color(connection, sid, color_for_stage(stage))
        update_stage_file(path, state, stage)
        known[path] = state

    while True:
        await asyncio.sleep(1)
        try:
            current = read_state_files()

            # 新出现的文件 → 立即设绿
            for path, state in current.items():
                if path not in known:
                    sid = state.get("iterm2_session", "")
                    if sid:
                        log(f"新 idle session {extract_uuid(sid)[:8]}… → green")
                        await apply_tab_color(connection, sid, COLOR_GREEN)
                        update_stage_file(path, state, "green")

            # 消失的文件 → 立即重置
            for path, state in known.items():
                if path not in current:
                    sid = state.get("iterm2_session", "")
                    if sid:
                        log(f"session {extract_uuid(sid)[:8]}… 恢复活跃 → 重置颜色")
                        await apply_tab_color(connection, sid, None)

            known = current
        except Exception as e:
            log(f"watch 出错: {e}")
            # 连接断开，退出让 launchd 重启
            if "close" in str(e).lower() or "connection" in str(e).lower():
                log("连接已断，退出等待 launchd 重启")
                return


# ------------------------------------------------------------------ #
#  定时轮询：处理黄/红升级
# ------------------------------------------------------------------ #

async def color_poller(connection):
    """每 POLL_INTERVAL 秒检查空闲时长，按需升级颜色。"""
    log(f"守护进程启动 ✅  监听间隔=1s  轮询间隔={POLL_INTERVAL}s  "
        f"黄色阈值={CFG['THRESHOLD_YELLOW']}min  红色阈值={CFG['THRESHOLD_RED']}min")

    while True:
        await asyncio.sleep(POLL_INTERVAL)
        try:
            now = time.time()
            states = read_state_files()
            idle_count = len(states)

            for path, state in states.items():
                sid        = state.get("iterm2_session", "")
                idle_since = state.get("idle_since", now)
                prev_stage = state.get("color_stage", "green")

                if not sid:
                    continue

                idle_seconds = now - idle_since
                new_stage    = compute_color_stage(idle_seconds)

                if new_stage != prev_stage:
                    log(f"session {extract_uuid(sid)[:8]}… "
                        f"idle {idle_seconds/60:.1f}min → {prev_stage} → {new_stage}")
                    await apply_tab_color(connection, sid, color_for_stage(new_stage))
                    update_stage_file(path, state, new_stage)

            if 0 < idle_count < CONCURRENT_TARGET:
                log(f"提示：当前 {idle_count} 个 tab 等待中，"
                    f"目标并发 {CONCURRENT_TARGET}，可以多开任务 💪")

        except Exception as e:
            log(f"poll 出错: {e}")
            if "close" in str(e).lower() or "connection" in str(e).lower():
                log("连接已断，退出等待 launchd 重启")
                return


# ------------------------------------------------------------------ #
#  入口
# ------------------------------------------------------------------ #

async def active_tab_watcher(connection):
    """
    每 2 秒检查活跃 tab 变化：
    - 切走一个 idle tab → 补上它的状态色
    - 切到一个 idle tab → 去掉颜色（保持白色）
    """
    prev_active_tab_ids: set[str] = set()

    while True:
        await asyncio.sleep(0.5)
        try:
            app = await iterm2.async_get_app(connection)

            # 收集当前所有窗口的活跃 tab
            cur_active_tab_ids: set[str] = set()
            for window in app.windows:
                ct = window.current_tab
                if ct:
                    cur_active_tab_ids.add(ct.tab_id)

            # 加载所有 idle session 的 tab_id → color 映射
            idle_tab_colors: dict[str, tuple[str, iterm2.Color]] = {}
            for state in read_state_files().values():
                sid = state.get("iterm2_session", "")
                if not sid:
                    continue
                uuid = extract_uuid(sid)
                session = app.get_session_by_id(uuid)
                if session is None or session.tab is None:
                    continue
                tab_id = session.tab.tab_id
                stage = state.get("color_stage", "green")
                idle_tab_colors[tab_id] = (sid, color_for_stage(stage))

            # 切走的 tab（之前活跃，现在不活跃）→ 补色
            gone_active = prev_active_tab_ids - cur_active_tab_ids
            for tab_id in gone_active:
                if tab_id in idle_tab_colors:
                    sid, color = idle_tab_colors[tab_id]
                    log(f"tab 切走 → 补色 {extract_uuid(sid)[:8]}…")
                    await apply_tab_color(connection, sid, color)

            # 切到的 tab（现在活跃，之前不活跃）→ 去色
            new_active = cur_active_tab_ids - prev_active_tab_ids
            for tab_id in new_active:
                if tab_id in idle_tab_colors:
                    sid, _ = idle_tab_colors[tab_id]
                    log(f"tab 切入 → 去色 {extract_uuid(sid)[:8]}…")
                    await apply_tab_color(connection, sid, None)

            prev_active_tab_ids = cur_active_tab_ids

        except Exception as e:
            log(f"active tab watch 出错: {e}")
            if "close" in str(e).lower() or "connection" in str(e).lower():
                log("连接已断，退出等待 launchd 重启")
                return


async def main(connection):
    asyncio.create_task(watch_idle_dir(connection))
    asyncio.create_task(color_poller(connection))
    asyncio.create_task(active_tab_watcher(connection))
    await asyncio.Event().wait()


iterm2.run_forever(main)
