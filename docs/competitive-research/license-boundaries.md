# 许可证与 clean-room 边界

访问日期：2026-07-22。

| 来源 | 已确认许可证/权利状态 | Lyris 边界 |
| --- | --- | --- |
| LyricsX、MusicPlayer、LyricsKit | MPL-2.0 | 只借鉴公开行为与抽象思想；不复制、逐行翻译或轻改 covered files。若未来直接复用，必须单独履行 MPL 文件级源码义务。 |
| Lyricify Lyrics Helper | Apache-2.0 | 可研究其模型与格式事实；任何直接复用都要保留许可证/NOTICE、标注修改，并单独审查第三方服务条款。当前实现仍按 clean-room 自行编写。 |
| Lyricify 4 主程序、UI、文档和图片 | 没有据此确认的通用源码许可证 | 不复制 UI、图标、截图、文案或闭源内部行为；官方文档仅作为功能事实来源。 |
| 灵动歌词 | 黑盒产品 | 仅记录用户可见行为；不逆向、不抓包、不提取资源或算法。 |
| Atoll | GPL-3.0；部分实现注明来源于同为 GPL-3.0 的 Boring.Notch | 只借鉴公开行为、macOS API 组合与架构思想；不复制、逐行翻译或轻改窗口、形状、事件监听及媒体代码。 |
| 歌词与翻译内容 | 通常属于原权利人或服务条款约束范围 | 不把第三方歌词库、真实歌曲全文或竞品缓存随仓库分发；测试使用合成文本。 |
| Spotify | Developer Terms、Web API 文档和用户授权 | 只使用公开 API/公开 Apple Events；不使用 `sp_dc`、内部 color-lyrics/pathfinder、共享 Secret 或抓取 Web Player Token。 |

## clean-room 工作法

- 研究输出仅包含：行为规格、字段语义、公开格式、风险和黑盒测试。
- 实现者只依据本仓库规格、官方平台文档和自主设计的测试，不照搬第三方代码表达。
- 新模型使用 Lyris 自有命名：`LyricDocument`、`LyricLine`、`LyricToken`、`LyricTranslation`、`LyricProvenance` 等。
- 保留来源与采用决策记录，便于以后证明实现路径。

## 明确禁止

- 私有 `MediaRemote` 框架、第三方绕过 sandbox 的桥接方案。
- Spotify 会话 Cookie、内部歌词端点、外部 Secret 字典或任何盗用 Token 路径。
- 将“接口可访问”误写为“获得数据使用或再分发授权”。
- 把竞品外观做成近似复刻；新产品名称、Logo 和视觉语言必须独立设计并经用户确认。

来源：

- [LyricsX MPL-2.0](https://github.com/MxIris-LyricsX-Project/LyricsX/blob/e84963a6346b9a99dfdcaf082908f12247f1637b/LICENSE)
- [Lyricify Lyrics Helper Apache-2.0](https://github.com/WXRIW/Lyricify-Lyrics-Helper/blob/983709b2519f7c5ba32206424896533d14159c97/LICENSE)
- [Apple App Review Guidelines 2.5.1](https://developer.apple.com/app-store/review/guidelines/)
- [Spotify Developer Terms](https://developer.spotify.com/terms)
