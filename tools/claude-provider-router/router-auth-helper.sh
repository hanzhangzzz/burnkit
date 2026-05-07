#!/bin/bash
# apiKeyHelper：
# - 当 ANTHROPIC_BASE_URL 指向本地路由代理（127.0.0.1）时：
#   - leader 进程有 CLAUDE_TEAM_ROLE=leader → 返回 "leader-token"
#   - teammate 进程没有这个变量（被 claude 过滤） → 返回 "teammate-token"
# - 否则输出真实的 ANTHROPIC_AUTH_TOKEN（透传，不干扰正常模式）

if [[ "$ANTHROPIC_BASE_URL" == *"127.0.0.1"* ]]; then
    if [[ "$CLAUDE_TEAM_ROLE" == "leader" ]]; then
        echo "leader-token"
    else
        echo "teammate-token"
    fi
else
    echo "$CLAUDE_AUTH_TOKEN"
fi
