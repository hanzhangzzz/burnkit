#!/usr/bin/env python3
"""立即重置指定 session 所在 tab 的颜色（后台调用，不阻塞 hook）。"""
import sys
import asyncio
import iterm2

SESSION_ID = sys.argv[1] if len(sys.argv) > 1 else ""
if not SESSION_ID:
    sys.exit(0)

UUID = SESSION_ID.split(":")[-1] if ":" in SESSION_ID else SESSION_ID

async def reset():
    async with iterm2.Connection() as conn:
        app = await iterm2.async_get_app(conn)
        session = app.get_session_by_id(UUID)
        if session is None:
            return
        tab = session.tab
        targets = list(tab.sessions) if tab else [session]
        for s in targets:
            change = iterm2.LocalWriteOnlyProfile()
            change.set_use_tab_color(False)
            await s.async_set_profile_properties(change)

asyncio.run(reset())
