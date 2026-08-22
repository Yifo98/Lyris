import SwiftUI

struct LyrisSettingsRootView: View {
    @ObservedObject var runtime: LyrisRuntime

    var body: some View {
        Group {
            if let store = runtime.store {
                LyrisSettingsView(
                    store: store,
                    surfaceVisibility: runtime.surfaceVisibility
                )
            } else {
                ProgressView(
                    LyrisDisplayPreferences.load(from: .standard).interfaceLanguage.pick(
                        zh: "正在载入 Lyris 设置…",
                        en: "Loading Lyris settings…"
                    )
                )
                    .frame(width: 680, height: 480)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            runtime.surfaceVisibility.setSystemSettingsVisible(true)
        }
        .onDisappear {
            runtime.surfaceVisibility.setSystemSettingsVisible(false)
        }
    }
}

struct LyrisSettingsView: View {
    @ObservedObject var store: LyrisStore
    @ObservedObject var surfaceVisibility: LyrisSurfaceVisibility
    @State private var revealsSpotifyClientID = false
    @State private var revealsTranslationAPIKey = false

    var body: some View {
        ZStack {
            store.interfaceSkin.backgroundColor.ignoresSafeArea()
            LinearGradient(
                colors: [
                    store.interfaceSkin.raisedBackgroundColor.opacity(0.72),
                    store.interfaceSkin.backgroundColor,
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            let material = LyrisSettingsMaterialProfile.resolve(
                style: store.linkedEffectStyle
            )
            if material.effectOpacity > 0 {
                LyrisLinkedEffectOverlay(
                    style: store.linkedEffectStyle,
                    skin: store.interfaceSkin,
                    isPlaying: material.animates,
                    isActive: surfaceVisibility.isSettingsWindowVisible,
                    framesPerSecond: 12,
                    seed: "lyris-settings-\(store.interfaceSkin.rawValue)",
                    progress: 0.5
                )
                .opacity(material.effectOpacity)
                .ignoresSafeArea()
                LyrisGlobalFlowThreadOverlay(
                    style: store.linkedEffectStyle,
                    skin: store.interfaceSkin,
                    isPlaying: material.animates,
                    isActive: surfaceVisibility.isSettingsWindowVisible,
                    framesPerSecond: 12,
                    seed: "lyris-settings-flow-\(store.interfaceSkin.rawValue)"
                )
                .opacity(material.effectOpacity * 0.38)
                .ignoresSafeArea()
            }

            TabView(selection: $store.settingsSection) {
                languagePane
                    .tabItem {
                        Label(copy(zh: "语言", en: "Language"), systemImage: "character.book.closed")
                    }
                    .tag(SettingsSection.language)
                spotifyPane
                    .tabItem { Label("Spotify", systemImage: "music.note") }
                    .tag(SettingsSection.spotify)
                translationPane
                    .tabItem {
                        Label(copy(zh: "翻译", en: "Translation"), systemImage: "character.bubble")
                    }
                    .tag(SettingsSection.translation)
                appearancePane
                    .tabItem { Label(copy(zh: "外观", en: "Appearance"), systemImage: "sparkles") }
                    .tag(SettingsSection.appearance)
                windowPane
                    .tabItem { Label(copy(zh: "显示", en: "Display"), systemImage: "rectangle.on.rectangle") }
                    .tag(SettingsSection.window)
                usagePane
                    .tabItem { Label(copy(zh: "用量", en: "Usage"), systemImage: "chart.bar.xaxis") }
                    .tag(SettingsSection.usage)
                storagePane
                    .tabItem { Label(copy(zh: "存储", en: "Storage"), systemImage: "externaldrive") }
                    .tag(SettingsSection.storage)
            }
        }
        .tint(store.interfaceSkin.accentColor)
        .frame(minWidth: 760, minHeight: 520)
    }

    private var languagePane: some View {
        Form {
            Section(copy(zh: "语言与歌词", en: "Language & Lyrics")) {
                Picker(copy(zh: "界面语言", en: "Interface Language"), selection: Binding(
                    get: { store.interfaceLanguage },
                    set: { store.updateInterfaceLanguage($0) }
                )) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.displayName).tag(language)
                    }
                }

                Picker(copy(zh: "翻译目标", en: "Translation Target"), selection: Binding(
                    get: { store.translationTarget },
                    set: { store.updateTranslationTarget($0) }
                )) {
                    ForEach(TranslationTargetLanguage.allCases) { target in
                        Text(target.displayName(in: store.interfaceLanguage)).tag(target)
                    }
                }

                Picker(copy(zh: "译文字体", en: "Translation Font"), selection: Binding(
                    get: { store.translationFont },
                    set: { store.updateTranslationFont($0) }
                )) {
                    ForEach(TranslationFontChoice.allCases) { font in
                        Text(font.displayName(in: store.interfaceLanguage)).tag(font)
                    }
                }

                if store.translationFont == .custom {
                    LabeledContent(copy(zh: "已安装字体", en: "Installed Font")) {
                        LyrisInstalledFontPicker(
                            selection: Binding(
                                get: { store.customTranslationFontFamily },
                                set: { store.updateCustomTranslationFontFamily($0) }
                            ),
                            options: store.availableTranslationFontOptions,
                            accentColor: store.interfaceSkin.accentColor,
                            language: store.interfaceLanguage
                        )
                    }
                }

                HStack {
                    Button(copy(
                        zh: "使用系统推荐：\(recommendedFont.displayName)",
                        en: "Use System Recommendation: \(recommendedFont.displayName)"
                    )) {
                        store.applyRecommendedTranslationFont()
                    }
                    Button(copy(zh: "添加 .ttf / .otf 字体…", en: "Add .ttf / .otf Font…")) {
                        store.importTranslationFont()
                    }
                }

                Toggle(copy(
                    zh: "繁体中文歌词默认转换为简体",
                    en: "Convert Traditional Chinese Lyrics to Simplified"
                ), isOn: Binding(
                    get: { store.convertsTraditionalChineseToSimplified },
                    set: { store.updateTraditionalChineseConversion($0) }
                ))
                Text(copy(
                    zh: "原文与目标语言相同时不重复调用翻译；副行会改为显示下一句歌词。",
                    en: "When the original already matches the target language, Lyris skips translation and shows the next lyric on the secondary line."
                ))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section {
                Text(copy(
                    zh: "界面语言、翻译目标和字体只影响显示，不改变歌词来源。",
                    en: "Interface language, translation target, and font affect presentation only; they do not change the lyric source."
                ))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    private var appearancePane: some View {
        Form {
            Section(copy(zh: "界面皮肤", en: "Interface Skin")) {
                Picker(copy(zh: "皮肤", en: "Skin"), selection: Binding(
                    get: { store.interfaceSkin },
                    set: { store.updateInterfaceSkin($0) }
                )) {
                    ForEach(LyrisInterfaceSkin.allCases) { skin in
                        Text(skin.displayName(in: store.interfaceLanguage)).tag(skin)
                    }
                }

                HStack(spacing: 12) {
                    ForEach(LyrisInterfaceSkin.allCases) { skin in
                        Button {
                            store.updateInterfaceSkin(skin)
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: [skin.raisedBackgroundColor, skin.backgroundColor],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .overlay(alignment: .bottomLeading) {
                                        Capsule()
                                            .fill(skin.accentColor)
                                            .frame(width: 54, height: 4)
                                            .padding(10)
                                    }
                                    .frame(height: 70)
                                Text(skin.displayName(in: store.interfaceLanguage))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.primary)
                            }
                            .padding(8)
                            .background(
                                store.interfaceSkin == skin
                                    ? skin.accentColor.opacity(0.14)
                                    : Color.white.opacity(0.035),
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                Text(copy(
                    zh: "Spotify 官方客户端支持 Canvas，但当前 Web API 与 Web Playback SDK 都未公开 Canvas 视频字段；OAuth 授权也不会增加该字段。Lyris 使用稳定的本机封面呈现，不提供容易造成误解的 Canvas 切换。",
                    en: "Spotify's official client supports Canvas, but neither the Web API nor Web Playback SDK exposes Canvas video data. OAuth does not add it. Lyris therefore uses reliable local artwork instead of a misleading Canvas switch."
                ))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section(copy(zh: "顶部与氛围", en: "Top Surface & Atmosphere")) {
                Picker(copy(zh: "呈现模式", en: "Presentation Mode"), selection: Binding(
                    get: { store.floatingPresentationMode },
                    set: { store.updateFloatingPresentationMode($0) }
                )) {
                    ForEach(FloatingPresentationMode.allCases) { mode in
                        Text(
                            "\(mode.displayName(in: store.interfaceLanguage)) · "
                                + mode.guidance(in: store.interfaceLanguage)
                        )
                        .tag(mode)
                    }
                }

                Picker(copy(zh: "联动效果", en: "Linked Effect"), selection: Binding(
                    get: { store.linkedEffectStyle },
                    set: { store.updateLinkedEffectStyle($0) }
                )) {
                    ForEach(LinkedEffectStyle.allCases) { style in
                        Text(style.displayName(in: store.interfaceLanguage)).tag(style)
                    }
                }

                LyrisLinkedEffectPreview(
                    style: store.linkedEffectStyle,
                    skin: store.interfaceSkin
                )
                .frame(height: 72)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    private var windowPane: some View {
        Form {

            Section(copy(zh: "灵动岛", en: "Dynamic Island")) {
                Picker(copy(zh: "呈现模式", en: "Presentation Mode"), selection: Binding(
                    get: { store.floatingPresentationMode },
                    set: { store.updateFloatingPresentationMode($0) }
                )) {
                    ForEach(FloatingPresentationMode.allCases) { mode in
                        Text(
                            "\(mode.displayName(in: store.interfaceLanguage)) · "
                                + mode.guidance(in: store.interfaceLanguage)
                        )
                        .tag(mode)
                    }
                }

                Picker(copy(zh: "收起状态歌词", en: "Compact Lyric"), selection: Binding(
                    get: { store.menuBarLyricMode },
                    set: { store.updateMenuBarLyricMode($0) }
                )) {
                    ForEach(MenuBarLyricMode.allCases) { mode in
                        Text(mode.displayName(in: store.interfaceLanguage)).tag(mode)
                    }
                }

                Picker(copy(zh: "展开保留时间", en: "Expanded Hold Time"), selection: Binding(
                    get: { store.macIslandExpandedHoldDuration },
                    set: { store.updateMacIslandExpandedHoldDuration($0) }
                )) {
                    ForEach(MacIslandExpandedHoldDuration.allCases) { duration in
                        Text(duration.displayName(in: store.interfaceLanguage)).tag(duration)
                    }
                }

                Picker(copy(zh: "展开触发方式", en: "Expansion Trigger"), selection: Binding(
                    get: { store.macIslandExpansionTrigger },
                    set: { store.updateMacIslandExpansionTrigger($0) }
                )) {
                    ForEach(MacIslandExpansionTrigger.allCases) { trigger in
                        Text(trigger.displayName(in: store.interfaceLanguage)).tag(trigger)
                    }
                }

                if store.macIslandExpansionTrigger.allowsHover {
                    HStack {
                        Text(copy(zh: "悬停展开延迟", en: "Hover Expansion Delay"))
                        Slider(
                            value: Binding(
                                get: { store.macIslandHoverExpandDelay },
                                set: { store.updateMacIslandHoverExpandDelay($0) }
                            ),
                            in: 0...5,
                            step: 0.5
                        )
                        Text(
                            store.macIslandHoverExpandDelay == 0
                                ? copy(zh: "立即", en: "Now")
                                : copy(
                                    zh: String(format: "%.1f 秒", store.macIslandHoverExpandDelay),
                                    en: String(format: "%.1f s", store.macIslandHoverExpandDelay)
                                )
                        )
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 72, alignment: .trailing)
                    }
                }

                Text(
                    store.macIslandExpansionTrigger.guidance(in: store.interfaceLanguage)
                        + store.interfaceLanguage.pick(
                            zh: " 移开后按保留时间自动收回。",
                            en: " It collapses after the selected hold time when the pointer leaves."
                        )
                )
                    .font(.callout)
                    .foregroundStyle(.secondary)

                HStack {
                    Text(copy(zh: "歌词校准", en: "Lyric Calibration"))
                    Slider(
                        value: Binding(
                            get: { store.lyricTimingDelay },
                            set: { store.updateLyricTimingDelay($0) }
                        ),
                        in: -3...3,
                        step: 0.1
                    )
                    Text(copy(
                        zh: String(format: "%+.1f 秒", store.lyricTimingDelay),
                        en: String(format: "%+.1f s", store.lyricTimingDelay)
                    ))
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 72, alignment: .trailing)
                }
                Text(copy(
                    zh: "正值让歌词更晚出现，负值让歌词更早出现；调整会同时作用于灵动岛、悬浮条和桌面歌词。",
                    en: "Positive values show lyrics later and negative values show them earlier. The adjustment applies to the Dynamic Island, floating bar, and desktop lyrics."
                ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Text(copy(
                    zh: "菜单栏只保留小型 Lyris 入口；歌名与当前歌词由收起状态的灵动岛显示。",
                    en: "The menu bar keeps a small Lyris entry; the compact Dynamic Island shows the song title and current lyric."
                ))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    private var usagePane: some View {
        Form {
            Section(copy(zh: "今日用量", en: "Today's Usage")) {
                LabeledContent(
                    copy(zh: "翻译服务", en: "Translation Service"),
                    value: store.translationProvider.displayName(in: store.interfaceLanguage)
                )
                LabeledContent(copy(zh: "模型", en: "Model"), value: store.translationModel)
                LabeledContent(copy(zh: "API 请求", en: "API Requests"), value: "\(store.apiRequestCount)")
                LabeledContent(
                    copy(zh: "已翻译歌词", en: "Translated Lyrics"),
                    value: copy(zh: "\(store.translatedLineCount) 行", en: "\(store.translatedLineCount) lines")
                )
                LabeledContent(
                    copy(zh: "估算 Token", en: "Estimated Tokens"),
                    value: "\(store.estimatedInputTokenCount + store.estimatedOutputTokenCount)"
                )
                LabeledContent(copy(zh: "预估费用", en: "Estimated Cost"), value: store.estimatedAPICostFormatted)
            }

            Section(copy(zh: "价格与币种", en: "Pricing & Currency")) {
                Picker(copy(zh: "显示币种", en: "Display Currency"), selection: Binding(
                    get: { store.costCurrency },
                    set: { store.updateCostCurrency($0) }
                )) {
                    ForEach(CostCurrency.allCases) { currency in
                        Text(currency.displayName(in: store.interfaceLanguage)).tag(currency)
                    }
                }

                if store.costCurrency != .usd {
                    TextField(
                        copy(zh: "每 1 USD 对应币种数量", en: "Currency Units per 1 USD"),
                        value: Binding(
                            get: { store.costCurrencyUnitsPerUSD },
                            set: { store.updateCostCurrencyUnitsPerUSD($0) }
                        ),
                        format: .number.precision(.fractionLength(2...6))
                    )
                    Text(copy(
                        zh: "汇率仅用于本机显示，可按当前账单汇率手动修改。",
                        en: "The exchange rate is used for local display only and can be adjusted to match your bill."
                    ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    TextField(
                        copy(zh: "输入单价 / 百万 Token", en: "Input Price / Million Tokens"),
                        value: Binding(
                            get: { store.translationInputPriceInSelectedCurrency },
                            set: { store.updateTranslationInputPriceInSelectedCurrency($0) }
                        ),
                        format: .number.precision(.fractionLength(0...6))
                    )
                    TextField(
                        copy(zh: "输出单价 / 百万 Token", en: "Output Price / Million Tokens"),
                        value: Binding(
                            get: { store.translationOutputPriceInSelectedCurrency },
                            set: { store.updateTranslationOutputPriceInSelectedCurrency($0) }
                        ),
                        format: .number.precision(.fractionLength(0...6))
                    )
                }

                HStack {
                    Button(
                        store.isRefreshingOfficialPricing
                            ? copy(zh: "正在联网匹配…", en: "Fetching Official Price…")
                            : copy(zh: "联网匹配官方参考价", en: "Fetch Official Reference Price")
                    ) {
                        store.refreshTranslationPricingFromOfficialSource()
                    }
                    .disabled(store.isRefreshingOfficialPricing)
                    Button(copy(zh: "打开官方价格页", en: "Open Official Pricing")) {
                        store.openOfficialTranslationPricing()
                    }
                        .disabled(store.translationPricingReference.sourceURL == nil)
                }

                if let status = store.officialPricingStatus {
                    Text(status)
                        .font(.callout)
                        .foregroundStyle(store.interfaceSkin.accentColor)
                }

                Text(copy(
                    zh: "参考价核对日期：\(store.translationPricingReference.verifiedDate)。\(store.translationPricingReference.note)。价格可手动覆盖；费用为本机估算值，不代表服务商正式账单。",
                    en: "Reference price checked \(store.translationPricingReference.verifiedDate). \(store.translationPricingReference.note). Prices can be overridden manually; estimates are local and do not represent the provider's final bill."
                ))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    private var spotifyPane: some View {
        Form {
            Section(copy(zh: "账户增强", en: "Account Enhancements")) {
                Text(copy(
                    zh: "本机播放不需要账户授权；跨设备播放状态和收藏同步需要 Spotify PKCE。",
                    en: "Local playback needs no account authorization. Cross-device playback state and Liked Songs sync require Spotify PKCE."
                ))
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Text(copy(
                    zh: "Client ID 来自这台 Mac 的本地 Lyris 配置，不会打包进 App。重新下载或替换相同 Bundle ID 的 Lyris 时，macOS 会继续恢复这份本机设置。",
                    en: "The Client ID comes from this Mac's local Lyris settings and is never bundled in the app. macOS restores it when replacing Lyris with the same bundle identifier."
                ))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Group {
                        if revealsSpotifyClientID {
                            TextField("Spotify Client ID", text: $store.spotifyClientID)
                        } else {
                            SecureField("Spotify Client ID", text: $store.spotifyClientID)
                        }
                    }
                    .textFieldStyle(.roundedBorder)

                    Button {
                        revealsSpotifyClientID.toggle()
                    } label: {
                        Image(systemName: revealsSpotifyClientID ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.borderless)
                    .focusable(false)
                    .help(
                        revealsSpotifyClientID
                            ? copy(zh: "隐藏 Client ID", en: "Hide Client ID")
                            : copy(zh: "显示 Client ID", en: "Show Client ID")
                    )
                }

                LabeledContent(copy(zh: "连接状态", en: "Connection Status"), value: store.spotifyConnectionStatus)

                HStack {
                    Button(copy(zh: "仅保存 Client ID", en: "Save Client ID Only")) {
                        store.saveSpotifyConfiguration()
                    }
                    Button(
                        store.isAuthorizingSpotify
                            ? copy(zh: "取消等待", en: "Cancel Authorization")
                            : copy(zh: "保存并开始授权", en: "Save and Authorize")
                    ) {
                        if store.isAuthorizingSpotify {
                            store.cancelSpotifyAuthorization()
                        } else {
                            store.authorizeSpotify()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            Section(copy(zh: "如何获取 Client ID", en: "How to Get a Client ID")) {
                Text(copy(
                    zh: "1. 打开 Spotify Developer Dashboard，新建或选择一个应用。",
                    en: "1. Open Spotify Developer Dashboard and create or select an app."
                ))
                Text(copy(
                    zh: "2. 在应用设置中加入下面的 Redirect URI，必须逐字一致。",
                    en: "2. Add the Redirect URI below to the app settings exactly as shown."
                ))
                HStack {
                    Text(LyrisStore.spotifyRedirectURI)
                        .font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)
                    Spacer()
                    Button(copy(zh: "复制", en: "Copy")) { store.copyRedirectURI() }
                }
                Text(copy(
                    zh: "3. 复制应用的 Client ID，粘贴到上方并开始 PKCE 授权。",
                    en: "3. Copy the app's Client ID, paste it above, and start PKCE authorization."
                ))
                HStack {
                    Button(copy(zh: "打开 Developer Dashboard", en: "Open Developer Dashboard")) {
                        store.openSpotifyDashboard()
                    }
                    Spacer()
                }
                Text(copy(
                    zh: "桌面应用无法安全保管 Client Secret。Lyris 使用 Spotify 官方推荐的 PKCE 流程，因此不会要求或保存 Client Secret。",
                    en: "Desktop apps cannot safely keep a Client Secret. Lyris uses Spotify's recommended PKCE flow and never asks for or stores a Client Secret."
                ))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if let status = store.configurationStatus, !status.isEmpty {
                Section(copy(zh: "状态", en: "Status")) {
                    Text(status)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    private var translationPane: some View {
        Form {
            Section(copy(zh: "翻译服务", en: "Translation Service")) {
                Picker(copy(zh: "服务", en: "Service"), selection: Binding(
                    get: { store.translationProvider },
                    set: { store.updateTranslationProvider($0) }
                )) {
                    ForEach(TranslationProvider.allCases) { provider in
                        Text(provider.displayName(in: store.interfaceLanguage)).tag(provider)
                    }
                }

                TextField("Base URL", text: Binding(
                    get: { store.translationBaseURL },
                    set: { store.updateTranslationBaseURLDraft($0) }
                ))
                .textFieldStyle(.roundedBorder)

                if LyrisTranslationModelSelection.usesFetchedPicker(
                    available: store.availableTranslationModels
                ) {
                    Picker(copy(zh: "模型", en: "Model"), selection: Binding(
                        get: { store.translationModel },
                        set: { store.updateTranslationModelDraft($0) }
                    )) {
                        ForEach(
                            LyrisTranslationModelSelection.options(
                                available: store.availableTranslationModels,
                                current: store.translationModel
                            ),
                            id: \.self
                        ) { model in
                            Text(model).tag(model)
                        }
                    }
                    .pickerStyle(.menu)
                    Text(copy(
                        zh: "已从当前翻译服务读取 \(store.availableTranslationModels.count) 个可用模型。",
                        en: "Loaded \(store.availableTranslationModels.count) available models from the current translation service."
                    ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    TextField(copy(zh: "模型", en: "Model"), text: Binding(
                        get: { store.translationModel },
                        set: { store.updateTranslationModelDraft($0) }
                    ))
                    .textFieldStyle(.roundedBorder)
                    Text(copy(
                        zh: "测试连接后，服务返回的模型会在这里改为下拉选择。",
                        en: "After testing the connection, models returned by the service will appear here as a menu."
                    ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Group {
                        if revealsTranslationAPIKey {
                            TextField("API Key", text: Binding(
                                get: { store.translationAPIKey },
                                set: { store.updateTranslationAPIKeyDraft($0) }
                            ))
                        } else {
                            SecureField("API Key", text: Binding(
                                get: { store.translationAPIKey },
                                set: { store.updateTranslationAPIKeyDraft($0) }
                            ))
                        }
                    }
                    .textFieldStyle(.roundedBorder)

                    Button {
                        revealsTranslationAPIKey.toggle()
                    } label: {
                        Image(systemName: revealsTranslationAPIKey ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.borderless)
                    .focusable(false)
                }

                if store.translationCredentialRequiresAuthorization {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Button(copy(
                            zh: "读取本机已保存的 API Key",
                            en: "Read Saved API Key"
                        )) {
                            store.authorizeSavedTranslationCredential()
                        }
                        .buttonStyle(.bordered)

                        Text(copy(
                            zh: "只有点击这里才会请求登录钥匙串权限；请选择“始终允许”，本正式版本后续启动将不再重复询问。",
                            en: "Keychain access is requested only after you click here. Choose Always Allow so this signed build will not ask again on later launches."
                        ))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Picker(copy(zh: "翻译方式", en: "Translation Style"), selection: Binding(
                    get: { store.translationStyle },
                    set: { store.updateTranslationStyle($0) }
                )) {
                    ForEach(LyricsTranslationStyle.allCases) { style in
                        Text(style.displayName(in: store.interfaceLanguage)).tag(style)
                    }
                }

                Toggle(copy(zh: "思考模式", en: "Reasoning Mode"), isOn: Binding(
                    get: { store.translationThinkingEnabled },
                    set: { store.updateTranslationThinkingDraft($0) }
                ))

                HStack {
                    Button(copy(zh: "保存配置", en: "Save Configuration")) {
                        store.saveTranslationConfiguration()
                    }
                    Button(
                        store.isTestingTranslation
                            ? copy(zh: "测试中…", en: "Testing…")
                            : copy(zh: "测试连接并读取模型", en: "Test Connection & Load Models")
                    ) {
                        store.testTranslationConnection()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(store.isTestingTranslation)
                }
            }

            if let status = store.configurationStatus, !status.isEmpty {
                Section(copy(zh: "状态", en: "Status")) {
                    Text(status)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    private var storagePane: some View {
        Form {
            Section("LyrisData") {
                LabeledContent(
                    copy(zh: "歌词库", en: "Lyrics Library"),
                    value: copy(
                        zh: "\(store.storageUsage.cachedLyricCount) 个文件 · \(store.storageUsage.formattedLyricsBytes)",
                        en: "\(store.storageUsage.cachedLyricCount) files · \(store.storageUsage.formattedLyricsBytes)"
                    )
                )
                LabeledContent(
                    copy(zh: "封面与网络缓存", en: "Artwork & Network Cache"),
                    value: store.storageUsage.formattedNetworkCacheBytes
                )

                HStack {
                    Button(copy(zh: "刷新占用", en: "Refresh Usage")) { store.refreshStorageUsage() }
                    Button(copy(zh: "在访达中打开", en: "Open in Finder")) { store.openLocalDataFolder() }
                }
            }

            Section(copy(zh: "分目录管理", en: "Folder Management")) {
                HStack {
                    Button(copy(zh: "打开歌词库", en: "Open Lyrics Library")) { store.openLyricsFolder() }
                    Button(copy(zh: "清除自动歌词缓存", en: "Clear Generated Lyrics Cache")) {
                        store.clearGeneratedLyricsCache()
                    }
                }
                HStack {
                    Button(copy(zh: "打开缓存目录", en: "Open Cache Folder")) { store.openCacheFolder() }
                    Button(copy(zh: "清除封面/网络缓存", en: "Clear Artwork/Network Cache")) {
                        store.clearArtworkCache()
                    }
                }
            }

            if let status = store.cacheStatus, !status.isEmpty {
                Section(copy(zh: "状态", en: "Status")) {
                    Text(status)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .task { store.refreshStorageUsage() }
    }

    private var recommendedFont: LyrisFontRecommendation {
        LyrisFontRecommendation.recommendation(
            for: store.translationTarget,
            availableFamilies: store.availableTranslationFontFamilies
        )
    }

    private func copy(zh: String, en: String) -> String {
        store.interfaceLanguage.pick(zh: zh, en: en)
    }
}

private struct LyrisInstalledFontPicker: View {
    @Binding var selection: String
    let options: [LyrisInstalledFontOption]
    let accentColor: Color
    let language: AppLanguage

    @State private var isPresented = false
    @State private var query = ""

    var body: some View {
        Button {
            isPresented = true
        } label: {
            HStack(spacing: 10) {
                Text(selection.isEmpty ? language.pick(zh: "请选择字体", en: "Choose a Font") : selection)
                    .font(selection.isEmpty ? .body : .custom(selection, size: 13))
                    .foregroundStyle(selection.isEmpty ? .secondary : .primary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .frame(width: 280, height: 28)
            .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isPresented, arrowEdge: .trailing) {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField(language.pick(zh: "搜索已安装字体", en: "Search Installed Fonts"), text: $query)
                        .textFieldStyle(.plain)
                }
                .padding(.horizontal, 12)
                .frame(height: 38)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 9))
                .padding(10)

                Divider()

                ScrollView {
                    LazyVStack(spacing: 2) {
                        if filteredOptions.isEmpty {
                            VStack(spacing: 8) {
                                Image(systemName: "text.magnifyingglass")
                                    .font(.title2)
                                    .foregroundStyle(.secondary)
                                Text(language.pick(zh: "没有匹配字体", en: "No Matching Fonts"))
                                    .font(.headline)
                                Text(language.pick(
                                    zh: "可搜索字体家族名、显示名或 PostScript 名称。",
                                    en: "Search by font family, display name, or PostScript name."
                                ))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(height: 180)
                        } else {
                            ForEach(filteredOptions) { option in
                                Button {
                                    selection = option.familyName
                                    isPresented = false
                                } label: {
                                    HStack(spacing: 10) {
                                        Group {
                                            if selection == option.familyName {
                                                Image(systemName: "checkmark")
                                                    .foregroundStyle(accentColor)
                                            } else {
                                                Color.clear
                                            }
                                        }
                                        .frame(width: 14, height: 14)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(option.familyName)
                                                .font(.custom(option.familyName, size: 14))
                                                .foregroundStyle(.primary)
                                            if option.displayName != option.familyName {
                                                Text(option.displayName)
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                        Spacer()
                                    }
                                    .padding(.horizontal, 12)
                                    .frame(height: 42)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .background(
                                    selection == option.familyName
                                        ? accentColor.opacity(0.10)
                                        : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 8)
                                )
                            }
                        }
                    }
                    .padding(8)
                }
            }
            .frame(width: 360, height: 420)
            .preferredColorScheme(.dark)
        }
    }

    private var filteredOptions: [LyrisInstalledFontOption] {
        LyrisInstalledFontCatalog.filteredOptions(options, query: query)
    }
}
