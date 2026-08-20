# LyricsX 架构映射（clean-room 行为规格）

验证日期：2026-07-22。所有第三方事实均为 **Level B**，来自固定提交 LyricsX `e84963a…`、MusicPlayer `ced0ac74…` 与 LyricsKit `6f071990…`。本文件只映射职责和行为，不移植类型名、控制流或 UI。

| 第三方可验证职责 | Level B 精确证据 | Lyris 自有模块 | 采用决定 |
| --- | --- | --- | --- |
| 统一曲目、状态、时间轴、命令与事件 | [MusicPlayer.swift L13-L31](https://github.com/MxIris-LyricsX-Project/MusicPlayer/blob/ced0ac74f3dd2d364743581e66404af0e35d37e7/Sources/MusicPlayer/MusicPlayer.swift#L13-L31) | `PlaybackSource` + `PlaybackSnapshot` | 采用协议思想，自行实现类型与状态语义。 |
| 把当前播放器的状态和命令转发给上层 | [Agent.swift L33-L86](https://github.com/MxIris-LyricsX-Project/MusicPlayer/blob/ced0ac74f3dd2d364743581e66404af0e35d37e7/Sources/MusicPlayer/Players/Agent.swift#L33-L86) | `HybridPlaybackCoordinator` | 采用单一权威 source；切换来源时不自动双写命令。 |
| 在多个本地播放器中选择当前播放者 | [NowPlaying.swift L30-L58](https://github.com/MxIris-LyricsX-Project/MusicPlayer/blob/ced0ac74f3dd2d364743581e66404af0e35d37e7/Sources/MusicPlayer/Players/NowPlaying.swift#L30-L58) | `PlaybackSourceSelection` | 采用“正在播放优先”的状态规则；先只支持 Spotify。 |
| 监听 Spotify 进程、曲目与播放状态并本地控制 | [LXScriptingMusicPlayer.m L38-L76](https://github.com/MxIris-LyricsX-Project/MusicPlayer/blob/ced0ac74f3dd2d364743581e66404af0e35d37e7/Sources/LXMusicPlayer/LXScriptingMusicPlayer.m#L38-L76)、[LXPlayerSpotify.m L48-L124](https://github.com/MxIris-LyricsX-Project/MusicPlayer/blob/ced0ac74f3dd2d364743581e66404af0e35d37e7/Sources/LXMusicPlayer/Players/LXPlayerSpotify.m#L48-L124) | `LocalSpotifyPlaybackSource` | 采用公开 Apple Events 能力，另写授权说明、错误模型和测试。 |
| 用本地时间轴写入实现 seek | [LXPlayerSpotify.m L83-L87](https://github.com/MxIris-LyricsX-Project/MusicPlayer/blob/ced0ac74f3dd2d364743581e66404af0e35d37e7/Sources/LXMusicPlayer/Players/LXPlayerSpotify.m#L83-L87) | `PlaybackClock` + `PlaybackCommand.seek` | 采用“命令后立即校准本地时钟，再等来源确认”；具体容错自行定义。 |
| 本地歌词优先、网络来源补全 | [AppController.swift L174-L241](https://github.com/MxIris-LyricsX-Project/LyricsX/blob/e84963a6346b9a99dfdcaf082908f12247f1637b/LyricsX/Component/AppController.swift#L174-L241) | `LyricsPipeline` | Lyris 顺序固定为用户编辑 > 合法缓存 > 合规 provider。 |
| 搜索、获取、规范化来源元数据 | [LyricsProvider.swift L7-L19](https://github.com/MxIris-LyricsX-Project/LyricsKit/blob/6f071990d0c9c6f48d29284db805990bffb912ed/Sources/LyricsService/Provider/LyricsProvider.swift#L7-L19)、[LyricsProvider.swift L28-L60](https://github.com/MxIris-LyricsX-Project/LyricsKit/blob/6f071990d0c9c6f48d29284db805990bffb912ed/Sources/LyricsService/Provider/LyricsProvider.swift#L28-L60) | `LyricsProvider` + `LyricsCandidate` | 采用生命周期，自行定义 cancellation、provenance 与缓存指纹。 |
| 候选质量综合标题、艺人、时长、翻译和逐字信息 | [Lyrics+Quality.swift L14-L45](https://github.com/MxIris-LyricsX-Project/LyricsKit/blob/6f071990d0c9c6f48d29284db805990bffb912ed/Sources/LyricsService/Utilities/Lyrics%2BQuality.swift#L14-L45)、[Lyrics+Quality.swift L47-L85](https://github.com/MxIris-LyricsX-Project/LyricsKit/blob/6f071990d0c9c6f48d29284db805990bffb912ed/Sources/LyricsService/Utilities/Lyrics%2BQuality.swift#L47-L85) | `LyricsMatcher` | 采用字段集合，不采用其权重/阈值；Lyris 另加版本冲突和最低置信度测试。 |
| 统一行、语言化翻译和逐字附件 | [Lyrics.swift L3-L16](https://github.com/MxIris-LyricsX-Project/LyricsKit/blob/6f071990d0c9c6f48d29284db805990bffb912ed/Sources/LyricsCore/Lyrics.swift#L3-L16)、[LyricsLineAttachment.swift L25-L73](https://github.com/MxIris-LyricsX-Project/LyricsKit/blob/6f071990d0c9c6f48d29284db805990bffb912ed/Sources/LyricsCore/LyricsLineAttachment.swift#L25-L73)、[LyricsLineAttachment.swift L151-L219](https://github.com/MxIris-LyricsX-Project/LyricsKit/blob/6f071990d0c9c6f48d29284db805990bffb912ed/Sources/LyricsCore/LyricsLineAttachment.swift#L151-L219) | `LyricDocument` + `LyricTimeline` | 自行定义 line/token/translation/provenance；行级先稳定，token 逐步接入。 |
| 单曲 offset 与全局 offset 叠加 | [Extension.swift L209-L216](https://github.com/MxIris-LyricsX-Project/LyricsX/blob/e84963a6346b9a99dfdcaf082908f12247f1637b/LyricsX/Utility/Extension.swift#L209-L216) | `LyricsTimingAdjustment` | 只采用“双层持久化”；Lyris 明确定义正数使歌词更晚显示，不能复制 LyricsX 的相反符号。 |
| 桌面与菜单栏是同一歌词状态的不同投影 | [KaraokeLyricsController.swift L110-L163](https://github.com/MxIris-LyricsX-Project/LyricsX/blob/e84963a6346b9a99dfdcaf082908f12247f1637b/LyricsX/Controller/KaraokeLyricsController.swift#L110-L163)、[MenuBarLyricsController.swift L46-L89](https://github.com/MxIris-LyricsX-Project/LyricsX/blob/e84963a6346b9a99dfdcaf082908f12247f1637b/LyricsX/Controller/MenuBarLyricsController.swift#L46-L89) | `OverlayViewModel` + status item projection | 采用共享状态模型；视觉、交互与窗口结构保持 Lyris 自有设计。 |
| 文本导入、LRC/LRCX 持久化和导出 | [AppController.swift L306-L336](https://github.com/MxIris-LyricsX-Project/LyricsX/blob/e84963a6346b9a99dfdcaf082908f12247f1637b/LyricsX/Component/AppController.swift#L306-L336)、[Extension.swift L131-L170](https://github.com/MxIris-LyricsX-Project/LyricsX/blob/e84963a6346b9a99dfdcaf082908f12247f1637b/LyricsX/Utility/Extension.swift#L131-L170) | `ManualLyricsStore` + `LyricsCache` | 采用用户可编辑和可导入导出能力；格式、校验、文件布局自行设计。 |

## 明确拒绝

- **私有系统播放 API**：`SystemMedia` 导入 `MediaRemotePrivate`（[SystemMedia.swift L1-L12](https://github.com/MxIris-LyricsX-Project/MusicPlayer/blob/ced0ac74f3dd2d364743581e66404af0e35d37e7/Sources/MusicPlayer/Players/SystemMedia.swift#L1-L12)）。Lyris 不采用。
- **第三方私有歌词端点或认证材料**：源码可见不等于接口或数据获得授权；Lyris 只接入有明确使用边界的 provider。
- **UI 与表达复制**：不复制窗口结构、控制器组织、文件名、类型名、动画、文案或资源。
- **权重和常量照搬**：候选评分、刷新容错、offset 符号和时间阈值由 Lyris 自己的需求与测试确定。

## 仍需 Level A 的内容

Apple Events 首次授权、Spotify/Apple Music 不同版本兼容性、seek 实际延迟、休眠唤醒后的生命周期以及歌词窗口性能，均无法由固定源码单独证明。
