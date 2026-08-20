# Spotify 授权模式核心对照结论

日期：2026-07-22。范围：Lyris v0.3 当前授权抽象与产品接线的本地、确定性验证；未使用真实 Spotify 账户、Token、Client Secret 或远程网络请求。

## 结论

PKCE 与 Authorization Code + Client Secret 在 Lyris 中申请同一组 scopes，下游能力由实际 `grantedScopes` 决定，而不是由授权模式名称决定。当前没有证据证明 Secret Flow 拥有更高配额、更多 Web API 能力、更少 429 或更高稳定性。

- 默认和推荐模式继续使用 **Custom Client + PKCE**；它已接入当前产品设置 UI、profile、Keychain Token 与播放账户路径。
- Secret Flow 的底层 core、per-profile Keychain 生命周期和 token exchange 模型存在，但正式 runtime 通过硬编码产品策略只允许 PKCE；产品 UI 没有 Client Secret 输入、模式切换或实机授权入口。
- 同一 App、同一账户、同一 scopes、同一网络下的真实对照尚未执行，因此 Secret Flow 应继续保持内部实验状态；可以延期或最终删除。
- `authorizedAt` 只驱动六个月到期前 14 天及越过六个月后的提醒。即使时间戳已越过六个月，只要 Spotify Token endpoint 接受 Refresh Token，就保留 Token 并维持连接；只有 `invalid_grant` 才强制重新授权。

## 已验证的核心行为

| 项目 | PKCE | Secret Flow | 核心差异 |
| --- | --- | --- | --- |
| Authorization Request | `code_challenge_method=S256` 与 challenge | 不携带 PKCE challenge，也不把 Secret 放入浏览器 URL | 仅授权码保护方式不同 |
| Token Exchange | 临时 verifier | 交换前才从 per-profile TokenStore 读取 Secret | 仅客户端证明不同 |
| 请求 scopes | 播放状态、播放控制、当前播放、收藏读写 | 完全相同 | 无源码产品能力差异 |
| Capability gate | 由 `grantedScopes` 映射 metadata/transport/seek/shuffle/repeat/liked 等能力 | 使用相同映射 | 无差异；缺 scope 就不暴露能力 |
| Refresh Token | `spotify.refreshToken.<profileID>` | `spotify.refreshToken.<profileID>` | Keychain account 无差异 |
| 刷新客户端认证 | public client + Client ID | 刷新前按 profile 读取 Secret，使用 Basic auth | OAuth 请求组成不同 |
| Client Secret | 不需要 | `spotify.clientSecret.<profileID>` | Secret Flow 独有风险 |
| 普通 Profile | Client ID、模式、Redirect URI、授权时间、scopes | 字段完全相同 | Profile 不含 Secret/Token |
| `authorizedAt` | 只作提醒，不单独清 Token | 相同 | 无差异 |
| Token endpoint `invalid_grant` | 清内存 Access Token 与该 profile 的 Refresh Token，进入重新授权且不持续重试 | 相同，但保留 Client Secret | Secret 保留策略不同 |
| Web API 403 | 进入 `permissionRequired`，移除被拒绝的陈旧 capabilities | 相同 | 不当作 Token 过期；无模式差异 |
| 删除 Profile | 删除 Refresh Token，并尝试清理 Secret account | 删除 Refresh Token 与 Secret | 同一清理入口 |

## 安全边界

- `SpotifyAuthorizationProfile` 是唯一普通配置模型；其版本化 JSON 不包含 Secret、Access Token 或 Refresh Token 字段。
- `SpotifyTokenStore` 通过现有 `CredentialVault` 接缝工作；生产组合注入 `KeychainCredentialVault`。
- Secret 只在 Secret Flow 执行 code exchange 或 refresh 前读取，不保存在 Flow、Coordinator、Profile 或 UI 的长期属性中。
- 删除 Profile 会先尝试删除两个 per-profile Keychain account；即使一个删除失败，另一个仍会被尝试。
- 从 Secret 模式切回 PKCE 时会删除该 Profile 的 Client Secret；之后每次保存 PKCE Profile 都会再次执行同一幂等删除，因此短暂的 Keychain 故障不会让旧 Secret 永久失去清理机会。即使是已授权 PKCE Profile 的同配置保存，只要清理无法确认，也会先持久阻断当前会话再报错，缓存 Access Token 与仍在 Keychain 的 Refresh Token 都不能继续联网。
- persisted 或被外部修改为 Secret mode 的 profile 不能生成正式播放账户，也不能恢复连接；明确点击保存 PKCE 配置会清理其 Refresh Token 与 Client Secret、重置 scopes/授权时间并转回 PKCE。
- Secret→PKCE 或 Client 身份变更使用跨 UserDefaults/Keychain 的**补偿式恢复**，不是原子事务：保存前只快照 Refresh Token，绝不为配置保存读取 Client Secret。若 Profile 持久化失败则恢复原 Refresh Token；若补偿失败返回专门错误。授权完成阶段若 Profile 保存失败且旧 Refresh Token 也无法恢复，则返回 `credentialRollbackFailed`，同时先推进并持久化会话 fence；即使新 Refresh Token 残留，当前或重建 Broker 也会在网络前 fail-closed。Profile 已转为 PKCE 后若旧 Secret 清理失败，则保持 Refresh Token 已删除、账户增强关闭并提示检查 Keychain，不把 Secret 模式凭证恢复到 PKCE 身份；下一次 PKCE 保存继续重试清理。
- `SpotifySessionBroker` 的 Access Token 缓存绑定 `profileID + clientID + authorizationMode`；即使复用同一 Profile ID，Client ID 或模式改变也会取消旧 refresh flight 并丢弃旧 Access Token。
- 配置变更或 `invalid_grant` 会同步递增 profile-scoped session fence，并把 `profileID + generation + blocked` 作为一个非敏感 UserDefaults v2 单记录持久化。同一进程内所有 Registry 在每次读写前都于 process-wide lock 下重新载入该权威记录，旧 Broker 不能用本地旧 generation 覆盖新 Broker。Token/API 请求在每个 `await` 后重新验证 fence，旋转后的 Refresh Token 与 Access Token cache 只会在同一 fence 锁内提交；旧授权 completion 即使跨 Broker 重建也不能清除较新的阻断。迟到的内存清理只会取消 generation 不同的旧 refresh flight/cache，不会取消同 generation 的合法新授权。只有当前 generation 的授权已完成 Profile/Refresh Token 提交后，Broker 才会清除持久 marker 并接管新 Access Token。
- 正式 runtime 当前只支持一个 Spotify Profile。若本机意外存在多个 Profile，会在迁移、播放、恢复和保存之前 fail-closed，不按随机 UUID 选择账户，也不修改任一 Profile、Keychain 凭证或发起网络请求。
- Legacy `spotifyClientID` 迁移为默认 PKCE Profile；若旧全局 Refresh Token 存在，会先复制并校验到 profile-scoped Keychain account，再删除旧 account，并保留当时已知的五项 legacy scopes。`authorizedAt` 始终保持 `nil`，迁移后的凭证仍必须由 Spotify Token endpoint 验证，不能用本地时间戳冒充新授权。
- 日志模型只输出 mode、profile ID、scope 数量与是否有 Refresh Token，不输出 Secret、Token、authorization code、PKCE verifier/state 或 callback query。

## 当前产品接线

- `SpotifyAuthorizationRuntime` 已组合 profile store、token store、PKCE/Secret core coordinator 与 `SpotifySessionBroker`，同时在产品边界用 `SpotifyProductAuthorizationPolicy` fail-closed，只允许 `.pkce` 进入正式播放、恢复和授权路径。
- 当前设置页只保存 Client ID、生成 PKCE 授权并恢复 profile-scoped Refresh Token；这是正式产品路径。
- `SpotifyPlaybackAccount.playbackCapabilities` 从 `grantedScopes` 计算能力；缺 library scopes 时不会显示假收藏状态。
- Web API 403 会发布 `permissionRequired`，并清除本次被拒绝的 stale capability；UI 可据此提示重新连接并补足权限。
- 多 Profile 冲突已有明确双语 fail-closed 提示，但产品尚未提供 Profile 选择或旧授权配置清理入口；这是安全门，不是多账户管理功能。
- Secret Flow 仍没有设置入口、Client Secret SecureField、主动模式选择或真实账户完成页。因此不能把“core 存在”写成“Secret 模式已作为产品功能完成”。
- Spotify Connect/设备枚举与播放转移当前只有 capability 名称，没有完整 endpoint、选择 UI 和实机验收，不能列为已交付能力。

## 本轮确定性证据

以下不含真实凭证的 Harness 已在当前源码上运行通过：

- `spotify-authorization`：profile 不含 Secret、per-profile account、PKCE exchange、Secret 临时读取、mode scope/capability parity、清理与 legacy migration。
- `spotify-network-policy`：401/403/429/5xx/断网分类、`Retry-After`、有界退避、`invalid_grant` 决策与日志脱敏。
- `spotify-broker`：`invalid_grant` 清理且不重试、401 只强制刷新一次、`Retry-After` 不缩短、Refresh Token 5xx 重试与请求重放边界。
- `scope-capabilities`：scope-bound capability 与缺 library scope 时隐藏收藏。
- `permission-handling`：403 发布 `permissionRequired` 并清 stale capabilities。
- `refresh-token-advisory`：过期时间戳只提醒；服务端接受 Refresh Token 时保留凭证和连接。
- `secret-mode-product-gate`：正式模式策略只允许 PKCE；persisted Secret profile 无法进入播放；明确保存 PKCE 后清理实验凭证；Profile 保存失败时补偿恢复 Refresh Token；保存配置全过程不读取 Secret；Secret 清理失败时保持 fail-closed，并在下一次 PKCE 保存成功重试删除；已授权 PKCE 的同配置清理失败也会阻断 cached session 且零网络；多个 Profile 时保留全部状态并在网络前 fail-closed；Refresh 正在飞行时配置变更不会晚到回写；旧 completion 不能解锁新 generation；旧 Broker 不能覆盖新 Broker 的 generation；授权完成的 Refresh Token 回滚失败仍会持久阻断且跨重建零网络；当前 generation 的成功授权才可清除 fence。
- `spotify-broker`：除 invalid_grant、401、429、5xx 与重放边界外，额外验证同一 Profile ID 更换 Client ID 后不会复用旧 Access Token。

正式 XCTest 测试文件已存在且可完成类型检查，但本机只有 CommandLineTools，缺少 XCTest 运行时，因此本轮没有执行成功的 `swift test` 结果。以上 Harness 证明本地抽象与模拟响应行为，不证明 Spotify 服务端配额、账户政策、Secret 刷新实机表现或两种模式的真实 parity。

完整 17 项状态见 `spotify-auth-flow-comparison.md`。在真实同账号对照完成前，产品决策保持 **PKCE 默认，Secret UI 不开放**。
