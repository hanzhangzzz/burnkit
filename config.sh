#!/bin/bash
# ============================================================
# iTerm2 Tab Color - 统一配置文件
# 修改这里的参数即可自定义行为
# ============================================================

# --- 时间阈值（单位：分钟）---
# AI CLI 完成回复后，tab 开始进入 idle 计时
THRESHOLD_YELLOW=10   # 超过此分钟数 → 变黄（需要关注）
THRESHOLD_RED=20      # 超过此分钟数 → 变红（长时间等待）

# --- Tab 颜色（RGB，0-255）---
# 绿色：AI CLI 刚回复完，等待你输入
COLOR_GREEN_R=30
COLOR_GREEN_G=180
COLOR_GREEN_B=30

# 黄色：已等待超过 THRESHOLD_YELLOW 分钟
COLOR_YELLOW_R=220
COLOR_YELLOW_G=160
COLOR_YELLOW_B=0

# 红色：已等待超过 THRESHOLD_RED 分钟
COLOR_RED_R=200
COLOR_RED_G=40
COLOR_RED_B=40

# --- 守护进程轮询间隔（秒）---
# 影响颜色升级的延迟精度，建议 30~60
POLL_INTERVAL=30

# --- 状态文件目录 ---
# Stop hook 写时间戳，daemon 读取并计算等待时长
IDLE_STATE_DIR="$HOME/.claude/idle_state"

# --- 并发窗口上限（仅用于提示，不强制）---
# 当检测到等待中的 AI CLI tab 数量低于此值时，守护进程会在日志中提示
CONCURRENT_TARGET=3
