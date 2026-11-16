# chatgpt-quick-chat

给 macOS 的 ChatGPT 浮窗。按 **⌥ Space** 随手问一句，再按一次就收起。

### 未展开 · 输入问题

输入框出现在当前屏幕下方，全屏工作时也能直接唤出。

<img src="docs/images/compact.png" width="520" alt="紧凑输入框中写着：在 Mac 上，怎么只截取一个窗口？">

### 展开 · 阅读与追问

发送后，窗口向上展开。默认 30 分钟内再次唤出可以接着聊，时限可在菜单栏调整。

<img src="docs/images/expanded.png" width="462" alt="展开后的阅读窗口展示 ChatGPT 的截图操作说明，底部可以继续提问">

### 从源码运行

需要 macOS 14 或更高版本，以及 Xcode 的 Swift 工具链。在项目目录运行：

```sh
bash scripts/build.sh
open build/chatgpt-quick-chat.app
```

首次登录可从菜单栏选择「显示完整页面」。应用代码在 `Sources/ChatPanel/`，构建入口在 `scripts/`。
