# Lyricify Mobile v1.5.1 macOS 发布包：静态结构与合规边界审阅

> 审阅日期：2026-08-17（Asia/Shanghai）
> 对象：官方 [Release `mobile-v1.5.1`](https://github.com/WXRIW/Lyricify-App/releases/tag/mobile-v1.5.1) 的 `LyricifyMobile.v1.5.1-release.macOS.zip` 与推荐安装包 `LyricifyMobile.v1.5.1-release.macOS.pkg`。
> 本地样本：`apple/Lyris/.build/research/lyricify-mobile-1.5.1/`（该目录受 Git 忽略）。
> 方法限制：仅检查 ZIP、`.app` bundle 的 `Info.plist`、文件/程序集名、Mach-O load commands、代码签名及项目方/Microsoft 一手公开资料；**未**运行 app、登录、调用 app 网络、抓包、反编译托管程序集或进行广泛 `strings` 扫描。

## 结论先行

该发行物是一个 **macOS 11.0+、x86_64 + arm64 的通用 `.app` 外壳**，内部以 `MonoBundle` 携带 **Mono + Xamarin.Forms/Xamarin.Mac 的托管程序集**；它不是 SwiftUI/AppKit 原生实现，也不能据此取得或改写其闭源业务代码。包内文件名可确认 `Lyricify.Lyrics.Helper.dll`、`SpotifyAPI.Web.dll`、`SpotifyAPI.Web.Auth.dll` 和 `EmbedIO.dll` 随包分发，但在不反编译的前提下，不能断言它们在何种代码路径、功能或配置中被调用。

官方 Release 所列 macOS ZIP 与 PKG 的 SHA-256 均与本地样本重新计算值一致，且 ZIP 压缩数据测试通过；这只能将本地字节与该 Release 资产对应起来，**不代表 app 有 Apple Developer ID 公证或可验证的发布者身份**。ZIP 与 PKG 中的主可执行文件和 `Info.plist` 分别逐字节一致；实际 bundle 的启动器是 ad-hoc 签名，`codesign --verify --deep --strict` 报告 bundle 未完整签名，`pkgutil --check-signature` 也报告 PKG 无签名。当前主机 Gatekeeper 处于关闭状态，故 `spctl` 的“accepted”不能作为安全/信任结论。

对 Lyris 和任何未来获授权的 Lyricify Mobile 2 Apple 端，正确借鉴对象是功能范围与可替换的歌词领域契约，而非复制 UI、资产、发行物或闭源托管程序集。高质量的 macOS 顶部悬浮/刘海体验仍应由原生 SwiftUI/AppKit 窗口与交互层实现。

## 证据等级

| 标记 | 含义 |
| --- | --- |
| **R** | 项目方 GitHub Release / README / 用户指南的公开一手资料。 |
| **L** | 对本地下载 ZIP 或其解压 app bundle 的只读观察。 |
| **M** | Microsoft 官方支持生命周期资料。 |
| **I** | 基于上述事实的工程推断，不是对闭源代码行为的断言。 |

## 1. 发行物身份与完整性

| 项目 | 结果 | 依据 |
| --- | --- | --- |
| Release | `mobile-v1.5.1`，标题为 `Lyricify Mobile v1.5.1-release`，发布于 2026-01-18 03:26:17 UTC，关联提交 `85857c8`。 | **R** [Release 页面](https://github.com/WXRIW/Lyricify-App/releases/tag/mobile-v1.5.1)。 |
| 官方 ZIP asset | `LyricifyMobile.v1.5.1-release.macOS.zip`；Release 页面给出的 SHA-256 为 `6b72126cb00f3f879a3e770907e9cd10fcbd7eb9434adbc124f9b95d31bc308d`。 | **R** [展开的资产清单](https://github.com/WXRIW/Lyricify-App/releases/expanded_assets/mobile-v1.5.1)。 |
| 本地重新计算 | 相同：`6b72126cb00f3f879a3e770907e9cd10fcbd7eb9434adbc124f9b95d31bc308d`（`shasum -a 256`）。`unzip -t` 报告压缩数据无错误。 | **L**。 |
| 官方 PKG asset | `LyricifyMobile.v1.5.1-release.macOS.pkg`；Release API 给出的 SHA-256 为 `01ca25a6ab66d2055b7f0bbc369e6721dd208a5184c56cf4682eb2f57236c651`，本地重新计算一致。 | **R/L** [Release 页面](https://github.com/WXRIW/Lyricify-App/releases/tag/mobile-v1.5.1)。 |
| 官方安装说明 | Release 推荐 `.macOS.pkg`，也明确支持 ZIP：解压后将 `Lyricify Mobile for macOS.app` 拖入 Applications。 | **R** [Release 页面](https://github.com/WXRIW/Lyricify-App/releases/tag/mobile-v1.5.1)。 |

ZIP 的哈希一致仅验证当前本地字节等同于 GitHub Release 页面列出的该 ZIP 哈希，不能证明作者身份、供应链历史或运行时安全性。**I**

## 2. bundle、平台与运行时结构

### 2.1 可直接观察的 app 元数据

`Contents/Info.plist` 的关键项：

| 键 | 值 | 结论 |
| --- | --- | --- |
| `CFBundleIdentifier` | `com.wxriw.LyricifyMobile` | 发布物标识。**L** |
| `CFBundleShortVersionString` | `1.5.1` | 与 Release 版本一致。**L** |
| `LSMinimumSystemVersion` | `11.0` | 声明最低 macOS 为 11.0。**L** |
| `CFBundleExecutable` | `Lyricify Mobile for macOS` | 原生 Mach-O 启动器名称。**L** |
| `MonoBundleExecutable` | `Lyricify Mobile for macOS.exe` | App 外壳会交给 MonoBundle 中的托管入口。**L** |
| `NSPrincipalClass` / `NSMainStoryboardFile` | `NSApplication` / `Main` | 带 AppKit 应用壳及 storyboard 资源；这不等同于业务 UI 完全由 AppKit 原生实现。**L/I** |
| `DTSDKName` / `DTXcode` | `macosx15.5` / `16F6` | 构建记录使用 macOS 15.5 SDK、Xcode 16.4。不是最低系统版本。**L** |

启动器是 universal Mach-O：`x86_64` 与 `arm64` 两个 slice；其 `LC_BUILD_VERSION` 在两个 slice 均记录 `platform macOS`、`minos 11.0`。**L**

### 2.2 运行时与程序集名证据

`Contents/MonoBundle/` 中存在以下名称（仅枚举文件名，未读取/反编译 DLL 内容）：

- 运行时：`mscorlib.dll`、`Mono.Security.dll`、`libmono-native.dylib`、`libMonoPosixHelper.dylib`；后两者同为 x86_64 + arm64 universal dylib。**L**
- Xamarin：`Xamarin.Forms.Core.dll`、`Xamarin.Forms.Xaml.dll`、`Xamarin.Forms.Platform.dll`、`Xamarin.Forms.Platform.macOS.dll`、`Xamarin.Mac.dll`、`Xamarin.Essentials.dll`、`Xamarin.CommunityToolkit.dll`。**L**
- 应用/歌词：`Lyricify Mobile for macOS.exe`、`Lyricify Mobile.dll`、`Lyricify.Lyrics.Helper.dll`。**L**
- Spotify/HTTP 相关：`SpotifyAPI.Web.dll`、`SpotifyAPI.Web.Auth.dll`、`EmbedIO.dll`、`System.Net.Http.dll`。**L**

这些事实足以证明该 macOS 包随附 Xamarin.Forms/Xamarin.Mac 与 Mono 运行时资产，并随附指定的歌词、Spotify 与 EmbedIO 程序集。它们**不能**在不读取程序集实现的情况下证明 OAuth 流程、网络端点、歌词来源、凭证保存方式、EmbedIO 是否运行/监听，或具体 UI/窗口实现。**I**

官方 README 亦将歌词处理库单独指向 `.NET Standard` 的 [Lyricify-Lyrics-Helper](https://github.com/WXRIW/Lyricify-Lyrics-Helper)，而 Release 文档称该 Mobile 版本覆盖 macOS 等 Apple/桌面平台。README 中仍保留“未来提供 macOS 支持”的旧句，与此 Release 的 macOS asset/安装说明冲突；此处以同一项目方的具体 Release asset 为准。**R** [项目 README](https://github.com/WXRIW/Lyricify-App/blob/main/README.md)、[Mobile 指南](https://github.com/WXRIW/Lyricify-App/blob/main/docs/Lyricify%20Mobile/README.md)。

## 3. 原生依赖面与签名事实

### 3.1 Mach-O load commands

启动器的 `LC_LOAD_DYLIB` 可观察到系统框架：`AppKit`、`Foundation`、`Security`、`WebKit`/`JavaScriptCore`、`AVFoundation`/`AVKit`、`CoreMedia`/`CoreVideo`、`CoreText`、`QuartzCore`、`AuthenticationServices`、`CloudKit`、`OpenGL` 等，另有系统库 `libSystem`、`libobjc`、`libc++`、`libz`、`libiconv`。**L**

这表明启动器链接了多项 macOS 系统能力，不能由 load commands 推导某个特性一定被应用使用。例如，看到 `AppKit`/`WebKit` 不能证明顶层歌词窗、Spotify 登录或具体播放 UI 的实现细节。**I**

### 3.2 代码签名与 Gatekeeper 的边界

| 检查 | 实测 | 能说明什么 / 不能说明什么 |
| --- | --- | --- |
| `codesign -dvvv`（启动器） | `Signature=adhoc`、`TeamIdentifier=not set`、`Sealed Resources=none`、`Info.plist=not bound`；有 SHA-256 CodeDirectory/CDHash。 | 启动器携带 ad-hoc 签名记录，**没有**可归属的 Developer Team/Developer ID 身份。ad-hoc 不是发布者身份认证。**L/I** |
| `codesign --verify --deep --strict --verbose=4`（app） | `code object is not signed at all`。 | Bundle 作为整体不满足该严格深度签名验证；不应声称已完整签名/已公证。**L** |
| `spctl --assess --type execute --verbose=4` | 输出 `accepted`，同时为 `source=no usable signature`、`override=security disabled`。 | 当前主机的系统安全策略关闭，结果不是 Gatekeeper 对有效开发者签名或 notarization 的认可。**L/I** |

### 3.3 官方 PKG 的安装边界

- `pkgutil --check-signature` 对推荐的 PKG 返回 `Status: no signature`。**L**
- `PackageInfo` 声明安装到 `/Applications`、`auth="root"`、无 post-install action，payload 为 53 个文件；`Distribution` 声明最低 macOS 11.0、支持 x86_64/arm64、无需安装脚本。**L**
- 静态解开 payload 后，PKG 内的主可执行文件和 `Info.plist` 与 ZIP 版本逐字节一致；因此 PKG 没有替换成另一份正式 Developer ID 签名的 app。**L**

这意味着推荐安装器需要管理员授权把应用写入 `/Applications`，但管理员授权只是安装位置要求，不等于开发者签名、公证或更高可信度。由于本轮目标是静态审阅，未执行安装。**L/I**

本审阅没有联网到 Apple notarization 服务，也没有在安全策略正常的干净主机上启动 app；因此不对可运行性、恶意代码、隐私行为或跨机 Gatekeeper 体验下结论。**L/I**

## 4. Xamarin 支持状态与维护含义

Microsoft 的 [Xamarin support policy](https://dotnet.microsoft.com/en-us/platform/support/policy/xamarin) 说明，含 Xamarin.Forms 在内的 Xamarin SDK 支持已于 **2024-05-01** 结束；Xamarin.Android/iOS/Mac 对应迁入 .NET 6+，Xamarin.Forms 的迁移目标为 .NET MAUI。其 [Xamarin.Mac 生命周期页](https://learn.microsoft.com/en-us/lifecycle/products/xamarinmac) 给出退休时间为 2024-05-01 22:59:59.999 PT；Microsoft 的 [迁移指南](https://learn.microsoft.com/en-us/dotnet/maui/migration/?view=net-maui-10.0) 也列出 Xamarin.Mac 到 .NET、Xamarin.Forms 到 .NET MAUI 的迁移方向。**M**

因此，此 v1.5.1 发行物中实际出现的 Xamarin.Forms/Xamarin.Mac 资产属于已停止支持的技术栈；这不证明它当下不能运行，但意味着不会再得到 Xamarin 本身的修复、更新或在线技术支持。继续依赖该栈会把新 macOS/SDK 兼容性、安全修复与运行时问题留给项目维护方。**M/I**

## 5. 为什么它不适合作为高质量原生顶部悬浮窗的直接基础

以下是工程判断，不是从闭源程序集反推出的内部实现：

1. **顶层窗口控制需要原生所有权。** macOS 顶部悬浮体验依赖 `NSWindow`/`NSPanel` 的 level、collection behavior、激活策略、屏幕与安全区域几何、鼠标命中、键盘焦点、动画同步和多显示器重定位。现有包的 Xamarin.Forms 抽象层和 Mono 托管运行时会在这些问题上增加跨边界协调；可通过自定义原生 renderer/绑定补足，却不等于可直接复用其 UI。**L/I**
2. **刘海/Top Island 是连续表面而非普通跨平台页面。** 需要让物理刘海区域、附着卡片的 frame、内容裁剪和 hit region 用同一时序形变。Xamarin.Forms 的跨平台布局可以显示页面，但包内结构没有提供任何可审计的、可授权复用的实现来解决 AppKit 窗口层级与视觉表面的一致性。**L/I**
3. **发布维护成本会叠加。** 该包同时包含 native launcher、Mono dylib、托管程序集和不完整的可验证签名边界；把它作为新功能底座，会把 runtime 打包、签名、公证、升级以及旧 Xamarin 支持终止共同带入。**L/M/I**

这不是“Xamarin 绝不能制作浮窗”的结论，而是对“以该闭源发布包直接改写/作为高质量原生 macOS UI 基座”的否定：两者在许可、可维护性和窗口控制上均不成立。**I**

## 6. 对 Lyris 与未来获授权上游的建议

| 目标 | 建议 | 边界 |
| --- | --- | --- |
| Lyris | 继续原生 SwiftUI/AppKit：以 AppKit 统一持有顶部窗口、notch-safe geometry、层级、非激活交互和连续 frame/content 动画；SwiftUI 只作为内容视图。 | 不复制 Release 中的程序集、UI、图标、名称、文案或配置。 |
| 歌词领域 | 将公开可许可的歌词格式、时间模型、对唱/逐字/翻译的降级规则提炼为独立契约和测试向量；若考虑 Apache-2.0 Helper，须单独核对许可证与 Swift 集成成本。 | `Lyricify.Lyrics.Helper.dll` 出现在闭源 app 包内，**不**赋予该二进制的再利用授权。 |
| 未来 Lyricify Mobile 2 | 先让作者书面确定仓库、许可证、品牌/视觉资产、Spotify OAuth 和歌词服务的使用边界；再贡献独立 Apple-native 模块或共享的无 UI 歌词 schema。 | 不把本 Release 视作可 fork 或可逆向移植的上游源。 |
| 技术迁移 | 若作者希望维持 .NET 共享核心，优先评估受支持的 .NET SDK-style core，macOS 表层仍保留明确 AppKit 接口；是否选择 .NET MAUI 需以窗口/刘海原型实际验证。 | 不建议为追求共享代码而牺牲 native top-overlay 的可控性。 |

## 7. 审阅范围与未回答问题

- 已验证 ZIP、PKG 与官方 Release 公布的 SHA-256 一致，并静态确认两种分发形式中的主程序一致；未安装或启动 app，也未验证功能、网络访问、Spotify 登录或歌词展示。
- 未读取、反编译或反汇编任何 `.dll`/`.exe`；因此没有对业务逻辑、协议、密钥、内部 API、数据处理或 UI 布局作出结论。
- 未对包内素材或 UI 做相似性复刻；项目公开仓库/发行物并不自动授予闭源应用代码、商标或视觉资产的使用权。
- 本文不构成安全审计或发布认证。若未来要评估分发，需在安全策略开启的干净 macOS 环境中按作者授权和 Apple 规则另行检查签名、公证、sandbox/entitlements 与隐私声明。
