# Lyris 竞品与来源研究

本目录记录可复核的产品行为、公开源码结构、官方平台约束和采用决策。它不是素材仓库，也不授权复制竞品 UI、品牌、歌词数据或非公开接口。

## 证据分级

- **A — 实机行为**：在本机实际运行、操作或读取公开应用字典得到。
- **B — 固定提交源码**：引用具体仓库、提交和文件位置；只证明该版本代码。
- **C — 官方文档**：平台方或项目方发布的正式文档。
- **D — 推断/待验证**：由现象推导，不能写成既定事实。

研究结论必须同时标注证据级别和访问日期。登录、付费、撤销授权、填写 Secret 等会改变用户状态的动作，必须停下来交给用户完成或获得明确授权。

## 目录

- `dynamic-lyrics/`：灵动歌词黑盒体验，不逆向、不抓包、不绕过授权。
- `lyricsx/`：LyricsX / MusicPlayer / LyricsKit 的固定提交源码审阅。
- `lyricify/`：Lyricify 4 官方文档与 Lyricify Lyrics Helper 源码审阅。
- `atoll-implementation-notes.md`：Atoll 顶部窗口、刘海形变、交互状态机和 GPL 边界审阅。
- `atoll-runtime-and-windows-reference-2026-08-17.md`：清理后的 Atoll 实机状态、录屏限制与 Windows/Lyricify 综合取舍。
- `cross-product-matrix.md`：跨产品能力和证据对照。
- `adoption-decisions.md`：Lyris 采用、拒绝与暂缓决策。
- `evidence-policy.md`：如何记录证据和不确定性。
- `license-boundaries.md`：许可证、clean-room 和内容权利边界。

二进制截图与录屏默认保留在项目 `.build/research/` 且由 `.gitignore` 排除；文档只提交不含账号、曲目历史或凭证的文字结论。
