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
                ProgressView("正在载入 Lyris 设置…")
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
                    .tabItem { Label("语言", systemImage: "character.book.closed") }
                    .tag(SettingsSection.language)
                spotifyPane
                    .tabItem { Label("Spotify", systemImage: "music.note") }
                    .tag(SettingsSection.spotify)
                translationPane
                    .tabItem { Label("翻译", systemImage: "character.bubble") }
                    .tag(SettingsSection.translation)
                appearancePane
                    .tabItem { Label("外观", systemImage: "sparkles") }
                    .tag(SettingsSection.appearance)
                windowPane
                    .tabItem { Label("显示", systemImage: "rectangle.on.rectangle") }
                    .tag(SettingsSection.window)
                usagePane
                    .tabItem { Label("用量", systemImage: "chart.bar.xaxis") }
                    .tag(SettingsSection.usage)
                storagePane
                    .tabItem { Label("存储", systemImage: "externaldrive") }
                    .tag(SettingsSection.storage)
            }
        }
        .tint(store.interfaceSkin.accentColor)
        .frame(minWidth: 760, minHeight: 520)
    }

    private var languagePane: some View {
        Form {
            Section("语言与歌词") {
                Picker("界面语言", selection: Binding(
                    get: { store.interfaceLanguage },
                    set: { store.updateInterfaceLanguage($0) }
                )) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.displayName).tag(language)
                    }
                }

                Picker("翻译目标", selection: Binding(
                    get: { store.translationTarget },
                    set: { store.updateTranslationTarget($0) }
                )) {
                    ForEach(TranslationTargetLanguage.allCases) { target in
                        Text(target.displayName(in: store.interfaceLanguage)).tag(target)
                    }
                }

                Picker("译文字体", selection: Binding(
                    get: { store.translationFont },
                    set: { store.updateTranslationFont($0) }
                )) {
                    ForEach(TranslationFontChoice.allCases) { font in
                        Text(font.displayName(in: store.interfaceLanguage)).tag(font)
                    }
                }

                if store.translationFont == .custom {
                    LabeledContent("已安装字体") {
                        LyrisInstalledFontPicker(
                            selection: Binding(
                                get: { store.customTranslationFontFamily },
                                set: { store.updateCustomTranslationFontFamily($0) }
                            ),
                            options: store.availableTranslationFontOptions,
                            accentColor: store.interfaceSkin.accentColor
                        )
                    }
                }

                HStack {
                    Button("使用系统推荐：\(recommendedFont.displayName)") {
                        store.applyRecommendedTranslationFont()
                    }
                    Button("添加 .ttf / .otf 字体…") {
                        store.importTranslationFont()
                    }
                }

                Toggle("繁体中文歌词默认转换为简体", isOn: Binding(
                    get: { store.convertsTraditionalChineseToSimplified },
                    set: { store.updateTraditionalChineseConversion($0) }
                ))
                Text("原文与目标语言相同时不重复调用翻译；副行会改为显示下一句歌词。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section {
                Text("界面语言、翻译目标和字体只影响显示，不改变歌词来源。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    private var appearancePane: some View {
        Form {
            Section("界面皮肤") {
                Picker("皮肤", selection: Binding(
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

                Text("Spotify 官方客户端支持 Canvas，但当前 Web API 与 Web Playback SDK 都未公开 Canvas 视频字段；OAuth 授权也不会增加该字段。Lyris 使用稳定的本机封面呈现，不提供容易造成误解的 Canvas 切换。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("顶部与氛围") {
                Picker("呈现模式", selection: Binding(
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

                Picker("联动效果", selection: Binding(
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

            Section("灵动岛") {
                Picker("呈现模式", selection: Binding(
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

                Picker("收起状态歌词", selection: Binding(
                    get: { store.menuBarLyricMode },
                    set: { store.updateMenuBarLyricMode($0) }
                )) {
                    ForEach(MenuBarLyricMode.allCases) { mode in
                        Text(mode.displayName(in: store.interfaceLanguage)).tag(mode)
                    }
                }

                Picker("展开保留时间", selection: Binding(
                    get: { store.macIslandExpandedHoldDuration },
                    set: { store.updateMacIslandExpandedHoldDuration($0) }
                )) {
                    ForEach(MacIslandExpandedHoldDuration.allCases) { duration in
                        Text(duration.displayName(in: store.interfaceLanguage)).tag(duration)
                    }
                }

                Picker("展开触发方式", selection: Binding(
                    get: { store.macIslandExpansionTrigger },
                    set: { store.updateMacIslandExpansionTrigger($0) }
                )) {
                    ForEach(MacIslandExpansionTrigger.allCases) { trigger in
                        Text(trigger.displayName(in: store.interfaceLanguage)).tag(trigger)
                    }
                }

                if store.macIslandExpansionTrigger.allowsHover {
                    HStack {
                        Text("悬停展开延迟")
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
                                ? "立即"
                                : String(format: "%.1f 秒", store.macIslandHoverExpandDelay)
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
                    Text("歌词校准")
                    Slider(
                        value: Binding(
                            get: { store.lyricTimingDelay },
                            set: { store.updateLyricTimingDelay($0) }
                        ),
                        in: -3...3,
                        step: 0.1
                    )
                    Text(String(format: "%+.1f 秒", store.lyricTimingDelay))
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 72, alignment: .trailing)
                }
                Text("正值让歌词更晚出现，负值让歌词更早出现；调整会同时作用于灵动岛、悬浮条和桌面歌词。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Text("菜单栏只保留小型 Lyris 入口；歌名与当前歌词由收起状态的灵动岛显示。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    private var usagePane: some View {
        Form {
            Section("今日用量") {
                LabeledContent("翻译服务", value: store.translationProvider.displayName(in: store.interfaceLanguage))
                LabeledContent("模型", value: store.translationModel)
                LabeledContent("API 请求", value: "\(store.apiRequestCount)")
                LabeledContent("已翻译歌词", value: "\(store.translatedLineCount) 行")
                LabeledContent("估算 Token", value: "\(store.estimatedInputTokenCount + store.estimatedOutputTokenCount)")
                LabeledContent("预估费用", value: store.estimatedAPICostFormatted)
            }

            Section("价格与币种") {
                Picker("显示币种", selection: Binding(
                    get: { store.costCurrency },
                    set: { store.updateCostCurrency($0) }
                )) {
                    ForEach(CostCurrency.allCases) { currency in
                        Text(currency.displayName(in: store.interfaceLanguage)).tag(currency)
                    }
                }

                if store.costCurrency != .usd {
                    TextField(
                        "每 1 USD 对应币种数量",
                        value: Binding(
                            get: { store.costCurrencyUnitsPerUSD },
                            set: { store.updateCostCurrencyUnitsPerUSD($0) }
                        ),
                        format: .number.precision(.fractionLength(2...6))
                    )
                    Text("汇率仅用于本机显示，可按当前账单汇率手动修改。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    TextField(
                        "输入单价 / 百万 Token",
                        value: Binding(
                            get: { store.translationInputPriceInSelectedCurrency },
                            set: { store.updateTranslationInputPriceInSelectedCurrency($0) }
                        ),
                        format: .number.precision(.fractionLength(0...6))
                    )
                    TextField(
                        "输出单价 / 百万 Token",
                        value: Binding(
                            get: { store.translationOutputPriceInSelectedCurrency },
                            set: { store.updateTranslationOutputPriceInSelectedCurrency($0) }
                        ),
                        format: .number.precision(.fractionLength(0...6))
                    )
                }

                HStack {
                    Button(store.isRefreshingOfficialPricing ? "正在联网匹配…" : "联网匹配官方参考价") {
                        store.refreshTranslationPricingFromOfficialSource()
                    }
                    .disabled(store.isRefreshingOfficialPricing)
                    Button("打开官方价格页") { store.openOfficialTranslationPricing() }
                        .disabled(store.translationPricingReference.sourceURL == nil)
                }

                if let status = store.officialPricingStatus {
                    Text(status)
                        .font(.callout)
                        .foregroundStyle(store.interfaceSkin.accentColor)
                }

                Text("参考价核对日期：\(store.translationPricingReference.verifiedDate)。\(store.translationPricingReference.note)。价格可手动覆盖；费用为本机估算值，不代表服务商正式账单。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    private var spotifyPane: some View {
        Form {
            Section("账户增强") {
                Text("本机播放不需要账户授权；跨设备播放状态和收藏同步需要 Spotify PKCE。")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Text("Client ID 来自这台 Mac 的本地 Lyris 配置，不会打包进 App。重新下载或替换相同 Bundle ID 的 Lyris 时，macOS 会继续恢复这份本机设置。")
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
                    .help(revealsSpotifyClientID ? "隐藏 Client ID" : "显示 Client ID")
                }

                LabeledContent("连接状态", value: store.spotifyConnectionStatus)

                HStack {
                    Button("仅保存 Client ID") { store.saveSpotifyConfiguration() }
                    Button(store.isAuthorizingSpotify ? "取消等待" : "保存并开始授权") {
                        if store.isAuthorizingSpotify {
                            store.cancelSpotifyAuthorization()
                        } else {
                            store.authorizeSpotify()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            Section("如何获取 Client ID") {
                Text("1. 打开 Spotify Developer Dashboard，新建或选择一个应用。")
                Text("2. 在应用设置中加入下面的 Redirect URI，必须逐字一致。")
                HStack {
                    Text(LyrisStore.spotifyRedirectURI)
                        .font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)
                    Spacer()
                    Button("复制") { store.copyRedirectURI() }
                }
                Text("3. 复制应用的 Client ID，粘贴到上方并开始 PKCE 授权。")
                HStack {
                    Button("打开 Developer Dashboard") { store.openSpotifyDashboard() }
                    Spacer()
                }
                Text("桌面应用无法安全保管 Client Secret。Lyris 使用 Spotify 官方推荐的 PKCE 流程，因此不会要求或保存 Client Secret。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if let status = store.configurationStatus, !status.isEmpty {
                Section("状态") {
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
            Section("翻译服务") {
                Picker("服务", selection: Binding(
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
                    Picker("模型", selection: Binding(
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
                    Text("已从当前翻译服务读取 \(store.availableTranslationModels.count) 个可用模型。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    TextField("模型", text: Binding(
                        get: { store.translationModel },
                        set: { store.updateTranslationModelDraft($0) }
                    ))
                    .textFieldStyle(.roundedBorder)
                    Text("测试连接后，服务返回的模型会在这里改为下拉选择。")
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
                        Button("读取本机已保存的 API Key") {
                            store.authorizeSavedTranslationCredential()
                        }
                        .buttonStyle(.bordered)

                        Text("只有点击这里才会请求登录钥匙串权限；请选择“始终允许”，本正式版本后续启动将不再重复询问。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Picker("翻译方式", selection: Binding(
                    get: { store.translationStyle },
                    set: { store.updateTranslationStyle($0) }
                )) {
                    ForEach(LyricsTranslationStyle.allCases) { style in
                        Text(style.displayName(in: store.interfaceLanguage)).tag(style)
                    }
                }

                Toggle("思考模式", isOn: Binding(
                    get: { store.translationThinkingEnabled },
                    set: { store.updateTranslationThinkingDraft($0) }
                ))

                HStack {
                    Button("保存配置") { store.saveTranslationConfiguration() }
                    Button(store.isTestingTranslation ? "测试中…" : "测试连接并读取模型") {
                        store.testTranslationConnection()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(store.isTestingTranslation)
                }
            }

            if let status = store.configurationStatus, !status.isEmpty {
                Section("状态") {
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
                LabeledContent("歌词库", value: "\(store.storageUsage.cachedLyricCount) 个文件 · \(store.storageUsage.formattedLyricsBytes)")
                LabeledContent("封面与网络缓存", value: store.storageUsage.formattedNetworkCacheBytes)

                HStack {
                    Button("刷新占用") { store.refreshStorageUsage() }
                    Button("在访达中打开") { store.openLocalDataFolder() }
                }
            }

            Section("分目录管理") {
                HStack {
                    Button("打开歌词库") { store.openLyricsFolder() }
                    Button("清除自动歌词缓存") { store.clearGeneratedLyricsCache() }
                }
                HStack {
                    Button("打开缓存目录") { store.openCacheFolder() }
                    Button("清除封面/网络缓存") { store.clearArtworkCache() }
                }
            }

            if let status = store.cacheStatus, !status.isEmpty {
                Section("状态") {
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
}

private struct LyrisInstalledFontPicker: View {
    @Binding var selection: String
    let options: [LyrisInstalledFontOption]
    let accentColor: Color

    @State private var isPresented = false
    @State private var query = ""

    var body: some View {
        Button {
            isPresented = true
        } label: {
            HStack(spacing: 10) {
                Text(selection.isEmpty ? "请选择字体" : selection)
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
                    TextField("搜索已安装字体", text: $query)
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
                                Text("没有匹配字体")
                                    .font(.headline)
                                Text("可搜索字体家族名、显示名或 PostScript 名称。")
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
