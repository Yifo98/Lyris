# Lyricify App：macOS 上游贡献可行性研究

> 访问日期：2026-08-17（Asia/Shanghai）
> 主仓库固定提交：[`9b739669356efb78bb6d4426b7b905f1e83bd2c7`](https://github.com/WXRIW/Lyricify-App/tree/9b739669356efb78bb6d4426b7b905f1e83bd2c7)（`main` 当次读取的最新提交，2026-07-30）。
> Helper 固定提交：[`c14bba9b49037c305192d59cff1289d79347477b`](https://github.com/WXRIW/Lyricify-Lyrics-Helper/tree/c14bba9b49037c305192d59cff1289d79347477b)（`master` 当次读取的最新提交，2026-08-11）。
> 证据标记：**B** = 固定提交源码/仓库树；**C** = 项目方在固定提交中的文档或声明；**D** = 基于前述证据的工程推断。

## 结论先行

**不能把 `WXRIW/Lyricify-App` 当成 Lyricify 4 源码直接改写为 macOS 客户端。** 当前仓库是发布、文档、i18n 和资产仓库；固定提交的完整树没有 `.sln`、`.csproj`、`.cs` 或应用源码目录。仓库中的 XAML 是语言/主题资源，不是可构建的 WPF 应用。作者也在 issue #387 明确回复 Lyricify app 闭源、公开仓库没有应用源码。当前仓库没有 macOS 应用构建目标、许可证或既定代码贡献边界，因此不能假定直接增加一套客户端源码的 PR 会被接收。

可行且值得与作者讨论的路线是：以 **Lyris 的原生 SwiftUI/AppKit 壳**继续验证高质量 macOS 体验；`Lyricify-Lyrics-Helper` 可按 Apache-2.0 条款独立评估，不需要把闭源主程序当作前提。若目标是“同步并入 Lyricify”，则必须先由作者决定目标产品、技术栈、代码托管位置、许可证、品牌和词库接入授权；在这些条件未明确前，不应提交功能 PR 或使用 Lyricify 品牌/词库。

| 判断 | 结论 | 证据 |
| --- | --- | --- |
| Lyricify 4 是否开源 | 否；当前公开仓库没有 Windows 客户端实现源码，作者也明确称 app closed source。 | **B/C** [固定树](https://github.com/WXRIW/Lyricify-App/tree/9b739669356efb78bb6d4426b7b905f1e83bd2c7)、[作者回复 issue #387](https://github.com/WXRIW/Lyricify-App/issues/387#issuecomment-2306039383)。 |
| Windows 技术栈能否从源码审计 | 不能完整审计；文档可确认 Windows `.NET Desktop Runtime 6.0`、WPF 与 Edge WebView2，但不能核定项目边界或内部实现。 | **C** [运行时要求](https://github.com/WXRIW/Lyricify-App/blob/9b739669356efb78bb6d4426b7b905f1e83bd2c7/docs/Lyricify%204/README.md#L46-L50)、[WPF 说明](https://github.com/WXRIW/Lyricify-App/blob/9b739669356efb78bb6d4426b7b905f1e83bd2c7/docs/Lyricify%204/README.md#L669-L675)。 |
| 有无跨平台可复用代码 | 有，单独仓库 `Lyricify-Lyrics-Helper`；但它是 .NET 库，不是 macOS UI 或播放层。 | **B** [csproj：`netstandard2.1`](https://github.com/WXRIW/Lyricify-Lyrics-Helper/blob/c14bba9b49037c305192d59cff1289d79347477b/Lyricify.Lyrics.Helper/Lyricify.Lyrics.Helper.csproj#L1-L37)。 |
| 最优 macOS 路线 | 原生 SwiftUI/AppKit + 可移植歌词域模型/解析层；不是把 Windows 客户端套 Wine，也不是先迁移到跨平台 UI。 | **D**，基于无客户端源码、Lyris 的原生目标及下文平台约束。 |
| 是否应先联系作者 | 必须。特别是 app 源码、目标产品（Lyricify 4 还是 Mobile 2）、商标/名称、Lyricify 词库、商业/商店权益和上游接收方式。 | **C/B** [作者的 macOS 路线回复](https://github.com/WXRIW/Lyricify-App/issues/404#issuecomment-2423836010)、[用户协议知识产权条款](https://github.com/WXRIW/Lyricify-App/blob/9b739669356efb78bb6d4426b7b905f1e83bd2c7/docs/Lyricify%204/UserAgreement.txt#L59-L60)、[开发者文档](https://github.com/WXRIW/Lyricify-App/blob/9b739669356efb78bb6d4426b7b905f1e83bd2c7/docs/Developer/README.md#L1-L33)。 |

## 1. 主仓库的实际边界

### 1.1 是“发布/文档壳”，不是 Lyricify 4 源码库

- 固定树含 `README.md`、`docs/`、`i18n/`、图片、主题 XAML 和图标；不含应用项目文件或 C# 实现源码。主题与语言 XAML 仅能证明资源格式，不能组成可构建应用。**B** [完整固定树](https://github.com/WXRIW/Lyricify-App/tree/9b739669356efb78bb6d4426b7b905f1e83bd2c7)。
- GitHub Release 自动显示的 `Source code (zip/tar.gz)` 只是对应 tag 的仓库快照；`v4.3.52` 的 tag 树同样没有 `.sln`、`.csproj` 或 `.cs`，不能把自动生成的源码包误认为 Lyricify 4 客户端源码。**B** [v4.3.52 tag](https://github.com/WXRIW/Lyricify-App/tree/625f0ec3d2353310282279eb50a080a29b1c5d28)。
- 作者已直接说明 Lyricify app 闭源，公开的只有 Lyrics Helper。**C** [issue #387](https://github.com/WXRIW/Lyricify-App/issues/387#issuecomment-2306039383)。
- 项目 README 把 Lyricify 4 标为 Windows，并将当前版本链接到 Release；这证明公开交付的是发行物，而不是源项目。**C** [产品表](https://github.com/WXRIW/Lyricify-App/blob/9b739669356efb78bb6d4426b7b905f1e83bd2c7/README.md#L9-L14)。
- 文档明确要求 Windows 版 `.NET Desktop Runtime 6.0`；并在 Apple Music 歌词性能说明中直接提到 WPF。因而可确认 Windows UI 至少使用 WPF；但缺少 `.csproj` 和源码，仍无法核定其项目拆分、控件库、渲染策略或全部宿主技术。**C** [运行要求](https://github.com/WXRIW/Lyricify-App/blob/9b739669356efb78bb6d4426b7b905f1e83bd2c7/docs/Lyricify%204/README.md#L46-L50)、[WPF 性能说明](https://github.com/WXRIW/Lyricify-App/blob/9b739669356efb78bb6d4426b7b905f1e83bd2c7/docs/Lyricify%204/README.md#L669-L675)。
- README 对 macOS 给出的支持路线是 Windows on ARM 虚拟机或 CrossOver/Wine，而非原生客户端；这也不能替代源代码许可。**C** [macOS 说明](https://github.com/WXRIW/Lyricify-App/blob/9b739669356efb78bb6d4426b7b905f1e83bd2c7/README.md#L18-L23)。

### 1.2 可以从文档提取的产品能力，而非实现

Lyricify 4 面向 Spotify，文档列出歌词展示、逐字/逐行格式、翻译、动态歌词岛、桌面歌词、控制与音量等能力；这些是产品需求或可观察行为，不是可复制的源代码/UI 资产。**C** [README 的产品与创作说明](https://github.com/WXRIW/Lyricify-App/blob/9b739669356efb78bb6d4426b7b905f1e83bd2c7/README.md#L73-L119)、[Premium 功能](https://github.com/WXRIW/Lyricify-App/blob/9b739669356efb78bb6d4426b7b905f1e83bd2c7/docs/Lyricify%204/README.md#L56-L62)。

Lyricify 把“Dynamic Lyrics Island”“Magic Strip”等带 `*` 的创作声明为 CC BY-SA 4.0，并要求署名与相同方式许可；该声明**不等于**给予未公开 Windows 源码、Lyricify 商标、服务或歌词数据的许可。**C** [创作声明原文](https://github.com/WXRIW/Lyricify-App/blob/9b739669356efb78bb6d4426b7b905f1e83bd2c7/README.md#L101-L119)。若要采用相关视觉表达，仍应先让作者书面确认具体授权对象、署名方式和衍生作品范围。**D**

## 2. Windows 专属边界与可复用核心

### 2.1 Windows 专属部分：无法迁移，只能重写

由于客户端源码没有公开，不能列出全部实际调用的 Windows API 或建立完整调用图。项目文档仍明确给出了这些 Windows 专属边界：

- Windows Desktop Runtime 6.0 的运行前提。**C** [指南](https://github.com/WXRIW/Lyricify-App/blob/9b739669356efb78bb6d4426b7b905f1e83bd2c7/docs/Lyricify%204/README.md#L46-L50)。
- WPF 是其文档直接点名的桌面 UI 技术；在 macOS 上不能直接复用。**C** [性能说明](https://github.com/WXRIW/Lyricify-App/blob/9b739669356efb78bb6d4426b7b905f1e83bd2c7/docs/Lyricify%204/README.md#L669-L675)。
- 内嵌 Spotify 播放依赖 Microsoft Edge WebView2；macOS 必须改用 `WKWebView` 或放弃内嵌播放，不能迁移该宿主。**C/D** [内嵌播放说明](https://github.com/WXRIW/Lyricify-App/blob/9b739669356efb78bb6d4426b7b905f1e83bd2c7/docs/Lyricify%204/README.md#L354-L363)。
- 文档说明 Media Session 连接会影响播放信息与控制；它在 Windows 端的实际 API 封装未公开，macOS 仍须重写相应集成。**C/D** [Media Session 说明](https://github.com/WXRIW/Lyricify-App/blob/9b739669356efb78bb6d4426b7b905f1e83bd2c7/docs/Lyricify%204/README.md#L560-L565)。
- Lyricify Lite 文档把全播放器控制建立在 SMTC（System Media Transport Controls）上；SMTC 是 Windows 平台契约，不能直接用于 macOS。此条是 Lite 的明确描述，不能外推为 Lyricify 4 内部实现。**C** [README 的 Lite 说明](https://github.com/WXRIW/Lyricify-App/blob/9b739669356efb78bb6d4426b7b905f1e83bd2c7/README.md#L121-L124)。
- macOS 版本必须独立实现：Spotify 的授权/播放、macOS 媒体会话、AppKit 窗口层级与命中测试、刘海显示几何、状态栏和安全存储。**D**

### 2.2 独立 Helper 是唯一明确的可复用实现资产

主 README 明确把“歌词处理相关代码”指向 `WXRIW/Lyricify-Lyrics-Helper` 并标为 Apache-2.0。**C** [主 README](https://github.com/WXRIW/Lyricify-App/blob/9b739669356efb78bb6d4426b7b905f1e83bd2c7/README.md#L55-L61)。该库本身包含 Apache-2.0 `LICENSE`，目标为 `netstandard2.1`，并列出解析、生成、搜索、优化、KRC/QRC 解密等模块。**B** [许可证](https://github.com/WXRIW/Lyricify-Lyrics-Helper/blob/c14bba9b49037c305192d59cff1289d79347477b/LICENSE)、[项目文件](https://github.com/WXRIW/Lyricify-Lyrics-Helper/blob/c14bba9b49037c305192d59cff1289d79347477b/Lyricify.Lyrics.Helper/Lyricify.Lyrics.Helper.csproj#L1-L37)、[结构说明](https://github.com/WXRIW/Lyricify-Lyrics-Helper/blob/c14bba9b49037c305192d59cff1289d79347477b/README.md#L5-L56)。

可复用性分级：

| 层 | 结论 | 原因与处理建议 |
| --- | --- | --- |
| 纯歌词模型、格式解析/生成、偏移与降级 | **高（.NET 客户端）/中（Swift 客户端）** | `netstandard2.1` 表明 .NET 跨平台可引用；Swift 不能原生链接 C#，应在 Swift 中基于公开格式重写，或以独立 .NET 进程/FFI 集成（后者增加安装、IPC、启动与签名复杂度）。**B/D** [csproj](https://github.com/WXRIW/Lyricify-Lyrics-Helper/blob/c14bba9b49037c305192d59cff1289d79347477b/Lyricify.Lyrics.Helper/Lyricify.Lyrics.Helper.csproj#L1-L37)。 |
| 网络 provider/searcher | **低到中** | Helper 包含多个第三方音乐服务 Provider；其 `BaseApi` 固定了伪装 Windows 浏览器 UA 与特定 Cookie。即使 Apache-2.0，这些网络接口仍可能是未公开/易变服务边界，不能作为生产可靠性或授权依据。**B/D** [Provider 基类](https://github.com/WXRIW/Lyricify-Lyrics-Helper/blob/c14bba9b49037c305192d59cff1289d79347477b/Lyricify.Lyrics.Helper/Providers/Web/BaseApi.cs#L1-L109)。 |
| UI、播放、账号、词库服务 | **无** | 主仓库未给出其实现，不能复用。 |

## 3. macOS 技术路线比较

| 路线 | 可行性 | 与现有公开资产的关系 | 建议 |
| --- | --- | --- | --- |
| 原生 SwiftUI/AppKit + Swift 领域层 | **高** | 不依赖未公开 Windows 客户端；可按公开格式实现兼容，选择性采用 Apache Helper 的设计/独立服务。 | **Lyris 推荐路线**。最匹配 macOS 顶部岛、状态栏、窗口与授权体验；是否适合 Lyricify Mobile 2 上游，必须由作者先确认其 Apple 端技术栈。 |
| 共享 .NET 歌词 core + 原生 SwiftUI/AppKit 壳 | **中** | 可直接使用 Apache-2.0 Helper，但需要将 .NET 运行时、IPC/FFI、签名、升级与错误隔离纳入 macOS 发布。 | 只在确实需要 Helper 的全部格式/解密能力时采用；先做小型可替换 Adapter 验证。 |
| Avalonia / Uno | **中偏低** | 公开仓库未提供可迁移 UI 源；引入它们等于重做整套 UI，无法“直接改写”。 | 不建议用于首个高质量 macOS Top Island；仅当作者未来公开 .NET UI/core 且愿意维护跨平台产品时再评估。 |
| .NET MAUI / Mac Catalyst | **中偏低** | 同样没有待迁移的 app 源；Mac Catalyst 对原生菜单栏、非激活悬浮窗和刘海体验不占优势。 | 不建议。 |
| Wine/Windows on ARM 虚拟机 | **可运行但不是原生开发路线** | 正是项目 README 当前的 macOS 运行建议。 | 不作为 Lyris 或上游 macOS 客户端方案。**C** [README](https://github.com/WXRIW/Lyricify-App/blob/9b739669356efb78bb6d4426b7b905f1e83bd2c7/README.md#L18-L23)。 |

对官方 `Lyricify Mobile v1.5.1` macOS ZIP/PKG 的独立静态检查进一步确认，当前 Mobile macOS 发行物使用 Mono + Xamarin.Forms/Xamarin.Mac，而非 SwiftUI/AppKit 原生业务 UI；Xamarin 已于 2024-05-01 结束 Microsoft 支持，因此这份旧实现适合用于确认“共享 C# core + macOS 宿主”的历史路线，不适合作为新 Apple 端直接续建的技术底座。详见 [Lyricify Mobile v1.5.1 macOS bundle 审阅](lyricify-mobile-1.5.1-macos-bundle-review.md)。

## 4. 许可证、品牌、歌词与私有接口风险

1. **主仓库没有根许可证。** 固定树中无 `LICENSE`/`COPYING`，作者又明确说明 app 闭源；用户协议写明“All rights reserved by WXRIW”，并对名称、商标、文字、图形与图像保留权利。因此不能把主仓库的资源、主题、图标或发行物视为开放再分发/改作授权。**B/C** [固定树](https://github.com/WXRIW/Lyricify-App/tree/9b739669356efb78bb6d4426b7b905f1e83bd2c7)、[issue #387](https://github.com/WXRIW/Lyricify-App/issues/387#issuecomment-2306039383)、[用户协议](https://github.com/WXRIW/Lyricify-App/blob/9b739669356efb78bb6d4426b7b905f1e83bd2c7/docs/Lyricify%204/UserAgreement.txt#L59-L60)。
2. **Helper 可以依法采用，但需保留 Apache-2.0 所要求的许可证、版权/归属声明和修改声明；它不授予 Lyricify 商标。** Apache 第 4、6 条规定再分发义务与商标限制。**B** [Apache-2.0 LICENSE](https://github.com/WXRIW/Lyricify-Lyrics-Helper/blob/c14bba9b49037c305192d59cff1289d79347477b/LICENSE#L65-L102)。
3. **Lyricify 词库不是当前可接入 API。** 开发者文档第一行称计划“暂时搁置”，接口 URL 是占位符，且其描述的词库混合用户上传及多个来源；这既不是可用契约，也不是歌词内容版权/再授权证明。**C** [开发者文档](https://github.com/WXRIW/Lyricify-App/blob/9b739669356efb78bb6d4426b7b905f1e83bd2c7/docs/Developer/README.md#L1-L33)。
4. **不应复制视觉资产或混淆品牌。** 即使作者允许提交 macOS 实现，也需要书面确认“Lyricify / Lyricify 4 / 图标 / Dynamic Lyrics Island”等名称与视觉表达是否可用于新客户端、署名方式、商店与捐赠/付费权益归属。**D**
5. **避免采用非公开音乐服务接口或规避访问控制。** Helper 的 provider 代码应逐一经过服务条款、官方 API 可用性、地域与速率审查；生产实现优先 Spotify 官方 API、官方授权和允许的歌词来源。**D**

## 5. 可向作者提出的最小可接受上游方案

### 先联系，先获得以下书面答复

1. Lyricify 4 Windows 客户端是否有计划开放给受邀贡献者；若没有，macOS 工作是否应归入作者已经公开规划的 `Lyricify Mobile 2`。作者此前明确表示数字系列面向 Windows，Apple 平台计划走下一代 Mobile 重构。**C** [issue #404](https://github.com/WXRIW/Lyricify-App/issues/404#issuecomment-2423836010)、[README 未来计划](https://github.com/WXRIW/Lyricify-App/blob/9b739669356efb78bb6d4426b7b905f1e83bd2c7/README.md#L64-L71)。
2. 是否愿意建立独立 `Lyricify macOS` / `Lyricify Mobile 2 Apple` 仓库，采用何种许可证与贡献者协议；提交代码归属、维护责任和发布签名如何约定。
3. 是否授权使用 Lyricify 名称、图标、动态歌词岛/Magic Strip 的具体视觉表达，以及必须的归属与 CC BY-SA 履行方式。
4. Lyricify Lyrics Vault 是否有正式、可签约/可授权的只读 API；若无，macOS 客户端是否必须完全使用独立、合法的歌词来源。
5. Spotify OAuth Client 的归属、redirect URI、隐私政策和商店分发责任；不要复用对方现有 Client ID、token 或服务端接口。

### 获得许可后的最小 PR/试点

1. 由作者先确定目标产品与仓库，再建立**独立 macOS 原生 target/仓库**；不把它包装成 Lyricify 4 的直接端口，也不假设 Windows UI 有源码可共享。
2. 仅交付可替换的跨平台歌词域契约：`TrackMetadata`、`LyricsData`、行/词级时间模型、LRC/Lyricify Lines 解析测试向量；UI 和 Spotify adapter 留在 macOS 层。
3. 默认使用合法、公开、可配置的歌词 provider；Lyricify 词库 adapter 保持禁用，直到作者提供正式契约与授权。
4. 用不含 Lyricify 受保护素材的临时名称/图标完成 QA；获得品牌授权后再做品牌整合。
5. 把许可证、第三方 notice、数据来源归属、隐私说明与 API 失败降级作为 PR 的验收条件。

## 6. 对 Lyris 的实际决策

- 可以把 Lyricify 当作**功能与交互研究参照**，但不要把该主仓库当作可 fork 的 Windows 源码或 UI 素材库。
- 可以独立评估 Apache-2.0 Helper 的某些歌词格式实现；若直接引入 .NET，则先做隔离 Adapter 和许可 notice，避免把 UI/网络 provider/私有接口耦入 Lyris。
- 继续选择原生 SwiftUI/AppKit 的 macOS-first 路线。它能产出高质量 macOS 客户端，也保留了未来经作者许可后向 Lyricify 贡献“可独立接收的 macOS 模块”的可能。

## 研究限制

本研究未运行发行二进制、未登录账号、未调用歌词服务、未抓包或逆向，也未读取非公开源。除固定提交外，本文只引用项目作者公开 issue 回复与 GitHub Release 元数据；所有主要结论均可由所列一手链接复核。
