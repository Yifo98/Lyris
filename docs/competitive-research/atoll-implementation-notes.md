# Atoll 实现层参考笔记

访问日期：2026-08-15
证据级别：B — 固定提交源码
研究对象：[Ebullioscopic/Atoll](https://github.com/Ebullioscopic/Atoll/tree/0d9e94853d55654517dd86861f75d2203d94d024)
固定提交：`0d9e94853d55654517dd86861f75d2203d94d024`

## 结论

Atoll 最值得 Lyris 参考的不是媒体抓取，而是 macOS 顶部窗口的分层方式：

1. 使用透明、无边框、非激活 `NSPanel` 作为宿主，并加入所有 Space。
2. 宿主窗口先到达可容纳展开态的目标范围，视觉上只让内部同一块 SwiftUI 表面从物理刘海连续形变为整张卡片。
3. 把物理刘海和无刘海屏幕的悬浮胶囊明确建模成两种形状，不复用同一套外壳。
4. 悬停、顶边触发、点击和自动收缩由独立交互协调器处理，并为延迟任务提供取消机制。
5. 屏幕变化后重新解析刘海尺寸与窗口位置；多屏需要按显示器分别维护状态。

这几项能直接解释 Lyris 目前“窗口尺寸动画和内容动画互相追赶”时出现的中间胶囊、收缩残影、点击热区不同步和副屏错位。建议后续 clean-room 重写这些机制，不复制 Atoll 源码。

## 可参考的实现层

### 1. NSPanel 宿主

Atoll 的 `DynamicIslandWindow` 是透明、无边框、不可移动的浮动面板，使用 `.fullScreenAuxiliary`、`.canJoinAllSpaces`、`.stationary` 等行为，并允许首击进入内容。

- [DynamicIslandWindow.swift L25-L67](https://github.com/Ebullioscopic/Atoll/blob/0d9e94853d55654517dd86861f75d2203d94d024/DynamicIsland/components/Notch/DynamicIslandWindow.swift#L25-L67)
- [DynamicIslandApp.swift L395-L430](https://github.com/Ebullioscopic/Atoll/blob/0d9e94853d55654517dd86861f75d2203d94d024/DynamicIsland/DynamicIslandApp.swift#L395-L430)

Lyris 已有同类 `NSPanel` 基础，不需要重建窗口系统。后续重点应放在宿主窗口尺寸策略、首击响应和事件热区，而不是继续增加新的卡片窗口。

### 2. 物理刘海尺寸与屏幕定位

Atoll 通过 `safeAreaInsets.top`、`auxiliaryTopLeftArea` 和 `auxiliaryTopRightArea` 区分物理刘海屏与普通屏，并用屏幕顶部中心定位窗口。它还保留约 4pt 的视觉修整量。

- [matters.swift L246-L359](https://github.com/Ebullioscopic/Atoll/blob/0d9e94853d55654517dd86861f75d2203d94d024/DynamicIsland/sizing/matters.swift#L246-L359)
- [DynamicIslandApp.swift L433-L457](https://github.com/Ebullioscopic/Atoll/blob/0d9e94853d55654517dd86861f75d2203d94d024/DynamicIsland/DynamicIslandApp.swift#L433-L457)

Lyris 当前也已使用这些 API，因此几何公式不是主要缺口。应补的是稳定屏幕标识：位置偏好宜基于 `NSScreenNumber`/显示器 ID，而不是仅靠数组顺序或显示器名称。

### 3. 同一表面的连续形变

Atoll 把背景、裁剪形状、内容区域和交互形状放在同一 SwiftUI 表面上，由状态驱动形状与内容动画；外层窗口本身避免参与同一轮 SwiftUI 状态动画。

- [ContentView.swift L515-L616](https://github.com/Ebullioscopic/Atoll/blob/0d9e94853d55654517dd86861f75d2203d94d024/DynamicIsland/ContentView.swift#L515-L616)
- [ContentView.swift L725-L740](https://github.com/Ebullioscopic/Atoll/blob/0d9e94853d55654517dd86861f75d2203d94d024/DynamicIsland/ContentView.swift#L725-L740)
- [NotchShape.swift L25-L134](https://github.com/Ebullioscopic/Atoll/blob/0d9e94853d55654517dd86861f75d2203d94d024/DynamicIsland/components/Notch/NotchShape.swift#L25-L134)

Lyris 后续最重要的调整是消除“双动画源”：不要同时用 `panel.animator().setFrame` 和内部 `withAnimation` 驱动两套不同节奏。建议透明宿主先准备目标空间，内部只保留一个可动画的刘海/整卡表面。

### 4. 状态机与可取消自动收缩

Atoll 的视图模型用明确的 `.closed/.open` 状态管理尺寸；展开前先更新宿主窗口，再更新视觉状态。临时展开使用一个可取消任务，新的交互会取消旧的自动隐藏。

- [DynamicIslandViewModel.swift L23-L58](https://github.com/Ebullioscopic/Atoll/blob/0d9e94853d55654517dd86861f75d2203d94d024/DynamicIsland/models/DynamicIslandViewModel.swift#L23-L58)
- [DynamicIslandViewModel.swift L321-L392](https://github.com/Ebullioscopic/Atoll/blob/0d9e94853d55654517dd86861f75d2203d94d024/DynamicIsland/models/DynamicIslandViewModel.swift#L321-L392)
- [DynamicIslandViewCoordinator.swift L328-L455](https://github.com/Ebullioscopic/Atoll/blob/0d9e94853d55654517dd86861f75d2203d94d024/DynamicIsland/DynamicIslandViewCoordinator.swift#L328-L455)

Lyris 已有可选保留时长与 `Task` 取消逻辑，可以保留产品设置；后续应把窗口准备、视觉展开、交互保持和收缩复位统一到单一状态机，避免多个订阅和延迟任务争用状态。

### 5. 顶边悬停与点击可靠性

Atoll 不只依赖 SwiftUI `.onHover`。它增加顶边激活区、局部/全局鼠标监听、悬停去抖和退出延迟，并针对屏幕最顶部像素及 `CGRect.contains` 的半开区间做修正。

- [ContentView.swift L1925-L2045](https://github.com/Ebullioscopic/Atoll/blob/0d9e94853d55654517dd86861f75d2203d94d024/DynamicIsland/ContentView.swift#L1925-L2045)
- [ContentView.swift L2088-L2219](https://github.com/Ebullioscopic/Atoll/blob/0d9e94853d55654517dd86861f75d2203d94d024/DynamicIsland/ContentView.swift#L2088-L2219)

这部分值得 Lyris 优先吸收为独立的 `TopIslandInteractionCoordinator`。它应统一处理：顶边命中、悬停滞后、设置/弹层打开时禁止收缩、首击、自动收缩计时和销毁监听。所有事件监听必须有确定的 teardown，不能只依赖无边框窗口的 `onDisappear`。

### 6. 多屏

Atoll 监听屏幕参数变化；在全屏显示模式下为每个 `NSScreen` 创建独立窗口与视图模型。

- [DynamicIslandApp.swift L853-L897](https://github.com/Ebullioscopic/Atoll/blob/0d9e94853d55654517dd86861f75d2203d94d024/DynamicIsland/DynamicIslandApp.swift#L853-L897)
- [DynamicIslandApp.swift L1425-L1507](https://github.com/Ebullioscopic/Atoll/blob/0d9e94853d55654517dd86861f75d2203d94d024/DynamicIsland/DynamicIslandApp.swift#L1425-L1507)

Lyris 目前优先选择带刘海屏幕，适合“只在内建屏显示”的默认策略。如果未来支持所有屏幕，不应让多个窗口共享一个容易互相覆盖的展开/收缩任务；每块屏幕需要自己的几何和交互状态。

## 不建议采用的部分

### 媒体状态

Atoll 动态加载私有 `MediaRemote.framework`，并包含额外适配进程；Spotify 控制还使用 AppleScript/ScriptingBridge。

- [NowPlayingController.swift L46-L84](https://github.com/Ebullioscopic/Atoll/blob/0d9e94853d55654517dd86861f75d2203d94d024/DynamicIsland/MediaControllers/NowPlayingController.swift#L46-L84)
- [SpotifyController.swift L27-L137](https://github.com/Ebullioscopic/Atoll/blob/0d9e94853d55654517dd86861f75d2203d94d024/DynamicIsland/MediaControllers/SpotifyController.swift#L27-L137)

Lyris 的本机读取 + Spotify Web API/OAuth 分层更适合跨设备、收藏同步和歌词业务，不应替换为 Atoll 的媒体方案。

### 真实音频 Tap

Atoll 在 macOS 14.2+ 使用 Core Audio process tap 获取实时幅度，但源码也记录了 Spotify + 蓝牙输出可能影响耳机暂停目标的问题。

- [AudioTap.swift L103-L285](https://github.com/Ebullioscopic/Atoll/blob/0d9e94853d55654517dd86861f75d2203d94d024/DynamicIsland/audio/AudioTap.swift#L103-L285)

因此它只适合未来作为明确提示权限和兼容风险的可选增强，不能替代 Lyris 当前低风险、由播放进度驱动的默认律动。

## 许可证边界

Atoll 使用 GPL-3.0，`NOTICE` 还说明其中部分实现来自同为 GPL-3.0 的 Boring.Notch。

- [LICENSE](https://github.com/Ebullioscopic/Atoll/blob/0d9e94853d55654517dd86861f75d2203d94d024/LICENSE)
- [NOTICE](https://github.com/Ebullioscopic/Atoll/blob/0d9e94853d55654517dd86861f75d2203d94d024/NOTICE)

除非决定让 Lyris 整体按 GPL 兼容方式发布，否则不要复制、逐行翻译、轻改 Atoll 的形状路径、事件协调器或媒体实现。允许的安全路径是：记录可观察行为与公开 API 组合，由 Lyris 按自己的命名、结构和测试 clean-room 实现。

## 后续实施优先级（本次不执行）

1. `TopIslandInteractionCoordinator`：顶边命中、首击、去抖、自动收缩和 teardown。
2. 单一视觉表面形变：移除窗口帧动画与内容动画的双重竞争。
3. 稳定显示器 ID 与屏幕变化后的几何重算。
4. 状态转换测试：展开、取消自动收缩、弹层保持、跨屏与缩回无残影。
5. 继续保留 Lyris 自有 Spotify、歌词、翻译、缓存与收藏架构。

本文件只记录研究依据和采用边界；具体采用情况以 Lyris 后续代码差异和测试为准。
