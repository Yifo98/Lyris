# Lyricify 4 歌词来源优先级与翻译路由研究

验证日期：2026-08-17
研究范围：只读审阅 Lyricify 官方公开材料；未运行或反编译 Lyricify 4，也未修改 Lyris 生产代码、测试或配置。

## 结论先行

1. **Lyricify 4 主程序的 provider router 没有公开源码。** `WXRIW/Lyricify-App` 固定提交 `9b739669356efb78bb6d4426b7b905f1e83bd2c7` 只有产品文档、i18n、图片和发布资料；官方只声明“歌词处理相关代码”在 Apache-2.0 的 `Lyricify-Lyrics-Helper` 开源。因此，当前可以确认产品行为与 Helper 的单来源搜索算法，但不能还原 Lyricify 4 的跨来源 comparator、缓存、超时、取消或重试实现。[官方开源边界](https://github.com/WXRIW/Lyricify-App/blob/9b739669356efb78bb6d4426b7b905f1e83bd2c7/README.md#L55-L61)
2. **官方明确描述的产品路由是：** `Lyricify 服务器歌词库 -> 用户首选自动搜索来源 -> 备选自动搜索来源`。服务器有已收录歌词时会直接采用，即使该歌词原始来源不符合当前首选；若用户想强制换来源，需要在曲目管理里重新搜索并标记。[来源与获取流程](https://github.com/WXRIW/Lyricify-App/blob/9b739669356efb78bb6d4426b7b905f1e83bd2c7/docs/Lyricify%204/README.md#L123-L140)
3. **当前 UI 明确暴露四种来源偏好：**“QQ 音乐优先”“网易云音乐优先”“翻译优先且 QQ 音乐优先”“翻译优先且网易云音乐优先”。但公开材料只有 i18n 资源键，没有对应 enum、配置字段或排序函数；不能声称已经知道“翻译优先”的具体评分和降级顺序。[当前来源选项](https://github.com/WXRIW/Lyricify-App/blob/9b739669356efb78bb6d4426b7b905f1e83bd2c7/i18n/Lyricify%204/Language.zh-CN.xaml#L418-L429)
4. **Helper 的候选排序只发生在单个 provider 内。** 它会逐步放宽查询，按标题、艺人、专辑、专辑艺人和时长计算匹配等级，再降序返回最佳候选；这不是 QQ/网易/Musixmatch 之间的路由算法。[`Searcher`](https://github.com/WXRIW/Lyricify-Lyrics-Helper/blob/c14bba9b49037c305192d59cff1289d79347477b/Lyricify.Lyrics.Helper/Searchers/Searcher.cs#L19-L100)、[`CompareHelper`](https://github.com/WXRIW/Lyricify-Lyrics-Helper/blob/c14bba9b49037c305192d59cff1289d79347477b/Lyricify.Lyrics.Helper/Searchers/Helpers/CompareHelper.cs#L13-L73)
5. **Lyricify 的“翻译”主要是歌词来源随原文返回或词库中已有的逐行译文，不是公开证据中的运行时 AI 翻译。** QQ 和网易的公开 Helper 模型都包含翻译字段；官方曲目管理还允许人工对齐/补充翻译。[QQ 翻译字段](https://github.com/WXRIW/Lyricify-Lyrics-Helper/blob/c14bba9b49037c305192d59cff1289d79347477b/Lyricify.Lyrics.Helper/Providers/Web/QQMusic/Api.cs#L17-L23)、[网易翻译字段](https://github.com/WXRIW/Lyricify-Lyrics-Helper/blob/c14bba9b49037c305192d59cff1289d79347477b/Lyricify.Lyrics.Helper/Providers/Web/Netease/Response.cs#L80-L96)、[人工翻译流程](https://github.com/WXRIW/Lyricify-App/blob/9b739669356efb78bb6d4426b7b905f1e83bd2c7/docs/Lyricify%204/README.md#L239-L261)

## 证据等级与固定版本

| 等级 | 含义 | 本文证据 |
| --- | --- | --- |
| Level B | 可定位到固定提交的公开源码 | `Lyricify-Lyrics-Helper`：`c14bba9b49037c305192d59cff1289d79347477b`（2026-08-11） |
| Level C | 官方产品文档、配置样例或 i18n 资源；可证明产品声明/UI，但不能证明闭源内部实现 | `Lyricify-App`：`9b739669356efb78bb6d4426b7b905f1e83bd2c7`（2026-07-30） |
| 不可确认 | 官方公开材料没有对应实现 | Lyricify 4 跨 provider router、翻译优先 comparator、本地缓存与完整错误策略 |

本仓库已有的相关审阅也明确维持相同边界：[Lyricify 4 官方文档审阅](./lyricify-4-docs-review.md)、[Helper 固定提交源码审阅](./lyrics-helper-source-review.md)、[许可证边界](./license-notes.md)。

## 设置项：哪些只是显示，哪些会影响来源路由

| 用户可见含义 / 公开键 | 可确认的作用 | 是否影响 provider routing | 证据与边界 |
| --- | --- | --- | --- |
| `lyrics.translation` / “中文翻译” | 控制可用中文翻译是否显示 | **否，属于呈现开关** | 旧配置样例有 `translation`；当前 i18n 描述为“当中文翻译可用时将会被显示”。[配置 L7-L15](https://github.com/WXRIW/Lyricify-App/blob/9b739669356efb78bb6d4426b7b905f1e83bd2c7/docs/Lyricify%204/settings.json#L7-L15)、[i18n L403-L405](https://github.com/WXRIW/Lyricify-App/blob/9b739669356efb78bb6d4426b7b905f1e83bd2c7/i18n/Lyricify%204/Language.zh-CN.xaml#L403-L405) |
| `lyrics.romaji_option` / “翻译优先、罗马音优先、仅罗马音” | 决定译文与日语罗马音的显示组合/次序 | **否，不能当成来源优先级** | 这是 `Romaji` 下的独立 UI 组，与 `Source` 四态不是同一概念。[i18n L406-L411](https://github.com/WXRIW/Lyricify-App/blob/9b739669356efb78bb6d4426b7b905f1e83bd2c7/i18n/Lyricify%204/Language.zh-CN.xaml#L406-L411) |
| `lyrics.use_lyricify_server` | 是否使用 Lyricify 歌词库/服务器 | **会改变路由入口** | 旧配置样例可以确认键存在；公开源码未显示具体请求与失败策略。[配置 L10-L14](https://github.com/WXRIW/Lyricify-App/blob/9b739669356efb78bb6d4426b7b905f1e83bd2c7/docs/Lyricify%204/settings.json#L10-L14) |
| `lyrics.use_available_lyrics` | 服务器已有歌词时直接使用 | **会让服务器命中短路自动搜索** | 与官方流程“服务器命中即采用”一致，但当前版本是否仍沿用同名键不可确认。[配置 L11-L15](https://github.com/WXRIW/Lyricify-App/blob/9b739669356efb78bb6d4426b7b905f1e83bd2c7/docs/Lyricify%204/settings.json#L11-L15) |
| `lyrics.is_qq_first` | 旧版 QQ 优先布尔偏好 | **会影响首选自动搜索来源** | 旧样例只支持布尔 QQ/网易二选一；不能把它当成当前四态配置的完整模型。[配置 L11-L14](https://github.com/WXRIW/Lyricify-App/blob/9b739669356efb78bb6d4426b7b905f1e83bd2c7/docs/Lyricify%204/settings.json#L11-L14) |
| `Source.ComboBox.QQFirst` / `NeteaseFirst` | 当前 UI 的两种普通来源偏好 | **产品含义是首选来源** | 只公开了 i18n 资源键；实际 enum/value 未公开。[i18n L418-L423](https://github.com/WXRIW/Lyricify-App/blob/9b739669356efb78bb6d4426b7b905f1e83bd2c7/i18n/Lyricify%204/Language.zh-CN.xaml#L418-L423) |
| `Source.ComboBox.TranslationFirst.QQFirst` / `...NeteaseFirst` | 当前 UI 的“翻译优先 + 来源次序”四态中的两项 | **名称表明会影响候选/来源选择，但算法不可确认** | 未公开 backing config、enum、比较器、是否并发查询、无译文时的确切回退顺序。只能确认 UI 语义，不能反推实现。[同上](https://github.com/WXRIW/Lyricify-App/blob/9b739669356efb78bb6d4426b7b905f1e83bd2c7/i18n/Lyricify%204/Language.zh-CN.xaml#L418-L423) |
| `lyrics.enable_netease_yrc` / “网易云音乐逐字歌词” | 允许使用网易 YRC 逐字数据 | **属于来源能力开关，不等于来源排序** | 旧配置与当前 i18n 均可确认。[配置 L12-L15](https://github.com/WXRIW/Lyricify-App/blob/9b739669356efb78bb6d4426b7b905f1e83bd2c7/docs/Lyricify%204/settings.json#L12-L15)、[i18n L424-L425](https://github.com/WXRIW/Lyricify-App/blob/9b739669356efb78bb6d4426b7b905f1e83bd2c7/i18n/Lyricify%204/Language.zh-CN.xaml#L424-L425) |
| “启用 Musixmatch” / “Musixmatch 逐字歌词” | UI 明确把 Musixmatch 称为备用歌词来源，并可单独启用逐字数据 | **可能加入 fallback 链，但确切位置不可确认** | i18n 能证明产品选项；Helper enum/注册能证明有该 provider 能力；闭源 App 的调用顺序未公开。[i18n L426-L429](https://github.com/WXRIW/Lyricify-App/blob/9b739669356efb78bb6d4426b7b905f1e83bd2c7/i18n/Lyricify%204/Language.zh-CN.xaml#L426-L429) |

### 一个容易混淆的点

“罗马音 -> 翻译优先”是**显示层排序**；“来源 -> 翻译优先且 QQ/网易优先”才是**来源/候选层偏好**。两者使用不同的 i18n key，不能共用一个配置概念。

## 官方文档可确认的产品调用链

```text
Spotify 曲目身份
  -> 请求 Lyricify 服务器歌词库
     -> 命中：直接使用服务器记录
        （即使记录的原始来源不是当前首选）
     -> 未命中：进入自动搜索
        -> 先查用户首选来源（QQ 或网易）
        -> 未找到歌词时查备选来源
        -> UI 还可启用 Musixmatch 作为备用来源
  -> 用户发现错配/想强制换来源
     -> 曲目管理手动搜索、导入、应用并标记
     -> 正确歌词上传/标记到 Lyricify 服务器
     -> 后续服务器命中，跳过自动搜索
```

上述前两级顺序和服务器短路行为来自官方文档；Musixmatch 的精确插入位置、是否与 QQ/网易串行或并发、以及“翻译优先”如何参与选择均未公开。[获取流程](https://github.com/WXRIW/Lyricify-App/blob/9b739669356efb78bb6d4426b7b905f1e83bd2c7/docs/Lyricify%204/README.md#L130-L140)、[手动导入与标记](https://github.com/WXRIW/Lyricify-App/blob/9b739669356efb78bb6d4426b7b905f1e83bd2c7/docs/Lyricify%204/README.md#L142-L158)

### 为什么产品推荐 QQ 优先

官方给出的理由不是品牌偏好，而是歌词能力与数据质量：QQ 歌词通常能提供更真实的卡拉 OK/逐字体验和更精确时间轴；部分网易 LRC 不规范，可能在反序列化时失败。[官方说明](https://github.com/WXRIW/Lyricify-App/blob/9b739669356efb78bb6d4426b7b905f1e83bd2c7/docs/Lyricify%204/README.md#L123-L129)

这只能解释默认/推荐偏好，不能证明内部把 `QQ` 写成固定最高分。用户仍可选择网易优先，当前 UI 还把“是否要求翻译”与“同层来源偏好”组合成四态。

## Helper 可确认的源码调用链

Helper 固定提交 `c14bba...` 提供 provider/searcher 基础设施，但不是 Lyricify 4 App 的完整 orchestrator：

1. [`Searchers` enum](https://github.com/WXRIW/Lyricify-Lyrics-Helper/blob/c14bba9b49037c305192d59cff1289d79347477b/Lyricify.Lyrics.Helper/Searchers/Searchers.cs#L6-L16) 枚举 `QQMusic`、`Netease`、`Kugou`、`Musixmatch`、`SodaMusic`、`AppleMusic`、`Spotify`、`LRCLIB`。
2. [`SearcherHelper`](https://github.com/WXRIW/Lyricify-Lyrics-Helper/blob/c14bba9b49037c305192d59cff1289d79347477b/Lyricify.Lyrics.Helper/Searchers/SearcherHelper.cs#L6-L38) 为每个 searcher 创建懒加载单例；[`SearchersHelper`](https://github.com/WXRIW/Lyricify-Lyrics-Helper/blob/c14bba9b49037c305192d59cff1289d79347477b/Lyricify.Lyrics.Helper/Searchers/SearchersHelper.cs#L14-L68) 负责 enum 与实例的双向映射。
3. [`Providers.Web.Providers`](https://github.com/WXRIW/Lyricify-Lyrics-Helper/blob/c14bba9b49037c305192d59cff1289d79347477b/Lyricify.Lyrics.Helper/Providers/Web/Providers.cs#L3-L35) 懒加载 QQ、网易、Musixmatch 等 API wrapper。
4. 单个 provider 的 `Searcher` 先查询“标题 + 艺人 + 专辑”；无结果或要求完整搜索时放宽为“标题 + 艺人”，再放宽为“标题”，同时去掉 `feat.` 片段。[`Searcher.cs`](https://github.com/WXRIW/Lyricify-Lyrics-Helper/blob/c14bba9b49037c305192d59cff1289d79347477b/Lyricify.Lyrics.Helper/Searchers/Searcher.cs#L57-L100)
5. 每个候选用 `CompareHelper.CompareTrack` 评分，再按 `MatchType` 降序；调用者还可以设置最低匹配等级，不够则返回 `null`。[最佳候选与阈值](https://github.com/WXRIW/Lyricify-Lyrics-Helper/blob/c14bba9b49037c305192d59cff1289d79347477b/Lyricify.Lyrics.Helper/Searchers/Searcher.cs#L19-L50)

这里的 enum 声明次序与 singleton 声明次序**都不是 provider 优先级**；公开 Helper 没有默认的跨来源排序数组或四态来源策略。

## 候选获取、匹配与单来源回退

### 查询降级

`Searcher` 的降级发生在一个 provider 内：

- 第一轮：标题 + 艺人 + 专辑；
- 第二轮：标题 + 艺人；
- 第三轮：标题；
- 标题会去掉 `(feat.` / ` - feat.` 后缀；
- 最终合并候选、评分、降序排序。

### 匹配模型

[`CompareHelper`](https://github.com/WXRIW/Lyricify-Lyrics-Helper/blob/c14bba9b49037c305192d59cff1289d79347477b/Lyricify.Lyrics.Helper/Searchers/Helpers/CompareHelper.cs#L24-L73) 比较：

- 标题：权重 1.0；
- 艺人：权重 1.0；
- 专辑：权重 0.4；
- 专辑艺人：权重 0.2；
- 时长：权重 1.0；
- 缺失专辑/专辑艺人/时长时按比例调整总分；
- 最终映射为 `Perfect`、`VeryHigh`、`High`、`PrettyHigh`、`Medium`、`Low`、`VeryLow`、`NoMatch` 八档。

名称匹配会做简繁/大小写/标点等归一，并处理 `feat`、版本字样与模糊相似度；艺人匹配比较规范化后的集合；时长差按 0/300/700/1500/3500 ms 分档。[`NameMatch`](https://github.com/WXRIW/Lyricify-Lyrics-Helper/blob/c14bba9b49037c305192d59cff1289d79347477b/Lyricify.Lyrics.Helper/Searchers/Helpers/MatchHelpers/NameMatch.cs)、[`ArtistMatch`](https://github.com/WXRIW/Lyricify-Lyrics-Helper/blob/c14bba9b49037c305192d59cff1289d79347477b/Lyricify.Lyrics.Helper/Searchers/Helpers/MatchHelpers/ArtistMatch.cs)、[`DurationMatch`](https://github.com/WXRIW/Lyricify-Lyrics-Helper/blob/c14bba9b49037c305192d59cff1289d79347477b/Lyricify.Lyrics.Helper/Searchers/Helpers/MatchHelpers/DurationMatch.cs#L11-L23)

**重要边界：** 上述匹配分不包含“是否有翻译”“来自 QQ 还是网易”或“逐字质量”这几个维度。因而它不能解释当前 UI 的“翻译优先”四态；那部分一定在未公开的调用层，或由未公开的新版逻辑完成。

## 翻译数据如何进入候选

### QQ 音乐

- QQ API XML 映射显式区分原文 `orig`、译文 `ts`、罗马音 `roma`。[`Api.cs` L17-L23](https://github.com/WXRIW/Lyricify-Lyrics-Helper/blob/c14bba9b49037c305192d59cff1289d79347477b/Lyricify.Lyrics.Helper/Providers/Web/QQMusic/Api.cs#L17-L23)
- `GetLyricsAsync` 把原文写入 `Lyrics`、译文写入 `Trans`；两者都为空才返回 `null`。[`Api.cs` L264-L353](https://github.com/WXRIW/Lyricify-Lyrics-Helper/blob/c14bba9b49037c305192d59cff1289d79347477b/Lyricify.Lyrics.Helper/Providers/Web/QQMusic/Api.cs#L264-L353)
- 另一歌词响应模型同样暴露 `Lyric` 与 `Trans` 并做 Base64 解码。[`Response.cs` L283-L304](https://github.com/WXRIW/Lyricify-Lyrics-Helper/blob/c14bba9b49037c305192d59cff1289d79347477b/Lyricify.Lyrics.Helper/Providers/Web/QQMusic/Response.cs#L283-L304)

### 网易云音乐

- 旧/新歌词接口请求原文、翻译、罗马音、逐字及逐字翻译字段。[`Api.cs` L189-L244](https://github.com/WXRIW/Lyricify-Lyrics-Helper/blob/c14bba9b49037c305192d59cff1289d79347477b/Lyricify.Lyrics.Helper/Providers/Web/Netease/Api.cs#L189-L244)
- 响应模型暴露 `Lrc`、`Tlyric`、`Romalrc`、`Yrc`、`Ytlrc`、`Yromalrc`，并区分无歌词/未收录标志。[`Response.cs` L80-L113](https://github.com/WXRIW/Lyricify-Lyrics-Helper/blob/c14bba9b49037c305192d59cff1289d79347477b/Lyricify.Lyrics.Helper/Providers/Web/Netease/Response.cs#L80-L113)

因此可以确认“是否有译文”是 provider 返回结果中可观察的能力；但公开源码没有展示 Lyricify 4 如何把该能力插入跨来源排序。

## 回退、缓存与错误处理

### 可确认

- **跨来源产品回退：** 首选 QQ/网易未找到歌词后查备选来源；服务器命中会先短路。[官方流程](https://github.com/WXRIW/Lyricify-App/blob/9b739669356efb78bb6d4426b7b905f1e83bd2c7/docs/Lyricify%204/README.md#L130-L140)
- **单来源查询回退：** Helper 逐步放宽搜索字符串。
- **网易端点回退：** `NeteaseSearcher` 会在旧/新搜索端点间切换；异常或 `code == -460` 会尝试另一端点，并记忆下次优先端点。[`NeteaseSearcher`](https://github.com/WXRIW/Lyricify-Lyrics-Helper/blob/c14bba9b49037c305192d59cff1289d79347477b/Lyricify.Lyrics.Helper/Searchers/NeteaseSearcher.cs#L13-L68)
- **QQ 搜索错误：** `QQMusicSearcher` 捕获异常并返回 `null`，由上层把它当成无结果/失败继续处理。[`QQMusicSearcher`](https://github.com/WXRIW/Lyricify-Lyrics-Helper/blob/c14bba9b49037c305192d59cff1289d79347477b/Lyricify.Lyrics.Helper/Searchers/QQMusicSearcher.cs#L13-L40)
- **产品错误文案：** UI 分开表达无歌词、加载错误与纯音乐；服务器上传还区分网络、空歌词、已存在、锁定、拒绝和服务端异常。[错误状态资源](https://github.com/WXRIW/Lyricify-App/blob/9b739669356efb78bb6d4426b7b905f1e83bd2c7/i18n/Lyricify%204/Language.zh-CN.xaml#L1476-L1515)
- **远程复用层：** 用户标记正确歌词后上传到 Lyricify 服务器；后续服务器直接返回，跳过厂商声称约 0.5–2 秒的自动搜索。[标记收益](https://github.com/WXRIW/Lyricify-App/blob/9b739669356efb78bb6d4426b7b905f1e83bd2c7/docs/Lyricify%204/README.md#L136-L140)

### 不可确认

公开材料没有足够证据确认：

- 本地歌词结果缓存的 key、TTL、LRU、负缓存与持久化；
- 多 provider 是串行、并行还是竞速；
- provider 超时、重试次数、指数退避、熔断或速率限制；
- 请求取消、快速切歌的旧会话隔离；
- “翻译优先”在服务器命中、首选 provider 无译文、备选 provider 有译文时的确切决策；
- Musixmatch 在 QQ/网易之后还是只在特定数据能力缺失时调用；
- 解析失败是否计为“该来源未找到”，以及错误是否对用户保留来源信息。

这里的“Lyricify 服务器歌词库”是**远程已验证/已标记歌词层**，不能写成本地缓存。Helper 的 singleton 也只是对象复用，不是歌词结果缓存。

另外，Helper 中 [`QQMusicProviderResult`](https://github.com/WXRIW/Lyricify-Lyrics-Helper/blob/c14bba9b49037c305192d59cff1289d79347477b/Lyricify.Lyrics.Helper/Providers/QQMusicProviderResult.cs#L5-L10) 与 [`NeteaseProviderResult`](https://github.com/WXRIW/Lyricify-Lyrics-Helper/blob/c14bba9b49037c305192d59cff1289d79347477b/Lyricify.Lyrics.Helper/Providers/NeteaseProviderResult.cs#L5-L10) 的关键属性仍抛 `NotImplementedException`，进一步说明不能把 Helper 当成 Lyricify 4 的生产 router 实现。

## “翻译优先”的最小可确认语义与证据缺口

当前只能确认它是一个与 QQ/网易偏好组合的来源选择维度。以下具体问题均没有公开答案：

| 问题 | 状态 |
| --- | --- |
| 是否先查两个来源，再优先选带翻译候选 | 不可确认 |
| 是否先查首选来源；没有翻译就改查另一来源 | 不可确认 |
| 另一来源匹配置信度较低但有翻译时是否胜出 | 不可确认 |
| 两边都有翻译时是否再按 QQ/网易偏好决定 | UI 名称暗示如此，但 comparator 未公开 |
| 两边都无翻译时是否退回普通来源优先 | 不可确认 |
| Lyricify 服务器已有无翻译记录时是否仍短路 | 官方一般流程说服务器命中直接使用，但未单独说明翻译优先例外 |

所以，在 Lyris 中不能把这个选项照抄成一个不透明布尔值。更稳妥的 clean-room 产品模型是把两条轴分开表达：

- **硬需求/能力轴：** 是否必须有译文、逐字、罗马音；缺失时是否允许降级；
- **来源偏好轴：** QQ/网易/其他许可来源的先后；
- **匹配质量轴：** 曲名、艺人、专辑、时长与版本冲突；
- **数据有效性轴：** 能否解析、时间轴是否合理、译文是否能与原文对齐；
- **存储轴：** 用户手工歌词 > 本地已验证缓存 > 网络候选；每一层都应有来源署名和版本指纹。

这是根据公开行为推导的 Lyris 设计建议，**不是**对 Lyricify 4 闭源代码的描述。

## 对 Lyris 的安全取舍

可以借鉴：

- 把“是否要翻译”与“来源偏好”拆成正交策略，而不是只做 `qqFirst`；
- 先验证曲目身份与匹配置信度，再比较候选能力；
- 明确区分“无歌词”“来源失败”“解析失败”“无翻译”“纯音乐”；
- 对用户手工歌词和已验证缓存提供最高优先级，并保留来源/修改记录；
- 无逐字或无翻译时做用户可配置的可解释降级。

不能直接采用：

- Lyricify 4 闭源主程序的 UI、配置结构或未公开路由；
- Helper 中的私有/非公开第三方接口、Cookie、解密流程或常量；
- QQ/网易/Musixmatch 歌词内容或数据库数据，除非另行确认服务条款与授权；
- 把 Apache-2.0 Helper 的开源许可误解为第三方歌词和 API 使用许可。

[`Lyricify-Lyrics-Helper` 的 Apache-2.0 许可证](https://github.com/WXRIW/Lyricify-Lyrics-Helper/blob/c14bba9b49037c305192d59cff1289d79347477b/LICENSE#L1-L5) 只覆盖 Helper 代码；Lyris 当前仍应维持 clean-room：研究行为与数据模型，自行设计 Swift 接口、路由、权重和测试，不复制代码、注释、常量、资源或产品文案。

## 最终证据缺口清单

| 想确认的实现事实 | 公开材料状态 | 结论 |
| --- | --- | --- |
| Lyricify 4 主程序源码类、DI 容器、路由服务注册 | 主程序未开源 | 不可确认 |
| 当前四态来源偏好的 enum/config key | 只有 i18n key；旧样例只有 `is_qq_first` | 不可确认 |
| 翻译优先 comparator 与 tie-break | 无源码/文档算法 | 不可确认 |
| QQ/网易/Musixmatch 完整调用顺序 | 只确认 QQ/网易首选/备选与 Musixmatch “备用”UI | 部分确认 |
| 单 provider 候选查询与匹配排序 | Helper 固定源码完整可见 | 可确认 |
| provider 返回的翻译/罗马音/逐字字段 | Helper 固定源码可见 | 可确认 |
| 服务器词库短路与人工标记复用 | 官方文档明确 | 可确认 |
| 本地缓存、取消、并发、超时、退避、旧结果隔离 | 无主程序源码 | 不可确认 |
| 产品级无歌词/错误/纯音乐文案状态 | i18n 可见 | 可确认 UI；状态机不可确认 |
