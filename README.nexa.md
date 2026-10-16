# Nexa Agent

一个放在桌面上的悬浮小工具，随时显示 **Claude Code** 和 **Codex** 的额度、Token 用量和会话。Agent 回复完会直接显示回复内容；Agent 需要你批准操作时也能直接在这里点「允许」或「拒绝」。

基于开源项目 [Agent HUD Open](https://github.com/jazzenchen/agent-hud-open)（Apache-2.0）二次开发，改动见 [NOTICE](NOTICE)。原项目的英文说明保留在 [README.md](README.md)。

## 和原项目的区别

- **可以拖到桌面任意位置**：按住悬浮条拖动，松手就停在那里，下次启动还在原处；拖到离屏幕边缘很近（16pt 以内）时会吸附到边上。鼠标移上去，面板从它所在的位置朝屏幕中间展开。
- **回复提醒显示完整内容**：打开就停在回复末尾，可以选中复制；显示 20 秒，鼠标停在上面时不会消失；同一个对话只保留最新一条。要接着聊，请回到 Claude 或 Codex 里发。
- **小机器人有表情**：Agent 干活时会打字、冒汗、思考，空闲时会打瞌睡、打哈欠。
- **只接 Claude Code 和 Codex**：不读取、也不往其他任何工具里写配置。Claude 桌面版自带的 Claude Code 也能识别。
- **Nexa 品牌**：Nexa 图标和配色（强调色 #F15436），界面默认中文。
- **只用命令行工具就能编译**，不需要装 Xcode。

## 安装

需要 macOS 14 以上和 Xcode Command Line Tools（`xcode-select --install`）。

```bash
git clone https://github.com/Tumblr-code/nexa-agent.git
cd nexa-agent
scripts/build-app.sh release
cp -R "build/Nexa Agent.app" ~/Applications/
open ~/Applications/"Nexa Agent.app"
```

第一次启动后，它会在 Claude Code 的 `~/.claude/settings.json` 和 Codex 的 `~/.codex/hooks.json` 里各加几条指向自己的钩子（用于批准请求、完成提醒和会话定位），不会改动其他设置。在 设置 → 通用 → 客户端回调 里可以关掉，关掉时会把这些钩子移除。

**升级**：重新执行上面的编译和复制命令，再退出并重新打开 Nexa Agent。钩子写的是 `~/Applications/Nexa Agent.app` 里的路径，所以请始终装在这个位置。

## 用法

| 操作 | 方法 |
|---|---|
| 看额度 | 悬浮条上每个 Agent 的圆环和百分比：绿色 < 70%，黄色 ≥ 70%，红色 ≥ 90% |
| 看详情 | 鼠标移到悬浮条上，展开额度、24 小时 Token 和会话 |
| 移动位置 | 按住拖动；设置 → 显示 → 重置位置 回到顶部正中 |
| 批准操作 | Agent 请求权限时卡片自动弹出，点「拒绝」「允许一次」或「始终允许」 |
| 用量统计 | 面板右下角的图表按钮，查看 30 天内按时间、模型、会话的 Token 和费用估算 |
| 显示形态 | 设置 → 显示：「简约」是圆环加百分比，「动态」是一排 Agent 标志 |

## 开发

```bash
scripts/build-app.sh debug     # 编译到 build/Nexa Agent.app
make snapshot                  # 用演示数据把界面渲染成图片，放在 build/snapshots
```

单元测试用的是 XCTest，需要完整的 Xcode 才能运行（`make test`）。

## 许可

Apache License 2.0，见 [LICENSE](LICENSE) 和 [NOTICE](NOTICE)。界面里各 Agent 的标志版权归各自所有者，见 [THIRD_PARTY_NOTICES.txt](THIRD_PARTY_NOTICES.txt)。
