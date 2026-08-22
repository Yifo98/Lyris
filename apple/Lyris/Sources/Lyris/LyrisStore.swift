import AppKit
import CoreText
import Foundation
import SwiftUI
import UniformTypeIdentifiers

enum LyricLRCExportPreparation: Equatable, Sendable {
    case ready(LyricLRCExportResult)
    case requiresExplicitEstimation(lineNumbers: [Int])
    case requiresLossConfirmation(LyricLRCExportResult)
}

enum LyricLRCUIWorkflow {
    static func prepareExport(
        document: LyricDocument,
        trackDuration: TimeInterval,
        estimateUntimedLines: Bool
    ) throws -> LyricLRCExportPreparation {
        let options = LyricLRCExportOptions(
            untimedLineStrategy: estimateUntimedLines
                ? .estimateEvenly(duration: trackDuration)
                : .reject
        )
        do {
            let result = try LyricLRCFileCodec.encode(document: document, options: options)
            return result.warnings.isEmpty
                ? .ready(result)
                : .requiresLossConfirmation(result)
        } catch LyricLRCFileError.untimedLines(let lineNumbers) where !estimateUntimedLines {
            return .requiresExplicitEstimation(lineNumbers: lineNumbers)
        }
    }

    static func importIssueMessage(
        _ issues: [LyricLRCImportIssue],
        language: AppLanguage
    ) -> String {
        issues.map { issue in
            let reason = switch issue.kind {
            case .missingTimestamp:
                language.pick(
                    zh: "缺少 [mm:ss.xx] 时间戳。",
                    en: "Missing [mm:ss.xx] timestamp."
                )
            case .invalidTimestamp:
                language.pick(
                    zh: "时间戳无效，请使用 [mm:ss.xx]。",
                    en: "Invalid timestamp; use [mm:ss.xx]."
                )
            case .missingLyricText:
                language.pick(
                    zh: "时间戳后缺少歌词正文。",
                    en: "Missing lyric text after the timestamp."
                )
            }
            return language.pick(
                zh: "第 \(issue.lineNumber) 行：\(reason)",
                en: "Line \(issue.lineNumber): \(reason)"
            )
        }
        .joined(separator: "\n")
    }

    static func exportWarningMessage(
        _ warnings: [LyricLRCExportWarning],
        language: AppLanguage
    ) -> String {
        warnings.map { warning in
            let lines = warning.lineNumbers.map(String.init).joined(separator: ", ")
            switch warning.kind {
            case .wordTimingFlattened:
                return language.pick(
                    zh: "第 \(lines) 行：逐字时间将降级为逐行时间。",
                    en: "Line \(lines): Word timing will be flattened to line timing."
                )
            case .estimatedTimingExportedAsLineTiming:
                return language.pick(
                    zh: "第 \(lines) 行：估算时间将写成普通 LRC 时间戳。",
                    en: "Line \(lines): Estimated timing will be written as ordinary LRC timestamps."
                )
            case .untimedLinesEstimated:
                return language.pick(
                    zh: "第 \(lines) 行：将按当前歌曲时长均匀估时。",
                    en: "Line \(lines): Timing will be estimated evenly from the current track duration."
                )
            }
        }
        .joined(separator: "\n")
    }
}

enum LyricLRCAlertPurpose: Equatable {
    case notice
    case estimateUntimedAndExport
    case confirmLossyExport
}

struct LyricLRCAlertModel: Identifiable, Equatable {
    let id: UInt64
    let purpose: LyricLRCAlertPurpose
    let title: String
    let message: String
    let primaryButtonTitle: String
    let cancelButtonTitle: String?
}

@MainActor
final class LyrisStore: ObservableObject {
    private struct PendingLRCExport {
        let result: LyricLRCExportResult
        let trackID: String
        let suggestedFilename: String
    }

    private struct PendingLRCExportEstimation {
        let document: LyricDocument
        let track: Track
    }

    private struct LyricsLoadContext: Equatable {
        let target: TranslationTargetLanguage
        let provider: TranslationProvider
        let baseURL: String
        let model: String
        let thinkingEnabled: Bool
        let translationStyle: LyricsTranslationStyle
        let apiKey: String

        var translationConfiguration: TranslationConfiguration {
            TranslationConfiguration(
                provider: provider,
                baseURL: baseURL,
                model: model,
                thinkingEnabled: thinkingEnabled,
                style: translationStyle
            )
        }
    }

    @Published private(set) var playback: PlaybackSnapshot
    @Published private(set) var lyrics: [TimedLyric] = []
    @Published private(set) var lyricPipelineStatus: String?
    @Published private(set) var lyricsPipelineState: LyricsPipelineState = .idle
    @Published private(set) var apiRequestCount = 0
    @Published private(set) var apiSuccessCount = 0
    @Published private(set) var apiFailureCount = 0
    @Published private(set) var translatedLineCount = 0
    @Published private(set) var translationCacheHits = 0
    @Published private(set) var lastAPILatencyMilliseconds: Int?
    @Published private(set) var estimatedInputTokenCount = 0
    @Published private(set) var estimatedOutputTokenCount = 0
    @Published private(set) var estimatedAPICostUSD: Double = 0
    @Published private(set) var costCurrency: CostCurrency = .cny
    @Published private(set) var costCurrencyUnitsPerUSD: Double = 1
    @Published var manualLyricsDraft = ""
    @Published private(set) var cacheStatus: String?
    @Published private(set) var storageUsage = LyrisStorageUsage.empty
    @Published private(set) var isRefreshingStorageUsage = false
    @Published private(set) var lrcFileAlert: LyricLRCAlertModel?
    @Published private(set) var isLRCFileOperationInProgress = false
    @Published var displayMode: LyricDisplayMode = .bilingual
    @Published var cardMode: CardMode = .capsule
    @Published private(set) var floatingPresentationMode: FloatingPresentationMode = .topIsland
    @Published private(set) var isTopIslandExpanded = false
    @Published var macIslandExpandedHoldDuration: MacIslandExpandedHoldDuration = .balanced
    @Published private(set) var macIslandExpansionTrigger: MacIslandExpansionTrigger = .hoverAndClick
    @Published private(set) var macIslandHoverExpandDelay: Double = 3
    @Published var linkedEffectStyle: LinkedEffectStyle = .aurora
    @Published var lyricTimingDelay: Double = 0
    @Published var interfaceLanguage: AppLanguage = .simplifiedChinese
    @Published var translationTarget: TranslationTargetLanguage = .simplifiedChinese
    @Published var translationFont: TranslationFontChoice = .rounded
    @Published private(set) var customTranslationFontFamily = ""
    @Published private(set) var interfaceSkin: LyrisInterfaceSkin = .midnightAurora
    @Published private(set) var artworkPresentationMode: LyrisArtworkPresentationMode = .staticArtwork
    @Published private(set) var convertsTraditionalChineseToSimplified = true
    @Published private(set) var fontLibraryRevision = 0
    @Published private(set) var availableTranslationFontOptions: [LyrisInstalledFontOption] = []
    @Published var menuBarLyricMode: MenuBarLyricMode = .translated
    @Published var presentation: WindowPresentation = .card
    @Published var isLocked = false
    @Published var settingsSection: SettingsSection = .spotify
    @Published private(set) var firstUseState = FirstUseFlowState()

    @Published var spotifyClientID = ""
    @Published private(set) var spotifyConnectionStatus = ""
    @Published private(set) var isSpotifyConnected = false
    @Published private(set) var isAuthorizingSpotify = false
    @Published private(set) var spotifyAuthorizationState: SpotifyAuthorizationState = .disconnected
    @Published var translationProvider: TranslationProvider = .deepSeek
    @Published var translationBaseURL = TranslationProvider.deepSeek.defaultBaseURL
    @Published var translationModel = TranslationProvider.deepSeek.defaultModel
    @Published var translationAPIKey = ""
    @Published var translationThinkingEnabled = false
    @Published var translationStyle: LyricsTranslationStyle = .contextual
    @Published var translationInputPriceUSDPerMillion = 0.14
    @Published var translationOutputPriceUSDPerMillion = 0.28
    @Published private(set) var isRefreshingOfficialPricing = false
    @Published private(set) var officialPricingStatus: String?
    @Published private(set) var availableTranslationModels: [String] = []
    @Published private(set) var isTestingTranslation = false
    @Published private(set) var isTranslationConnected = false
    @Published private(set) var translationCredentialRequiresAuthorization = false
    @Published var configurationStatus: String?

    var onHideRequested: (() -> Void)?
    var onQuitRequested: (() -> Void)?
    var onSpotifyAccountStateRefreshRequested: (() -> Void)?
    var onSettingsRequested: ((SettingsSection) -> Void)?
    var onMainWindowRequested: (() -> Void)?

    private let playbackAdapter: PlaybackAdapting
    private let lyricsProvider: LyricsProviding
    private let translationAdapter: TranslationProviding
    private let spotifyAuthorizer: SpotifyAuthorizing
    private let credentialVault: CredentialVault
    private let lyricsCacheStore: LyricsCaching
    private let translationOverrideCoordinator: UserTranslationOverrideCoordinator
    private let asyncTranslationCoordinator = AsyncTranslationCoordinator()
    private let defaults: UserDefaults
    private let lyricsRetryMinimumDelay: TimeInterval
    private var spotifyAuthorizationTask: Task<Void, Never>?
    private var spotifyRestoreTask: Task<Void, Never>?
    private var spotifyConnectionGeneration: UInt64 = 0
    private var likedIntentCoordinator = LyrisLikedIntentCoordinator()
    private var lyricLoadTask: Task<Void, Never>?
    private var lyricLoadGeneration: UInt64 = 0
    private var lyricRetryTask: Task<Void, Never>?
    private var lyricRetryGate = LyricsRetryGate()
    private var translationTestTask: Task<Void, Never>?
    private var translationTestGeneration: UInt64 = 0
    private var officialPricingTask: Task<Void, Never>?
    private var translationCredentialRestoreTask: Task<Void, Never>?
    private var lyricCache: [LyricsCacheFingerprint: [TimedLyric]] = [:]
    private var baseTranslationsByLineID: [UUID: String] = [:]
    private var overrideKeysByLineID: [UUID: UserTranslationOverrideKey] = [:]
    private var presentedLyricsTrackID: String?
    private var presentedLyricDocument: LyricDocument?
    private var firstUseSetupReturnStep: FirstUseStep?
    private var lrcFileOperationGeneration: UInt64 = 0
    private var lrcAlertSequence: UInt64 = 0
    private var pendingLRCExport: PendingLRCExport?
    private var pendingLRCExportEstimation: PendingLRCExportEstimation?

    private static let firstUseStateKey = "firstUseFlowState.v1"

    private static var lyricsCacheAppVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "0.2.0-dev"
    }

    init(
        playbackAdapter: PlaybackAdapting,
        lyricsProvider: LyricsProviding,
        translationAdapter: TranslationProviding,
        spotifyAuthorizer: SpotifyAuthorizing,
        credentialVault: CredentialVault,
        lyricsCacheStore: LyricsCaching = LyricsDiskCache(),
        translationOverrideStore: UserTranslationOverrideStoring = UserTranslationOverrideDiskStore(),
        defaults: UserDefaults = .standard,
        lyricsRetryMinimumDelay: TimeInterval = 1
    ) {
        self.playbackAdapter = playbackAdapter
        self.lyricsProvider = lyricsProvider
        self.translationAdapter = translationAdapter
        self.spotifyAuthorizer = spotifyAuthorizer
        self.credentialVault = credentialVault
        self.lyricsCacheStore = lyricsCacheStore
        translationOverrideCoordinator = UserTranslationOverrideCoordinator(
            store: translationOverrideStore
        )
        self.defaults = defaults
        self.lyricsRetryMinimumDelay = max(0, lyricsRetryMinimumDelay)
        let initialLanguage = LyrisDisplayPreferences.load(from: defaults).interfaceLanguage
        playback = PlaybackSnapshot(
            track: Track(
                id: "loading",
                title: initialLanguage.pick(zh: "正在连接", en: "Connecting"),
                artist: "Lyris",
                album: "",
                duration: 1
            ),
            position: 0,
            isPlaying: false,
            isLiked: false,
            isShuffled: false,
            repeatMode: .off,
            capabilities: [],
            source: .unavailable
        )

        restorePreferences()
        refreshAvailableTranslationFonts()
        restoreFirstUseState()
        if firstUseState.isFirstUse {
            presentation = .firstUse
        }
        playbackAdapter.onSnapshot = { [weak self] snapshot in
            Task { @MainActor in
                guard let self else { return }
                let shouldReloadLyrics = LyrisLyricsReloadPolicy.shouldReload(
                    previous: self.playback,
                    next: snapshot,
                    currentlyHasLyrics: !self.lyrics.isEmpty
                )
                self.playback = snapshot
                self.resolvePendingLikedToggle(with: snapshot)
                if shouldReloadLyrics {
                    self.lyrics = []
                    self.resetPresentedLyricsMetadata()
                    self.lyricPipelineStatus = snapshot.track.id == "spotify:idle"
                        ? nil
                        : self.localized(zh: "正在获取歌词…", en: "Loading lyrics…")
                    self.startLyricsLoad(for: snapshot.track)
                }
            }
        }
        playbackAdapter.onAuthorizationState = { [weak self] state in
            self?.applySpotifyAuthorizationState(state)
        }
        playbackAdapter.start()
        if hasStoredTranslationCredentialMetadata(for: translationProvider) {
            restoreTranslationCredential(for: translationProvider)
        }
        restoreSpotifyConnectionIfPossible()
    }

    var windowSize: CGSize {
        presentation.logicalSize(cardMode: cardMode)
    }

    var activeLyricIndex: Int {
        LyrisLyricLineProgress.activeIndex(
            position: playback.position,
            timingDelay: lyricTimingDelay,
            lyrics: lyrics
        ) ?? 0
    }

    var activeLyric: TimedLyric? {
        lyrics.indices.contains(activeLyricIndex) ? lyrics[activeLyricIndex] : nil
    }

    var activeLyricTimelineProgress: Double {
        LyrisLyricLineProgress.value(
            position: playback.position,
            timingDelay: lyricTimingDelay,
            lyrics: lyrics,
            trackDuration: playback.track.duration
        )
    }

    var activeLyricProgress: Double {
        guard let activeLyric else { return 0 }
        guard let sourceLine = presentedLyricDocument?.lines.first(where: {
                  $0.id == activeLyric.id
              }) else {
            return 1
        }
        return LyrisLyricTextProgress.value(
            position: playback.position,
            timingDelay: lyricTimingDelay,
            line: sourceLine,
            fallback: 1
        )
    }

    func displayedTranslation(for lyric: TimedLyric) -> String? {
        let storedTranslation = lyric.translation
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !storedTranslation.isEmpty {
            return lyric.translation
        }
        let sourceLines = lyrics.isEmpty
            ? [lyric.original]
            : lyrics.map(\.original)
        guard LyricsTranslationDecision.sourceAlreadyMatchesTarget(
            lines: sourceLines,
            target: translationTarget
        ) else {
            return nil
        }
        // Same-language lyrics need no translation request. Returning the
        // original here produced a duplicate row which the UI then hid,
        // leaving an apparently broken blank subtitle.
        return nil
    }

    func displayedOriginal(for lyric: TimedLyric) -> String {
        LyrisLyricDisplayPolicy.originalText(
            lyric.original,
            convertsTraditionalChineseToSimplified: convertsTraditionalChineseToSimplified
        )
    }

    func secondaryIslandLyric(
        for lyric: TimedLyric,
        showsAdjacentLyrics: Bool = true
    ) -> String? {
        LyrisLyricDisplayPolicy.secondaryText(
            for: lyric,
            in: lyrics,
            translatedText: displayedTranslation(for: lyric),
            convertsTraditionalChineseToSimplified: convertsTraditionalChineseToSimplified,
            showsAdjacentLyrics: showsAdjacentLyrics
        )
    }

    var progress: Double {
        LyrisPlaybackProgress.value(
            position: playback.position,
            duration: playback.track.duration
        )
    }

    var apiUsageSummary: String {
        interfaceLanguage.pick(
            zh: "今日 \(apiRequestCount) 次 · \(translatedLineCount) 行",
            en: "Today \(apiRequestCount) requests · \(translatedLineCount) lines"
        )
    }

    var estimatedTokenCount: Int {
        estimatedInputTokenCount + estimatedOutputTokenCount
    }

    var estimatedAPICostFormatted: String {
        costCurrency.formatted(
            usdValue: estimatedAPICostUSD,
            unitsPerUSD: costCurrencyUnitsPerUSD
        )
    }

    var translationInputPriceInSelectedCurrency: Double {
        costCurrency.convertFromUSD(
            translationInputPriceUSDPerMillion,
            unitsPerUSD: costCurrencyUnitsPerUSD
        )
    }

    var translationOutputPriceInSelectedCurrency: Double {
        costCurrency.convertFromUSD(
            translationOutputPriceUSDPerMillion,
            unitsPerUSD: costCurrencyUnitsPerUSD
        )
    }

    var activeTranslationPricing: TranslationPricingRates {
        TranslationPricingRates(
            inputUSDPerMillion: max(0, translationInputPriceUSDPerMillion),
            outputUSDPerMillion: max(0, translationOutputPriceUSDPerMillion)
        )
    }

    var playbackSourceSummary: String {
        switch playback.source {
        case .local:
            localized(zh: "本地伴侣 · 无需账户", en: "Local Companion · no account required")
        case .hybrid:
            localized(zh: "本地播放 + 账户增强", en: "Local playback + account enhancements")
        case .web:
            localized(zh: "Spotify 账户远程播放", en: "Spotify account remote playback")
        case .demo:
            localized(zh: "演示数据", en: "Demo data")
        case .unavailable:
            localized(zh: "正在等待本机 Spotify", en: "Waiting for Spotify on this Mac")
        case .unknown:
            localized(zh: "正在识别播放来源", en: "Detecting playback source")
        }
    }

    var localCompanionStatus: String {
        switch playback.source {
        case .local, .hybrid:
            localized(
                zh: "已识别 · \(playback.track.title)",
                en: "Detected · \(playback.track.title)"
            )
        case .web:
            localized(
                zh: "本机未识别；当前使用账户远程状态",
                en: "Local playback unavailable; using remote account state"
            )
        case .demo:
            localized(zh: "演示模式", en: "Demo mode")
        case .unavailable, .unknown:
            playback.track.title
        }
    }

    var firstUseLocalReadiness: LocalLyricsReadiness {
        if playback.track.id != "spotify:idle" {
            if !lyrics.isEmpty { return .displayed }
            if case .loading = lyricsPipelineState { return .searchingLyrics }
            return .recognized
        }
        let message = playback.track.title
        if message.contains("未安装") { return .notInstalled }
        if message.contains("尚未运行") { return .notRunning }
        if message.contains("没有正在播放") || message.contains("未在播放") {
            return .notPlaying
        }
        return .notRunning
    }

    func localized(zh: String, en: String) -> String {
        interfaceLanguage.pick(zh: zh, en: en)
    }

    var canImportLRCFile: Bool {
        playback.track.kind == .track
            && playback.track.id != "loading"
            && playback.track.id != "spotify:idle"
            && !isLRCFileOperationInProgress
    }

    var canExportLRCFile: Bool {
        canImportLRCFile && !lyrics.isEmpty
    }

    func send(_ command: PlaybackCommand) {
        playbackAdapter.send(command)
    }

    var likedControlAction: LyrisLikedControlAction {
        LyrisLikedControlPolicy.action(
            authorizationState: spotifyAuthorizationState,
            capabilities: playback.capabilities,
            likedState: playback.likedState
        )
    }

    func handleLikedControlTap() {
        switch likedControlAction {
        case .toggle:
            likedIntentCoordinator.cancel()
            playbackAdapter.send(.toggleLiked)
        case .refreshThenToggle:
            let trackID = canonicalTrackID(playback.track.id)
            guard !trackID.isEmpty,
                  trackID != "spotify:idle",
                  trackID != "loading" else {
                onSpotifyAccountStateRefreshRequested?()
                return
            }
            likedIntentCoordinator.begin(trackID: trackID)
            playback.likedState = .checking(
                lastKnown: playback.likedState.displayedValue
            )
            onSpotifyAccountStateRefreshRequested?()
        case .openSpotifySettings:
            likedIntentCoordinator.cancel()
            showSettings(.spotify)
        }
    }

    func seek(to position: TimeInterval) {
        playbackAdapter.send(.seek(position))
    }

    func retryLyrics() {
        guard lyricsPipelineState.canRetry,
              lyricsPipelineState.trackID == playback.track.id,
              playback.track.id != "spotify:idle" else { return }
        lyrics = []
        lyricPipelineStatus = localized(zh: "正在重试歌词…", en: "Retrying lyrics…")
        startLyricsLoad(for: playback.track)
    }

    private func resolvePendingLikedToggle(with snapshot: PlaybackSnapshot) {
        guard likedIntentCoordinator.shouldToggle(
            trackID: canonicalTrackID(snapshot.track.id),
            capabilities: snapshot.capabilities,
            likedState: snapshot.likedState
        ) else { return }
        playbackAdapter.send(.toggleLiked)
    }

    private func canonicalTrackID(_ trackID: String) -> String {
        SpotifyTrackURI.canonical(trackID) ?? trackID
    }

    func toggleLock() {
        isLocked.toggle()
    }

    func showCard() {
        if firstUseSetupReturnStep != nil, firstUseState.isFirstUse {
            firstUseSetupReturnStep = nil
            presentation = .firstUse
            return
        }
        presentation = .card
    }

    func continueFirstUseLocalLyrics() {
        _ = firstUseState.transition(.continueFromLocalLyrics)
        persistFirstUseState()
    }

    func continueFirstUseStatusDetection() {
        _ = firstUseState.transition(.localStatusChanged(firstUseLocalReadiness))
        _ = firstUseState.transition(.continueFromStatusDetection)
        persistFirstUseState()
    }

    func configureFirstUseAccount() {
        guard firstUseState.transition(.requestAccountEnhancement) == .presentAccountSetup else { return }
        firstUseSetupReturnStep = .accountEnhancement
        showSettings(.spotify)
    }

    func skipFirstUseAccount() {
        _ = firstUseState.transition(.skipAccountEnhancement)
        persistFirstUseState()
    }

    func configureFirstUseTranslation() {
        guard firstUseState.transition(.requestTranslation) == .presentTranslationSetup else { return }
        firstUseSetupReturnStep = .translation
        showSettings(.translation)
    }

    func skipFirstUseTranslation() {
        let effect = firstUseState.transition(.skipTranslation)
        persistFirstUseState()
        if effect == .finished {
            firstUseSetupReturnStep = nil
            presentation = .card
        }
    }

    func finishFirstUseLater() {
        _ = firstUseState.transition(.finishLater)
        persistFirstUseState()
        firstUseSetupReturnStep = nil
        presentation = .card
    }

    func showFirstUse() {
        guard firstUseState.isFirstUse else { return }
        presentation = .firstUse
    }

    func showMenu() {
        presentation = .menu
    }

    func showLyrics() {
        presentation = .lyricsFull
    }

    func toggleLyricsReader() {
        presentation = presentation == .lyricsFull ? .lyricsPartial : .lyricsFull
    }

    func showTranslationEditor() {
        presentation = .translationEditor
    }

    func showManualLyricsEditor() {
        manualLyricsDraft = lyrics.map { line in
            let minutes = Int(line.startTime) / 60
            let seconds = line.startTime - Double(minutes * 60)
            let translation = line.translation.isEmpty ? "" : " || \(line.translation)"
            return String(format: "[%02d:%05.2f] %@%@", minutes, seconds, line.original, translation)
        }.joined(separator: "\n")
        presentation = .manualLyricsEditor
    }

    func importLRCFile() {
        guard canImportLRCFile else {
            presentLRCNotice(
                title: localized(zh: "无法导入歌词", en: "Cannot Import Lyrics"),
                message: localized(
                    zh: "请先在 Spotify 播放一首可识别的歌曲。",
                    en: "Play a recognized track in Spotify first."
                )
            )
            return
        }
        let expectedTrack = playback.track
        guard let lrcType = UTType(
            filenameExtension: LyricLRCFileCodec.preferredFilenameExtension
        ) else {
            presentLRCNotice(
                title: localized(zh: "无法打开文件选择器", en: "Cannot Open File Picker"),
                message: localized(
                    zh: "系统无法识别 LRC 文件类型。",
                    en: "macOS could not register the LRC file type."
                )
            )
            return
        }
        isLRCFileOperationInProgress = true
        let panel = NSOpenPanel()
        panel.title = localized(zh: "导入 LRC 歌词", en: "Import LRC Lyrics")
        panel.prompt = localized(zh: "导入", en: "Import")
        panel.message = localized(
            zh: "只接受 UTF-8 编码的 .lrc 文件。发现无效行时不会静默保存。",
            en: "Only UTF-8 .lrc files are accepted. Files with invalid lines are never saved silently."
        )
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowsOtherFileTypes = false
        panel.allowedContentTypes = [lrcType]
        panel.begin { [weak self, weak panel] response in
            guard let self else { return }
            guard response == .OK, let url = panel?.url else {
                self.isLRCFileOperationInProgress = false
                return
            }
            guard self.playback.track.id == expectedTrack.id else {
                self.isLRCFileOperationInProgress = false
                self.presentLRCTrackChangedNotice()
                return
            }
            self.decodeAndImportLRCFile(at: url, expectedTrack: expectedTrack)
        }
    }

    func exportLRCFile() {
        pendingLRCExport = nil
        pendingLRCExportEstimation = nil
        guard canExportLRCFile, let document = currentLyricDocumentForExport() else {
            presentLRCNotice(
                title: localized(zh: "无法导出歌词", en: "Cannot Export Lyrics"),
                message: lyrics.isEmpty
                    ? localized(zh: "当前没有可导出的歌词。", en: "There are no lyrics to export.")
                    : localized(
                        zh: "请先在 Spotify 播放一首可识别的歌曲。",
                        en: "Play a recognized track in Spotify first."
                    )
            )
            return
        }
        prepareLRCExport(
            document: document,
            track: playback.track,
            estimateUntimedLines: false
        )
    }

    func confirmLRCFileAlert(_ purpose: LyricLRCAlertPurpose) {
        lrcFileAlert = nil
        switch purpose {
        case .notice:
            pendingLRCExport = nil
            pendingLRCExportEstimation = nil
        case .estimateUntimedAndExport:
            pendingLRCExport = nil
            guard let pendingLRCExportEstimation else { return }
            self.pendingLRCExportEstimation = nil
            guard pendingLRCExportEstimation.track.id == playback.track.id else {
                presentLRCTrackChangedNotice()
                return
            }
            prepareLRCExport(
                document: pendingLRCExportEstimation.document,
                track: pendingLRCExportEstimation.track,
                estimateUntimedLines: true
            )
        case .confirmLossyExport:
            pendingLRCExportEstimation = nil
            guard let pendingLRCExport else { return }
            self.pendingLRCExport = nil
            guard pendingLRCExport.trackID == playback.track.id else {
                presentLRCNotice(
                    title: localized(zh: "歌曲已经切换", en: "Track Changed"),
                    message: localized(
                        zh: "为避免导出错歌，本次导出已取消。请在新歌曲上重新操作。",
                        en: "Export was cancelled to avoid saving lyrics for the wrong track. Start again on the new track."
                    )
                )
                return
            }
            presentLRCSavePanel(for: pendingLRCExport)
        }
    }

    func dismissLRCFileAlert() {
        lrcFileAlert = nil
        pendingLRCExport = nil
        pendingLRCExportEstimation = nil
    }

    func hideLRCFileAlert() {
        lrcFileAlert = nil
    }

    private func decodeAndImportLRCFile(at url: URL, expectedTrack: Track) {
        lrcFileOperationGeneration &+= 1
        let generation = lrcFileOperationGeneration
        let options = LyricLRCImportOptions(
            trackID: expectedTrack.id,
            sourceID: "file:\(url.lastPathComponent)",
            provider: "LRC Import",
            translationLanguage: translationTarget.apiName
        )
        Task {
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    let data = try Data(contentsOf: url, options: .mappedIfSafe)
                    return try LyricLRCFileCodec.decode(
                        data: data,
                        filenameExtension: url.pathExtension,
                        options: options
                    )
                }.value
                guard validateCurrentLRCFileOperation(
                    generation: generation,
                    trackID: expectedTrack.id
                ) else {
                    return
                }
                guard result.issues.isEmpty else {
                    isLRCFileOperationInProgress = false
                    presentLRCAlert(
                        purpose: .notice,
                        title: localized(zh: "LRC 包含无效行", en: "LRC Contains Invalid Lines"),
                        message: LyricLRCUIWorkflow.importIssueMessage(
                            result.issues,
                            language: interfaceLanguage
                        ),
                        primaryButtonTitle: localized(zh: "返回修改", en: "Review File")
                    )
                    return
                }
                guard !result.document.lines.isEmpty else {
                    isLRCFileOperationInProgress = false
                    presentLRCNotice(
                        title: localized(zh: "没有可导入的歌词", en: "No Lyrics to Import"),
                        message: localized(
                            zh: "这个 LRC 文件没有包含有效歌词行。",
                            en: "This LRC file does not contain any valid lyric lines."
                        )
                    )
                    return
                }
                try await persistImportedLRCDocument(
                    result.document,
                    expectedTrack: expectedTrack,
                    generation: generation
                )
            } catch {
                guard validateCurrentLRCFileOperation(
                    generation: generation,
                    trackID: expectedTrack.id
                ) else {
                    return
                }
                isLRCFileOperationInProgress = false
                presentLRCNotice(
                    title: localized(zh: "LRC 导入失败", en: "LRC Import Failed"),
                    message: lrcFileErrorMessage(error)
                )
            }
        }
    }

    private func persistImportedLRCDocument(
        _ document: LyricDocument,
        expectedTrack: Track,
        generation: UInt64
    ) async throws {
        let importedLyrics = document.timedLyrics
        let entry = LyricsCacheEntry(
            trackID: expectedTrack.id,
            trackTitle: expectedTrack.title,
            artist: expectedTrack.artist,
            trackDuration: expectedTrack.duration,
            savedAt: Date(),
            source: .manual,
            lyrics: importedLyrics,
            document: document
        )
        try await lyricsCacheStore.save(entry)
        guard lrcFileOperationGeneration == generation else { return }
        guard playback.track.id == expectedTrack.id else {
            isLRCFileOperationInProgress = false
            presentLRCNotice(
                title: localized(zh: "歌曲已经切换", en: "Track Changed"),
                message: localized(
                    zh: "LRC 已安全保存到上一首歌曲，不会关联到当前歌曲；下次播放上一首时会自动显示。",
                    en: "The LRC was safely saved for the previous track and was not attached to the current one. It will appear next time that track plays."
                )
            )
            return
        }
        lyricLoadTask?.cancel()
        lyricLoadTask = nil
        lyricLoadGeneration &+= 1
        lyrics = importedLyrics
        rememberPresentedLyrics(
            importedLyrics,
            trackID: expectedTrack.id,
            sourceDocument: document
        )
        lyricCache.removeAll()
        lyricPipelineStatus = localized(zh: "用户歌词 · LRC 导入", en: "User lyrics · LRC import")
        cacheStatus = localized(
            zh: "LRC 已保存为当前歌曲的用户歌词。",
            en: "The LRC was saved as user lyrics for the current track."
        )
        isLRCFileOperationInProgress = false
        presentation = .lyricsFull
    }

    private func prepareLRCExport(
        document: LyricDocument,
        track: Track,
        estimateUntimedLines: Bool
    ) {
        lrcFileOperationGeneration &+= 1
        let generation = lrcFileOperationGeneration
        isLRCFileOperationInProgress = true
        Task {
            do {
                let preparation = try await Task.detached(priority: .userInitiated) {
                    try LyricLRCUIWorkflow.prepareExport(
                        document: document,
                        trackDuration: track.duration,
                        estimateUntimedLines: estimateUntimedLines
                    )
                }.value
                guard validateCurrentLRCFileOperation(
                    generation: generation,
                    trackID: track.id
                ) else {
                    return
                }
                isLRCFileOperationInProgress = false
                switch preparation {
                case .ready(let result):
                    presentLRCSavePanel(
                        for: PendingLRCExport(
                            result: result,
                            trackID: track.id,
                            suggestedFilename: suggestedLRCFilename(for: track)
                        )
                    )
                case .requiresExplicitEstimation(let lineNumbers):
                    pendingLRCExportEstimation = PendingLRCExportEstimation(
                        document: document,
                        track: track
                    )
                    let lines = lineNumbers.map(String.init).joined(separator: ", ")
                    presentLRCAlert(
                        purpose: .estimateUntimedAndExport,
                        title: localized(zh: "歌词缺少时间戳", en: "Lyrics Have No Timestamps"),
                        message: localized(
                            zh: "第 \(lines) 行没有时间戳。默认不会静默估时。只有你明确确认后，才会按当前歌曲时长均匀估时。",
                            en: "Line \(lines) has no timestamp. Lyris never estimates silently. Timing is estimated from the current track duration only after you confirm."
                        ),
                        primaryButtonTitle: localized(
                            zh: "按歌曲时长估时并继续",
                            en: "Estimate from Track Duration"
                        ),
                        cancelButtonTitle: localized(zh: "取消", en: "Cancel")
                    )
                case .requiresLossConfirmation(let result):
                    pendingLRCExportEstimation = nil
                    pendingLRCExport = PendingLRCExport(
                        result: result,
                        trackID: track.id,
                        suggestedFilename: suggestedLRCFilename(for: track)
                    )
                    presentLRCAlert(
                        purpose: .confirmLossyExport,
                        title: localized(zh: "确认 LRC 降级导出", en: "Confirm LRC Downgrade"),
                        message: LyricLRCUIWorkflow.exportWarningMessage(
                            result.warnings,
                            language: interfaceLanguage
                        ),
                        primaryButtonTitle: localized(zh: "仍然导出", en: "Export Anyway"),
                        cancelButtonTitle: localized(zh: "取消", en: "Cancel")
                    )
                }
            } catch {
                guard validateCurrentLRCFileOperation(
                    generation: generation,
                    trackID: track.id
                ) else {
                    return
                }
                isLRCFileOperationInProgress = false
                presentLRCNotice(
                    title: localized(zh: "LRC 导出失败", en: "LRC Export Failed"),
                    message: lrcFileErrorMessage(error)
                )
            }
        }
    }

    private func presentLRCSavePanel(for pending: PendingLRCExport) {
        guard let lrcType = UTType(filenameExtension: pending.result.filenameExtension) else {
            isLRCFileOperationInProgress = false
            presentLRCNotice(
                title: localized(zh: "无法打开保存面板", en: "Cannot Open Save Panel"),
                message: localized(
                    zh: "系统无法识别 LRC 文件类型。",
                    en: "macOS could not register the LRC file type."
                )
            )
            return
        }
        isLRCFileOperationInProgress = true
        let panel = NSSavePanel()
        panel.title = localized(zh: "导出 LRC 歌词", en: "Export LRC Lyrics")
        panel.prompt = localized(zh: "导出", en: "Export")
        panel.canCreateDirectories = true
        panel.allowsOtherFileTypes = false
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = pending.suggestedFilename
        panel.allowedContentTypes = [lrcType]
        panel.begin { [weak self, weak panel] response in
            guard let self else { return }
            guard response == .OK, let url = panel?.url else {
                self.isLRCFileOperationInProgress = false
                return
            }
            self.writeLRCExport(pending.result.data, to: url)
        }
    }

    private func writeLRCExport(_ data: Data, to url: URL) {
        lrcFileOperationGeneration &+= 1
        let generation = lrcFileOperationGeneration
        Task {
            do {
                try await Task.detached(priority: .userInitiated) {
                    try data.write(to: url, options: .atomic)
                }.value
                guard lrcFileOperationGeneration == generation else { return }
                isLRCFileOperationInProgress = false
                cacheStatus = localized(
                    zh: "LRC 已导出到 \(url.lastPathComponent)。",
                    en: "LRC exported to \(url.lastPathComponent)."
                )
            } catch {
                guard lrcFileOperationGeneration == generation else { return }
                isLRCFileOperationInProgress = false
                presentLRCNotice(
                    title: localized(zh: "LRC 导出失败", en: "LRC Export Failed"),
                    message: lrcFileErrorMessage(error)
                )
            }
        }
    }

    private func validateCurrentLRCFileOperation(generation: UInt64, trackID: String) -> Bool {
        guard lrcFileOperationGeneration == generation else { return false }
        guard playback.track.id == trackID else {
            isLRCFileOperationInProgress = false
            pendingLRCExport = nil
            pendingLRCExportEstimation = nil
            presentLRCTrackChangedNotice()
            return false
        }
        return true
    }

    private func presentLRCTrackChangedNotice() {
        presentLRCNotice(
            title: localized(zh: "歌曲已经切换", en: "Track Changed"),
            message: localized(
                zh: "为避免把歌词关联到错误歌曲，本次操作已停止。请在当前歌曲上重新操作。",
                en: "The operation stopped to avoid associating lyrics with the wrong track. Start again on the current track."
            )
        )
    }

    private func presentLRCNotice(title: String, message: String) {
        presentLRCAlert(
            purpose: .notice,
            title: title,
            message: message,
            primaryButtonTitle: localized(zh: "知道了", en: "OK")
        )
    }

    private func presentLRCAlert(
        purpose: LyricLRCAlertPurpose,
        title: String,
        message: String,
        primaryButtonTitle: String,
        cancelButtonTitle: String? = nil
    ) {
        lrcAlertSequence &+= 1
        lrcFileAlert = LyricLRCAlertModel(
            id: lrcAlertSequence,
            purpose: purpose,
            title: title,
            message: message,
            primaryButtonTitle: primaryButtonTitle,
            cancelButtonTitle: cancelButtonTitle
        )
    }

    private func suggestedLRCFilename(for track: Track) -> String {
        let forbidden = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let safeTitle = track.title
            .components(separatedBy: forbidden)
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let base = safeTitle.isEmpty ? "Lyris Lyrics" : safeTitle
        return "\(base).\(LyricLRCFileCodec.preferredFilenameExtension)"
    }

    private func lrcFileErrorMessage(_ error: Error) -> String {
        guard let fileError = error as? LyricLRCFileError else {
            return localized(
                zh: "文件操作失败：\(error.localizedDescription)",
                en: "File operation failed: \(error.localizedDescription)"
            )
        }
        switch fileError {
        case .unsupportedFilenameExtension:
            return localized(zh: "只支持 .lrc 文件。", en: "Only .lrc files are supported.")
        case .invalidUTF8:
            return localized(zh: "文件不是有效的 UTF-8 文本。", en: "The file is not valid UTF-8 text.")
        case .noLyrics:
            return localized(zh: "当前没有可导出的歌词。", en: "There are no lyrics to export.")
        case .untimedLines(let lineNumbers):
            let lines = lineNumbers.map(String.init).joined(separator: ", ")
            return localized(
                zh: "第 \(lines) 行缺少时间戳。",
                en: "Line \(lines) has no timestamp."
            )
        case .invalidTimestamp(let lineNumber):
            return localized(
                zh: "第 \(lineNumber) 行的时间戳无效。",
                en: "Line \(lineNumber) has an invalid timestamp."
            )
        case .missingLyricText(let lineNumber):
            return localized(
                zh: "第 \(lineNumber) 行缺少歌词正文。",
                en: "Line \(lineNumber) is missing lyric text."
            )
        case .invalidEstimationDuration:
            return localized(
                zh: "当前歌曲时长无效，无法估算歌词时间。",
                en: "The current track duration is invalid, so lyric timing cannot be estimated."
            )
        }
    }

    func saveManualLyrics() {
        persistManualLyrics(mode: .preserveValidTiming)
    }

    func estimateAndSaveManualLyrics() {
        persistManualLyrics(mode: .estimateAll)
    }

    private func persistManualLyrics(mode: ManualLyricsParsingMode) {
        guard playback.track.id != "spotify:idle" else {
            cacheStatus = localized(
                zh: "Spotify 当前没有可关联的歌曲。",
                en: "Spotify has no current track to associate with these lyrics."
            )
            return
        }
        let result = ManualLyricsParser.parse(
            manualLyricsDraft,
            duration: playback.track.duration,
            mode: mode
        )
        if !result.issues.isEmpty {
            let lines = result.issues.map { String($0.lineNumber) }.joined(separator: "、")
            cacheStatus = localized(
                zh: "第 \(lines) 行时间戳或正文无效；已保留其他有效行的原时间。",
                en: "Line \(lines) has an invalid timestamp or text; other valid timestamps were preserved."
            )
            return
        }
        if !result.untimedLineNumbers.isEmpty {
            let lines = result.untimedLineNumbers.map(String.init).joined(separator: "、")
            cacheStatus = localized(
                zh: "第 \(lines) 行缺少时间戳；请补写，或选择“全部估时并保存”。",
                en: "Line \(lines) has no timestamp. Add one, or choose Estimate All & Save."
            )
            return
        }
        guard !result.lyrics.isEmpty else {
            cacheStatus = localized(
                zh: "请至少写入一行歌词。",
                en: "Enter at least one lyric line."
            )
            return
        }
        let parsed = result.lyrics
        lyrics = parsed
        rememberPresentedLyrics(parsed, trackID: playback.track.id)
        lyricCache.removeAll()
        lyricPipelineStatus = localized(zh: "用户歌词 · 已保存", en: "User lyrics · saved")
        let entry = LyricsCacheEntry(
            trackID: playback.track.id,
            trackTitle: playback.track.title,
            artist: playback.track.artist,
            trackDuration: playback.track.duration,
            savedAt: Date(),
            source: .manual,
            lyrics: parsed
        )
        Task {
            do {
                try await lyricsCacheStore.save(entry)
                cacheStatus = localized(
                    zh: "用户歌词已保存到 LyrisData/Lyrics/manual。",
                    en: "User lyrics were saved to LyrisData/Lyrics/manual."
                )
                refreshStorageUsage()
                presentation = .card
            } catch {
                cacheStatus = localized(
                    zh: "用户歌词保存失败：\(error.localizedDescription)",
                    en: "Could not save user lyrics: \(error.localizedDescription)"
                )
            }
        }
    }

    func clearGeneratedLyricsCache() {
        Task {
            do {
                try await lyricsCacheStore.clearGenerated()
                lyricCache.removeAll()
                cacheStatus = localized(
                    zh: "自动生成歌词缓存已清除；用户歌词仍保留。",
                    en: "Generated lyric cache cleared; user lyrics were kept."
                )
                refreshStorageUsage()
            } catch {
                cacheStatus = error.localizedDescription
            }
        }
    }

    func clearManualLyrics() {
        Task {
            do {
                try await lyricsCacheStore.clearManual()
                lyricCache.removeAll()
                cacheStatus = localized(zh: "用户歌词已清除。", en: "User lyrics cleared.")
                refreshStorageUsage()
            } catch {
                cacheStatus = error.localizedDescription
            }
        }
    }

    func clearArtworkCache() {
        URLCache.shared.removeAllCachedResponses()
        cacheStatus = localized(
            zh: "封面与网络响应缓存已清除；Lyris 从未缓存 Spotify 音频。",
            en: "Artwork and network response caches cleared; Lyris never caches Spotify audio."
        )
        refreshStorageUsage()
    }

    func refreshStorageUsage() {
        guard !isRefreshingStorageUsage else { return }
        isRefreshingStorageUsage = true
        let lyricsURL = LyrisDataLocation.lyricsURL()
        let cacheURL = LyrisDataLocation.cacheURL()
        Task {
            let usage = await Task.detached(priority: .utility) {
                LyrisStorageUsage.inspect(
                    lyricsURL: lyricsURL,
                    cacheURL: cacheURL
                )
            }.value
            storageUsage = usage
            isRefreshingStorageUsage = false
        }
    }

    func openLocalDataFolder() {
        openDataDirectory(LyrisDataLocation.rootURL())
    }

    func openLyricsFolder() {
        openDataDirectory(LyrisDataLocation.lyricsURL())
    }

    func openCacheFolder() {
        openDataDirectory(LyrisDataLocation.cacheURL())
    }

    private func openDataDirectory(_ directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(directory)
    }

    func showSettings(_ section: SettingsSection = .spotify) {
        settingsSection = section
        presentation = .settings
        onSettingsRequested?(section)
    }

    func showDesktopLyrics() {
        updateFloatingPresentationMode(.desktopLyrics)
    }

    func cycleCardMode() {
        cardMode = .capsule
        defaults.set(CardMode.capsule.rawValue, forKey: "cardMode")
        presentation = .card
    }

    func cycleFloatingPresentationMode() {
        updateFloatingPresentationMode(floatingPresentationMode.next)
    }

    func updateFloatingPresentationMode(_ mode: FloatingPresentationMode) {
        if floatingPresentationMode == mode {
            if mode == .desktopLyrics {
                onMainWindowRequested?()
            }
            return
        }
        floatingPresentationMode = mode
        persistDisplayPreferences()
        persistProjectConfiguration()
        if mode == .desktopLyrics {
            onMainWindowRequested?()
        }
    }

    func setTopIslandExpanded(_ expanded: Bool) {
        isTopIslandExpanded = expanded
    }

    func updateMacIslandExpandedHoldDuration(
        _ duration: MacIslandExpandedHoldDuration
    ) {
        macIslandExpandedHoldDuration = duration
        persistDisplayPreferences()
        persistProjectConfiguration()
    }

    func updateMacIslandExpansionTrigger(_ trigger: MacIslandExpansionTrigger) {
        guard macIslandExpansionTrigger != trigger else { return }
        macIslandExpansionTrigger = trigger
        persistDisplayPreferences()
        persistProjectConfiguration()
    }

    func updateMacIslandHoverExpandDelay(_ delay: Double) {
        macIslandHoverExpandDelay = min(max(delay, 0), 5)
        persistDisplayPreferences()
        persistProjectConfiguration()
    }

    func cycleLinkedEffect() {
        updateLinkedEffectStyle(linkedEffectStyle.next)
    }

    func updateLinkedEffectStyle(_ style: LinkedEffectStyle) {
        let normalized = style.normalized
        linkedEffectStyle = normalized
        defaults.set(normalized.rawValue, forKey: "linkedEffectStyle")
        persistProjectConfiguration()
    }

    func updateLyricTimingDelay(_ delay: Double) {
        lyricTimingDelay = min(max(delay, -3), 3)
        defaults.set(lyricTimingDelay, forKey: "lyricTimingDelay")
        persistProjectConfiguration()
    }

    func updateInterfaceLanguage(_ language: AppLanguage) {
        interfaceLanguage = language
        persistDisplayPreferences()
        persistProjectConfiguration()
    }

    func updateTranslationTarget(_ target: TranslationTargetLanguage) {
        guard translationTarget != target else { return }
        translationTarget = target
        lyricCache.removeAll()
        lyrics = []
        lyricPipelineStatus = localized(zh: "正在按新目标语言加载歌词…", en: "Loading lyrics for the new target language…")
        persistDisplayPreferences()
        persistProjectConfiguration()
        startLyricsLoad(for: playback.track)
    }

    func updateTranslationFont(_ font: TranslationFontChoice) {
        translationFont = font
        persistDisplayPreferences()
        persistProjectConfiguration()
    }

    func updateCustomTranslationFontFamily(_ family: String) {
        customTranslationFontFamily = family
            .trimmingCharacters(in: .whitespacesAndNewlines)
        translationFont = customTranslationFontFamily.isEmpty ? .rounded : .custom
        persistDisplayPreferences()
        persistProjectConfiguration()
    }

    func applyRecommendedTranslationFont() {
        let recommendation = LyrisFontRecommendation.recommendation(
            for: translationTarget,
            availableFamilies: availableTranslationFontFamilies
        )
        if let family = recommendation.customFamily {
            updateCustomTranslationFontFamily(family)
        } else {
            updateTranslationFont(recommendation.choice)
        }
        configurationStatus = localized(
            zh: "已应用系统推荐字体：\(recommendation.displayName)。",
            en: "Applied the system recommendation: \(recommendation.displayName)."
        )
    }

    func importTranslationFont() {
        let panel = NSOpenPanel()
        panel.title = localized(zh: "添加译文字体", en: "Add Translation Font")
        panel.prompt = localized(zh: "添加字体", en: "Add Font")
        panel.allowedContentTypes = [.font]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let sourceURL = panel.url else { return }

        do {
            let directory = LyrisDataLocation.fontsURL()
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            let destination = uniqueFontDestination(
                for: sourceURL.lastPathComponent,
                in: directory
            )
            try FileManager.default.copyItem(at: sourceURL, to: destination)
            guard let family = registerFont(at: destination) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            LyrisInstalledFontCatalog.invalidateSystemOptionsCache()
            refreshAvailableTranslationFonts()
            updateCustomTranslationFontFamily(family)
            fontLibraryRevision += 1
            configurationStatus = localized(
                zh: "字体已保存在 LyrisData/Fonts，并应用到译文。",
                en: "Font saved in LyrisData/Fonts and applied to translations."
            )
        } catch {
            configurationStatus = localized(
                zh: "字体添加失败：\(error.localizedDescription)",
                en: "Could not add font: \(error.localizedDescription)"
            )
        }
    }

    func translationDisplayFont(size: CGFloat, weight: Font.Weight) -> Font {
        translationFont.font(
            size: size,
            weight: weight,
            customFamily: customTranslationFontFamily
        )
    }

    var availableTranslationFontFamilies: [String] {
        availableTranslationFontOptions.map(\.familyName)
    }

    func updateInterfaceSkin(_ skin: LyrisInterfaceSkin) {
        guard interfaceSkin != skin else { return }
        interfaceSkin = skin
        persistDisplayPreferences()
        persistProjectConfiguration()
    }

    func updateArtworkPresentationMode(_ mode: LyrisArtworkPresentationMode) {
        guard artworkPresentationMode != mode else { return }
        artworkPresentationMode = mode
        persistDisplayPreferences()
        persistProjectConfiguration()
    }

    func updateMenuBarLyricMode(_ mode: MenuBarLyricMode) {
        menuBarLyricMode = mode
        persistDisplayPreferences()
        persistProjectConfiguration()
    }

    func updateTraditionalChineseConversion(_ enabled: Bool) {
        guard convertsTraditionalChineseToSimplified != enabled else { return }
        convertsTraditionalChineseToSimplified = enabled
        persistDisplayPreferences()
        persistProjectConfiguration()
    }

    var translationPricingReference: TranslationPricingCatalog.Reference {
        TranslationPricingCatalog.reference(
            provider: translationProvider,
            model: translationModel
        )
    }

    func openOfficialTranslationPricing() {
        guard let url = translationPricingReference.sourceURL else { return }
        NSWorkspace.shared.open(url)
    }

    func updateTranslationProvider(_ provider: TranslationProvider) {
        cancelTranslationTest()
        translationProvider = provider
        translationBaseURL = provider.defaultBaseURL
        translationModel = provider.defaultModel
        translationAPIKey = ""
        translationCredentialRequiresAuthorization = false
        translationThinkingEnabled = false
        applySuggestedTranslationPricing()
        availableTranslationModels = []
        LyrisTranslationModelCatalogPersistence.clear(from: defaults)
        isTranslationConnected = false
        lyricCache.removeAll()
        configurationStatus = nil
        restartLyricsForConfigurationChange()
        if hasStoredTranslationCredentialMetadata(for: provider) {
            restoreTranslationCredential(for: provider)
        }
    }

    func updateTranslationBaseURLDraft(_ value: String) {
        guard translationBaseURL != value else { return }
        invalidatePendingTranslationConfiguration()
        translationBaseURL = value
        availableTranslationModels = []
        LyrisTranslationModelCatalogPersistence.clear(from: defaults)
        configurationStatus = localized(
            zh: "翻译配置已修改；请重新测试并保存。",
            en: "Translation settings changed; test and save again."
        )
    }

    func updateTranslationModelDraft(_ value: String) {
        guard translationModel != value else { return }
        invalidatePendingTranslationConfiguration()
        translationModel = value
        applySuggestedTranslationPricing()
        configurationStatus = localized(
            zh: "模型已修改；请重新测试并保存。",
            en: "Model changed; test and save again."
        )
    }

    #if DEBUG
    func loadTranslationModelsForQA(_ models: [String]) {
        let options = LyrisTranslationModelSelection.options(
            available: models,
            current: translationModel
        )
        availableTranslationModels = options
        if let first = options.first {
            translationModel = first
        }
    }
    #endif

    func updateTranslationInputPrice(_ value: Double) {
        translationInputPriceUSDPerMillion = max(0, value)
        persistTranslationPricing()
    }

    func updateTranslationOutputPrice(_ value: Double) {
        translationOutputPriceUSDPerMillion = max(0, value)
        persistTranslationPricing()
    }

    func updateCostCurrency(_ currency: CostCurrency) {
        costCurrency = currency
        if currency == .usd {
            costCurrencyUnitsPerUSD = 1
        } else {
            let storedRate = defaults.double(forKey: costCurrencyRateKey(for: currency))
            costCurrencyUnitsPerUSD = storedRate > 0
                ? storedRate
                : currency.referenceUnitsPerUSD
        }
        defaults.set(currency.rawValue, forKey: "costCurrency")
        persistProjectConfiguration()
    }

    func updateCostCurrencyUnitsPerUSD(_ value: Double) {
        let normalized = costCurrency == .usd ? 1 : max(0.000_001, value)
        costCurrencyUnitsPerUSD = normalized
        defaults.set(normalized, forKey: costCurrencyRateKey(for: costCurrency))
        persistProjectConfiguration()
    }

    func updateTranslationInputPriceInSelectedCurrency(_ value: Double) {
        updateTranslationInputPrice(
            costCurrency.convertToUSD(
                value,
                unitsPerUSD: costCurrencyUnitsPerUSD
            )
        )
    }

    func updateTranslationOutputPriceInSelectedCurrency(_ value: Double) {
        updateTranslationOutputPrice(
            costCurrency.convertToUSD(
                value,
                unitsPerUSD: costCurrencyUnitsPerUSD
            )
        )
    }

    func resetTranslationPricingToSuggested() {
        applySuggestedTranslationPricing()
    }

    func refreshTranslationPricingFromOfficialSource() {
        officialPricingTask?.cancel()
        let provider = translationProvider
        let model = translationModel
        isRefreshingOfficialPricing = true
        officialPricingStatus = localized(
            zh: "正在读取官方价格页…",
            en: "Reading the official pricing page…"
        )
        officialPricingTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.isRefreshingOfficialPricing = false }
            do {
                let snapshot = try await OfficialTranslationPricingClient().fetch(
                    provider: provider,
                    model: model
                )
                try Task.checkCancellation()
                guard self.translationProvider == provider,
                      self.translationModel == model else {
                    self.officialPricingStatus = self.localized(
                        zh: "模型已切换，已忽略刚才的价格结果。",
                        en: "The model changed; the previous pricing result was ignored."
                    )
                    return
                }
                self.translationInputPriceUSDPerMillion = snapshot.rates.inputUSDPerMillion
                self.translationOutputPriceUSDPerMillion = snapshot.rates.outputUSDPerMillion
                self.persistTranslationPricing()
                let formatter = DateFormatter()
                formatter.locale = self.interfaceLanguage.locale
                formatter.dateStyle = .medium
                formatter.timeStyle = .short
                self.officialPricingStatus = self.localized(
                    zh: "已联网更新：\(snapshot.note) · \(formatter.string(from: snapshot.checkedAt))",
                    en: "Updated online: \(snapshot.note) · \(formatter.string(from: snapshot.checkedAt))"
                )
            } catch is CancellationError {
                return
            } catch {
                self.officialPricingStatus = error.localizedDescription
            }
        }
    }

    func updateTranslationThinkingDraft(_ enabled: Bool) {
        guard translationThinkingEnabled != enabled else { return }
        invalidatePendingTranslationConfiguration()
        translationThinkingEnabled = enabled
        configurationStatus = localized(
            zh: "思考模式已修改；请重新测试并保存。",
            en: "Reasoning mode changed; test and save again."
        )
    }

    func updateTranslationStyle(_ style: LyricsTranslationStyle) {
        guard translationStyle != style else { return }
        translationStyle = style
        defaults.set(style.rawValue, forKey: "lyricsTranslationStyle")
        lyricCache.removeAll()
        persistProjectConfiguration()
        configurationStatus = localized(
            zh: style == .contextual
                ? "已启用上下文意译；整首歌词会作为统一语境重新生成。"
                : "已启用快速直译；将优先降低字幕生成延迟。",
            en: style == .contextual
                ? "Context-aware translation is enabled; the complete lyric will be regenerated as one coherent work."
                : "Fast literal translation is enabled to prioritize subtitle latency."
        )
        restartLyricsForConfigurationChange()
    }

    func updateTranslationAPIKeyDraft(_ value: String) {
        guard translationAPIKey != value else { return }
        invalidatePendingTranslationConfiguration()
        translationAPIKey = value
        if !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            translationCredentialRequiresAuthorization = false
        }
        availableTranslationModels = []
        LyrisTranslationModelCatalogPersistence.clear(from: defaults)
        configurationStatus = localized(
            zh: "API Key 已修改；请重新测试并保存。",
            en: "API key changed; test and save again."
        )
    }

    func saveSpotifyConfiguration() {
        let value = spotifyClientID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            configurationStatus = localized(
                zh: "请先粘贴 Spotify Client ID。",
                en: "Paste your Spotify Client ID first."
            )
            return
        }
        do {
            try spotifyAuthorizer.saveConfiguration(
                clientID: value,
                redirectURI: Self.spotifyRedirectURI
            )
        } catch {
            applySpotifyConfigurationFailure(error)
            return
        }
        cancelSpotifyConnectionTasks()
        spotifyClientID = value
        persistProjectConfiguration()
        isSpotifyConnected = false
        spotifyAuthorizationState = .disconnected
        spotifyConnectionStatus = localized(
            zh: "Client ID 已保存 · 尚未授权",
            en: "Client ID saved · not authorized"
        )
        configurationStatus = localized(
            zh: "Client ID 已保存在本机；还需要完成一次 Spotify PKCE 授权。",
            en: "The Client ID is saved locally; complete Spotify PKCE authorization next."
        )
    }

    func authorizeSpotify() {
        let value = spotifyClientID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            configurationStatus = localized(
                zh: "请先粘贴 Spotify Client ID。",
                en: "Paste your Spotify Client ID first."
            )
            return
        }
        spotifyClientID = value
        spotifyRestoreTask?.cancel()
        spotifyRestoreTask = nil
        spotifyAuthorizationTask?.cancel()
        spotifyConnectionGeneration &+= 1
        let generation = spotifyConnectionGeneration
        isAuthorizingSpotify = true
        isSpotifyConnected = false
        spotifyAuthorizationState = .authorizing
        spotifyConnectionStatus = localized(
            zh: "等待浏览器授权…",
            en: "Waiting for browser authorization…"
        )
        configurationStatus = localized(
            zh: "浏览器会打开 Spotify 授权页；完成后会自动回到 Lyris。",
            en: "Spotify authorization will open in your browser and return to Lyris when complete."
        )
        spotifyAuthorizationTask = Task {
            do {
                let report = try await spotifyAuthorizer.authorize(
                    clientID: value,
                    redirectURI: Self.spotifyRedirectURI
                )
                guard spotifyConnectionGeneration == generation, !Task.isCancelled else { return }
                isSpotifyConnected = true
                spotifyAuthorizationState = .connected
                spotifyConnectionStatus = localized(
                    zh: "已连接 · \(report.displayName)",
                    en: "Connected · \(report.displayName)"
                )
                configurationStatus = localized(
                    zh: "Spotify 令牌交换成功；刷新令牌已写入 Keychain，账户播放状态正在后台同步。",
                    en: "Spotify token exchange succeeded. The refresh token is in Keychain and account playback is syncing in the background."
                )
                completeFirstUseAccountIfNeeded()
            } catch {
                guard spotifyConnectionGeneration == generation else { return }
                isSpotifyConnected = false
                if Task.isCancelled || error is CancellationError {
                    spotifyAuthorizationState = .disconnected
                    spotifyConnectionStatus = localized(
                        zh: "Client ID 已保存 · 尚未授权",
                        en: "Client ID saved · not authorized"
                    )
                    configurationStatus = localized(
                        zh: "已取消等待。请确认粘贴的是 Client ID，而不是 Client Secret。",
                        en: "Authorization cancelled. Make sure you pasted the Client ID, not the Client Secret."
                    )
                } else {
                    spotifyAuthorizationState = authorizationFailureState(for: error)
                    spotifyConnectionStatus = switch spotifyAuthorizationState {
                    case .reauthorizationRequired:
                        localized(
                            zh: "授权已失效 · 请重新授权",
                            en: "Authorization expired · reconnect"
                        )
                    case .permissionRequired:
                        localized(
                            zh: "Spotify 权限不足 · 请重新授权所需范围",
                            en: "Spotify permission missing · reconnect with required scopes"
                        )
                    default:
                        localized(zh: "连接失败", en: "Connection failed")
                    }
                    configurationStatus = spotifyConfigurationErrorMessage(error)
                }
            }
            if spotifyConnectionGeneration == generation {
                isAuthorizingSpotify = false
                spotifyAuthorizationTask = nil
            }
        }
    }

    func cancelSpotifyAuthorization() {
        spotifyAuthorizationTask?.cancel()
        spotifyAuthorizationTask = nil
        spotifyConnectionGeneration &+= 1
        isAuthorizingSpotify = false
        if spotifyAuthorizationState == .authorizing {
            spotifyAuthorizationState = .disconnected
            spotifyConnectionStatus = localized(
                zh: "Client ID 已保存 · 尚未授权",
                en: "Client ID saved · not authorized"
            )
        }
    }

    func refreshSpotifyAuthorizationReminder() {
        guard isSpotifyConnected,
              let profile = try? spotifyAuthorizer.configuredProfile(),
              restoredSpotifyAuthorizationState(profile: profile) == .expiringSoon else { return }
        applySpotifyAuthorizationState(.expiringSoon)
        spotifyConnectionStatus = localized(
            zh: "已连接 · 建议近期重新授权",
            en: "Connected · reauthorization recommended soon"
        )
    }

    func saveTranslationConfiguration() {
        let key = translationAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !translationBaseURL.isEmpty else {
            configurationStatus = localized(
                zh: "请填写翻译服务的 Base URL。",
                en: "Enter the translation service Base URL."
            )
            return
        }
        guard !key.isEmpty else {
            configurationStatus = localized(
                zh: "请粘贴翻译服务的 API Key。",
                en: "Paste the translation service API key."
            )
            return
        }
        do {
            try credentialVault.write(key, account: translationProvider.credentialAccount)
            translationCredentialRequiresAuthorization = false
            defaults.set(
                true,
                forKey: translationCredentialMetadataKey(for: translationProvider)
            )
            defaults.set(translationProvider.rawValue, forKey: "translationProvider")
            defaults.set(translationBaseURL, forKey: "translationBaseURL")
            defaults.set(translationModel, forKey: "translationModel")
            defaults.set(translationThinkingEnabled, forKey: "translationThinkingEnabled")
            defaults.set(translationStyle.rawValue, forKey: "lyricsTranslationStyle")
            persistTranslationPricing()
            persistProjectConfiguration()
            isTranslationConnected = false
            lyricCache.removeAll()
            configurationStatus = localized(
                zh: "配置已保存；尚未执行连通测试。API Key 只在 macOS Keychain 中。",
                en: "Settings saved; the connection has not been tested yet. The API key stays only in macOS Keychain."
            )
            restartLyricsForConfigurationChange()
        } catch {
            configurationStatus = error.localizedDescription
        }
    }

    func testTranslationConnection() {
        let key = translationAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseURL = translationBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !baseURL.isEmpty else {
            configurationStatus = localized(
                zh: "请填写翻译服务的 Base URL。",
                en: "Enter the translation service Base URL."
            )
            return
        }
        guard !key.isEmpty else {
            configurationStatus = localized(
                zh: "请粘贴翻译服务的 API Key。",
                en: "Paste the translation service API key."
            )
            return
        }
        do {
            try credentialVault.write(key, account: translationProvider.credentialAccount)
            translationCredentialRequiresAuthorization = false
            defaults.set(
                true,
                forKey: translationCredentialMetadataKey(for: translationProvider)
            )
        } catch {
            configurationStatus = error.localizedDescription
            return
        }
        isTestingTranslation = true
        isTranslationConnected = false
        configurationStatus = localized(
            zh: "正在验证 API Key、读取模型并发送一条最小测试请求…",
            en: "Validating the API key, loading models, and sending a minimal test request…"
        )
        translationTestTask?.cancel()
        translationTestGeneration &+= 1
        let generation = translationTestGeneration
        let provider = translationProvider
        let configuration = TranslationConfiguration(
            provider: provider,
            baseURL: baseURL,
            model: translationModel,
            thinkingEnabled: translationThinkingEnabled,
            style: translationStyle
        )
        let startedAt = Date()
        translationTestTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if translationTestGeneration == generation {
                    isTestingTranslation = false
                    translationTestTask = nil
                }
            }
            do {
                let report = try await translationAdapter.testConnection(configuration: configuration, apiKey: key)
                guard isCurrentTranslationTest(generation: generation, configuration: configuration) else { return }
                recordAPIUsage(
                    requests: provider == .deepL ? 1 : 2,
                    lines: 0,
                    succeeded: true,
                    latencyMilliseconds: Int(Date().timeIntervalSince(startedAt) * 1_000)
                )
                availableTranslationModels = LyrisTranslationModelSelection.options(
                    available: report.models,
                    current: report.suggestedModel
                )
                if !report.suggestedModel.isEmpty {
                    translationModel = report.suggestedModel
                    applySuggestedTranslationPricing()
                }
                LyrisTranslationModelCatalogPersistence.save(
                    models: availableTranslationModels,
                    provider: provider,
                    baseURL: baseURL,
                    to: defaults
                )
                persistTranslationPreferences()
                isTranslationConnected = true
                let modelSummary = report.models.isEmpty
                    ? localized(zh: "无需选择模型", en: "No model selection needed")
                    : localized(
                        zh: "读取到 \(report.models.count) 个模型",
                        en: "Loaded \(report.models.count) models"
                    )
                configurationStatus = localized(
                    zh: "连接成功 · \(modelSummary) · \(report.latencyMilliseconds) ms",
                    en: "Connected · \(modelSummary) · \(report.latencyMilliseconds) ms"
                )
                completeFirstUseTranslationIfNeeded()
            } catch is CancellationError {
                return
            } catch {
                guard isCurrentTranslationTest(generation: generation, configuration: configuration) else { return }
                recordAPIUsage(
                    requests: provider == .deepL ? 1 : 2,
                    lines: 0,
                    succeeded: false,
                    latencyMilliseconds: Int(Date().timeIntervalSince(startedAt) * 1_000)
                )
                availableTranslationModels = []
                isTranslationConnected = false
                configurationStatus = error.localizedDescription
            }
        }
    }

    func openSpotifyDashboard() {
        NSWorkspace.shared.open(URL(string: "https://developer.spotify.com/dashboard")!)
    }

    func openProviderGuide() {
        let rawURL = switch translationProvider {
        case .deepSeek: "https://api-docs.deepseek.com/"
        case .openAI: "https://platform.openai.com/api-keys"
        case .deepL: "https://developers.deepl.com/docs/getting-started/auth"
        case .custom: "https://platform.openai.com/docs/api-reference/chat"
        }
        NSWorkspace.shared.open(URL(string: rawURL)!)
    }

    func copyRedirectURI() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(Self.spotifyRedirectURI, forType: .string)
        configurationStatus = localized(
            zh: "Redirect URI 已复制。请把它原样加入 Spotify 应用的 allowlist。",
            en: "Redirect URI copied. Add it unchanged to your Spotify app allowlist."
        )
    }

    func hide() {
        onHideRequested?()
    }

    func quit() {
        onQuitRequested?()
    }

    func replaceTranslation(for lineID: UUID, with value: String) {
        guard let index = lyrics.firstIndex(where: { $0.id == lineID }),
              let trackID = presentedLyricsTrackID,
              let key = overrideKeysByLineID[lineID] else { return }
        lyrics[index].translation = value
        let receipt = translationOverrideCoordinator.set(value, for: key, trackID: trackID)
        Task {
            do {
                try await receipt.wait()
                if playback.track.id == trackID {
                    cacheStatus = localized(
                        zh: "译文校对已保存到本机。",
                        en: "Translation edit saved locally."
                    )
                }
            } catch {
                if playback.track.id == trackID {
                    cacheStatus = localized(
                        zh: "译文校对保存失败：\(error.localizedDescription)",
                        en: "Could not save translation edit: \(error.localizedDescription)"
                    )
                }
            }
        }
    }

    func restoreGeneratedTranslation(for lineID: UUID) {
        guard let index = lyrics.firstIndex(where: { $0.id == lineID }),
              let trackID = presentedLyricsTrackID,
              let key = overrideKeysByLineID[lineID],
              let baseTranslation = baseTranslationsByLineID[lineID] else { return }
        lyrics[index].translation = baseTranslation
        let receipt = translationOverrideCoordinator.remove(key, trackID: trackID)
        Task {
            do {
                try await receipt.wait()
                if playback.track.id == trackID {
                    cacheStatus = localized(
                        zh: "已恢复原译文。",
                        en: "Original generated translation restored."
                    )
                }
            } catch {
                if playback.track.id == trackID {
                    cacheStatus = localized(
                        zh: "恢复原译文失败：\(error.localizedDescription)",
                        en: "Could not restore the generated translation: \(error.localizedDescription)"
                    )
                }
            }
        }
    }

    func clearUserTranslationOverrides() {
        let receipt = translationOverrideCoordinator.clearAll()
        Task {
            do {
                try await receipt.wait()
                cacheStatus = localized(
                    zh: "用户校对译文已清除；AI 与手写歌词缓存仍保留。",
                    en: "User translation edits cleared; AI and handwritten lyric caches were kept."
                )
                startLyricsLoad(for: playback.track)
            } catch {
                cacheStatus = error.localizedDescription
            }
        }
    }

    static let spotifyRedirectURI = "http://127.0.0.1:43821/oauth/callback"

    private func resetPresentedLyricsMetadata() {
        baseTranslationsByLineID = [:]
        overrideKeysByLineID = [:]
        presentedLyricsTrackID = nil
        presentedLyricDocument = nil
    }

    private func rememberPresentedLyrics(
        _ baseLyrics: [TimedLyric],
        trackID: String,
        sourceDocument: LyricDocument? = nil
    ) {
        presentedLyricsTrackID = trackID
        let baseDocument = sourceDocument ?? LyricDocument(
            trackID: trackID,
            sourceID: "lyris:presented",
            provider: "Lyris",
            timedLyrics: baseLyrics
        )
        presentedLyricDocument = synchronizedLyricDocument(
            baseDocument,
            with: baseLyrics,
            trackID: trackID
        )
        baseTranslationsByLineID = Dictionary(
            uniqueKeysWithValues: baseLyrics.map { ($0.id, $0.translation) }
        )
        overrideKeysByLineID = Dictionary(
            uniqueKeysWithValues: baseLyrics.map {
                ($0.id, UserTranslationOverrideKey.make(trackID: trackID, lyric: $0))
            }
        )
    }

    private func applyingUserTranslationOverrides(
        to baseLyrics: [TimedLyric],
        trackID: String,
        generation: UInt64,
        sourceDocument: LyricDocument? = nil
    ) async -> [TimedLyric]? {
        let overrides = await translationOverrideCoordinator.load(trackID: trackID)
        guard isCurrentLyricsLoad(trackID: trackID, generation: generation) else { return nil }
        let targetNormalized = LyricsTranslationDecision.fillingSameLanguageTranslation(
            in: baseLyrics,
            target: translationTarget
        )
        let presented = targetNormalized.map { lyric in
            let key = UserTranslationOverrideKey.make(trackID: trackID, lyric: lyric)
            guard let override = overrides[key] else { return lyric }
            var updated = lyric
            updated.translation = override
            return updated
        }
        rememberPresentedLyrics(
            targetNormalized,
            trackID: trackID,
            sourceDocument: sourceDocument
        )
        return presented
    }

    private func currentLyricDocumentForExport() -> LyricDocument? {
        guard !lyrics.isEmpty,
              let trackID = presentedLyricsTrackID,
              trackID == playback.track.id else { return nil }
        let baseDocument = presentedLyricDocument ?? LyricDocument(
            trackID: trackID,
            sourceID: "lyris:presented",
            provider: "Lyris",
            timedLyrics: lyrics
        )
        return synchronizedLyricDocument(baseDocument, with: lyrics, trackID: trackID)
    }

    private func synchronizedLyricDocument(
        _ document: LyricDocument,
        with presentedLyrics: [TimedLyric],
        trackID: String
    ) -> LyricDocument {
        let lyricsByID = Dictionary(uniqueKeysWithValues: presentedLyrics.map { ($0.id, $0) })
        guard document.lines.count == presentedLyrics.count,
              document.lines.allSatisfy({ lyricsByID[$0.id] != nil }) else {
            return LyricDocument(
                trackID: trackID,
                sourceID: document.source.sourceID,
                provider: document.source.provider,
                timedLyrics: presentedLyrics
            )
        }
        let lines = document.lines.map { line in
            guard let presented = lyricsByID[line.id] else { return line }
            var translations = line.translations
            let selectedTranslationIndex: Int?
            if let targetIndex = translations.firstIndex(where: {
                $0.targetLanguage == translationTarget.apiName
            }) {
                selectedTranslationIndex = targetIndex
            } else {
                selectedTranslationIndex = translations.indices.first
            }
            if let index = selectedTranslationIndex {
                translations[index].text = presented.translation
            } else if !presented.translation.isEmpty {
                translations.append(
                    LyricTranslation(
                        targetLanguage: translationTarget.apiName,
                        text: presented.translation
                    )
                )
            }
            return LyricLine(
                id: line.id,
                startTime: line.startTime,
                endTime: line.endTime,
                original: line.original,
                words: line.words,
                translations: translations,
                isEstimated: line.isEstimated || presented.isEstimated
            )
        }
        return LyricDocument(
            trackID: trackID,
            timingLevel: document.timingLevel,
            source: document.source,
            lines: lines
        )
    }

    private func lyricsCacheLookupKey(
        trackID: String,
        context: LyricsLoadContext
    ) -> LyricsCacheLookupKey {
        LyricsCacheLookupKey(
            trackID: trackID,
            targetLanguage: context.target.apiName,
            provider: context.provider.rawValue,
            model: context.model.isEmpty ? "provider-managed" : context.model,
            thinkingEnabled: context.thinkingEnabled,
            promptVersion: LyricsTranslationPrompt.version(for: context.translationStyle),
            schemaVersion: LyricsCacheFingerprint.currentSchemaVersion,
            appVersion: Self.lyricsCacheAppVersion
        )
    }

    private func startLyricsLoad(for track: Track) {
        cancelScheduledLyricsRetry()
        asyncTranslationCoordinator.cancel()
        lyricLoadTask?.cancel()
        lyricLoadGeneration &+= 1
        let generation = lyricLoadGeneration
        guard track.id != "spotify:idle" else {
            lyrics = []
            lyricPipelineStatus = nil
            lyricsPipelineState = .idle
            lyricLoadTask = nil
            return
        }
        lyricsPipelineState = .loading(trackID: track.id)
        let context = LyricsLoadContext(
            target: translationTarget,
            provider: translationProvider,
            baseURL: translationBaseURL.trimmingCharacters(in: .whitespacesAndNewlines),
            model: translationModel,
            thinkingEnabled: translationThinkingEnabled,
            translationStyle: translationStyle,
            apiKey: translationAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        lyricLoadTask = Task { [weak self] in
            guard let self else { return }
            await loadLyrics(for: track, generation: generation, context: context)
            if lyricLoadGeneration == generation {
                lyricLoadTask = nil
            }
        }
    }

    private func restartLyricsForConfigurationChange() {
        guard playback.track.id != "spotify:idle" else { return }
        lyrics = []
        lyricPipelineStatus = localized(
            zh: "正在按新的翻译配置加载歌词…",
            en: "Loading lyrics with the new translation settings…"
        )
        startLyricsLoad(for: playback.track)
    }

    private func isCurrentLyricsLoad(trackID: String, generation: UInt64) -> Bool {
        !Task.isCancelled
            && lyricLoadGeneration == generation
            && playback.track.id == trackID
    }

    private func cancelScheduledLyricsRetry() {
        lyricRetryTask?.cancel()
        lyricRetryTask = nil
        lyricRetryGate.cancel()
    }

    private func scheduleLyricsRetry(
        for track: Track,
        generation: UInt64,
        retryAfter: TimeInterval?
    ) {
        let key = LyricsRetryKey(trackID: track.id, generation: generation)
        guard lyricRetryGate.reserve(key) else { return }
        let requestedDelay = retryAfter ?? 5
        guard requestedDelay.isFinite else {
            lyricRetryGate.cancel()
            return
        }
        let delay = min(
            max(lyricsRetryMinimumDelay, requestedDelay),
            TimeInterval(UInt64.max / 1_000_000_000)
        )
        let delayNanoseconds = UInt64(delay * 1_000_000_000)
        lyricRetryTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: delayNanoseconds)
            guard !Task.isCancelled,
                  let self,
                  self.lyricRetryGate.consume(key),
                  self.isCurrentLyricsLoad(trackID: track.id, generation: generation) else {
                return
            }
            self.lyricRetryTask = nil
            self.lyricPipelineStatus = self.localized(
                zh: "限流等待结束，正在重试歌词…",
                en: "Rate-limit wait ended; retrying lyrics…"
            )
            self.startLyricsLoad(for: track)
        }
    }

    private func cachedLyricDocument(
        for entry: LyricsCacheEntry,
        trackID: String
    ) -> LyricDocument {
        if let document = entry.document {
            return synchronizedLyricDocument(document, with: entry.lyrics, trackID: trackID)
        }
        let sourceID = entry.fingerprint?.lyricsSourceID
            ?? (entry.source == .manual ? "lyris:user" : "lyris:cache")
        let provider = entry.fingerprint?.provider
            ?? (entry.source == .manual ? "User" : "Lyris Cache")
        return LyricDocument(
            trackID: trackID,
            sourceID: sourceID,
            provider: provider,
            timedLyrics: entry.lyrics
        )
    }

    private func markLyricsReady(
        trackID: String,
        document: LyricDocument,
        origin: LyricsLoadOrigin
    ) {
        lyricsPipelineState = .ready(
            trackID: trackID,
            source: document.source,
            timingLevel: document.timingLevel,
            origin: origin
        )
    }

    private func cancelTranslationTest() {
        translationTestTask?.cancel()
        translationTestTask = nil
        translationTestGeneration &+= 1
        isTestingTranslation = false
    }

    private func invalidatePendingTranslationConfiguration() {
        cancelTranslationTest()
        asyncTranslationCoordinator.cancel()
        lyricLoadTask?.cancel()
        lyricLoadTask = nil
        lyricLoadGeneration &+= 1
        isTranslationConnected = false
    }

    private func cancelSpotifyConnectionTasks() {
        spotifyAuthorizationTask?.cancel()
        spotifyAuthorizationTask = nil
        spotifyRestoreTask?.cancel()
        spotifyRestoreTask = nil
        spotifyConnectionGeneration &+= 1
        isAuthorizingSpotify = false
    }

    private func isCurrentTranslationTest(
        generation: UInt64,
        configuration: TranslationConfiguration
    ) -> Bool {
        !Task.isCancelled
            && translationTestGeneration == generation
            && translationProvider == configuration.provider
            && translationBaseURL.trimmingCharacters(in: .whitespacesAndNewlines) == configuration.baseURL
            && translationModel == configuration.model
            && translationThinkingEnabled == configuration.thinkingEnabled
    }

    private func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        return (error as? URLError)?.code == .cancelled || Task.isCancelled
    }

    private func loadLyrics(
        for track: Track,
        generation: UInt64,
        context: LyricsLoadContext
    ) async {
        guard track.id != "spotify:idle" else {
            lyrics = []
            lyricPipelineStatus = nil
            return
        }
        if let persisted = await lyricsCacheStore.loadManual(trackID: track.id),
           let cachedDuration = persisted.trackDuration,
           abs(cachedDuration - track.duration) <= 3 {
            let document = cachedLyricDocument(for: persisted, trackID: track.id)
            guard let presented = await applyingUserTranslationOverrides(
                to: persisted.lyrics,
                trackID: track.id,
                generation: generation,
                sourceDocument: document
            ) else { return }
            lyrics = presented
            markLyricsReady(trackID: track.id, document: document, origin: .userLocal)
            lyricPipelineStatus = localized(zh: "用户歌词 · 本机", en: "User lyrics · local")
            return
        }
        guard track.kind == .track else {
            guard isCurrentLyricsLoad(trackID: track.id, generation: generation) else { return }
            lyrics = []
            resetPresentedLyricsMetadata()
            lyricsPipelineState = .unsupported(trackID: track.id, kind: track.kind)
            lyricPipelineStatus = switch track.kind {
            case .episode:
                localized(
                    zh: "播客内容不自动搜索歌曲歌词",
                    en: "Song lyrics are not searched automatically for podcasts"
                )
            case .advertisement:
                localized(
                    zh: "广告播放期间不显示歌词",
                    en: "Lyrics are hidden during advertisements"
                )
            case .unknown:
                localized(zh: "当前内容无法识别", en: "This content could not be identified")
            case .track: nil
            }
            return
        }
        let lookupKey = lyricsCacheLookupKey(trackID: track.id, context: context)
        if let persisted = await lyricsCacheStore.loadLatestGenerated(matching: lookupKey),
           persisted.trackDuration.map({ abs($0 - track.duration) <= 3 }) ?? true {
            let document = cachedLyricDocument(for: persisted, trackID: track.id)
            guard let presented = await applyingUserTranslationOverrides(
                to: persisted.lyrics,
                trackID: track.id,
                generation: generation,
                sourceDocument: document
            ) else { return }
            lyrics = presented
            markLyricsReady(trackID: track.id, document: document, origin: .exactCache)
            if let fingerprint = persisted.fingerprint {
                lyricCache[fingerprint] = persisted.lyrics
            }
            translationCacheHits += 1
            persistAPIUsage()
            lyricPipelineStatus = localized(zh: "本机歌词 · 已缓存", en: "Local lyrics · cached")
            return
        }
        guard isCurrentLyricsLoad(trackID: track.id, generation: generation) else { return }
        do {
            try Task.checkCancellation()
            let providerResult = try await lyricsProvider.lyrics(for: track)
            guard isCurrentLyricsLoad(trackID: track.id, generation: generation) else { return }
            let sourceLyrics = providerResult.lyrics
            guard !sourceLyrics.isEmpty else {
                if await presentCompatibleGeneratedFallback(
                    for: track,
                    lookupKey: lookupKey,
                    generation: generation
                ) {
                    return
                }
                lyrics = []
                lyricsPipelineState = .noLyrics(trackID: track.id)
                lyricPipelineStatus = localized(zh: "未找到歌词", en: "No lyrics found")
                return
            }
            if LyricsTranslationDecision.sourceAlreadyMatchesTarget(
                lines: sourceLyrics.map(\.original),
                target: context.target
            ) {
                guard let presented = await applyingUserTranslationOverrides(
                    to: LyricsTranslationDecision.passthrough(sourceLyrics),
                    trackID: track.id,
                    generation: generation,
                    sourceDocument: providerResult.document
                ) else { return }
                lyrics = presented
                markLyricsReady(
                    trackID: track.id,
                    document: providerResult.document,
                    origin: .provider
                )
                lyricPipelineStatus = localized(
                    zh: "原文已是\(context.target.displayName(in: .simplifiedChinese)) · 未调用翻译 API",
                    en: "Lyrics already match \(context.target.displayName(in: .english)) · translation API skipped"
                )
                return
            }

            let fingerprint = LyricsCacheFingerprint(
                trackID: track.id,
                lyricsSourceID: providerResult.sourceID,
                originalLyricsHash: LyricsCacheFingerprint.originalLyricsHash(for: sourceLyrics),
                targetLanguage: context.target.apiName,
                provider: context.provider.rawValue,
                model: context.model.isEmpty ? "provider-managed" : context.model,
                thinkingEnabled: context.thinkingEnabled,
                promptVersion: LyricsTranslationPrompt.version(for: context.translationStyle),
                schemaVersion: LyricsCacheFingerprint.currentSchemaVersion,
                appVersion: Self.lyricsCacheAppVersion
            )

            if let persisted = await lyricsCacheStore.loadGenerated(fingerprint: fingerprint),
               persisted.trackDuration.map({ abs($0 - track.duration) <= 3 }) ?? true {
                let document = cachedLyricDocument(for: persisted, trackID: track.id)
                guard let presented = await applyingUserTranslationOverrides(
                    to: persisted.lyrics,
                    trackID: track.id,
                    generation: generation,
                    sourceDocument: document
                ) else { return }
                lyrics = presented
                markLyricsReady(trackID: track.id, document: document, origin: .exactCache)
                lyricCache[fingerprint] = persisted.lyrics
                translationCacheHits += 1
                persistAPIUsage()
                lyricPipelineStatus = localized(zh: "本机歌词 · 已缓存", en: "Local lyrics · cached")
                return
            }

            if let cached = lyricCache[fingerprint] {
                guard let presented = await applyingUserTranslationOverrides(
                    to: cached,
                    trackID: track.id,
                    generation: generation,
                    sourceDocument: providerResult.document
                ) else { return }
                lyrics = presented
                markLyricsReady(
                    trackID: track.id,
                    document: providerResult.document,
                    origin: .exactCache
                )
                translationCacheHits += 1
                persistAPIUsage()
                lyricPipelineStatus = nil
                return
            }

            guard let presentedSource = await applyingUserTranslationOverrides(
                to: sourceLyrics,
                trackID: track.id,
                generation: generation,
                sourceDocument: providerResult.document
            ) else { return }
            lyrics = presentedSource
            markLyricsReady(
                trackID: track.id,
                document: providerResult.document,
                origin: .provider
            )

            let key = context.apiKey
            guard !key.isEmpty else {
                if await presentCompatibleGeneratedFallback(
                    for: track,
                    lookupKey: lookupKey,
                    generation: generation
                ) {
                    return
                }
                lyricCache[fingerprint] = sourceLyrics
                guard isCurrentLyricsLoad(trackID: track.id, generation: generation) else { return }
                lyricPipelineStatus = localized(
                    zh: "未配置翻译 API",
                    en: "Translation API not configured"
                )
                return
            }
            lyricPipelineStatus = localized(
                zh: "正在调用 \(context.provider.displayName(in: .simplifiedChinese)) 翻译…",
                en: "Translating with \(context.provider.displayName(in: .english))…"
            )
            var requestConfiguration = context.translationConfiguration
            requestConfiguration.songContext = LyricsTranslationSongContext(
                title: track.title,
                artist: track.artist,
                album: track.album
            )
            let startedAt = Date()
            let translatedLines: [String]
            do {
                let completion = try await asyncTranslationCoordinator.translate(
                    request: AsyncTranslationRequest(
                        trackID: track.id,
                        generation: generation
                    )
                ) {
                    try await self.translationAdapter.translate(
                        lines: sourceLyrics.map(\.original),
                        targetLanguage: context.target.apiName,
                        configuration: requestConfiguration,
                        apiKey: key
                    )
                }
                guard case .translated(let completedLines) = completion else { return }
                translatedLines = completedLines
                guard isCurrentLyricsLoad(trackID: track.id, generation: generation) else { return }
                guard translatedLines.count == sourceLyrics.count else {
                    throw TranslationAdapterError.invalidResponse("服务返回的译文行数与原歌词不一致。")
                }
            } catch {
                if isCancellation(error) { return }
                guard isCurrentLyricsLoad(trackID: track.id, generation: generation) else { return }
                recordAPIUsage(
                    requests: 1,
                    lines: sourceLyrics.count,
                    succeeded: false,
                    latencyMilliseconds: Int(Date().timeIntervalSince(startedAt) * 1_000)
                )
                if await presentCompatibleGeneratedFallback(
                    for: track,
                    lookupKey: lookupKey,
                    generation: generation
                ) {
                    return
                }
                throw error
            }
            guard isCurrentLyricsLoad(trackID: track.id, generation: generation) else { return }
            let translated = zip(sourceLyrics, translatedLines).map { lyric, translation in
                TimedLyric(
                    id: lyric.id,
                    startTime: lyric.startTime,
                    original: lyric.original,
                    translation: translation,
                    isEstimated: lyric.isEstimated
                )
            }
            lyricCache[fingerprint] = translated
            try Task.checkCancellation()
            guard isCurrentLyricsLoad(trackID: track.id, generation: generation) else { return }
            do {
                try await saveLyricsToDisk(
                    translated,
                    for: track,
                    source: .generated,
                    translationTarget: context.target.apiName,
                    fingerprint: fingerprint,
                    sourceDocument: providerResult.document
                )
            } catch {
                if isCancellation(error) { return }
                guard isCurrentLyricsLoad(trackID: track.id, generation: generation) else { return }
                cacheStatus = localized(
                    zh: "歌词缓存保存失败：\(error.localizedDescription)",
                    en: "Could not save the lyric cache: \(error.localizedDescription)"
                )
            }
            guard isCurrentLyricsLoad(trackID: track.id, generation: generation) else { return }
            guard let presentedTranslation = await applyingUserTranslationOverrides(
                to: translated,
                trackID: track.id,
                generation: generation,
                sourceDocument: providerResult.document
            ) else { return }
            lyrics = presentedTranslation
            let usageEstimate = TranslationUsageEstimator.estimate(
                sourceLines: sourceLyrics.map(\.original),
                translatedLines: translatedLines,
                targetLanguage: context.target.apiName,
                style: context.translationStyle
            )
            recordAPIUsage(
                requests: 1,
                lines: sourceLyrics.count,
                succeeded: true,
                latencyMilliseconds: Int(Date().timeIntervalSince(startedAt) * 1_000),
                estimatedInputTokens: usageEstimate.inputTokens,
                estimatedOutputTokens: usageEstimate.outputTokens
            )
            lyricPipelineStatus = sourceLyrics.first?.isEstimated == true
                ? localized(zh: "估时歌词 · LRCLIB", en: "Estimated timing · LRCLIB")
                : nil
        } catch {
            if isCancellation(error) { return }
            guard isCurrentLyricsLoad(trackID: track.id, generation: generation) else { return }
            if await presentCompatibleGeneratedFallback(
                for: track,
                lookupKey: lookupKey,
                generation: generation
            ) {
                return
            }
            if lyrics.isEmpty {
                lyrics = []
                let failureState = LyricsPipelineFailureClassifier.state(
                    for: error,
                    trackID: track.id
                )
                lyricsPipelineState = failureState
                lyricPipelineStatus = failureState
                    .presentation(language: interfaceLanguage)?.title
                    ?? localized(zh: "歌词获取失败", en: "Could not load lyrics")
                if case .rateLimited(_, let retryAfter) = failureState {
                    scheduleLyricsRetry(
                        for: track,
                        generation: generation,
                        retryAfter: retryAfter
                    )
                }
            } else {
                lyricPipelineStatus = localized(zh: "翻译失败", en: "Translation failed")
            }
        }
    }

    private func presentCompatibleGeneratedFallback(
        for track: Track,
        lookupKey: LyricsCacheLookupKey,
        generation: UInt64
    ) async -> Bool {
        guard isCurrentLyricsLoad(trackID: track.id, generation: generation),
              let persisted = await lyricsCacheStore.loadCompatibleGeneratedFallback(
                  matching: lookupKey
              ),
              persisted.trackDuration.map({ abs($0 - track.duration) <= 3 }) ?? true else {
            return false
        }
        let document = cachedLyricDocument(for: persisted, trackID: track.id)
        guard let presented = await applyingUserTranslationOverrides(
            to: persisted.lyrics,
            trackID: track.id,
            generation: generation,
            sourceDocument: document
        ), isCurrentLyricsLoad(trackID: track.id, generation: generation) else {
            return false
        }
        lyrics = presented
        markLyricsReady(trackID: track.id, document: document, origin: .compatibleCache)
        if let fingerprint = persisted.fingerprint {
            lyricCache[fingerprint] = persisted.lyrics
        }
        translationCacheHits += 1
        persistAPIUsage()
        lyricPipelineStatus = localized(
            zh: "本机兼容缓存 · 当前服务不可用",
            en: "Compatible local cache · current service unavailable"
        )
        return true
    }

    private func saveLyricsToDisk(
        _ lyrics: [TimedLyric],
        for track: Track,
        source: LyricsCacheSource,
        translationTarget: String? = nil,
        fingerprint: LyricsCacheFingerprint? = nil,
        sourceDocument: LyricDocument? = nil
    ) async throws {
        try await lyricsCacheStore.save(
            LyricsCacheEntry(
                trackID: track.id,
                trackTitle: track.title,
                artist: track.artist,
                trackDuration: track.duration,
                translationTarget: source == .generated ? translationTarget : nil,
                savedAt: Date(),
                source: source,
                fingerprint: fingerprint,
                lyrics: lyrics,
                document: sourceDocument.map {
                    synchronizedLyricDocument($0, with: lyrics, trackID: track.id)
                }
            )
        )
    }

    private func restorePreferences() {
        registerStoredFonts()
        let displayPreferences = LyrisDisplayPreferences.load(from: defaults)
        interfaceLanguage = displayPreferences.interfaceLanguage
        translationTarget = displayPreferences.translationTarget
        translationFont = displayPreferences.translationFont
        customTranslationFontFamily = displayPreferences.customTranslationFontFamily
        interfaceSkin = displayPreferences.interfaceSkin
        artworkPresentationMode = displayPreferences.artworkPresentationMode
        floatingPresentationMode = displayPreferences.floatingPresentationMode
        macIslandExpandedHoldDuration = displayPreferences.macIslandExpandedHoldDuration
        macIslandExpansionTrigger = displayPreferences.macIslandExpansionTrigger
        macIslandHoverExpandDelay = displayPreferences.macIslandHoverExpandDelay
        menuBarLyricMode = displayPreferences.menuBarLyricMode
        convertsTraditionalChineseToSimplified = displayPreferences.convertsTraditionalChineseToSimplified
        do {
            spotifyClientID = try spotifyAuthorizer.configuredProfile()?.clientID ?? ""
            spotifyConnectionStatus = spotifyClientID.isEmpty
                ? localized(zh: "尚未配置", en: "Not configured")
                : localized(
                    zh: "Client ID 已保存 · 尚未授权",
                    en: "Client ID saved · not authorized"
                )
        } catch {
            spotifyClientID = ""
            if (error as? SpotifyAuthorizationCoreError) == .profileSelectionRequired {
                spotifyConnectionStatus = localized(
                    zh: "Spotify 配置冲突 · 本地模式仍可使用",
                    en: "Spotify configuration conflict · local mode still works"
                )
            } else {
                spotifyConnectionStatus = localized(
                    zh: "Spotify 配置读取失败 · 本地模式仍可使用",
                    en: "Could not read Spotify configuration · local mode still works"
                )
            }
            configurationStatus = spotifyConfigurationErrorMessage(error)
        }
        cardMode = .capsule
        defaults.set(CardMode.capsule.rawValue, forKey: "cardMode")
        if let raw = defaults.string(forKey: "linkedEffectStyle"),
           let saved = LinkedEffectStyle(rawValue: raw) {
            linkedEffectStyle = saved.normalized
            if saved != saved.normalized {
                defaults.set(saved.normalized.rawValue, forKey: "linkedEffectStyle")
            }
        }
        lyricTimingDelay = defaults.object(forKey: "lyricTimingDelay") == nil
            ? 0
            : defaults.double(forKey: "lyricTimingDelay")
        restoreAPIUsage()
        if let raw = defaults.string(forKey: "costCurrency"),
           let savedCurrency = CostCurrency(rawValue: raw) {
            costCurrency = savedCurrency
        }
        let storedRate = defaults.double(forKey: costCurrencyRateKey(for: costCurrency))
        costCurrencyUnitsPerUSD = costCurrency == .usd
            ? 1
            : storedRate > 0 ? storedRate : costCurrency.referenceUnitsPerUSD
        if let raw = defaults.string(forKey: "translationProvider"),
           let saved = TranslationProvider(rawValue: raw) {
            translationProvider = saved
        }
        translationBaseURL = defaults.string(forKey: "translationBaseURL")
            ?? translationProvider.defaultBaseURL
        let savedModel = defaults.string(forKey: "translationModel") ?? translationProvider.defaultModel
        if translationProvider == .deepSeek, ["deepseek-chat", "deepseek-reasoner"].contains(savedModel) {
            translationModel = TranslationProvider.deepSeek.defaultModel
        } else {
            translationModel = savedModel
        }
        availableTranslationModels = LyrisTranslationModelCatalogPersistence.load(
            provider: translationProvider,
            baseURL: translationBaseURL,
            from: defaults
        )
        if !availableTranslationModels.isEmpty,
           !availableTranslationModels.contains(translationModel),
           let firstModel = availableTranslationModels.first {
            translationModel = firstModel
        }
        let pricingMatchesConfiguration =
            defaults.string(forKey: "translationPricingProvider") == translationProvider.rawValue
            && defaults.string(forKey: "translationPricingModel") == translationModel
            && defaults.string(forKey: "translationPricingCatalogRevision")
                == TranslationPricingCatalog.revision
        if pricingMatchesConfiguration,
           defaults.object(forKey: "translationInputPriceUSDPerMillion") != nil,
           defaults.object(forKey: "translationOutputPriceUSDPerMillion") != nil {
            translationInputPriceUSDPerMillion = max(
                0,
                defaults.double(forKey: "translationInputPriceUSDPerMillion")
            )
            translationOutputPriceUSDPerMillion = max(
                0,
                defaults.double(forKey: "translationOutputPriceUSDPerMillion")
            )
        } else {
            applySuggestedTranslationPricing()
        }
        translationThinkingEnabled = defaults.object(forKey: "translationThinkingEnabled") as? Bool ?? false
        translationStyle = defaults.string(forKey: "lyricsTranslationStyle")
            .flatMap(LyricsTranslationStyle.init(rawValue:)) ?? .contextual
        translationAPIKey = ""
        persistProjectConfiguration()
    }

    private func registerStoredFonts() {
        let directory = LyrisDataLocation.fontsURL()
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return }
        for url in urls where ["otf", "ttf", "ttc"].contains(url.pathExtension.lowercased()) {
            _ = registerFont(at: url)
        }
    }

    private func refreshAvailableTranslationFonts() {
        availableTranslationFontOptions = LyrisInstalledFontCatalog.systemOptions()
    }

    private func registerFont(at url: URL) -> String? {
        var registrationError: Unmanaged<CFError>?
        _ = CTFontManagerRegisterFontsForURL(
            url as CFURL,
            .process,
            &registrationError
        )
        guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL)
                as? [CTFontDescriptor],
              let descriptor = descriptors.first,
              let family = CTFontDescriptorCopyAttribute(
                descriptor,
                kCTFontFamilyNameAttribute
              ) as? String else { return nil }
        return family
    }

    private func uniqueFontDestination(for filename: String, in directory: URL) -> URL {
        let proposed = directory.appendingPathComponent(filename)
        guard FileManager.default.fileExists(atPath: proposed.path) else { return proposed }
        let base = proposed.deletingPathExtension().lastPathComponent
        let ext = proposed.pathExtension
        return directory.appendingPathComponent(
            "\(base)-\(UUID().uuidString.prefix(8)).\(ext)"
        )
    }

    func authorizeSavedTranslationCredential() {
        restoreTranslationCredential(for: translationProvider, interaction: .userInitiated)
    }

    private func restoreTranslationCredential(
        for provider: TranslationProvider,
        interaction: CredentialReadInteraction = .silent
    ) {
        translationCredentialRestoreTask?.cancel()
        let vault = UncheckedCredentialVault(base: credentialVault)
        let account = provider.credentialAccount
        translationCredentialRestoreTask = Task { [weak self] in
            let outcome = await Task.detached(priority: .utility) {
                do {
                    return (
                        secret: try vault.base.read(account: account, interaction: interaction),
                        requiresAuthorization: false,
                        errorDescription: Optional<String>.none
                    )
                } catch {
                    return (
                        secret: Optional<String>.none,
                        requiresAuthorization:
                            (error as? KeychainError)?.requiresUserInteraction == true,
                        errorDescription: Optional(error.localizedDescription)
                    )
                }
            }.value
            guard !Task.isCancelled,
                  let self,
                  self.translationProvider == provider,
                  self.translationAPIKey.isEmpty else { return }
            if outcome.requiresAuthorization {
                self.translationCredentialRequiresAuthorization = true
                self.configurationStatus = self.localized(
                    zh: "检测到旧版本保存的 API Key。为避免启动时突然弹出系统密码框，请在翻译设置中主动允许读取一次。",
                    en: "A key saved by an earlier build was found. To avoid an unexpected password prompt at launch, authorize access once from Translation settings."
                )
                return
            }
            if let errorDescription = outcome.errorDescription {
                self.translationCredentialRequiresAuthorization = false
                if interaction == .userInitiated {
                    self.configurationStatus = errorDescription
                }
                return
            }
            self.translationCredentialRequiresAuthorization = false
            self.translationAPIKey = outcome.secret ?? ""
            if interaction == .userInitiated {
                self.configurationStatus = self.translationAPIKey.isEmpty
                    ? self.localized(
                        zh: "本机钥匙串中没有找到该翻译服务保存的 API Key。",
                        en: "No saved API key was found for this translation service."
                    )
                    : self.localized(
                        zh: "已读取本机保存的 API Key。选择“始终允许”后，本正式版本后续启动会静默读取。",
                        en: "The saved API key was loaded. After choosing Always Allow, this release will read it silently on later launches."
                    )
            }
            guard !self.translationAPIKey.isEmpty,
                  self.playback.track.id != "loading",
                  self.playback.track.id != "spotify:idle" else { return }
            self.startLyricsLoad(for: self.playback.track)
        }
    }

    private func hasStoredTranslationCredentialMetadata(
        for provider: TranslationProvider
    ) -> Bool {
        defaults.bool(forKey: translationCredentialMetadataKey(for: provider))
            || defaults.string(forKey: "translationProvider") == provider.rawValue
    }

    private func translationCredentialMetadataKey(
        for provider: TranslationProvider
    ) -> String {
        "translationCredentialStored.v1.\(provider.rawValue)"
    }

    private func restoreFirstUseState() {
        guard let data = defaults.data(forKey: Self.firstUseStateKey),
              let restored = try? JSONDecoder().decode(FirstUseFlowState.self, from: data) else {
            firstUseState = FirstUseFlowState()
            return
        }
        firstUseState = restored
    }

    private func persistFirstUseState() {
        guard let data = try? JSONEncoder().encode(firstUseState) else { return }
        defaults.set(data, forKey: Self.firstUseStateKey)
    }

    private func completeFirstUseAccountIfNeeded() {
        guard firstUseState.isFirstUse,
              firstUseState.currentStep == .accountEnhancement else { return }
        _ = firstUseState.transition(.accountEnhancementFinished)
        persistFirstUseState()
        firstUseSetupReturnStep = nil
        presentation = .firstUse
    }

    private func completeFirstUseTranslationIfNeeded() {
        guard firstUseState.isFirstUse,
              firstUseState.currentStep == .translation else { return }
        _ = firstUseState.transition(.translationFinished)
        persistFirstUseState()
        firstUseSetupReturnStep = nil
        presentation = .card
    }

    private func persistTranslationPreferences() {
        defaults.set(translationProvider.rawValue, forKey: "translationProvider")
        defaults.set(translationBaseURL.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "translationBaseURL")
        defaults.set(translationModel, forKey: "translationModel")
        defaults.set(translationThinkingEnabled, forKey: "translationThinkingEnabled")
        defaults.set(translationStyle.rawValue, forKey: "lyricsTranslationStyle")
        persistTranslationPricing()
        persistProjectConfiguration()
    }

    private func applySuggestedTranslationPricing() {
        let rates = TranslationPricingCatalog.suggestedRates(
            provider: translationProvider,
            model: translationModel
        )
        translationInputPriceUSDPerMillion = rates.inputUSDPerMillion
        translationOutputPriceUSDPerMillion = rates.outputUSDPerMillion
        persistTranslationPricing()
    }

    private func persistTranslationPricing() {
        defaults.set(
            translationInputPriceUSDPerMillion,
            forKey: "translationInputPriceUSDPerMillion"
        )
        defaults.set(
            translationOutputPriceUSDPerMillion,
            forKey: "translationOutputPriceUSDPerMillion"
        )
        defaults.set(translationProvider.rawValue, forKey: "translationPricingProvider")
        defaults.set(translationModel, forKey: "translationPricingModel")
        defaults.set(
            TranslationPricingCatalog.revision,
            forKey: "translationPricingCatalogRevision"
        )
    }

    private func persistDisplayPreferences() {
        LyrisDisplayPreferences(
            interfaceLanguage: interfaceLanguage,
            translationTarget: translationTarget,
            translationFont: translationFont,
            customTranslationFontFamily: customTranslationFontFamily,
            interfaceSkin: interfaceSkin,
            artworkPresentationMode: artworkPresentationMode,
            floatingPresentationMode: floatingPresentationMode,
            macIslandExpandedHoldDuration: macIslandExpandedHoldDuration,
            macIslandExpansionTrigger: macIslandExpansionTrigger,
            macIslandHoverExpandDelay: macIslandHoverExpandDelay,
            menuBarLyricMode: menuBarLyricMode,
            convertsTraditionalChineseToSimplified: convertsTraditionalChineseToSimplified
        ).save(to: defaults)
    }

    private func persistProjectConfiguration() {
        LyrisDataLocation.writeConfiguration(
            NonSecretConfigurationSnapshot(
                hasSpotifyClientID: !spotifyClientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                interfaceLanguage: interfaceLanguage.rawValue,
                translationProvider: translationProvider.rawValue,
                translationBaseURL: translationBaseURL,
                translationModel: translationModel,
                translationThinkingEnabled: translationThinkingEnabled,
                translationStyle: translationStyle.rawValue,
                translationTargetLanguage: translationTarget.apiName,
                translationFont: translationFont.rawValue,
                customTranslationFontFamily: customTranslationFontFamily,
                interfaceSkin: interfaceSkin.rawValue,
                artworkPresentationMode: artworkPresentationMode.rawValue,
                menuBarLyricMode: menuBarLyricMode.rawValue,
                floatingPresentationMode: floatingPresentationMode.rawValue,
                macIslandExpandedHoldDuration: macIslandExpandedHoldDuration.rawValue,
                macIslandExpansionTrigger: macIslandExpansionTrigger.rawValue,
                macIslandHoverExpandDelay: macIslandHoverExpandDelay,
                convertsTraditionalChineseToSimplified: convertsTraditionalChineseToSimplified,
                linkedEffectStyle: linkedEffectStyle.rawValue,
                costCurrency: costCurrency.rawValue,
                costCurrencyUnitsPerUSD: costCurrencyUnitsPerUSD,
                lyricTimingDelay: lyricTimingDelay,
                sensitiveValuesLocation: "macOS Keychain (API Key and Spotify refresh token)"
            )
        )
    }

    private func costCurrencyRateKey(for currency: CostCurrency) -> String {
        "costCurrencyUnitsPerUSD.\(currency.rawValue)"
    }

    private func restoreSpotifyConnectionIfPossible() {
        let clientID = spotifyClientID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clientID.isEmpty else { return }
        spotifyConnectionGeneration &+= 1
        let generation = spotifyConnectionGeneration
        spotifyRestoreTask?.cancel()
        spotifyRestoreTask = Task {
            defer {
                if spotifyConnectionGeneration == generation {
                    spotifyRestoreTask = nil
                }
            }
            do {
                guard let report = try await spotifyAuthorizer.restoreConnection(
                    clientID: clientID,
                    redirectURI: Self.spotifyRedirectURI
                ) else {
                    guard spotifyConnectionGeneration == generation, !Task.isCancelled else { return }
                    applySpotifyAuthorizationState(.disconnected)
                    spotifyConnectionStatus = localized(
                        zh: "Client ID 已保存 · 尚未授权",
                        en: "Client ID saved · not authorized"
                    )
                    return
                }
                guard spotifyConnectionGeneration == generation, !Task.isCancelled else { return }
                let restoredState = restoredSpotifyAuthorizationState(profile: report.profile)
                applySpotifyAuthorizationState(restoredState)
                switch restoredState {
                case .connected:
                    spotifyConnectionStatus = localized(
                        zh: "已连接 · \(report.displayName)",
                        en: "Connected · \(report.displayName)"
                    )
                case .expiringSoon:
                    spotifyConnectionStatus = localized(
                        zh: "已连接 · \(report.displayName) · 授权即将到期",
                        en: "Connected · \(report.displayName) · authorization expiring soon"
                    )
                case .reauthorizationRequired:
                    spotifyConnectionStatus = localized(
                        zh: "授权已失效 · 请重新授权",
                        en: "Authorization expired · reconnect"
                    )
                case .permissionRequired:
                    spotifyConnectionStatus = localized(
                        zh: "已连接 · Spotify 权限不足，请重新授权",
                        en: "Connected · Spotify permission missing; reconnect"
                    )
                case .disconnected, .authorizing, .failed:
                    break
                }
            } catch {
                guard spotifyConnectionGeneration == generation, !Task.isCancelled else { return }
                isSpotifyConnected = false
                if isReauthorizationError(error) {
                    spotifyAuthorizationState = .reauthorizationRequired
                    spotifyConnectionStatus = localized(
                        zh: "授权已失效 · 请重新授权",
                        en: "Authorization expired · reconnect"
                    )
                } else if let failure = error as? SpotifyNetworkFailure,
                          failure == .offline || failure == .transport {
                    spotifyAuthorizationState = .disconnected
                    spotifyConnectionStatus = localized(
                        zh: "网络不可用 · 本地模式仍可使用",
                        en: "Network unavailable · local mode still works"
                    )
                } else if let coreError = error as? SpotifyAuthorizationCoreError,
                          case .authorizationModeUnavailable = coreError {
                    spotifyAuthorizationState = .disconnected
                    spotifyConnectionStatus = localized(
                        zh: "实验授权模式未启用 · 请使用 PKCE 重新连接",
                        en: "Experimental authorization is disabled · reconnect with PKCE"
                    )
                    configurationStatus = localized(
                        zh: "请在 Spotify 设置中确认 Client ID，然后保存并使用 PKCE 重新连接。",
                        en: "Confirm the Client ID in Spotify settings, then save and reconnect with PKCE."
                    )
                } else {
                    spotifyAuthorizationState = authorizationFailureState(for: error)
                    spotifyConnectionStatus = spotifyAuthorizationState == .permissionRequired
                        ? localized(
                            zh: "Spotify 权限不足 · 请重新授权所需范围",
                            en: "Spotify permission missing · reconnect with required scopes"
                        )
                        : localized(
                            zh: "连接失败 · 请稍后重试",
                            en: "Connection failed · try again later"
                        )
                }
            }
        }
    }

    private func applySpotifyAuthorizationState(_ state: SpotifyAuthorizationState) {
        spotifyAuthorizationState = state
        switch state {
        case .connected, .expiringSoon, .permissionRequired:
            isSpotifyConnected = true
        case .reauthorizationRequired:
            likedIntentCoordinator.cancel()
            isSpotifyConnected = false
            spotifyConnectionStatus = localized(
                zh: "授权已失效 · 请重新授权",
                en: "Authorization expired · reconnect"
            )
        case .failed:
            likedIntentCoordinator.cancel()
            isSpotifyConnected = false
            spotifyConnectionStatus = localized(
                zh: "Spotify 权限不足或请求失败",
                en: "Spotify permission missing or request failed"
            )
        case .disconnected, .authorizing:
            likedIntentCoordinator.cancel()
            isSpotifyConnected = false
        }
    }

    private func restoredSpotifyAuthorizationState(
        profile: SpotifyAuthorizationProfile?
    ) -> SpotifyAuthorizationState {
        guard let authorizedAt = profile?.authorizedAt else {
            return .connected
        }
        switch SpotifyRefreshTokenLifetimePolicy().status(originalAuthorizationDate: authorizedAt) {
        case .valid:
            return .connected
        case .reauthorizationReminderDue:
            return .expiringSoon
        case .expired:
            // `authorizedAt` is only a local reminder timestamp. Spotify's
            // token endpoint remains the authority: only `invalid_grant`
            // transitions the app into mandatory reauthorization.
            return .expiringSoon
        }
    }

    private func applySpotifyConfigurationFailure(_ error: Error) {
        cancelSpotifyConnectionTasks()
        isSpotifyConnected = false
        switch error as? SpotifyAuthorizationCoreError {
        case .profileSelectionRequired:
            spotifyAuthorizationState = .disconnected
            spotifyConnectionStatus = localized(
                zh: "Spotify 配置冲突 · 本地模式仍可使用",
                en: "Spotify configuration conflict · local mode still works"
            )
        case .credentialCleanupFailed, .credentialRollbackFailed:
            spotifyAuthorizationState = .reauthorizationRequired
            spotifyConnectionStatus = localized(
                zh: "Spotify 凭证状态需修复 · 请重新授权",
                en: "Spotify credentials need attention · reconnect"
            )
        default:
            spotifyAuthorizationState = .disconnected
            spotifyConnectionStatus = localized(
                zh: "Spotify 配置保存失败 · 本地模式仍可使用",
                en: "Could not save Spotify configuration · local mode still works"
            )
        }
        configurationStatus = spotifyConfigurationErrorMessage(error)
    }

    private func spotifyConfigurationErrorMessage(_ error: Error) -> String {
        switch error as? SpotifyAuthorizationCoreError {
        case .profileSelectionRequired:
            localized(
                zh: "检测到多个 Spotify 配置。为避免使用错误账户，账户增强已停用；本地歌词与播放识别仍可使用。",
                en: "Multiple Spotify profiles were found. Account enhancements are disabled to avoid using the wrong account; local lyrics and playback detection still work."
            )
        case .credentialCleanupFailed:
            localized(
                zh: "Spotify 账户会话已停用，但 Keychain 中的旧 Client Secret 清理失败。账户增强保持关闭，请检查 Keychain 后重新授权。",
                en: "The Spotify account session was disabled, but the old Client Secret could not be removed from Keychain. Account enhancements remain off; check Keychain and reconnect."
            )
        case .credentialRollbackFailed:
            localized(
                zh: "Spotify 配置保存失败，Refresh Token 回滚也未完成。账户增强已关闭，请重新授权。",
                en: "Spotify configuration failed and the refresh-token rollback did not complete. Account enhancements are off; reconnect."
            )
        default:
            error.localizedDescription
        }
    }

    private func isReauthorizationError(_ error: Error) -> Bool {
        if let error = error as? SpotifyAuthorizationCoreError {
            return error == .credentialCleanupFailed || error == .credentialRollbackFailed
        }
        if let error = error as? SpotifySessionError {
            return error == .reauthorizationRequired || error == .credentialCleanupFailed
        }
        return (error as? SpotifyNetworkFailure) == .invalidGrant
    }

    private func authorizationFailureState(for error: Error) -> SpotifyAuthorizationState {
        if isReauthorizationError(error) { return .reauthorizationRequired }
        if (error as? SpotifyNetworkFailure) == .forbidden { return .permissionRequired }
        return .failed
    }

    private func restoreAPIUsage() {
        let today = Self.usageDayKey()
        guard defaults.string(forKey: "apiUsageDay") == today else {
            defaults.set(today, forKey: "apiUsageDay")
            persistAPIUsage()
            return
        }
        apiRequestCount = defaults.integer(forKey: "apiRequestCount")
        apiSuccessCount = defaults.integer(forKey: "apiSuccessCount")
        apiFailureCount = defaults.integer(forKey: "apiFailureCount")
        translatedLineCount = defaults.integer(forKey: "translatedLineCount")
        translationCacheHits = defaults.integer(forKey: "translationCacheHits")
        estimatedInputTokenCount = defaults.integer(forKey: "estimatedInputTokenCount")
        estimatedOutputTokenCount = defaults.integer(forKey: "estimatedOutputTokenCount")
        estimatedAPICostUSD = max(0, defaults.double(forKey: "estimatedAPICostUSD"))
        let latency = defaults.integer(forKey: "lastAPILatencyMilliseconds")
        lastAPILatencyMilliseconds = latency > 0 ? latency : nil
    }

    private func recordAPIUsage(
        requests: Int,
        lines: Int,
        succeeded: Bool,
        latencyMilliseconds: Int,
        estimatedInputTokens: Int = 0,
        estimatedOutputTokens: Int = 0
    ) {
        if defaults.string(forKey: "apiUsageDay") != Self.usageDayKey() {
            apiRequestCount = 0
            apiSuccessCount = 0
            apiFailureCount = 0
            translatedLineCount = 0
            translationCacheHits = 0
            estimatedInputTokenCount = 0
            estimatedOutputTokenCount = 0
            estimatedAPICostUSD = 0
        }
        apiRequestCount += requests
        if succeeded {
            apiSuccessCount += requests
            translatedLineCount += lines
        } else {
            apiFailureCount += requests
        }
        let inputTokens = max(0, estimatedInputTokens)
        let outputTokens = max(0, estimatedOutputTokens)
        estimatedInputTokenCount += inputTokens
        estimatedOutputTokenCount += outputTokens
        estimatedAPICostUSD += activeTranslationPricing.estimatedCostUSD(
            inputTokens: inputTokens,
            outputTokens: outputTokens
        )
        lastAPILatencyMilliseconds = max(0, latencyMilliseconds)
        persistAPIUsage()
    }

    private func persistAPIUsage() {
        defaults.set(Self.usageDayKey(), forKey: "apiUsageDay")
        defaults.set(apiRequestCount, forKey: "apiRequestCount")
        defaults.set(apiSuccessCount, forKey: "apiSuccessCount")
        defaults.set(apiFailureCount, forKey: "apiFailureCount")
        defaults.set(translatedLineCount, forKey: "translatedLineCount")
        defaults.set(translationCacheHits, forKey: "translationCacheHits")
        defaults.set(estimatedInputTokenCount, forKey: "estimatedInputTokenCount")
        defaults.set(estimatedOutputTokenCount, forKey: "estimatedOutputTokenCount")
        defaults.set(estimatedAPICostUSD, forKey: "estimatedAPICostUSD")
        defaults.set(lastAPILatencyMilliseconds ?? 0, forKey: "lastAPILatencyMilliseconds")
    }

    private static func usageDayKey() -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
}

enum SettingsSection: String, CaseIterable, Identifiable {
    case language = "语言与字体"
    case spotify = "Spotify"
    case translation = "翻译 API"
    case appearance = "外观与联动"
    case window = "卡片与隐藏"
    case usage = "使用统计"
    case storage = "歌词与缓存"

    var id: Self { self }

    var icon: String {
        switch self {
        case .language: "character.book.closed"
        case .spotify: "music.note"
        case .translation: "character.bubble"
        case .appearance: "sparkles"
        case .window: "rectangle.compress.vertical"
        case .usage: "chart.bar.xaxis"
        case .storage: "externaldrive"
        }
    }

    func title(in language: AppLanguage) -> String {
        switch self {
        case .language: language.pick(zh: "语言与字体", en: "Language & Fonts")
        case .spotify: "Spotify"
        case .translation: language.pick(zh: "翻译 API", en: "Translation API")
        case .appearance: language.pick(zh: "外观与联动", en: "Appearance & Motion")
        case .window: language.pick(zh: "卡片与隐藏", en: "Card & Stowing")
        case .usage: language.pick(zh: "使用统计", en: "Usage")
        case .storage: language.pick(zh: "歌词与缓存", en: "Lyrics & Cache")
        }
    }

    func detail(in language: AppLanguage) -> String {
        switch self {
        case .language: language.pick(zh: "切换界面语言、翻译目标语言和译文字体。", en: "Choose the interface language, translation target, and lyric font.")
        case .spotify: language.pick(
            zh: "本地模式只读取当前 Mac；Windows、手机等其他设备播放与收藏同步需要账户授权。",
            en: "Local mode reads this Mac only; Windows/mobile playback and Liked Songs sync require account authorization."
        )
        case .translation: language.pick(zh: "配置低延迟翻译模型与安全保存的 API Key。", en: "Configure a low-latency translation model and securely stored API key.")
        case .appearance: language.pick(zh: "选择悬浮卡片或顶部灵动岛，并设置边框、波形和进度的联动质感。", en: "Choose Floating Card or Top Island and tune linked border, waveform, and progress effects.")
        case .window: language.pick(zh: "调整卡片尺寸，并选择侧边或顶部自动隐藏。", en: "Resize the card and configure side or top stowing.")
        case .usage: language.pick(zh: "查看 Lyris 在本机记录的调用次数与延迟。", en: "Review locally recorded request counts and latency.")
        case .storage: language.pick(zh: "管理项目内歌词库、封面缓存和用户歌词。", en: "Manage the project lyric library, artwork cache, and user lyrics.")
        }
    }
}

private extension TranslationProvider {
    var credentialAccount: String {
        "translation.\(rawValue)"
    }
}

private struct UncheckedCredentialVault: @unchecked Sendable {
    let base: any CredentialVault
}
