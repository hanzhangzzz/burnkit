# Burn AI 维护说明

Burn AI 是第三件工具：读取本机 Claude Code / Codex 已产生的 coding plan usage，计算燃烧节奏，并通过 SwiftBar 菜单栏和系统通知提醒用户。

## 设计边界

- 不处理登录态，不托管凭据，不读取或上传 API key。
- 不主动请求 Claude/Codex 的内部 usage backend；v1 只使用本机已有 usage 结果。
- Codex 数据源是 `~/.codex` session/rollout JSONL 中的 `payload.rate_limits`。
- Claude 数据源是 `burn-ai ingest claude-statusline` 写入的 `~/.burn-ai/claude/latest.json`。
- Claude Code 已有 `statusLine.command` 归用户所有；安装器不能覆盖、透明代理或自动改写用户已有 status line。
- 如果用户没有 Claude status line，安装器可以创建 Burn AI 管理的最小 status line。
- 如果用户已有 Claude status line，只检测是否已接入 Burn AI ingest，未接入时输出手动接入说明。
- 通过 `npx burn-ai install` 安装时，Claude status line 不能依赖 PATH 中存在全局 `burn-ai`；脚本必须调用 `~/.burn-ai/app/dist/cli.js` 这份稳定副本。

## 运行与分发

- npm 包名和 CLI 命令名都是 `burn-ai`。
- 用户入口是 `npx burn-ai install`。
- 日常命令是 `burn-ai doctor` 和 `burn-ai status`。
- provider 监控范围由 `~/.burn-ai/config.json` 的 `providers` 控制，默认 `["codex", "claude"]`；临时覆盖可用 `BURN_AI_PROVIDERS=codex,claude`。
- v1 完整支持 macOS launchd；Windows 只保留通知/调度设计，不承诺可用。
- 安装器必须把当前构建产物复制到 `~/.burn-ai/app/`，launchd 只能指向该稳定副本，不能指向 npx 临时缓存。
- 安装器必须创建用户级 CLI shim：`~/.local/bin/burn-ai -> ~/.burn-ai/app/dist/cli.js`，否则 `burn-ai doctor/status` 不能作为日常命令直接使用。
- 安装器必须检查 SwiftBar；macOS 上缺失时通过 Homebrew cask 安装 SwiftBar，然后安装/更新 Burn AI SwiftBar 插件并启动 SwiftBar。
- SwiftBar 插件目录必须读取 SwiftBar 当前 `PluginDirectory`，不能硬编码 `~/Library/Application Support/SwiftBar/Plugins`。用户可能已经把插件目录设到别处。
- 重复安装必须覆盖两个入口：`npx --no-install burn-ai install` 更新 `~/.burn-ai/app`；已安装后的 `burn-ai install` 不能删除正在运行的 `~/.burn-ai/app`，只能跳过 runtime 自复制并刷新 CLI shim、SwiftBar 插件和 launchd。
- 安装器必须复制 `assets/` 到 `~/.burn-ai/app/assets/`；静态图标只作为 fallback。`terminal-notifier` 的主要视觉表达应使用运行时生成的动态数据卡片。
- 重复执行 `burn-ai install` 必须完整安装最新代码，并重启 launchd agent，不能只更新文件不重启。
- `~/.burn-ai/status.json` 是展示层唯一稳定数据入口。CLI、未来 watch、Menu Bar app、iTerm badge 都应读取该结构，不要重复实现采集逻辑。
- `burn-ai status` 默认读取 `~/.burn-ai/status.json`；只有 `--refresh`、`--fixtures` 或 daemon 才应触发本机 usage 采集。
- Menu Bar v1 使用 SwiftBar 插件作为薄展示层：`burn-ai menubar render` 只读 `status.json`，`burn-ai menubar install` 只安装 wrapper 插件，不采集 provider 数据。`burn-ai uninstall` 只删除本工具管理的插件，不卸载 SwiftBar 本体。

## 燃烧策略

- `low` 是默认档，保守保护 7d 额度。
- `high` 是激进档，但仍受 7d 总预算约束。
- 不鼓励每个 5h 窗口打满；核心目标是在 7d 总预算下让 5h 不空转。
- 样本不足时状态为 `RAW`，只能展示原始 usage 和 limit risk，不能假装给动态建议。

## 验证

修改本工具后至少运行：

```bash
npm ci
npm test
npm run build
npx --no-install burn-ai install
burn-ai install
npx --no-install burn-ai doctor --dry-run
npx --no-install burn-ai status --fixtures
npx --no-install burn-ai menubar render
```

真实 install 是本工具代码变更的必跑项；`npx --no-install burn-ai install` 和 `burn-ai install` 两条路径都要覆盖。验证后不要提交 `node_modules/` 或 `dist/`。
