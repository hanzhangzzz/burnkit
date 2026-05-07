#!/usr/bin/env python3
"""
Claude Code 多 Provider 路由代理

路由策略：基于 auth token 区分 leader / teammate
  - leader 进程的 apiKeyHelper 返回 "leader-token"
  - teammate 进程的 apiKeyHelper 返回 "teammate-token"（因为 CLAUDE_TEAM_ROLE 被 claude 过滤）
  - 路由器检查请求中的 Authorization header 来决定路由

启动方式（由 c 脚本调用）：
  ROUTER_LEADER_URL=...      ROUTER_LEADER_TOKEN=...
  ROUTER_TEAMMATE_URL=...    ROUTER_TEAMMATE_TOKEN=...
  ROUTER_TEAMMATE_MODEL=...  # 转发给 teammate 时替换的模型名（可选）
  uvicorn router:app --port 3100
"""

import os
import json
import logging
import httpx
from fastapi import FastAPI, Request, HTTPException
from fastapi.responses import StreamingResponse, JSONResponse, Response

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
logger = logging.getLogger(__name__)

app = FastAPI()

LEADER_URL      = os.environ.get("ROUTER_LEADER_URL", "").rstrip("/")
LEADER_TOKEN    = os.environ.get("ROUTER_LEADER_TOKEN", "")
TEAMMATE_URL    = os.environ.get("ROUTER_TEAMMATE_URL", "").rstrip("/")
TEAMMATE_TOKEN  = os.environ.get("ROUTER_TEAMMATE_TOKEN", "")
TEAMMATE_MODEL  = os.environ.get("ROUTER_TEAMMATE_MODEL", "")

# 部分 provider（如 MiniMax）不支持的 beta header
UNSUPPORTED_BETA_PREFIXES = [
    "interleaved-thinking",
    "output-128k",
]


def extract_role_token(request: Request) -> str:
    """从请求头中提取角色 token（apiKeyHelper 写入的）"""
    auth = request.headers.get("authorization", "")
    if auth.startswith("Bearer "):
        return auth[7:].strip()
    # 兜底：检查 x-api-key
    return request.headers.get("x-api-key", "").strip()


def resolve_route(request: Request, model: str = "") -> dict:
    """根据 auth token 路由：leader-token → leader, teammate-token → teammate"""
    role_token = extract_role_token(request)

    if role_token == "leader-token":
        return {"url": LEADER_URL, "token": LEADER_TOKEN, "role": "leader", "model_override": None}
    elif role_token == "teammate-token":
        return {"url": TEAMMATE_URL, "token": TEAMMATE_TOKEN, "role": "teammate", "model_override": TEAMMATE_MODEL or None}
    else:
        # 兜底：无法识别 token 时按 model name 路由（兼容旧逻辑）
        logger.warning(f"未知 token: {role_token!r}, 按 model 兜底路由")
        if model and ("opus" in model.lower()):
            return {"url": LEADER_URL, "token": LEADER_TOKEN, "role": "leader", "model_override": None}
        return {"url": TEAMMATE_URL, "token": TEAMMATE_TOKEN, "role": "teammate", "model_override": TEAMMATE_MODEL or None}


def build_headers(route: dict, request: Request) -> dict:
    headers = {
        "authorization":     f"Bearer {route['token']}",
        "anthropic-version": request.headers.get("anthropic-version", "2023-06-01"),
        "content-type":      "application/json",
    }
    for key, val in request.headers.items():
        if not key.lower().startswith("anthropic-beta"):
            continue
        if route["role"] == "teammate":
            skip = any(val.lower().find(prefix) >= 0 for prefix in UNSUPPORTED_BETA_PREFIXES)
            if skip:
                logger.info(f"过滤 beta header: {key}={val}")
                continue
        headers[key] = val
    return headers


def prepare_body(body: dict, route: dict) -> dict:
    result = {**body}
    if route["model_override"]:
        result["model"] = route["model_override"]
    if route["role"] == "teammate":
        for field in ("output_config",):
            if field in result:
                logger.info(f"过滤不支持字段: {field}")
                del result[field]
    return result


@app.get("/")
async def health():
    return {
        "status": "ok",
        "leader": LEADER_URL,
        "teammate": TEAMMATE_URL,
        "teammate_model": TEAMMATE_MODEL or "(透传原始 model)",
    }


@app.post("/v1/messages")
async def proxy_messages(request: Request):
    try:
        body = await request.json()
    except Exception:
        raise HTTPException(status_code=400, detail="invalid json body")

    model = body.get("model", "")
    route = resolve_route(request, model)
    out_body = prepare_body(body, route)
    headers = build_headers(route, request)

    tag = "🔵 LEADER" if route["role"] == "leader" else "🟢 TEAMMATE"
    msg = f"{tag} model={model!r}"
    if route["model_override"]:
        msg += f" → {out_body['model']!r}"
    # 只显示域名部分，简洁
    upstream_host = route["url"].replace("https://", "").replace("http://", "").split("/")[0]
    msg += f" → {upstream_host}"
    logger.info(msg)

    upstream_url = f"{route['url']}/v1/messages"
    is_stream = body.get("stream", False)

    if is_stream:
        try:
            async with httpx.AsyncClient(timeout=300) as client:
                async with client.stream("POST", upstream_url, headers=headers, json=out_body) as resp:
                    status = resp.status_code
                    content = await resp.aread()
        except Exception as e:
            logger.error(f"request error: {e}")
            raise HTTPException(status_code=502, detail=str(e))

        if status != 200:
            logger.error(f"upstream error {status}: {content[:300]}")
            import time as _time
            dump_path = os.path.join(os.path.dirname(__file__), ".routers", f"failed_{int(_time.time()*1000)}.json")
            try:
                with open(dump_path, "w") as _f:
                    json.dump({"status": status, "response": content.decode(), "request": out_body}, _f, ensure_ascii=False, indent=2)
                logger.error(f"完整请求体已写入: {dump_path}")
            except Exception:
                pass
            try:
                return JSONResponse(status_code=status, content=json.loads(content))
            except Exception:
                return JSONResponse(status_code=status, content={"error": content.decode()})

        return Response(content=content, media_type="text/event-stream", status_code=200)
    else:
        try:
            async with httpx.AsyncClient(timeout=300) as client:
                resp = await client.post(upstream_url, headers=headers, json=out_body)
            return JSONResponse(status_code=resp.status_code, content=resp.json())
        except Exception as e:
            logger.error(f"request error: {e}")
            raise HTTPException(status_code=502, detail=str(e))


@app.post("/v1/messages/count_tokens")
async def proxy_count_tokens(request: Request):
    try:
        body = await request.json()
    except Exception:
        raise HTTPException(status_code=400, detail="invalid json body")

    model = body.get("model", "")
    route = resolve_route(request, model)
    out_body = prepare_body(body, route)
    headers = build_headers(route, request)
    upstream_url = f"{route['url']}/v1/messages/count_tokens"

    try:
        async with httpx.AsyncClient(timeout=60) as client:
            resp = await client.post(upstream_url, headers=headers, json=out_body)
        return JSONResponse(status_code=resp.status_code, content=resp.json())
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))
