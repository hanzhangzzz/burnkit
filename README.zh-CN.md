# 卷死你三件套

> AI 没卡住。你卡住了。

[English README](README.md)

这是一个给高并发 AI 编程工作流用的小工具集，气质不太稳定，但目标很稳定：把人的瓶颈暴露出来，然后逼你处理它。

Claude Code 跑完了。Codex 跑完了。另一个 tab 已经等你十分钟了。你没看到，因为你正在错误的终端里认真发呆。

所以这个仓库干一件很朴素的事：让你的注意力债务变成可见光。

![六个 AI 编程 session 分布在多个终端 tab 中，并按空闲压力显示颜色](assets/readme/hero-ai-tabs.png)

## 为什么要有这个东西

AI 越来越快，但人的注意力没有升级。

开一个 session，你还能盯。开五个 session，你需要调度。开十个 session，你需要一个会变色的羞耻仪表盘。

这个项目就是那个仪表盘。

- 用 `c` 快速切 Claude Code Provider，不用每次翻配置。
- Agent Team 场景里，把 leader 和 teammate 流量分到不同 Provider。
- Claude Code / Codex CLI 等你输入时，把 iTerm2 tab 染成绿、黄、红。
- 盯住 Claude Code / Codex 的 plan usage，别让 5h 窗口空转，也别无脑烧穿 7d 额度。

## 真正的高度

这不是一个让你永远手动接球的工具。

它先把你榨干：榨干你的空闲时间，榨干你的上下文切换，榨干你同时盯十几个 AI session 的自信。直到某一刻，你发现自己已经开不了更多窗口、切不了更多 tab、回不了更多“继续”。

然后问题会自己冒出来：

```text
为什么它总要问我？
为什么它不能自己判断下一步？
为什么我还在当人肉调度器？
为什么这些 session 不能排队、分工、验证、交付？
```

没错。你开始 harness 了。

先用颜色把人逼到极限，再用系统把人从循环里拿出来。这才是三件套真正想干的事：不是让你更勤奋地喂 AI，而是逼你承认，下一层生产力不在更多窗口里，在更自主的 agent harness 里。

![从更多终端窗口，到人类瓶颈，再到自主 agent harness 的三阶段升级图](assets/readme/harness-evolution.png)

## 三件套

| 工具 | 状态 | 它干什么 | 你为什么会想用 |
|------|------|----------|----------------|
| Claude Provider Router | 可用 | 通过 `c` 启动 Claude Code，按编号切 Provider，Team 模式按角色分流 | 该烧哪个额度烧哪个额度，不再手动搬 endpoint |
| iTerm2 Tab Color | 可用 | Claude Code 或 Codex 等你时，把非当前 iTerm2 tab 染色 | 你的终端从遗忘现场变成调度台 |
| Burn AI | 初版 | 追踪本机 Claude Code / Codex coding plan usage，判断燃烧节奏过慢、过快或接近限额 | 别浪费昂贵窗口，也别每个 5h 都无脑打满 |

![三件套总览：Provider 路由、tab 颜色压迫和 plan usage 节奏控制](assets/readme/toolkit-overview.png)

## 注意力拷打协议

| 颜色 | 含义 | 精神攻击 |
|------|------|----------|
| 绿色 | AI 刚跑完，正在等你 | "还新鲜，快去收结果。" |
| 黄色 | 已经等了一会儿 | "你的并行能力开始漏水了。" |
| 红色 | 等太久了 | "机器准备好了，瓶颈还在打字。" |
| 白色 | 当前 tab、处理中，或干净状态 | "这里暂时没人在催你。" |

只有非当前 tab 会变色。你正在看的 tab 保持白色，因为提示应该指向你没看到的地方，而不是给你正在看的地方贴花。

![tab 颜色从白色到绿色、黄色、红色，再在用户响应后回到白色](assets/readme/tab-color-escalation.png)

## 快速开始

克隆仓库：

```bash
git clone https://github.com/doingdd/iterm2-claude-tab-color.git
cd iterm2-claude-tab-color
```

使用 Claude Provider Router：

```bash
cd tools/claude-provider-router
cp config.env.example config.env
chmod 600 config.env
./c 0
```

安装 iTerm2 Tab Color：

```bash
pip3 install iterm2
bash tools/iterm2-tab-color/install.sh
```

安装 Burn AI：

```bash
cd tools/burn-ai
npm install
npx burn-ai install
burn-ai doctor
burn-ai status
```

Burn AI 会安装本地运行副本到 `~/.burn-ai/app`，在 `~/.local/bin` 创建 `burn-ai` 命令软链，安装 macOS launchd 采集器，并配置 SwiftBar 菜单栏插件。它不负责 Claude Code 或 Codex 的登录态。

然后开几个 Claude Code 或 Codex CLI session，让它们干活，再停止幻想自己能记住每个 tab 到底跑到哪了。

## 用起来是什么感觉

之前：

```text
tab 1：大概跑完了？
tab 2：可能还在跑？
tab 3：我什么时候开的这个？
tab 4：风扇怎么开始表演了？
tab 5：完了
```

之后：

```text
绿色 -> 现在收结果
黄色 -> 已经开始变质
红色 -> 别装调度系统了，快切过去
白色 -> 当前活跃或状态干净
```

## 项目结构

```text
.
├── tools/
│   ├── claude-provider-router/
│   ├── iterm2-tab-color/
│   └── burn-ai/
├── assets/
├── AGENTS.md
├── CLAUDE.md
├── README.md
└── README.zh-CN.md
```

根目录不提供 `install.sh` / `uninstall.sh`。每个工具的安装和卸载入口都在自己的目录里。

## 工具文档

- [Claude Provider Router](tools/claude-provider-router/README.md)
- [iTerm2 Tab Color](tools/iterm2-tab-color/README.md)
- [iTerm2 Tab Color 中文说明](tools/iterm2-tab-color/README.zh-CN.md)
- [Burn AI](tools/burn-ai/README.md)

## 安全边界

- 不提交 `tools/claude-provider-router/config.env`；仓库只维护 `config.env.example`。
- Burn AI 不处理登录态、不托管凭据，只读取 Claude Code / Codex 已经在本机产生的 usage 数据。
- tab 颜色行为、state 清理、进程检测、hook 语义都属于功能行为变更，不能混进目录整理里。

## 开发验证

修改 iTerm2 Tab Color 后至少运行：

```bash
bash -n tools/iterm2-tab-color/install.sh tools/iterm2-tab-color/uninstall.sh tools/iterm2-tab-color/tab_color_hook.sh
python3 -m py_compile tools/iterm2-tab-color/tab_color_daemon.py tools/iterm2-tab-color/reset_tab.py tools/iterm2-tab-color/test_daemon.py
python3 -m unittest tools/iterm2-tab-color/test_daemon.py
```

修改 Burn AI 后至少运行：

```bash
cd tools/burn-ai
npm ci
npm test
npm run build
npx --no-install burn-ai install
burn-ai install
npx --no-install burn-ai doctor --dry-run
npx --no-install burn-ai status --fixtures
npx --no-install burn-ai menubar render
git diff --check
```

## License

[MIT](LICENSE)
