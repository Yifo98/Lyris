# macOS 本地 Now Playing / Spotify 控制方案

记录日期：2026-07-22。目标是让默认 **Local Companion** 模式不要求 Spotify OAuth、Client ID 或 Client Secret。

## 当前可验证的公开能力

本机 Spotify `1.2.94.583` 自带公开脚本字典：
`/Applications/Spotify.app/Contents/Resources/Spotify.sdef`。

| 能力 | 公开字典 | 本机验证 | 结论 |
| --- | --- | --- | --- |
| 曲名、艺人、专辑、Spotify URI、封面 URL、时长 | 有 | 已读取，输出时做隐私脱敏 | 可用于曲目识别与歌词匹配 |
| 播放/暂停/停止状态、当前位置 | 有 | 已读取 | 可作为原始播放快照 |
| 播放、暂停、切换播放状态 | 有 | 已执行 `paused → playing → paused` 并恢复原状态 | 可用于本机控制 |
| seek | `player position` 可写 | 已写回原位置并读回，未改变用户实际进度 | 可用于拖动进度条 |
| 上一首/下一首 | 有 | 未实机执行，避免擅自切歌 | 实现后需 Level A 验证 |
| shuffle/repeat | 可读写属性 | 尚未实机改变 | 实现后需 Level A 验证 |
| 收藏状态 | `starred` 只读且语义未由 Spotify 保证等同当前 Liked Songs | 未采用 | Local Companion 不展示可操作收藏 |
| 当前活跃设备的 Web API 控制 | 无 | 不适用 | 必须使用 OAuth 账户模式；设备列表/播放转移不在当前版本 |
| 音质 | 无 | 不适用 | 不伪造、不展示 |

Spotify 字典把 `duration` 描述为秒，但本机返回值表现为毫秒；适配器必须做范围校验与单位归一化，测试同时覆盖秒和毫秒输入。

## 推荐实现

采用公开 Apple Events / ScriptingBridge 适配器，不使用私有 MediaRemote：

1. `LocalSpotifyCompanion` 每 0.5–1 秒读取低频权威快照。
2. `PlaybackClock` 在快照间用单调时钟平滑外推；暂停立即冻结，seek 立即重建基线。
3. 曲目键优先使用公开 Spotify URI；缺失时使用规范化标题、艺人、专辑和时长指纹。
4. 本地模式只呈现已证实能力：曲目信息、歌词、翻译、进度、播放控制。
5. 收藏、远端设备和 Connect 在 UI 中明确锁定为“需要 Spotify 账户模式”，不显示失效按钮。

## 权限与发布边界

- 首次控制 Spotify 时 macOS 会请求 Automation 权限，`Info.plist` 必须提供清晰的 `NSAppleEventsUsageDescription`。
- Hardened Runtime 下需要 `com.apple.security.automation.apple-events` 才能提示用户授权。
- Mac App Store 要求 App Sandbox；向其他应用发送 Apple Events 还涉及 `scripting-targets` 或临时 Apple Events exception，必须单独做签名/商店验收，不能以 Debug 成功代替。
- 直接分发也应签名、最小化 entitlement，并在设置里提供“打开系统设置/重新检查权限”的修复路径。

官方参考：

- [Apple Events entitlement](https://developer.apple.com/documentation/BundleResources/Entitlements/com.apple.security.automation.apple-events)
- [App Sandbox](https://developer.apple.com/documentation/security/app-sandbox)
- [Sandboxing and Automation](https://developer.apple.com/library/archive/qa/qa1888/)

## 被拒绝方案

- 私有 `MediaRemote`、注入、Accessibility 抓 UI、读取 Spotify 缓存/数据库：稳定性、审核和隐私风险不可接受。
- 用 Web API 轮询冒充“免授权”：Web API 的用户播放数据本身需要 OAuth。
- 在本地模式展示灰色爱心但暗中失败：能力必须在界面上诚实降级。
