# Lyricify 4 官方文档审阅

验证日期：2026-07-22
证据级别：**Level C（产品官方文档、产品官方仓库或 Spotify 官方文档）**
验证版本：Lyricify 4 官方仓库在验证日列出的最新版本为 `v4.3.52-release`（2026-07-14）。本机未安装 Lyricify 4，因此下列内容不是 Level A 实机结论，也不推断闭源主程序内部实现。

## §16 逐项结论

| 研究项 | 证据级别 | 验证日期 | 结论 | 状态 | 直接证据 |
| --- | --- | --- | --- | --- | --- |
| Custom API Client | Level C | 2026-07-22 | 官方教程要求用户在 Spotify Developer Dashboard 创建自己的 App，再在 Lyricify 中配置该 Client。 | **确认支持** | [Custom Spotify API Client Configuration Tutorial](https://docs.lyricify.app/en/lyricify-4/custom-api-client/) |
| Client ID + Client Secret | Level C | 2026-07-22 | 教程明确要求查看并填写 `Client ID` 与 `Client Secret`。这只证明产品收集这两个输入，不足以证明 Secret 在本机还是服务端交换，也不足以证明具体 OAuth grant。 | **确认输入；内部用途待验证** | [Custom Client：Preparations / Works on Lyricify](https://docs.lyricify.app/en/lyricify-4/custom-api-client/) |
| Authorization Code Flow | Level C | 2026-07-22 | Lyricify 教程只写“浏览器授权”和“完成 authorization”，未公开 `grant_type`、token exchange 或请求头；不能仅凭出现 Secret 就断言主程序使用 Spotify Authorization Code Flow。 | **待验证，不作内部实现结论** | [Lyricify Getting Started](https://docs.lyricify.app/en/lyricify-4/getting-started/)、[Spotify Authorization Code Flow](https://developer.spotify.com/documentation/web-api/tutorials/code-flow) |
| 429 | Level C | 2026-07-22 | Custom Client 页面声称可避免公共 Client 带来的 429；但 Lyricify 自己的 429 FAQ 又明确记录“配置 Custom Client 后仍可能出现长 429”，并提供公共 Client 回退或新建 Client 的建议。因此只能得出“隔离共享请求负载、降低部分 429 风险”，不能写成“消灭 429”。 | **确认有缓解路径；不保证消除** | [Custom Client benefit](https://docs.lyricify.app/en/lyricify-4/custom-api-client/)、[Lyricify 429 FAQ](https://docs.lyricify.app/en/lyricify-4/faq/error-429/)、[Spotify Rate Limits](https://developer.spotify.com/documentation/web-api/concepts/rate-limits) |
| Premium | Level C | 2026-07-22 | Custom Client 教程要求 Client 所有者具有有效 Spotify Premium；Getting Started 还把主动控制、进度、音量等列为 Premium 能力，但说明本机 Media Session 正常时 Free 账户也可控制本机播放。 | **确认，且有能力边界** | [Custom Client requirements](https://docs.lyricify.app/en/lyricify-4/custom-api-client/)、[Getting Started：Premium features](https://docs.lyricify.app/en/lyricify-4/getting-started/)、[Spotify Quota Modes](https://developer.spotify.com/documentation/web-api/concepts/quota-modes) |
| 五用户限制 | Level C | 2026-07-22 | Lyricify 教程写明一个 Client 最多五名用户；Spotify 官方文档确认 Development Mode App 最多五名已认证用户，且每人必须加入 allowlist，否则即使能登录，API 请求也可能返回 403。 | **确认（Development Mode）** | [Lyricify Custom Client](https://docs.lyricify.app/en/lyricify-4/custom-api-client/)、[Spotify Quota Modes](https://developer.spotify.com/documentation/web-api/concepts/quota-modes) |
| Redirect URI | Level C | 2026-07-22 | Lyricify 教程要求登记 `http://127.0.0.1:766/callback` 和 `lyricify://callback`，并明确 `localhost` 与 `https://127.0.0.1...` 会导致 invalid redirect。Spotify 当前规则确认 HTTP 只允许显式 loopback IP、禁止 `localhost`、请求值必须匹配 allowlist。Spotify 当前页面没有把自定义 scheme 列为允许形式，Lyris 不复制 `lyricify://`。 | **loopback 已确认；自定义 scheme 不采用** | [Lyricify Custom Client：Redirect URI](https://docs.lyricify.app/en/lyricify-4/custom-api-client/)、[Spotify Redirect URIs](https://developer.spotify.com/documentation/web-api/concepts/redirect_uri) |
| 授权失败 | Level C | 2026-07-22 | Lyricify 文档覆盖 invalid redirect，以及“浏览器显示成功但应用无响应/手动授权失败”的网络排查；这只是厂商给出的故障指导，并非对所有失败根因的证明。 | **确认有文档；完整状态机待验证** | [Custom Client common issues](https://docs.lyricify.app/en/lyricify-4/custom-api-client/)、[Authorization no response](https://docs.lyricify.app/en/lyricify-4/faq/auth-no-response/) |
| 重新授权 | Level C | 2026-07-22 | 配置 Custom Client 前要求先退出当前 Spotify 登录；非 Premium Custom Client 故障页描述删除登录信息后重新授权。`v4.3.52` Release Notes 还写明已处理 Spotify Refresh Token 六个月强制过期。具体 UI 流程和是否自动清理所有旧凭证仍待实机验证。 | **确认有重授权路径；细节待 Level A** | [Custom Client：Works on Lyricify](https://docs.lyricify.app/en/lyricify-4/custom-api-client/)、[Non-Premium Custom Client FAQ](https://docs.lyricify.app/en/lyricify-4/faq/non-premium-custom-client/)、[v4.3.52 Release Notes](https://github.com/WXRIW/Lyricify-App/releases/tag/v4.3.52)、[Spotify refresh-token expiration](https://developer.spotify.com/blog/2026-06-18-refresh-token-expiration) |
| 灵动词岛 | Level C | 2026-07-22 | 官方术语页定义它为与 Dynamic Island/刘海相关的浮动歌词窗口；官方仓库称该创意于 2022-09-30 首创、在 3.8.1 发布。FAQ 证明它可配置“全屏时隐藏”。文档没有完整列出布局、交互和动画状态，不能照图推断。 | **确认存在；详细交互待验证** | [Lyricify Terms](https://docs.lyricify.app/en/lyricify-4/terms/)、[Official repository README](https://github.com/WXRIW/Lyricify-App#lyricify-4-original)、[Overlay disappearance FAQ](https://docs.lyricify.app/en/lyricify-4/faq/desktop-lyrics-disappear/) |
| 桌面歌词 | Level C | 2026-07-22 | 官方术语页和 FAQ 明确存在 Desktop Lyrics，并支持全屏窗口出现时隐藏；当前公开说明不足以证明具体行数、锁定、拖动或点击穿透行为。 | **确认存在；交互细节待验证** | [Lyricify Terms](https://docs.lyricify.app/en/lyricify-4/terms/)、[Overlay disappearance FAQ](https://docs.lyricify.app/en/lyricify-4/faq/desktop-lyrics-disappear/) |
| 纵向歌词 | Level C | 2026-07-22 | Getting Started 只证明主窗口缩窄后会自动切换 `Portrait Style`，以及出现 Floating Track Box。它没有证明存在一个独立的“纵向歌词浮窗模式”。 | **主窗口纵向布局已确认；独立模式待验证** | [Getting Started：Portrait Style](https://docs.lyricify.app/en/lyricify-4/getting-started/)、[Lyricify Terms](https://docs.lyricify.app/en/lyricify-4/terms/) |
| 全屏歌词 | Level C | 2026-07-22 | 主界面 Fullscreen 按钮进入 Lyricify Fullscreen，右键进入 Mobile UI Fullscreen；Apple Music Lyrics 性能 FAQ 同时警告原生全屏渲染资源消耗较高。 | **确认支持，存在性能代价** | [Getting Started：Keys and Functions](https://docs.lyricify.app/en/lyricify-4/getting-started/)、[Apple Music Lyrics performance FAQ](https://docs.lyricify.app/en/lyricify-4/faq/apple-music-performance/) |
| 多行 | Level C | 2026-07-22 | 官方术语定义 Multi-line Highlight；歌词标准说明 QRC 时间段重叠可产生多行同时高亮。不能据此推断所有歌词来源或所有表面均支持。 | **特定格式/界面确认支持** | [Lyricify Terms](https://docs.lyricify.app/en/lyricify-4/terms/)、[Lyrics Guide and Standards](https://docs.lyricify.app/en/lyrics/guide/) |
| 逐字 | Level C | 2026-07-22 | 官方歌词标准列出 QRC/YRC 的逐字时间、Lyricify Syllable/Apple Syllable 的逐音节信息；Track Management 仅允许手动导入其中部分格式，YRC 明确不支持手动导入。 | **数据与显示能力确认；导入能力有限** | [Lyrics Guide and Standards](https://docs.lyricify.app/en/lyrics/guide/)、[Lyrics and Track Management](https://docs.lyricify.app/en/lyricify-4/lyrics-and-track-management/) |
| 对唱 | Level C | 2026-07-22 | Track Management 可配置 Duet View；官方术语定义为歌词左右两侧显示。它依赖歌词中的对唱信息，不能视为普通行级歌词自动具备。 | **确认支持，依赖数据** | [Lyrics and Track Management：Duet View](https://docs.lyricify.app/en/lyricify-4/lyrics-and-track-management/)、[Lyricify Terms](https://docs.lyricify.app/en/lyricify-4/terms/) |
| 性能预设 | Level C | 2026-07-22 | 首次设置提供 Default、Better Performance、Better Quality；官方说明 Better Performance 会关闭部分效果，Better Quality 会打开全部效果并可能导致滚动卡顿。Apple Music Lyrics FAQ 还建议缩小窗口、避免全屏、关闭模糊/动态背景/Karaoke。 | **确认支持** | [Getting Started：Preset Configuration](https://docs.lyricify.app/en/lyricify-4/getting-started/)、[Apple Music Lyrics performance FAQ](https://docs.lyricify.app/en/lyricify-4/faq/apple-music-performance/) |
| 歌词管理 | Level C | 2026-07-22 | 官方文档覆盖来源顺序、标记正确歌词、搜索/导入/上传、Offset、对唱信息、歌词库、手动歌词与翻译。自动搜索约 `0.5–2s` 是厂商文档数值，未做独立测量。 | **确认支持** | [Lyrics and Track Management](https://docs.lyricify.app/en/lyricify-4/lyrics-and-track-management/) |
| 429 与切歌问题 | Level C | 2026-07-22 | 官方 FAQ 把“切歌后仍显示旧曲”列为可能的 429 表现，把“曲目信息已更新但歌词延迟”与未标记歌词关联；另一个 FAQ 记录时间线校正可能造成切歌时约一秒卡顿/首秒重复。它们是不同故障，不应合并成单一根因。 | **确认记录三类现象；根因边界明确** | [Song Switch Lag](https://docs.lyricify.app/en/lyricify-4/faq/song-switch-lag/)、[Stutter on Track Change](https://docs.lyricify.app/en/lyricify-4/faq/stutter-on-track-change/)、[429 FAQ](https://docs.lyricify.app/en/lyricify-4/faq/error-429/) |

## 官方文档不能证明的内容

- 不能证明 Lyricify 4 的 OAuth token exchange 一定运行在桌面端、一定使用 Authorization Code Flow，或 Secret 在内存/磁盘中的保存方式。
- 不能证明 Client Secret 会提高 Spotify 配额。Spotify 官方把 429 归因于 **App 在滚动 30 秒窗口内的请求量和 quota mode**；Secret 是认证凭证，不是配额单位。
- 不能把 Lyricify 文档中的“Custom Client 避免 429”解释为技术保证；同一套官方 FAQ 已记录 Custom Client 的长 429。
- 不能从术语页或截图复制灵动词岛、桌面歌词、Magic Strip 的 UI、文案或动画。主程序闭源，公开文档仅能作为功能事实来源。

## 对 Lyris 的可采用结论

1. 保留“本机低门槛播放来源 + 可选 Spotify 账户能力”的分层，但不复制 Windows SMTC 或 Lyricify UI。
2. Spotify 账户模式使用用户自己的 Custom Client **不等于**必须使用 Secret；桌面端推荐 Custom Client + PKCE。
3. 429 必须按 `Retry-After`、退避、请求合并、低频权威快照和可解释错误处理，不能用“再填一个 Secret”替代流量治理。
4. 灵动岛式表面可以作为 Lyris 自有显示模式，但布局与动效必须重新设计；Level C 研究只证明竞品存在这种产品形态。
5. 多行、逐字、背景人声和对唱应当由歌词数据能力驱动；缺少相应时间/角色信息时明确降级到行级显示。
6. 性能档位应控制实际渲染成本，并用实机帧率/CPU 验证；不能只做一个视觉开关。
