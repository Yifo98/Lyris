# Lyris 采用决策

## 立即采用

1. **默认 Local Companion**：公开 Spotify Apple Events 获取曲目/状态/进度并控制本机播放；不要求账号、ID 或 Secret。
2. **能力驱动 UI**：收藏、远端设备、Connect 只在账户模式出现；不可用时显示原因和升级入口，不留假按钮。
3. **Custom Client + PKCE**：桌面推荐账户模式，只需要 Client ID；Token 进入 Keychain。
4. **独立播放时钟**：低频权威快照 + 单调时钟外推 + seek/暂停/恢复明确状态机。
5. **来源可追踪歌词模型**：手动优先，缓存含完整 fingerprint，provider 结果经过规范化和版本冲突检查。
6. **generation/cancellation**：切歌、语言、Provider、Model、Thinking 任一变化都取消旧工作；旧结果不能写 UI/缓存/计数。
7. **透明权限与故障状态**：Automation、Spotify OAuth、Premium/allowlist/六个月重授权分别说明。

## 实验后再决定

- Client ID + Secret：仅当真实对照证明 PKCE 无法完成某项必要能力，才保留高级模式；否则删除。
- 逐字歌词、背景人声、发音：数据模型预留，v0.2 不以牺牲行级稳定性换取复杂渲染。
- Mac App Store：Automation entitlement 与 sandbox 验收通过前，只能承诺 Developer ID 直接分发路径。

## 明确拒绝

- 私有 MediaRemote、UI 抓取、读取 Spotify 数据库/缓存、会话 Cookie、内部歌词 API、共享 Client Secret。
- 复制灵动歌词/LyricsX/Lyricify 的 UI、品牌、文案、截图或源码表达。
- 把未授权、429、403、断网统一显示成“未收藏”或“无歌词”。
- 把真实歌词、账号信息、Token、API Key、Client ID 或研究截图提交到公开 Git。
