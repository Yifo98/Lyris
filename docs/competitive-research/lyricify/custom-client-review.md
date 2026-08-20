# Lyricify Custom Client 与 Spotify OAuth 审阅

验证日期：2026-07-22
证据级别：**Level C（Lyricify 与 Spotify 官方文档）**
边界：Lyricify 4 主程序闭源且本机未安装；只记录官方公开行为，不推断内部 token exchange、Secret 存储或服务端架构。

## 已确认的 Lyricify 配置事实

Lyricify 4 官方教程要求用户：

1. 在 Spotify Developer Dashboard 创建 App；
2. 登记 `http://127.0.0.1:766/callback` 与 `lyricify://callback`；
3. 获取 `Client ID`、点击查看 `Client Secret`；
4. 在 Lyricify 中同时输入两者；
5. 继续浏览器登录并完成 Spotify 用户授权。

教程还要求 Custom Client 所有者拥有 Spotify Premium，并写明 Development Mode Client 最多五名用户。以上均为 **Level C 已确认产品行为**，来源：[Lyricify Custom Spotify API Client Tutorial](https://docs.lyricify.app/en/lyricify-4/custom-api-client/)。

## 四个容易混淆的概念

| 概念 | Spotify 官方含义 | 与 Secret / 配额的关系 |
| --- | --- | --- |
| Custom Client | 用户在 Developer Dashboard 自己创建的 Spotify App/Client。 | 可以搭配 Authorization Code，也可以搭配 PKCE；“自定义”不等于“必须有 Secret”。 |
| Authorization Code Flow | 可访问用户资源并刷新 Token；token exchange 使用 `client_id:client_secret`。Spotify 建议只在 Secret 能被安全保存时使用。 | **需要 Secret**，但 Secret 只是客户端认证凭证。 |
| Authorization Code with PKCE | 可访问用户资源并刷新 Token；使用 code verifier/challenge，不需要 Client Secret。Spotify 明确把桌面、移动和浏览器应用列为适用场景。 | **不需要 Secret**，并不因此获得较低配额。 |
| Quota / Rate Limit | Spotify 按 App 在滚动 30 秒窗口内的调用量和 quota mode 计算；Development Mode 与 Extended Quota 的上限不同。 | 与 App/Client 及请求量有关；官方没有把“是否携带 Secret”列为配额维度。 |

官方来源：[Authorization overview](https://developer.spotify.com/documentation/web-api/concepts/authorization)、[Authorization Code Flow](https://developer.spotify.com/documentation/web-api/tutorials/code-flow)、[Authorization Code with PKCE](https://developer.spotify.com/documentation/web-api/tutorials/code-pkce-flow)、[Rate Limits](https://developer.spotify.com/documentation/web-api/concepts/rate-limits)。

## Lyricify 到底使用哪种 Flow？

**待验证。** Lyricify 教程证明它要求输入 Secret，也证明随后会打开浏览器完成用户授权；但公开页面没有展示：

- `/authorize` 的参数；
- 是否存在 `code_challenge` / `code_verifier`；
- `/api/token` 的 `grant_type` 与请求头；
- token exchange 在桌面端还是 Lyricify 服务端完成；
- Client Secret 的实际存储位置与生命周期。

因此当前不能把“输入 Client ID + Secret”升级为“已证实使用 Authorization Code Flow”。这是一项 **Level C 未覆盖、需 Level A 网络/产品验证或厂商说明才能确认** 的事实。

## 429：Custom Client 有价值，但 Secret 不是配额

Lyricify 的 Custom Client 页面声称自定义后可避免公共 API Client 的 429；合理的产品解释是：用户从多人共享的 App 切换到自己的 App，隔离了请求负载。这个解释是根据 Spotify 配额模型作出的推论，不是 Lyricify 内部实现证据。

必须同时保留两个限制：

- Lyricify 自己的 [429 FAQ](https://docs.lyricify.app/en/lyricify-4/faq/error-429/) 明确承认 Custom Client 连续使用后仍可能出现“长 429”，并建议回退公共 Client、等待或创建新 Client；所以 Custom Client 不能保证消灭 429。
- Spotify [Rate Limits](https://developer.spotify.com/documentation/web-api/concepts/rate-limits) 要求读取 `Retry-After` 并降低请求速率；其配额描述围绕 App、请求量和 quota mode，不围绕 Client Secret。

结论：**Custom Client 可能隔离共享限流；Secret 本身不会增加额度，也不能替代退避、合并请求和轮询治理。**

## Premium、五用户与 403

Spotify 当前 [Quota Modes](https://developer.spotify.com/documentation/web-api/concepts/quota-modes) 规定：

- Development Mode App 的所有者必须为 Premium；
- 最多五名已认证用户；
- 每名用户必须加入 allowlist；
- 用户可能完成登录但未在 allowlist，此后 API 请求会返回 403。

这些是 Development Mode 边界，不是 Authorization Code Flow 或 Client Secret 独有的能力。Lyricify 的 Premium/五用户说明与该边界一致，但不应把它们描述成“Secret 模式的优势”。

## Redirect URI 与授权故障

- Lyricify 文档要求 `http://127.0.0.1:766/callback`，并明确 `http://localhost...`、`https://127.0.0.1...` 会触发 invalid redirect。
- Spotify [Redirect URI rules](https://developer.spotify.com/documentation/web-api/concepts/redirect_uri) 要求除 loopback 外使用 HTTPS；loopback 必须使用显式 `127.0.0.1` 或 `[::1]`，禁止 `localhost`，且请求 URI 必须匹配 allowlist。
- Spotify 当前规则页没有把 `lyricify://callback` 这类自定义 scheme 列为允许形式。此研究不据此断言 Lyricify 当前一定失败，但 Lyris 不采用该形式。
- Lyricify 的 [authorization no response FAQ](https://docs.lyricify.app/en/lyricify-4/faq/auth-no-response/) 仅给出网络排查；完整的取消、超时、state mismatch、access denied、invalid client 和安全回滚状态仍待 Level A 产品验证。

## 重新授权与 Refresh Token

Lyricify 文档要求配置 Custom Client 前先退出当前 Spotify 登录；非 Premium Custom Client FAQ 描述删除登录信息再授权，并称 `4.3.49+` 会自动删除相关登录信息。[v4.3.52 Release Notes](https://github.com/WXRIW/Lyricify-App/releases/tag/v4.3.52) 还写明已处理 Spotify Refresh Token 六个月强制过期。

Spotify 官方在 [refresh-token expiration announcement](https://developer.spotify.com/blog/2026-06-18-refresh-token-expiration) 中规定：Refresh Token 自原始授权起六个月后过期，刷新 Access Token 不延长期限；token endpoint 返回 `invalid_grant` 时应丢弃旧 Token、不要重试刷新，并重新走用户授权。Authorization Code 与 PKCE 都受此规则影响。

## Lyris 决策

- **默认 Local Companion**：不要求 Spotify ID、Secret 或 OAuth；只提供本机公开能力允许的识曲与控制。
- **推荐账户模式**：用户自己的 Custom Client + PKCE，只输入 Client ID；Token 进入 Keychain。
- **Secret 模式**：不得因为 Lyricify 要求 Secret 就默认启用。只有真实同账号对照证明某项必要功能 PKCE 无法完成，才可保留为隔离高级实验。
- **凭证边界**：若保留实验模式，Secret 只进 Keychain、默认隐藏、不进日志/配置/截图，不在 UI 状态长期持有；删除 Profile 或切换 PKCE 时清除。
- **不推荐共享**：Lyricify 教程允许借用朋友的 Client 信息，但 Lyris 不主动建议分享 Client Secret。需要多人测试时，应由 App 所有者管理 allowlist，并清楚说明五用户与 403 边界。
- **429 处理**：读取 `Retry-After`、暂停相关请求、合并/去重、降低轮询频率，并把 429 与 401、403、断网、无播放设备分开呈现。
