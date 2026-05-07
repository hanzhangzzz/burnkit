# iTerm2 Tab Color

本目录是 iTerm2 tab color 工具的唯一维护位置。项目级规则见仓库根目录 `AGENTS.md`。

## 迁移边界

- 只做目录整理和路径适配。
- 功能行为必须保持等同于 HEAD `0ba4914 feat: improve codex install and idle cleanup`。
- 不在迁移中改 hook state 语义、颜色升级逻辑、活跃 tab 判断、进程检测或 daemon 调度。
- 发现功能问题时先停止并单独提出修复计划。

## 运行入口

```bash
bash tools/iterm2-tab-color/install.sh
bash tools/iterm2-tab-color/uninstall.sh
```

根目录不维护安装/卸载转发脚本。

## 验证

```bash
bash -n tools/iterm2-tab-color/install.sh tools/iterm2-tab-color/uninstall.sh tools/iterm2-tab-color/tab_color_hook.sh
python3 -m py_compile tools/iterm2-tab-color/tab_color_daemon.py tools/iterm2-tab-color/reset_tab.py tools/iterm2-tab-color/test_daemon.py
python3 -m unittest tools/iterm2-tab-color/test_daemon.py
```
