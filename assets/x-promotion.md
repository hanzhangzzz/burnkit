开多个 iTerm2 tab 跑 Claude Code，最大的瓶颈不是 AI —— 是你自己。

某个 tab 的 Claude 早就回复完了等你输入，你却在另一个 tab 里发呆。

所以我写了个小工具：让 tab 颜色自动反映空闲状态 🚦

---

🟢 绿色 = Claude 刚回复完，等你
🟡 黄色 = 空闲 10 分钟了，该去看看
🔴 红色 = 空闲 20 分钟，你在干嘛？

当前正在看的 tab 保持白色 —— 颜色是通知，不是干扰。

一眼扫过去就知道该切哪个 tab。

---

这是我的「卷自己」三件套之第二件。

核心理念：**卷 AI 不如卷自己。** 人已经是 AI 工作流的瓶颈了。AI 几秒就回复，人切个上下文要几分钟。

用视觉压力逼自己加速上下文切换，提高并行能力。不是 AI 等你，是你追 AI。

---

开源免费，一条命令安装：

```
pip3 install iterm2
git clone https://github.com/doingdd/iterm2-claude-tab-color
cd iterm2-claude-tab-color && bash tools/iterm2-tab-color/install.sh
```

GitHub: https://github.com/doingdd/iterm2-claude-tab-color

#ClaudeCode #iTerm2 #AI工具 #开发者效率
