# Claude Provider Router

> BurnKit 第一件工具：让 Claude Code 的模型、Provider、Team 路由和状态行更可控。

这个目录整合了原有 `c` 工具。`c` 是主入口，负责按编号启动 Claude Code；Team 模式下会启动本地 FastAPI 路由代理，把 leader 和 teammate 请求分发到不同 Provider。

## 文件说明

| 文件 | 说明 |
|------|------|
| `c` | 主启动脚本，支持单 Provider 和 `c team` |
| `router.py` | Team 模式本地路由代理，按 auth token 区分 leader / teammate |
| `router-auth-helper.sh` | Claude Code `apiKeyHelper`，给单 Provider 和 Team 模式提供 token |
| `ccline-with-model.sh` | Claude Code status line，显示模型、上下文、耗时、Git 分支和高级能力调用次数 |
| `install-core.sh` | 内部安装器；由 `bin/burnkit install router` 调用 |
| `config.env.example` | Provider 配置模板 |
| `config.env` | 本地真实配置，包含 token，必须忽略提交 |

## 安装准备

从仓库根目录走 BurnKit 统一入口：

```bash
bin/burnkit install router
c 0
```

`install-core.sh` 只在 `config.env` 缺失时从 `config.env.example` 创建并设置权限为 `600`。如果 `config.env` 已经存在，重复安装必须原样保留内容和权限。安装器还会把 `c` 安装为 `~/.local/bin/c` 软链；如果该路径已有用户自己的命令，会跳过不覆盖。

如果只使用本工具，也可以手动配置：

```bash
cd tools/claude-provider-router
cp config.env.example config.env
chmod 600 config.env
```

编辑 `config.env`，按编号填写 Provider：

```bash
CONFIG_0_BASE_URL=https://api.example.com/anthropic
CONFIG_0_AUTH_TOKEN=your-token
CONFIG_0_COMPACT_WINDOW=150000
CONFIG_0_MODEL=your-model-name
```

Team 模式需要：

```bash
python3 -m pip install fastapi uvicorn httpx
```

`ccline-with-model.sh` 需要 `jq`：

```bash
brew install jq
```

## Claude Code 设置

`c` 默认使用 `~/.claude/settings-c.json`。至少需要配置 `apiKeyHelper`：

```json
{
  "apiKeyHelper": "/absolute/path/to/tools/claude-provider-router/router-auth-helper.sh"
}
```

如果希望启用状态行，把同一个文件扩展为：

```json
{
  "apiKeyHelper": "/absolute/path/to/tools/claude-provider-router/router-auth-helper.sh",
  "statusLine": {
    "type": "command",
    "command": "/absolute/path/to/tools/claude-provider-router/ccline-with-model.sh",
    "padding": 0
  }
}
```

也可以把 `statusLine` 放到 `~/.claude/settings.json`，让普通 `claude` 启动方式也使用同一条状态行。

## 使用

从仓库根目录：

```bash
c 0
c 2 --resume
c team 2 0
c router status
```

从本目录：

```bash
# 显示帮助和可用配置
./c

# 使用配置 0 启动
./c 0

# 使用配置 2 并恢复会话
./c 2 --resume

# Team 模式：leader 用 2，teammate 用 0
./c team 2 0

# 查看或停止路由代理
./c router status
./c router stop
```

如果要手动创建全局 `c` 软链：

```bash
mkdir -p "$HOME/.local/bin"
ln -sf "$PWD/c" "$HOME/.local/bin/c"
```

## Team 模式路由

```text
Claude Code leader
  ├─ ANTHROPIC_BASE_URL=http://127.0.0.1:{port}
  └─ CLAUDE_TEAM_ROLE=leader
        |
        v
apiKeyHelper -> leader-token

Claude Code teammate
  └─ CLAUDE_TEAM_ROLE 被 Claude Code 过滤
        |
        v
apiKeyHelper -> teammate-token

router.py
  ├─ leader-token   -> leader Provider
  └─ teammate-token -> teammate Provider
```

## 安全边界

- 不要提交 `config.env`、`.routers/` 或路由失败请求体。
- `router.py` 只监听 `127.0.0.1`，不要改成公网监听。
- `router-auth-helper.sh` 只在本地路由代理场景返回占位 token；普通 Provider 模式返回 `CLAUDE_AUTH_TOKEN`。
