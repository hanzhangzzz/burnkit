#!/usr/bin/env python3
"""
iTerm2 Tab Color Daemon
======================
守护进程脚本，通过 launchd 在登录时自动启动。

架构：单一写入者
  - watch (500ms)：唯一负责写 tab 颜色的循环
    读 state 文件 → 根据色阶 + 活跃状态 → 应用颜色
  - poller (30s)：只更新 state 文件的元数据
    孤儿清理、同 tab 去重、色阶升级（green → yellow → red）
    绝不直接操作 iTerm2 API

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


async def apply_tab_color(connection, iterm2_session_id: str, color, *, app=None, session=None):
    """
    给同一 tab 下所有 pane 都设 tab color。
    color=None 表示重置（恢复默认色）。
    活跃 tab 上色时跳过（用户已经在看了）。
    """
    uuid = extract_uuid(iterm2_session_id)
    if app is None or session is None:
        app = await iterm2.async_get_app(connection)
        session = app.get_session_by_id(uuid)
    if session is None:
        return

    if color is not None and is_active_tab(app, session):
        return

    target_tab = session.tab
    target_sessions = [session] if target_tab is None else list(target_tab.sessions)

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
#  watch：唯一的颜色写入者（1s 周期）
# ------------------------------------------------------------------ #

async def watch_idle_dir(connection):
    """
    每秒扫描，唯一负责 iTerm2 API 调用的循环。

    逻辑：
    - 有 state 文件 + 非活跃 tab → 按 color_stage 上色
    - 有 state 文件 + 活跃 tab   → 重置（白色）
    - 无 state 文件（刚删除）     → 重置（白色）
    """
    known: dict[str, dict] = {}

    # 启动恢复：对所有已有文件按当前空闲时长设色
    now = time.time()
    for path, state in read_state_files().items():
        sid = state.get("iterm2_session", "")
        if not sid:
            continue
        idle_seconds = now - state.get("idle_since", now)
        stage = compute_color_stage(idle_seconds)
        update_stage_file(path, state, stage)
        log(f"启动恢复: session {extract_uuid(sid)[:8]}… idle {idle_seconds/60:.1f}min → {stage}")
        known[path] = state

    # 启动后立即做一次全量上色
    await _apply_all_colors(connection)

    while True:
        await asyncio.sleep(0.5)
        try:
            current = read_state_files()

            # 消失的文件 → 记住 session 以便重置
            disappeared = []
            for path, state in known.items():
                if path not in current:
                    sid = state.get("iterm2_session", "")
                    if sid:
                        log(f"session {extract_uuid(sid)[:8]}… 恢复活跃 → 重置颜色")
                        disappeared.append(sid)

            known = current

            # 全量刷新颜色：每个 state 文件根据 活跃/非活跃 决定颜色
            await _apply_all_colors(connection)

            # 重置已消失的 session
            for sid in disappeared:
                await apply_tab_color(connection, sid, None)

        except Exception as e:
            log(f"watch 出错: {e}")
            if "close" in str(e).lower() or "connection" in str(e).lower():
                log("连接已断，退出等待 launchd 重启")
                return


async def _apply_all_colors(connection):
    """读所有 state 文件，根据 color_stage + is_active 统一应用颜色。"""
    states = read_state_files()
    if not states:
        return

    app = await iterm2.async_get_app(connection)

    for path, state in states.items():
        sid = state.get("iterm2_session", "")
        if not sid:
            continue
        uuid = extract_uuid(sid)
        session = app.get_session_by_id(uuid)
        if session is None:
            continue

        active = is_active_tab(app, session)
        stage = state.get("color_stage", "green")

        if active:
            await apply_tab_color(connection, sid, None, app=app, session=session)
        else:
            await apply_tab_color(connection, sid, color_for_stage(stage), app=app, session=session)


# ------------------------------------------------------------------ #
#  poller：只更新 state 文件，不碰颜色（30s 周期）
# ------------------------------------------------------------------ #

async def color_poller(connection):
    """
    每 POLL_INTERVAL 秒更新 state 文件元数据：
    - 清理孤儿 state 文件（iTerm2 session 已不存在）
    - 同 tab 多 session 去重（只保留最新 idle_since）
    - 升级 color_stage（green → yellow → red）

    绝不直接调用 iTerm2 API 设色 —— 那是 watch 的职责。
    """
    log(f"守护进程启动 ✅  监听间隔=1s  轮询间隔={POLL_INTERVAL}s  "
        f"黄色阈值={CFG['THRESHOLD_YELLOW']}min  红色阈值={CFG['THRESHOLD_RED']}min")

    while True:
        await asyncio.sleep(POLL_INTERVAL)
        try:
            now = time.time()
            states = read_state_files()
            app = await iterm2.async_get_app(connection)

            # ---- 1. 清理孤儿文件 ----
            for path, state in list(states.items()):
                sid = state.get("iterm2_session", "")
                if not sid:
                    continue
                uuid = extract_uuid(sid)
                if app.get_session_by_id(uuid) is None:
                    log(f"清理孤儿: {uuid[:8]}… iTerm2 session 已不存在")
                    try:
                        Path(path).unlink()
                    except OSError:
                        pass
                    states.pop(path, None)

            # ---- 2. 同 tab 多 session 去重 ----
            tab_sessions: dict[str, tuple[str, dict]] = {}
            for path, state in list(states.items()):
                sid = state.get("iterm2_session", "")
                if not sid:
                    continue
                uuid = extract_uuid(sid)
                session = app.get_session_by_id(uuid)
                if session is None or session.tab is None:
                    continue
                tab_id = session.tab.tab_id
                if tab_id in tab_sessions:
                    _, existing_state = tab_sessions[tab_id]
                    if state.get("idle_since", 0) > existing_state.get("idle_since", 0):
                        old_path = tab_sessions[tab_id][0]
                        log(f"同 tab 去重: 删除旧 session {extract_uuid(states[old_path].get('iterm2_session',''))[:8]}…")
                        try:
                            Path(old_path).unlink()
                        except OSError:
                            pass
                        states.pop(old_path, None)
                        tab_sessions[tab_id] = (path, state)
                    else:
                        log(f"同 tab 去重: 删除旧 session {uuid[:8]}…")
                        try:
                            Path(path).unlink()
                        except OSError:
                            pass
                        states.pop(path, None)
                else:
                    tab_sessions[tab_id] = (path, state)

            # ---- 3. 升级 color_stage（只改文件，不改颜色）----
            for path, state in states.items():
                idle_since = state.get("idle_since", now)
                prev_stage = state.get("color_stage", "green")
                idle_seconds = now - idle_since
                new_stage = compute_color_stage(idle_seconds)

                if new_stage != prev_stage:
                    log(f"session {extract_uuid(state.get('iterm2_session',''))[:8]}… "
                        f"idle {idle_seconds/60:.1f}min → {prev_stage} → {new_stage}")
                    update_stage_file(path, state, new_stage)

            idle_count = len(states)
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

async def main(connection):
    asyncio.create_task(watch_idle_dir(connection))
    asyncio.create_task(color_poller(connection))
    await asyncio.Event().wait()


iterm2.run_forever(main)
