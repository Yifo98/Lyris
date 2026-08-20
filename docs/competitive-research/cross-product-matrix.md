# 跨产品能力矩阵

访问/测试日期：2026-07-22。

| 能力 | 灵动歌词 | LyricsX | Lyricify 4 / Helper | Lyris 决策 |
| --- | --- | --- | --- | --- |
| 无 Spotify OAuth 的本机识曲 | 当前已授权环境无法证明 | 固定源码显示公开 Apple Events adapter | Windows 文档有 SMTC，但账号授权仍是主路径 | **采用**公开 Spotify Apple Events，设为默认 Local Companion |
| 远端设备/Connect | 当前已授权 UI 有相关检查 | 非本次研究重点 | 官方文档描述账号设备播放 | **采用**PKCE 账户模式，Local 模式锁定 |
| 收藏 | UI 有入口，未实测 | `starred` 不足以证明现代 Liked Songs | 账号模式可合理支持，但内部未公开 | 只在账户模式使用正式 library endpoint |
| 播放时钟 | 可见同步歌词，内部未知 | 统一播放器抽象可参考 | 本机 Media Session 用于更及时校正 | 自有 `PlaybackClock` + 权威快照校准 |
| 多来源歌词 | UI 有搜索/缓存，来源未知 | 本地优先 + provider 搜索 | Helper 有多格式/parser/searcher | 自有 `LyricsPipeline`，来源可追踪 |
| 逐字/背景/翻译 | 当前 UI 可显示双语 | 附件模型支持翻译与逐字 | Helper 模型更丰富 | v0.2 先稳定行级；模型预留 token/background/translation |
| 手动歌词 | 设置文案区分手动上传与自动缓存 | 支持本地文件优先 | Helper 有 parser/generator | 手动来源最高优先级，可编辑、可删除、带版本 |
| Client Secret | 黑盒未知 | 本机 Spotify 不需要 | 教程要求桌面输入 Secret | 默认拒绝；只保留隔离的高级实验，不作为推荐路径 |
| 私有/非官方接口 | 不检查内部实现 | SystemMedia 有私有 API 路径 | Helper 有 Cookie/内部端点路径 | 全部拒绝 |
| UI 外观 | 黑盒观察 | 开源但受版权/品牌约束 | 闭源主程序 | 不复制；保留 Lyris 自有胶囊设计 |

证据级别：灵动歌词列主要为 A；LyricsX/Helper 为固定提交 B；Lyricify 4 行为为官方文档 C。未知项不做内部实现推断。
