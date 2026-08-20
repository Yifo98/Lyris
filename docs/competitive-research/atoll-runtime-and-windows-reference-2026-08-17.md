# Atoll 实机观察与 Windows 歌词界面综合取舍

日期：2026-08-17
阶段：旧界面清理完成后的产品框架研究
结论边界：只决定行为与架构取舍，不决定最终名称、Logo、配色或视觉稿。

## 1. 本轮证据

### Atoll

- 本机应用：Atoll 2.3.3（Build 20260720004），Universal arm64/x86_64，Developer ID 签名。
- 源码依据：官方仓库固定提交 `0d9e94853d55654517dd86861f75d2203d94d024`。
- 实机界面捕获：收缩态与展开态均通过 macOS Accessibility 应用级捕获确认。
- 实机系统录屏：标准 `screencapture` 录制了屏幕顶部与鼠标，但没有包含可见于应用级捕获的展开面板。当前证据不能确定原因，因此不把它归因于某个未验证的 `NSWindow` 属性。

项目内未跟踪的研究产物：

```text
apple/Lyris/.build/research/atoll-runtime/
├── atoll-collapsed-ax-capture.jpeg
├── atoll-expanded-ax-capture.jpeg
├── atoll-system-recording-capture-limitation-2026-08-17.mov
└── atoll-state-comparison-derived-2026-08-17.mov
```

最后一个视频只把两个真实状态捕获做成淡入淡出对照，**不是 Atoll 原始动画录屏**；不得用于测量真实时长、缓动曲线或中间形态。

### Windows / Lyricify 参考

本轮没有把对话中早期以 MeloFloat 名义粘贴的 Windows 截图当作可复核文件：对应临时路径已经失效。可复核的 Windows 证据来自用户提供的 Lyricify 4 参考档案：

```text
Lyricify4_Interface_Reference_2026-08-17/
├── docs/01-interface-and-core-functions.md
├── docs/02-settings-matrix.md
├── docs/04-evidence-index.md
└── assets/screenshots/
```

重点证据为普通歌词与播放器、连续自动滚动、桌面歌词、灵动词岛、任务栏歌词、全屏和歌词舞台。Windows 更新/蓝屏主题只证明扩展能力，不是新 Mac 产品的视觉方向。

## 2. Atoll 可观察行为

1. 收缩态与物理刘海完全同色，视觉上不像第二个悬浮胶囊。
2. 点击顶部激活区后，内容从刘海下方形成一个连续黑色面；展开态包括状态附件、媒体信息、进度与播放控制。
3. 展开内容密度较低，但层级稳定：附件在顶部，媒体信息与进度居中，主要控制在底部。
4. 界面捕获表明展开后的点击元素都有可访问性语义，首击可进入交互。
5. 多次启动后，临时音量/录制状态会先占用刘海，再回到空闲状态，说明它把多种提示统一到同一宿主表面。

源码解释与官方证据：

- 透明 `NSPanel` 宿主：[DynamicIslandWindow.swift](https://github.com/Ebullioscopic/Atoll/blob/0d9e94853d55654517dd86861f75d2203d94d024/DynamicIsland/components/Notch/DynamicIslandWindow.swift#L25-L67)
- 屏幕与刘海几何：[matters.swift](https://github.com/Ebullioscopic/Atoll/blob/0d9e94853d55654517dd86861f75d2203d94d024/DynamicIsland/sizing/matters.swift#L246-L359)
- 单一表面形变：[ContentView.swift](https://github.com/Ebullioscopic/Atoll/blob/0d9e94853d55654517dd86861f75d2203d94d024/DynamicIsland/ContentView.swift#L515-L616)
- 可取消展开/收缩状态：[DynamicIslandViewModel.swift](https://github.com/Ebullioscopic/Atoll/blob/0d9e94853d55654517dd86861f75d2203d94d024/DynamicIsland/models/DynamicIslandViewModel.swift#L321-L392)
- 顶边命中与鼠标协调：[ContentView.swift](https://github.com/Ebullioscopic/Atoll/blob/0d9e94853d55654517dd86861f75d2203d94d024/DynamicIsland/ContentView.swift#L1925-L2045)

## 3. 综合取舍

| 方向 | 采用 | 不采用 |
|---|---|---|
| 窗口 | 透明宿主窗口；视觉表面独立形变；每块屏幕独立几何 | 同时动画窗口 frame 与 SwiftUI 内容；叠加第二张卡片 |
| 刘海 | 运行时读取 `NSScreen`；刘海屏与无刘海屏分别建模 | 写死某一代 MacBook 刘海宽高；把普通胶囊冒充物理刘海 |
| 交互 | 顶边激活区、首击、悬停去抖、取消旧收缩任务、确定 teardown | 只靠 `.onHover`；多个 Timer/Task 分别抢同一展开状态 |
| 播放信息 | Windows/Spotify 式清晰层级：封面、曲目、歌词、进度、核心控制 | 把所有播放模式、收藏、设置和更多按钮同时常驻 |
| 歌词 | 当前句优先、逐句/逐字进度、翻译副行、完整歌词独立窗口 | 独立跑马灯；让歌词滚动脱离播放时钟；Windows 任务栏内部嵌入 |
| 状态提示 | 借鉴 Atoll，把音量、连接、播放和歌词视为同一提示系统 | 让每种提示创建新窗口或新胶囊 |
| 媒体实现 | 保留项目现有 Local/Web/Hybrid Spotify、PKCE、收藏和歌词架构 | Atoll 私有 `MediaRemote.framework`、默认 Core Audio Tap、媒体适配进程 |
| 视觉 | 使用已批准的 Lyris 设计系统 | 复制 Atoll 黑色形状、Lyricify Windows 皮肤或旧 MeloFloat 渐变模板 |

## 4. 推荐的新产品框架

不先画卡片，而是先定义四个相互独立的产品表面：

1. **Glance** — 播放中的低干扰歌词提示；是否与物理刘海结合由显示器能力决定。
2. **Player** — 用户主动展开的完整播放卡片，包含封面、当前歌词、进度和必要控制。
3. **Lyrics** — 多行/逐字/翻译的沉浸式歌词窗口，不挤进 Player。
4. **Settings** — 标准激活窗口，负责 Spotify、翻译、缓存和每个视图的独立设置。

四个表面共享一个应用会话，不共享窗口状态。播放、歌词与翻译状态来自保留的核心；macOS 窗口只做投影和交互。

## 5. 必须先讨论的决策

在重新实现 UI 前，需要与用户和 ChatGPT 共同确定：

1. 最终产品名称与中英文关系；
2. Logo 是强调音乐、歌词、漂浮还是 Mac 顶部提示；
3. Glance 默认位于刘海、菜单栏附近还是自由悬浮；
4. Player 展开后保留多少控制；
5. Windows Spotify 参考中要保留的层级，而不是要复制的外观；
6. 是否支持无刘海副屏和多屏同时显示。

这些决策完成前，只允许继续拆分核心接口和补测试，不新增产品视觉代码。

## 6. 许可证边界

Atoll 为 GPL-3.0，并声明部分实现来自同为 GPL-3.0 的 Boring.Notch。除非未来明确改变整个项目的许可策略，否则不得复制、翻译或轻改 Atoll 的形状、事件协调器、媒体实现或源码结构。

- [Atoll LICENSE](https://github.com/Ebullioscopic/Atoll/blob/0d9e94853d55654517dd86861f75d2203d94d024/LICENSE)
- [Atoll NOTICE](https://github.com/Ebullioscopic/Atoll/blob/0d9e94853d55654517dd86861f75d2203d94d024/NOTICE)
