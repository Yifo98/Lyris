# Spotify 授权流程对照

访问日期：2026-07-22。官方规则与当前源码已核对；本轮没有使用真实 Spotify 账户、Token 或 Client Secret，也没有完成“同一 App、同一账户、同一 scopes、同一网络”的实机对照。因此，下表中的“源码/模拟一致”不能写成“Spotify 实机已证明无差异”。

## 推荐结论

| 模式 | 产品状态 | 用户输入 | 当前可用能力 | 主要限制 |
| --- | --- | --- | --- | --- |
| Local Companion | 默认 | 无 | 本机曲目、封面、状态、进度、基础播放控制、歌词、翻译、缓存 | 无 Spotify Liked Songs；不依赖 Web API；需要 macOS Automation 权限 |
| Custom Client + PKCE | 推荐账户模式，已接入产品 UI | Client ID | Local 全部 + scopes 允许的 Web API 播放控制与 Liked Songs | app owner Premium、Development Mode 5 用户、Refresh Token 六个月规则 |
| Client ID + Secret | 仅保留底层实验 core；正式运行时 fail-closed，未提供产品 UI | 无正式入口 | 实验测试可验证 OAuth 组成；正式运行时不允许 persisted Secret profile 进入播放或恢复 | 桌面端无法安全保管 Secret；同账号实机对照未完成 |

Spotify 官方明确：桌面应用不能安全保存 Client Secret，应使用 PKCE；Authorization Code + Secret 适合能安全保存 Secret 的服务端。PKCE 同样可以获取 Refresh Token。当前结论仍是 **PKCE 默认、Secret Flow 不进入正式运行时**。正式 runtime 只允许 `.pkce`；被篡改或遗留的 Secret profile 不能恢复连接或生成播放账户，用户明确点击保存 PKCE 配置时才会清旧凭证并转回 PKCE。若同账号实机对照仍没有必要收益，Secret 实验 core 可以继续延期或删除。

正式 runtime 当前只支持一个 Spotify Profile：检测到多个 Profile 时会在迁移、恢复、保存和网络请求之前 fail-closed，不按 UUID 隐式选账户。Secret→PKCE 或 Client 身份变更使用补偿式 Refresh Token 恢复而非跨存储原子事务，保存配置绝不读取 Client Secret；若 Profile 已转为 PKCE 后旧 Secret 清理失败，则保持 fail-closed 并要求检查 Keychain，后续每次 PKCE 保存继续重试删除。已授权 PKCE Profile 即使保存同一配置，只要 Secret 清理无法确认，也会先持久阻断会话再报错，避免 cached Access Token 或仍在 Keychain 的 Refresh Token 继续使用。授权完成阶段若 Profile 保存和旧 Refresh Token 恢复连续失败，则返回专门错误并持久阻断会话，残留的新 Token 也不能被重建 Broker 使用。Access Token 缓存同时绑定 Profile ID、Client ID、授权模式与 session fence，身份或 generation 变化不会复用旧会话。配置变更还会将 blocked 状态与 generation 写入同一权威记录，并在每次 Registry 操作前重新载入：飞行中的旧 Refresh 响应不能回写，旧 Broker 或旧授权 completion 不能解除较新的阻断；只有当前 generation 的完整授权成功后才恢复会话。

## OAuth 共同规则

- Redirect URI 必须精确匹配；loopback 使用 `http://127.0.0.1:PORT` 或 `http://[::1]:PORT`，不能使用 `localhost`。
- 当前两种账户模式申请完全相同的 scopes：
  - `user-read-playback-state`
  - `user-modify-playback-state`
  - `user-read-currently-playing`
  - `user-library-read`
  - `user-library-modify`
- 能力由实际 granted scopes 决定，不由“PKCE/Secret”标签决定：缺少播放读取 scope 时不暴露账户元数据能力；缺少播放修改 scope 时不暴露 transport、seek、shuffle 或 repeat；缺少 library scopes 时收藏读取/写入保持不可用。
- 403 会进入 `permissionRequired`，并移除已被服务端拒绝的陈旧能力；它不会被当作 Token 过期，也不会触发 Refresh Token 清理。
- 2026 Development Mode：app 所有者必须 Premium；新 app 每开发者 1 个 Client ID、每 app 5 名授权用户。
- 新 Development Mode 库操作使用 `GET /me/library/contains`、`PUT /me/library`、`DELETE /me/library` 和 Spotify URI。
- Refresh Token 从原始授权起六个月到期；刷新 access token 不延长。`authorizedAt` 仅用于提前 14 天及越过六个月后的轻量提醒，不能证明服务端 Token 已失效，也不能单独清 Token 或强制断开。
- 只有 Token endpoint 返回 `400 invalid_grant` 才清理当前 profile 的内存 Access Token 和 Refresh Token、阻止继续刷新并进入 `reauthorizationRequired`。Secret 模式的 Client Secret 保留到用户切换 PKCE 或删除 profile。
- 429 应尊重 `Retry-After`；缺失时使用有上限的指数退避和抖动。导航命令不会自动重放，避免 next/previous 重复执行。

## 安全存储

| 数据 | 存储 | UI/日志 |
| --- | --- | --- |
| Client ID | 非 Secret，但按用户要求默认遮罩；可存项目本地非敏感配置 | `SecureField` 风格，点击“显示”才短暂可见；离开设置后重新遮罩；日志只显示是否已配置 |
| Client Secret | 实验 core 的 Keychain-only 设计 | 正式 runtime 与产品 UI 均不开放；若未来开放，必须默认隐藏，不得成为长期 `@Published String`，不得写 JSON/UserDefaults/日志/截图 |
| Access / Refresh Token | Keychain only | 永不展示值；状态只显示有效、提醒、需重新授权 |
| PKCE verifier/state | 仅本次授权会话内存；回调结束或取消即清理 | 只记录流程阶段，不记录值 |
| 授权时间 | 非敏感时间戳，可持久化 | 仅作提醒；Token endpoint 才是失效判定权威 |

## 17 项对照矩阵

证据标签：**源码** = 当前生产路径已存在；**模拟** = 不含真实凭证的确定性 Harness 已运行；**实机未测** = 未在真实 Spotify 同账号环境验证。项目中的 XCTest 文件存在并完成类型检查，但本机 CommandLineTools 缺少 XCTest 运行时，本轮没有把它写成正式 `swift test` 执行成功。

| 项目 | PKCE | Secret Flow | 是否存在差异 |
| --- | --- | --- | --- |
| 1. 获取当前播放 | 源码：共用 Web API broker；scope-bound capability 模拟通过；实机未测 | 源码：授权后进入同一 broker；模式 scope parity 模拟通过；实机未测 | 源码设计无产品差异；真实差异未知 |
| 2. 播放和暂停 | 源码：共用 `/me/player/play`、`pause` 与 `.transport` gate；实机未测 | 源码：同一命令路径与 gate；实机未测 | 源码无差异；真实差异未知 |
| 3. 上一首和下一首 | 源码：共用 previous/next；导航命令不自动重放；实机未测 | 源码：同一路径；实机未测 | 源码无差异；真实差异未知 |
| 4. seek | 源码：共用 seek endpoint 与 `.seek` gate；实机未测 | 源码：同一路径；实机未测 | 源码无差异；真实差异未知 |
| 5. shuffle | 源码：共用 shuffle endpoint 与 `.shuffle` gate；实机未测 | 源码：同一路径；实机未测 | 源码无差异；真实差异未知 |
| 6. repeat | 源码：共用 repeat endpoint 与 `.repeatMode` gate；实机未测 | 源码：同一路径；实机未测 | 源码无差异；真实差异未知 |
| 7. 读取收藏 | 源码：`GET /me/library/contains`，要求 `user-library-read`；收藏模拟覆盖未知态/刷新/竞态；实机未测 | 源码：同一路径与 scope；模式 capability parity 模拟通过；实机未测 | 源码无差异；真实差异未知 |
| 8. 收藏 | 源码：`PUT /me/library`，要求 `user-library-modify`；乐观更新/确认/回滚模拟通过；实机未测 | 源码：同一路径与 scope；实机未测 | 源码无差异；真实差异未知 |
| 9. 取消收藏 | 源码：`DELETE /me/library`，要求 `user-library-modify`；实机未测 | 源码：同一路径与 scope；实机未测 | 源码无差异；真实差异未知 |
| 10. Spotify Connect | 当前只建模 `.remoteDevices` capability，没有设备枚举/Connect 产品 UI 或完整 endpoint 路径 | 相同；未因 Secret 开放额外能力 | 两种模式都未实现，不能做能力差异结论 |
| 11. 远程设备控制 | 当前只建模 `.transferPlayback` capability，没有设备选择/播放转移命令与 UI | 相同；未因 Secret 开放额外能力 | 两种模式都未实现，不能做能力差异结论 |
| 12. Token 刷新 | 源码：public client 以 Client ID 刷新；broker 的成功、5xx 重试与并发顺序模拟通过；实机未测 | 源码：刷新前按 profile 从 Keychain 读取 Secret 并使用 Basic auth；完整实机刷新未测 | OAuth 客户端认证不同；刷新后的产品能力无已证实差异 |
| 13. Refresh Token 过期处理 | 源码：`authorizedAt` 只提醒；`invalid_grant` 才清 Refresh Token 并要求重授权；advisory/invalid_grant 模拟通过；实机未测 | 共用同一状态机；`invalid_grant` 保留 Secret；实机未测 | 清理策略只在是否保留 Secret 上不同；失效判定规则相同 |
| 14. 401 | 源码：强制刷新一次，第二次 401 清 Refresh Token 并要求重授权；broker 模拟通过；实机未测 | 共用响应与状态机；Secret 刷新认证由模式决定；实机未测 | OAuth 刷新认证不同；401 产品状态无已证实差异 |
| 15. 403 | 源码：进入 `permissionRequired`，清除被拒绝的陈旧 capabilities；模拟通过；实机 Premium/allowlist 条件未测 | 共用同一 403 路径；实机未测 | 源码无差异；真实账户条件可能造成差异，尚未对照 |
| 16. 429 | 源码：解析并不缩短 `Retry-After`，否则有界退避；policy/broker 模拟通过；实机未测 | 共用同一 retry policy；实机未测 | 同一 Client 下无模式差异证据；不同 Client/App 的配额不能归因于 Secret |
| 17. 断网恢复 | 源码：读操作和可安全重放的绝对写操作可有界重试；Local Companion 可继续提供本机能力；真实断网恢复未测 | 共用同一网络分类与 retry policy；实机未测 | 源码无差异；网络环境差异未排除 |

## 如何完成真实对照

真实对照必须固定同一个 Spotify App、同一个用户、同一 scopes、同一播放设备、同一网络与近似时间窗口。否则结果可能来自：

- OAuth code exchange 方式差异，而不是产品能力差异；
- 不同 Client/App 的滚动窗口配额；
- Premium、Development Mode allowlist 或账户状态；
- 网络条件与服务端瞬时错误；
- 轮询时序和人工操作误差。

在该对照完成前，不能声称 Secret 模式更稳定、额度更高或功能更多，也不能把源码 parity 当作 Spotify 服务端 parity。当前建议保持 PKCE 默认，并暂不开放 Secret 产品 UI。

## 官方来源

- [Authorization flow selection](https://developer.spotify.com/documentation/web-api/concepts/authorization)
- [Authorization Code with PKCE](https://developer.spotify.com/documentation/web-api/tutorials/code-pkce-flow)
- [Redirect URI requirements](https://developer.spotify.com/documentation/web-api/concepts/redirect_uri)
- [February 2026 migration guide](https://developer.spotify.com/documentation/web-api/tutorials/february-2026-migration-guide)
- [Refresh token expiration announcement](https://developer.spotify.com/blog/2026-06-18-refresh-token-expiration)
- [Refreshing tokens](https://developer.spotify.com/documentation/web-api/tutorials/refreshing-tokens)
- [Rate limits](https://developer.spotify.com/documentation/web-api/concepts/rate-limits)
