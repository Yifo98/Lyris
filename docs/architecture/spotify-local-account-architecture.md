# Spotify 本地伴侣与账户增强架构

状态：v0.2→v0.3 实施决策，2026-07-22。

## 结论

Lyris 不把 Local、PKCE、Secret 建模成三套互斥播放器。**Local Companion 始终是默认基础层**；账户连接只增量提供收藏，以及通过 Spotify Web API 控制当前活跃播放设备。PKCE 与 Secret 只是同一账户层的两种授权 adapter，下游 Web API 能力完全按 scopes 与账户状态判定。当前版本没有设备列表与播放转移 UI，因此不得把它描述为“远端设备管理”。

外部 seam 采用默认调用者优先的深模块：

```swift
@MainActor
final class ListeningSession: ObservableObject {
    @Published private(set) var playback: PlaybackPresentation
    @Published private(set) var account: SpotifyAccountPresentation

    func start()
    func perform(_ intent: PlaybackIntent) -> ActionReceipt
    func perform(_ operation: SpotifyAccountOperation) -> ActionReceipt
    func installClientSecret(
        _ secret: EphemeralClientSecret,
        for profileID: UUID
    ) async throws
}
```

卡片只学习 `playback` 与播放 intent；设置页才学习 `account` 与账户 operation。Secret 使用独立入口，避免进入通用枚举、日志、埋点或 Codable 状态。

## 设计比较

| 方案 | 优点 | 代价 | 决策 |
| --- | --- | --- | --- |
| 保留 `PlaybackAdapting` 闭包，在外面加 Hybrid | 当前改动小 | Store 仍承担授权/能力/任务边界，module 偏浅 | 仅用于迁移，不作为最终 seam |
| `AsyncStream<Snapshot>` + 单一 Intent | 接口最小、actor 顺序清晰 | 高频流与现有 SwiftUI/Store 改造幅度大 | 吸收 generation/commit permit 思路 |
| `ListeningSession` 分离 playback/account | 默认 Local 调用最短；SwiftUI 自然观察；高低频状态分开 | 内部较深，必须防止成为巨型类 | **采用**，内部拆私有 module |

## 外部呈现模型

```swift
struct PlaybackPresentation: Equatable {
    var item: PlaybackItem?
    var position: TimeInterval
    var duration: TimeInterval
    var progress: Double
    var isPlaying: Bool
    var shuffle: Bool?
    var repeatMode: RepeatMode?
    var liked: LikedSongsPresentation
    var origin: PlaybackOrigin
    var target: PlaybackTarget
    var capabilities: PlaybackCapabilities
    var pending: Set<PlaybackMutation>
    var issue: PlaybackIssue?
}

enum LikedSongsPresentation: Equatable {
    case hidden
    case loading
    case ready(Bool)
    case updating(desired: Bool, previous: Bool)
    case failed(lastKnown: Bool?, PlaybackIssue)
}
```

Local 模式必须使用 `.hidden`，不能用 `false` 冒充“未收藏”。Episode、广告和 Unknown 同样不查询普通歌曲收藏。

`PlaybackCapabilities` 至少覆盖：metadata、play/pause、previous/next、seek、shuffle、repeat、liked read/write、devices、transfer。每项是 `available`、`requiresAccount`、`requiresAutomationPermission` 或带原因的 unavailable；UI 与命令路由使用同一份原子判定。

## 模块内部

```text
ListeningSession
├── HybridPlaybackCoordinator
│   ├── LocalSpotifyPlaybackSource
│   │   └── SpotifyDesktopScripting adapter
│   ├── SpotifyWebAPIPlaybackSource
│   │   └── SpotifyWebAPIClient adapter
│   ├── HybridSnapshotReducer
│   ├── CommandRouter
│   ├── PlaybackClock
│   ├── LikedSongsCoordinator
│   └── GenerationLedger
└── SpotifyAuthorizationCoordinator
    ├── SpotifyPKCEAuthorizer
    ├── SpotifySecretAuthorizer (实验开关)
    ├── SpotifyTokenStore
    ├── SpotifyProfileStore
    ├── SpotifyRetryPolicy
    └── CredentialRedactor
```

本机、Web、Keychain、URLSession、浏览器 callback、profile 存储和时钟都是真实内部 seam：每个都有生产与 Fake adapter。UI 不直接拿到这些接口。

## 来源归属与防双发

1. 本机 Spotify 有活动曲目时，本地来源独占曲目、位置、播放状态和 transport；Web 只补收藏与设备。
2. 用户明确选择远端设备时，Web 来源独占播放字段。
3. 只有 canonical Spotify URI 与 track generation 同时匹配，才允许把 Web 收藏合并到本机曲目。
4. 每个命令只路由到一个 adapter：本机目标走 Local，远端目标走 Web，收藏永远走 Web；不可用则同步拒绝。
5. UI 的 toggle 在 module 内立即解析成绝对意图，例如 `setLiked(true)`、`setPlaying(false)`，重试不会反转两次。

## generation 与提交许可

内部维护：

- `sourceEpoch`
- `trackGeneration`
- `mutationGeneration[transport, seek, liked, shuffle, repeat]`
- `authorizationGeneration`
- `lyricsGeneration`（歌词流水线独立，但使用相同原则）

每个异步操作捕获 `CommitPermit`；完成时必须同时匹配来源实例、曲目 token 和 lane generation。A→B→A 中的新 A 有新 token，因此旧 A 永远不能回写。取消与 stale completion 不写 UI、缓存或计数，也不算失败。

## 播放时钟

`PlaybackClock` 是纯模块，输入权威 source sample、seek 和播放状态事件，输出单调投影位置：

- 播放中按 monotonic elapsed 外推；
- 暂停冻结；恢复、切歌重建 anchor；
- seek 立即更新，并在确认窗口内拒绝命令前的旧 poll；
- 小漂移渐进校正，大漂移直接校准；
- UI 10–20 Hz 更新，Spotify Web API 仍低频轮询。

时钟不读取 wall-clock Date，测试直接传手动 monotonic time，不依赖真实等待。

## 授权与凭证

```swift
enum SpotifyAuthorizationMode: String, Codable {
    case pkce
    case authorizationCodeWithSecretExperimental
}

struct SpotifyAuthorizationProfile: Codable, Identifiable {
    let id: UUID
    var displayName: String
    var clientID: String
    var authorizationMode: SpotifyAuthorizationMode
    var redirectURI: String
    var authorizedAt: Date?
    var grantedScopes: Set<String>
}
```

Secret 不进入 profile。Keychain account：

```text
spotify.refreshToken.<profileID>
spotify.clientSecret.<profileID>
```

PKCE 与 Secret 只在 code/token exchange 处不同；成功后共用 Token 生命周期、Web API、收藏、设备、RetryPolicy 与错误模型。Secret 仅在发 Token 请求前从 Keychain 读取，请求后不保存在长期 `@Published` 状态。

授权状态：disconnected → authorizing → connected / expiringSoon → reauthorizationRequired / failed。`authorizedAt` 只在完整用户授权成功时更新；access-token refresh 不更新。

`invalid_grant`：清内存 Access Token、删除对应 Refresh Token、保留 profile；Secret 模式默认保留 Secret；停止自动刷新并提示重新授权。删除 profile 才同时删除 Token、Secret 和 profile。

## 错误边界

呈现错误必须区分：Spotify 未安装/未运行、Automation 拒绝、无活动设备、缺 scope、Premium/allowlist 403、`invalid_grant`、离线、429 与 retry time、5xx。

错误和日志不得包含 Secret、Access/Refresh Token、authorization code、PKCE verifier/state、API Key、完整 header/body 或 callback query。取消与 stale discard 不是用户错误。

## 迁移顺序

1. 先加入正式 test target、纯 `PlaybackClock`、generation 与 capability/liked 状态模型。
2. 在现有 Web 路径前落 `ListeningSession`/Hybrid seam；Store 改为只桥接 presentation。
3. 实现公开 Apple Events 的 Local source，Local 默认启动；加入 Automation 权限说明。
4. 将 `SpotifySessionBroker` 拆为 Token/HTTP/Auth 职责，Web source 不再直接读 UserDefaults。
5. 旧 Client ID 迁移成单一 PKCE profile；旧全局 Refresh Token 成功复制到 profile Keychain key 后才删除。旧 Token 的 `authorizedAt` 保持 nil，不能伪造成新授权。
6. 设置首页改为“打开 Spotify 即显示歌词”，账户连接是可跳过的增强步骤。
7. 完成 PKCE、收藏、401/403/429/离线与六个月重授权测试。
8. 最后才做 Secret 对照实验；无可验证收益则删除实验 adapter/UI。

## 测试策略

测试跨 `ListeningSession` seam 断言可观察结果，内部 Fake 只负责注入刺激。必须覆盖 Local 零配置、来源不互相覆盖、单命令单 adapter、seek 旧快照、A→B→A、收藏确认/回滚、auth cancel、`invalid_grant`、PKCE/Secret 能力一致性与无真实等待。
