import CoreGraphics
import Foundation

enum LyricDisplayMode: String, CaseIterable, Identifiable {
    case original = "原文"
    case bilingual = "双语"
    case translated = "译文"

    var id: Self { self }

    func displayName(in language: AppLanguage) -> String {
        switch self {
        case .original: language.pick(zh: "原文", en: "Original")
        case .bilingual: language.pick(zh: "双语", en: "Bilingual")
        case .translated: language.pick(zh: "译文", en: "Translation")
        }
    }
}

enum CardMode: String, CaseIterable, Identifiable {
    case capsule = "标准"
    case compact = "紧凑"
    case text = "纯词"

    var id: Self { self }

    func displayName(in language: AppLanguage) -> String {
        switch self {
        case .capsule: language.pick(zh: "标准", en: "Standard")
        case .compact: language.pick(zh: "紧凑", en: "Compact")
        case .text: language.pick(zh: "纯词", en: "Lyrics only")
        }
    }

    var next: CardMode {
        switch self {
        case .capsule: .compact
        case .compact: .text
        case .text: .capsule
        }
    }

    var logicalSize: CGSize {
        switch self {
        case .capsule: CGSize(width: 424, height: 116)
        case .compact: CGSize(width: 344, height: 92)
        case .text: CGSize(width: 332, height: 82)
        }
    }
}

enum FloatingPresentationMode: String, Codable, CaseIterable, Identifiable {
    case floatingCard
    case topIsland
    case desktopLyrics

    var id: Self { self }

    static var allCases: [Self] { [.topIsland, .floatingCard, .desktopLyrics] }

    func displayName(in language: AppLanguage) -> String {
        switch self {
        case .floatingCard: language.pick(zh: "悬浮条", en: "Floating Bar")
        case .topIsland: language.pick(zh: "灵动岛", en: "Mac Island")
        case .desktopLyrics: language.pick(zh: "桌面歌词", en: "Desktop Lyrics")
        }
    }

    func guidance(in language: AppLanguage) -> String {
        switch self {
        case .topIsland:
            language.pick(zh: "适合带刘海或顶部黑块的 Mac", en: "For Macs with a camera housing")
        case .floatingCard:
            language.pick(zh: "适合无刘海外屏，可自由移动", en: "For external displays; freely movable")
        case .desktopLyrics:
            language.pick(zh: "完整歌词阅读与可调窗口", en: "Full lyrics in a resizable window")
        }
    }

    var symbolName: String {
        switch self {
        case .topIsland: "macbook"
        case .floatingCard: "rectangle"
        case .desktopLyrics: "text.alignleft"
        }
    }

    var next: Self {
        switch self {
        case .topIsland: .floatingCard
        case .floatingCard: .desktopLyrics
        case .desktopLyrics: .topIsland
        }
    }
}

enum MacIslandExpandedHoldDuration: String, Codable, CaseIterable, Identifiable {
    case brief
    case balanced
    case relaxed
    case persistent

    var id: Self { self }

    var seconds: TimeInterval? {
        switch self {
        case .brief: 1.5
        case .balanced: 3
        case .relaxed: 6
        case .persistent: nil
        }
    }

    func displayName(in language: AppLanguage) -> String {
        switch self {
        case .brief: language.pick(zh: "1.5 秒", en: "1.5 sec")
        case .balanced: language.pick(zh: "3 秒", en: "3 sec")
        case .relaxed: language.pick(zh: "6 秒", en: "6 sec")
        case .persistent: language.pick(zh: "保持展开", en: "Keep open")
        }
    }
}

enum MacIslandExpansionTrigger: String, Codable, CaseIterable, Identifiable {
    case hover
    case click
    case hoverAndClick

    var id: Self { self }

    var allowsHover: Bool {
        self == .hover || self == .hoverAndClick
    }

    var allowsClick: Bool {
        self == .click || self == .hoverAndClick
    }

    func displayName(in language: AppLanguage) -> String {
        switch self {
        case .hover:
            language.pick(zh: "鼠标悬停", en: "Pointer hover")
        case .click:
            language.pick(zh: "鼠标点击", en: "Pointer click")
        case .hoverAndClick:
            language.pick(zh: "悬停或点击（推荐）", en: "Hover or click (recommended)")
        }
    }

    func guidance(in language: AppLanguage) -> String {
        switch self {
        case .hover:
            language.pick(zh: "持续停留达到设定时长后展开。", en: "Expands after the configured dwell time.")
        case .click:
            language.pick(zh: "点击收起状态即可立即展开。", en: "Click the compact island to expand immediately.")
        case .hoverAndClick:
            language.pick(zh: "既可等待悬停，也可点击立即展开。", en: "Wait for hover or click to expand immediately.")
        }
    }
}

enum LyrisPlaybackProgress {
    static func value(position: TimeInterval, duration: TimeInterval) -> Double {
        guard position.isFinite, duration.isFinite, duration > 0 else { return 0 }
        return min(max(position / duration, 0), 1)
    }
}

enum LyrisLyricLineProgress {
    static func activeIndex(
        position: TimeInterval,
        timingDelay: TimeInterval,
        lyrics: [TimedLyric]
    ) -> Int? {
        guard !lyrics.isEmpty else { return nil }
        let adjustedPosition = max(0, position - timingDelay)
        return lyrics.lastIndex(where: { $0.startTime <= adjustedPosition }) ?? 0
    }

    static func value(
        position: TimeInterval,
        timingDelay: TimeInterval,
        lyrics: [TimedLyric],
        trackDuration: TimeInterval
    ) -> Double {
        guard let index = activeIndex(
            position: position,
            timingDelay: timingDelay,
            lyrics: lyrics
        ) else { return 0 }
        let adjustedPosition = max(0, position - timingDelay)
        let start = lyrics[index].startTime
        let nextStart = lyrics.dropFirst(index + 1)
            .first(where: { $0.startTime > start })?
            .startTime
        let fallbackEnd = trackDuration > start ? trackDuration : start + 4
        let end = nextStart ?? fallbackEnd
        guard end > start else { return 0 }
        return min(max((adjustedPosition - start) / (end - start), 0), 1)
    }
}

enum LyrisLyricTextProgress {
    static func value(
        position: TimeInterval,
        timingDelay: TimeInterval,
        line: LyricLine?,
        fallback: Double
    ) -> Double {
        let fallback = min(max(fallback, 0), 1)
        guard let line else { return fallback }
        let timedWords = line.words.filter { word in
            guard let start = word.startTime, let end = word.endTime else { return false }
            return start.isFinite && end.isFinite && end > start
        }
        guard !timedWords.isEmpty else { return fallback }

        let adjustedPosition = max(0, position - timingDelay)
        let totalWeight = timedWords.reduce(0.0) { partial, word in
            partial + Double(max(word.text.count, 1))
        }
        guard totalWeight > 0 else { return fallback }

        let completedWeight = timedWords.reduce(0.0) { partial, word in
            guard let start = word.startTime, let end = word.endTime else { return partial }
            let wordProgress = min(max((adjustedPosition - start) / (end - start), 0), 1)
            return partial + Double(max(word.text.count, 1)) * wordProgress
        }
        return min(max(completedWeight / totalWeight, 0), 1)
    }
}

enum LyrisCompactLyricContextPolicy {
    static func shouldShowNextLine(showsAdjacentLyrics: Bool) -> Bool {
        // The compact translation slot must never preview the next line.
        // Taller layouts may show it as clearly separated lyric context.
        showsAdjacentLyrics
    }
}

enum LinkedEffectStyle: String, CaseIterable, Identifiable {
    case aurora = "柔光"
    case pulse = "脉冲"
    case spectrum = "流彩"
    case off = "关闭"

    var id: Self { self }

    // Keep `spectrum` decodable for existing local preferences, but remove it
    // from every user-facing selector. Its former multi-colour treatment is
    // intentionally migrated to the shared light-flow language.
    static var allCases: [Self] { [.aurora, .pulse, .off] }

    var normalized: Self {
        self == .spectrum ? .aurora : self
    }

    func displayName(in language: AppLanguage) -> String {
        switch self {
        case .aurora: language.pick(zh: "柔光", en: "Aurora")
        case .pulse: language.pick(zh: "脉冲", en: "Pulse")
        case .spectrum: language.pick(zh: "流彩", en: "Spectrum")
        case .off: language.pick(zh: "关闭", en: "Off")
        }
    }

    var next: Self {
        switch self {
        case .aurora: .pulse
        case .pulse: .off
        case .spectrum: .aurora
        case .off: .aurora
        }
    }

    var profile: LyrisLinkedEffectProfile {
        switch self {
        case .aurora:
            LyrisLinkedEffectProfile(
                isEnabled: true,
                borderIntensity: 0.24,
                glowRadius: 34,
                animationRate: 0.38,
                colorStopCount: 2
            )
        case .pulse:
            LyrisLinkedEffectProfile(
                isEnabled: true,
                borderIntensity: 0.38,
                glowRadius: 38,
                animationRate: 1.18,
                colorStopCount: 2
            )
        case .spectrum:
            LinkedEffectStyle.aurora.profile
        case .off:
            LyrisLinkedEffectProfile(
                isEnabled: false,
                borderIntensity: 0,
                glowRadius: 0,
                animationRate: 0,
                colorStopCount: 0
            )
        }
    }
}

struct LyrisLinkedEffectProfile: Equatable, Hashable, Sendable {
    let isEnabled: Bool
    let borderIntensity: Double
    let glowRadius: Double
    let animationRate: Double
    let colorStopCount: Int
}

enum WindowPresentation: Equatable {
    case card
    case menu
    case lyricsPartial
    case lyricsFull
    case translationEditor
    case manualLyricsEditor
    case settings
    case firstUse

    func logicalSize(cardMode: CardMode) -> CGSize {
        switch self {
        case .card: cardMode.logicalSize
        case .menu: CardMode.capsule.logicalSize
        case .lyricsPartial, .lyricsFull, .translationEditor, .manualLyricsEditor: CGSize(width: 620, height: 560)
        case .settings, .firstUse: CGSize(width: 620, height: 560)
        }
    }
}

enum LyrisWindowTarget: Equatable {
    case main
    case lyrics
    case settings
}

enum LyrisWindowRouting {
    static func target(for presentation: WindowPresentation) -> LyrisWindowTarget {
        switch presentation {
        case .card, .menu:
            .main
        case .lyricsPartial, .lyricsFull, .translationEditor, .manualLyricsEditor:
            .lyrics
        case .settings, .firstUse:
            .settings
        }
    }
}

enum LyricAutoScrollPolicy {
    static func shouldFollowActiveLine(in presentation: WindowPresentation) -> Bool {
        switch presentation {
        case .lyricsPartial, .lyricsFull:
            true
        default:
            false
        }
    }
}

enum PlaybackItemKind: String, Codable, Equatable, Sendable {
    case track
    case episode
    case advertisement
    case unknown
}

enum PlaybackSourceKind: String, Codable, Equatable, Sendable {
    case local
    case web
    case hybrid
    case demo
    case unavailable
    case unknown
}

struct Track: Equatable, Identifiable {
    let id: String
    let title: String
    let artist: String
    let album: String
    let duration: TimeInterval
    let artworkURL: URL?
    let kind: PlaybackItemKind

    init(
        id: String,
        title: String,
        artist: String,
        album: String,
        duration: TimeInterval,
        artworkURL: URL? = nil,
        kind: PlaybackItemKind = .track
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.artworkURL = artworkURL
        self.kind = kind
    }
}

struct TimedLyric: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let startTime: TimeInterval
    let original: String
    var translation: String
    let isEstimated: Bool

    init(
        id: UUID = UUID(),
        startTime: TimeInterval,
        original: String,
        translation: String,
        isEstimated: Bool = false
    ) {
        self.id = id
        self.startTime = startTime
        self.original = original
        self.translation = translation
        self.isEstimated = isEstimated
    }
}

enum LyrisLyricDisplayPolicy {
    static func originalText(
        _ text: String,
        convertsTraditionalChineseToSimplified: Bool
    ) -> String {
        guard convertsTraditionalChineseToSimplified else { return text }
        return LyricsMetadataCanonicalizer.simplifiedChinese(text)
    }

    static func secondaryText(
        for current: TimedLyric,
        in lyrics: [TimedLyric],
        translatedText: String?,
        convertsTraditionalChineseToSimplified: Bool,
        showsAdjacentLyrics: Bool = true
    ) -> String? {
        let original = originalText(
            current.original,
            convertsTraditionalChineseToSimplified: convertsTraditionalChineseToSimplified
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        let translation = translatedText.map {
            originalText(
                $0,
                convertsTraditionalChineseToSimplified: convertsTraditionalChineseToSimplified
            ).trimmingCharacters(in: .whitespacesAndNewlines)
        } ?? ""
        if !translation.isEmpty, translation != original {
            return translation
        }
        guard LyrisCompactLyricContextPolicy.shouldShowNextLine(
            showsAdjacentLyrics: showsAdjacentLyrics
        ) else { return nil }
        guard let index = lyrics.firstIndex(where: { $0.id == current.id }),
              lyrics.indices.contains(index + 1) else { return nil }
        let next = originalText(
            lyrics[index + 1].original,
            convertsTraditionalChineseToSimplified: convertsTraditionalChineseToSimplified
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        return next.isEmpty || next == original ? nil : next
    }
}

enum LyrisSeekInteraction {
    static func normalizedProgress(x: CGFloat, width: CGFloat) -> Double {
        guard width.isFinite, width > 0, x.isFinite else { return 0 }
        return min(max(Double(x / width), 0), 1)
    }

    static func position(x: CGFloat, width: CGFloat, duration: TimeInterval) -> TimeInterval {
        guard duration.isFinite, duration > 0 else { return 0 }
        return normalizedProgress(x: x, width: width) * duration
    }
}

enum LikedSongsState: Equatable, Sendable {
    case unavailable
    case unknown
    case checking(lastKnown: Bool?)
    case value(Bool)
    case updating(desired: Bool, previous: Bool?)
    case failed(lastKnown: Bool?)

    var displayedValue: Bool? {
        switch self {
        case .value(let value): value
        case .checking(let lastKnown), .failed(let lastKnown): lastKnown
        case .updating(let desired, _): desired
        case .unavailable, .unknown: nil
        }
    }
}

struct PlaybackCapabilities: OptionSet, Equatable, Sendable {
    let rawValue: UInt16

    static let metadata = Self(rawValue: 1 << 0)
    static let transport = Self(rawValue: 1 << 1)
    static let seek = Self(rawValue: 1 << 2)
    static let shuffle = Self(rawValue: 1 << 3)
    static let repeatMode = Self(rawValue: 1 << 4)
    static let likedSongsRead = Self(rawValue: 1 << 5)
    static let likedSongsWrite = Self(rawValue: 1 << 6)
    static let remoteDevices = Self(rawValue: 1 << 7)
    static let transferPlayback = Self(rawValue: 1 << 8)
    static let volume = Self(rawValue: 1 << 9)

    static let localCompanion: Self = [
        .metadata,
        .transport,
        .seek,
        .shuffle,
        .repeatMode,
        .volume,
    ]
    static let accountPlayback: Self = [
        .metadata,
        .transport,
        .seek,
        .shuffle,
        .repeatMode,
        .volume,
        .likedSongsRead,
        .likedSongsWrite,
    ]
}

struct PlaybackSnapshot: Equatable {
    var track: Track
    var position: TimeInterval
    var isPlaying: Bool
    var likedState: LikedSongsState
    var isShuffled: Bool
    var repeatMode: RepeatMode
    var volume: Double?
    var capabilities: PlaybackCapabilities
    var source: PlaybackSourceKind

    var isLiked: Bool {
        get { likedState.displayedValue ?? false }
        set { likedState = .value(newValue) }
    }

    init(
        track: Track,
        position: TimeInterval,
        isPlaying: Bool,
        likedState: LikedSongsState,
        isShuffled: Bool,
        repeatMode: RepeatMode,
        volume: Double? = nil,
        capabilities: PlaybackCapabilities,
        source: PlaybackSourceKind = .unknown
    ) {
        self.track = track
        self.position = position
        self.isPlaying = isPlaying
        self.likedState = likedState
        self.isShuffled = isShuffled
        self.repeatMode = repeatMode
        self.volume = volume.map { min(max($0, 0), 1) }
        self.capabilities = capabilities
        self.source = source
    }

    init(
        track: Track,
        position: TimeInterval,
        isPlaying: Bool,
        isLiked: Bool,
        isShuffled: Bool,
        repeatMode: RepeatMode,
        volume: Double? = nil,
        capabilities: PlaybackCapabilities = .accountPlayback,
        source: PlaybackSourceKind = .unknown
    ) {
        self.init(
            track: track,
            position: position,
            isPlaying: isPlaying,
            likedState: .value(isLiked),
            isShuffled: isShuffled,
            repeatMode: repeatMode,
            volume: volume,
            capabilities: capabilities,
            source: source
        )
    }
}

enum LyrisLyricsReloadPolicy {
    static func shouldReload(
        previous: PlaybackSnapshot,
        next: PlaybackSnapshot,
        currentlyHasLyrics: Bool
    ) -> Bool {
        if previous.track.id != next.track.id {
            return true
        }
        guard !currentlyHasLyrics, next.track.id != "spotify:idle" else {
            return false
        }
        if previous.source != next.source {
            return true
        }
        return previous.track.title != next.track.title
            || previous.track.artist != next.track.artist
            || previous.track.album != next.track.album
            || abs(previous.track.duration - next.track.duration) > 1
            || previous.track.kind != next.track.kind
    }
}

enum RepeatMode: String {
    case off
    case all
    case one
}

enum PlaybackCommand {
    case togglePlayback
    case previous
    case next
    case seek(TimeInterval)
    case toggleLiked
    case toggleShuffle
    case cycleRepeat
    case setVolume(Double)
}

enum SpotifyAuthorizationState: Equatable, Sendable {
    case disconnected
    case authorizing
    case connected
    case expiringSoon
    case permissionRequired
    case reauthorizationRequired
    case failed
}

enum LyrisLikedControlAction: Equatable, Sendable {
    case toggle
    case refreshThenToggle
    case openSpotifySettings
}

enum LyrisLikedControlPolicy {
    static func action(
        authorizationState: SpotifyAuthorizationState,
        capabilities: PlaybackCapabilities,
        likedState: LikedSongsState
    ) -> LyrisLikedControlAction {
        if capabilities.contains(.likedSongsWrite),
           likedState.displayedValue != nil {
            return .toggle
        }
        switch authorizationState {
        case .connected, .expiringSoon:
            return .refreshThenToggle
        case .disconnected, .authorizing, .permissionRequired,
             .reauthorizationRequired, .failed:
            return .openSpotifySettings
        }
    }
}

struct LyrisLikedIntentCoordinator: Equatable, Sendable {
    private(set) var pendingTrackID: String?

    mutating func begin(trackID: String) {
        pendingTrackID = trackID
    }

    mutating func cancel() {
        pendingTrackID = nil
    }

    mutating func shouldToggle(
        trackID: String,
        capabilities: PlaybackCapabilities,
        likedState: LikedSongsState
    ) -> Bool {
        guard let pendingTrackID else { return false }
        guard pendingTrackID == trackID else {
            cancel()
            return false
        }
        guard capabilities.contains(.likedSongsWrite),
              likedState.displayedValue != nil else { return false }
        cancel()
        return true
    }
}

@MainActor
protocol PlaybackAdapting: AnyObject {
    var onSnapshot: ((PlaybackSnapshot) -> Void)? { get set }
    var onAuthorizationState: ((SpotifyAuthorizationState) -> Void)? { get set }
    func start()
    func send(_ command: PlaybackCommand)
}

struct LyricsProviderResult: Equatable, Sendable {
    let sourceID: String
    let document: LyricDocument

    var lyrics: [TimedLyric] { document.timedLyrics }

    init(sourceID: String, lyrics: [TimedLyric], trackID: String? = nil, provider: String = "unknown") {
        self.sourceID = sourceID
        document = LyricDocument(
            trackID: trackID,
            sourceID: sourceID,
            provider: provider,
            timedLyrics: lyrics
        )
    }

    init(document: LyricDocument) {
        sourceID = document.source.sourceID
        self.document = document
    }
}

protocol LyricsProviding {
    func lyrics(for track: Track) async throws -> LyricsProviderResult
}

protocol TranslationProviding {
    func testConnection(
        configuration: TranslationConfiguration,
        apiKey: String
    ) async throws -> TranslationConnectionReport

    func translate(
        lines: [String],
        targetLanguage: String,
        configuration: TranslationConfiguration,
        apiKey: String
    ) async throws -> [String]
}

struct TranslationConfiguration: Equatable {
    var provider: TranslationProvider
    var baseURL: String
    var model: String
    var thinkingEnabled: Bool
    var style: LyricsTranslationStyle
    var songContext: LyricsTranslationSongContext?

    init(
        provider: TranslationProvider,
        baseURL: String,
        model: String,
        thinkingEnabled: Bool,
        style: LyricsTranslationStyle = .contextual,
        songContext: LyricsTranslationSongContext? = nil
    ) {
        self.provider = provider
        self.baseURL = baseURL
        self.model = model
        self.thinkingEnabled = thinkingEnabled
        self.style = style
        self.songContext = songContext
    }
}

enum LyricsTranslationStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case contextual
    case fastLiteral

    var id: Self { self }

    func displayName(in language: AppLanguage) -> String {
        switch self {
        case .contextual:
            language.pick(zh: "上下文意译（推荐）", en: "Context-aware (Recommended)")
        case .fastLiteral:
            language.pick(zh: "快速直译", en: "Fast literal")
        }
    }

    func detail(in language: AppLanguage) -> String {
        switch self {
        case .contextual:
            language.pick(
                zh: "整首歌词一并理解代词、习语和重复副歌；模型只返回译文，不展示思考过程。",
                en: "Understands pronouns, idioms, and repeated hooks across the whole song; only the translation is returned."
            )
        case .fastLiteral:
            language.pick(
                zh: "更贴近逐句原义，延迟更低，适合只求快速可读。",
                en: "Stays close to each line for lower latency and quick readability."
            )
        }
    }
}

struct LyricsTranslationSongContext: Equatable, Sendable {
    let title: String
    let artist: String
    let album: String?
}

enum LyricsTranslationPrompt {
    static let version = version(for: .contextual)

    static func version(for style: LyricsTranslationStyle) -> String {
        "lyrics-translation-v3-\(style.rawValue)"
    }

    static func systemMessage(
        targetLanguage: String,
        style: LyricsTranslationStyle = .contextual
    ) -> String {
        let shared = """
        Translate the provided complete song lyric into \(targetLanguage). Preserve the exact input line count and order. Keep repeated hooks consistent. Return only a JSON string array with one translated string per input line. Do not expose analysis, reasoning, notes, markdown, or any other fields.
        """
        switch style {
        case .contextual:
            return shared + """
             Treat the lyric as one coherent work: silently infer pronouns, speaker relationships, idioms, slang, imagery, and tone from surrounding lines and song metadata. Prefer natural, singable wording over rigid word-for-word phrasing while preserving meaning.
            """
        case .fastLiteral:
            return shared + """
             Translate directly and concisely, staying close to each source line and avoiding unnecessary embellishment.
            """
        }
    }
}

struct TranslationConnectionReport: Equatable {
    var models: [String]
    var suggestedModel: String
    var latencyMilliseconds: Int
}

enum LyrisTranslationModelSelection {
    static func options(
        available: [String],
        current: String
    ) -> [String] {
        let normalizedAvailable = available
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if !normalizedAvailable.isEmpty {
            return Array(Set(normalizedAvailable)).sorted()
        }
        let normalizedCurrent = current.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalizedCurrent.isEmpty ? [] : [normalizedCurrent]
    }

    static func usesFetchedPicker(available: [String]) -> Bool {
        available.contains {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
}

enum LyrisTranslationModelCatalogPersistence {
    private static let modelsKey = "translationAvailableModels"
    private static let providerKey = "translationAvailableModelsProvider"
    private static let baseURLKey = "translationAvailableModelsBaseURL"

    static func save(
        models: [String],
        provider: TranslationProvider,
        baseURL: String,
        to defaults: UserDefaults
    ) {
        let options = LyrisTranslationModelSelection.options(
            available: models,
            current: ""
        )
        guard !options.isEmpty else {
            clear(from: defaults)
            return
        }
        defaults.set(options, forKey: modelsKey)
        defaults.set(provider.rawValue, forKey: providerKey)
        defaults.set(normalizedBaseURL(baseURL), forKey: baseURLKey)
    }

    static func load(
        provider: TranslationProvider,
        baseURL: String,
        from defaults: UserDefaults
    ) -> [String] {
        guard defaults.string(forKey: providerKey) == provider.rawValue,
              defaults.string(forKey: baseURLKey) == normalizedBaseURL(baseURL),
              let stored = defaults.stringArray(forKey: modelsKey) else {
            return []
        }
        return LyrisTranslationModelSelection.options(
            available: stored,
            current: ""
        )
    }

    static func clear(from defaults: UserDefaults) {
        defaults.removeObject(forKey: modelsKey)
        defaults.removeObject(forKey: providerKey)
        defaults.removeObject(forKey: baseURLKey)
    }

    private static func normalizedBaseURL(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}

enum TranslationProvider: String, CaseIterable, Identifiable {
    case deepSeek = "DeepSeek"
    case openAI = "OpenAI"
    case deepL = "DeepL"
    case custom = "自定义兼容 API"

    var id: Self { self }

    func displayName(in language: AppLanguage) -> String {
        switch self {
        case .deepSeek: "DeepSeek"
        case .openAI: "OpenAI"
        case .deepL: "DeepL"
        case .custom: language.pick(zh: "自定义兼容 API", en: "Custom compatible API")
        }
    }

    var defaultBaseURL: String {
        switch self {
        case .deepSeek: "https://api.deepseek.com"
        case .openAI: "https://api.openai.com/v1"
        case .deepL: "https://api-free.deepl.com/v2"
        case .custom: ""
        }
    }

    var defaultModel: String {
        switch self {
        case .deepSeek: "deepseek-v4-flash"
        case .openAI: "gpt-5-mini"
        case .deepL: ""
        case .custom: ""
        }
    }

    func setupHint(in language: AppLanguage) -> String {
        switch self {
        case .deepSeek: language.pick(zh: "在 DeepSeek 开放平台创建 API Key；Base URL 通常无需修改。", en: "Create an API key in DeepSeek Platform; the default Base URL usually works.")
        case .openAI: language.pick(zh: "在 OpenAI Platform 创建 API Key，并选择账号可用的模型。", en: "Create an API key in OpenAI Platform and choose a model available to your account.")
        case .deepL: language.pick(zh: "在 DeepL 账号的 API Keys 页面复制密钥；Free 密钥通常以 :fx 结尾。", en: "Copy the key from your DeepL API Keys page; Free keys usually end in :fx.")
        case .custom: language.pick(zh: "填写兼容 Chat Completions 的 Base URL、模型名与 API Key。", en: "Enter a Chat Completions-compatible Base URL, model, and API key.")
        }
    }
}

struct TranslationUsageEstimate: Equatable, Sendable {
    let inputTokens: Int
    let outputTokens: Int
}

enum TranslationUsageEstimator {
    static func estimate(
        sourceLines: [String],
        translatedLines: [String],
        targetLanguage: String,
        style: LyricsTranslationStyle = .contextual
    ) -> TranslationUsageEstimate {
        let prompt = LyricsTranslationPrompt.systemMessage(
            targetLanguage: targetLanguage,
            style: style
        )
        let input = ([prompt] + sourceLines).joined(separator: "\n")
        let output = translatedLines.joined(separator: "\n")
        return TranslationUsageEstimate(
            inputTokens: approximateTokenCount(in: input),
            outputTokens: approximateTokenCount(in: output)
        )
    }

    private static func approximateTokenCount(in text: String) -> Int {
        guard !text.isEmpty else { return 0 }
        let weightedCount = text.unicodeScalars.reduce(into: 0.0) { result, scalar in
            if CharacterSet.whitespacesAndNewlines.contains(scalar) {
                result += 0.08
            } else if isCJK(scalar.value) {
                result += 0.6
            } else {
                result += 0.3
            }
        }
        return max(1, Int(ceil(weightedCount)))
    }

    private static func isCJK(_ value: UInt32) -> Bool {
        switch value {
        case 0x3040...0x30FF, 0x3400...0x4DBF, 0x4E00...0x9FFF,
             0xAC00...0xD7AF, 0xF900...0xFAFF:
            return true
        default:
            return false
        }
    }
}

struct TranslationPricingRates: Equatable, Sendable {
    let inputUSDPerMillion: Double
    let outputUSDPerMillion: Double

    var isAvailable: Bool {
        inputUSDPerMillion > 0 || outputUSDPerMillion > 0
    }

    func estimatedCostUSD(inputTokens: Int, outputTokens: Int) -> Double {
        let inputCost = Double(max(0, inputTokens)) * inputUSDPerMillion / 1_000_000
        let outputCost = Double(max(0, outputTokens)) * outputUSDPerMillion / 1_000_000
        return inputCost + outputCost
    }
}

enum CostCurrency: String, CaseIterable, Identifiable, Codable, Sendable {
    case usd = "USD"
    case cny = "CNY"
    case eur = "EUR"
    case jpy = "JPY"
    case gbp = "GBP"
    case krw = "KRW"

    var id: String { rawValue }

    /// ECB reference rates for 2026-07-24, converted from EUR-base quotes
    /// into units of the selected currency per USD. These are editable
    /// display defaults, not transaction rates.
    var referenceUnitsPerUSD: Double {
        switch self {
        case .usd: 1
        case .cny: 6.772_172
        case .eur: 0.878_966
        case .jpy: 163.821_746
        case .gbp: 0.750_532
        case .krw: 1_461.000_264
        }
    }

    var referenceRateDate: String { "2026-07-24" }

    var symbol: String {
        switch self {
        case .usd: "$"
        case .cny, .jpy: "¥"
        case .eur: "€"
        case .gbp: "£"
        case .krw: "₩"
        }
    }

    func displayName(in language: AppLanguage) -> String {
        switch self {
        case .usd: language.pick(zh: "美元（USD）", en: "US Dollar (USD)")
        case .cny: language.pick(zh: "人民币（CNY）", en: "Chinese Yuan (CNY)")
        case .eur: language.pick(zh: "欧元（EUR）", en: "Euro (EUR)")
        case .jpy: language.pick(zh: "日元（JPY）", en: "Japanese Yen (JPY)")
        case .gbp: language.pick(zh: "英镑（GBP）", en: "British Pound (GBP)")
        case .krw: language.pick(zh: "韩元（KRW）", en: "South Korean Won (KRW)")
        }
    }

    func convertFromUSD(_ value: Double, unitsPerUSD: Double) -> Double {
        max(0, value) * max(0, unitsPerUSD)
    }

    func convertToUSD(_ value: Double, unitsPerUSD: Double) -> Double {
        let rate = max(0, unitsPerUSD)
        guard rate > 0 else { return 0 }
        return max(0, value) / rate
    }

    func formatted(usdValue: Double, unitsPerUSD: Double) -> String {
        let converted = convertFromUSD(usdValue, unitsPerUSD: unitsPerUSD)
        let precision = converted >= 100 ? 2 : 6
        return "\(symbol)\(String(format: "%.\(precision)f", converted)) \(rawValue)"
    }
}

enum TranslationPricingCatalog {
    static let revision = "2026-08-18.3"

    struct Reference: Equatable, Sendable {
        let rates: TranslationPricingRates
        let verifiedDate: String
        let sourceURL: URL?
        let note: String
    }

    // Official reference defaults checked on 2026-08-18. DeepSeek's input
    // estimate uses the cache-miss rate because Lyris cannot promise a cache hit.
    static func reference(
        provider: TranslationProvider,
        model: String
    ) -> Reference {
        let rates = suggestedRates(provider: provider, model: model)
        let sourceURL: URL? = switch provider {
        case .deepSeek:
            URL(string: "https://api-docs.deepseek.com/quick_start/pricing/")
        case .openAI:
            openAIModelPricingURL(model: model)
        case .deepL:
            URL(string: "https://www.deepl.com/pro-api")
        case .custom:
            nil
        }
        let note: String = switch provider {
        case .deepSeek: "DeepSeek 保守高峰、缓存未命中参考价"
        case .openAI: "OpenAI standard text-token rate"
        case .deepL: "DeepL is character-priced; enter the account rate manually"
        case .custom: "Custom provider pricing must be entered manually"
        }
        return Reference(
            rates: rates,
            verifiedDate: "2026-08-18",
            sourceURL: sourceURL,
            note: note
        )
    }

    static func suggestedRates(
        provider: TranslationProvider,
        model: String
    ) -> TranslationPricingRates {
        let normalizedModel = model.lowercased()
        switch provider {
        case .deepSeek:
            if normalizedModel.contains("pro") {
                return TranslationPricingRates(
                    inputUSDPerMillion: 1.32,
                    outputUSDPerMillion: 3.96
                )
            }
            return TranslationPricingRates(
                inputUSDPerMillion: 0.44,
                outputUSDPerMillion: 1.32
            )
        case .openAI:
            if normalizedModel.contains("gpt-5.6-sol") || normalizedModel == "gpt-5.6" {
                return TranslationPricingRates(inputUSDPerMillion: 5, outputUSDPerMillion: 30)
            }
            if normalizedModel.contains("gpt-5.6-terra") {
                return TranslationPricingRates(inputUSDPerMillion: 2.5, outputUSDPerMillion: 15)
            }
            if normalizedModel.contains("gpt-5.6-luna") {
                return TranslationPricingRates(inputUSDPerMillion: 1, outputUSDPerMillion: 6)
            }
            if normalizedModel.contains("gpt-5.4-nano") {
                return TranslationPricingRates(inputUSDPerMillion: 0.2, outputUSDPerMillion: 1.25)
            }
            if normalizedModel.contains("gpt-5.4-mini") {
                return TranslationPricingRates(inputUSDPerMillion: 0.75, outputUSDPerMillion: 4.5)
            }
            if normalizedModel.contains("gpt-5.4") {
                return TranslationPricingRates(inputUSDPerMillion: 2.5, outputUSDPerMillion: 15)
            }
            if normalizedModel.contains("gpt-5-mini") {
                return TranslationPricingRates(inputUSDPerMillion: 0.25, outputUSDPerMillion: 2)
            }
            return TranslationPricingRates(inputUSDPerMillion: 0, outputUSDPerMillion: 0)
        case .deepL, .custom:
            return TranslationPricingRates(inputUSDPerMillion: 0, outputUSDPerMillion: 0)
        }
    }

    private static func openAIModelPricingURL(model: String) -> URL? {
        let normalized = model.lowercased()
        let slug: String
        if normalized.contains("gpt-5.6-terra") {
            slug = "gpt-5.6-terra"
        } else if normalized.contains("gpt-5.6-luna") {
            slug = "gpt-5.6-luna"
        } else if normalized.contains("gpt-5.6") {
            slug = "gpt-5.6-sol"
        } else if normalized.contains("gpt-5-mini") {
            slug = "gpt-5-mini"
        } else {
            return URL(string: "https://developers.openai.com/api/docs/models")
        }
        return URL(string: "https://developers.openai.com/api/docs/models/\(slug)")
    }
}

struct SpotifyConnectionReport: Equatable {
    var displayName: String
    var profile: SpotifyAuthorizationProfile?

    init(displayName: String, profile: SpotifyAuthorizationProfile? = nil) {
        self.displayName = displayName
        self.profile = profile
    }
}

@MainActor
protocol SpotifyAuthorizing {
    func configuredProfile() throws -> SpotifyAuthorizationProfile?
    @discardableResult
    func saveConfiguration(clientID: String, redirectURI: String) throws -> SpotifyAuthorizationProfile
    func restoreConnection(clientID: String, redirectURI: String) async throws -> SpotifyConnectionReport?
    func authorize(clientID: String, redirectURI: String) async throws -> SpotifyConnectionReport
}

extension SpotifyAuthorizing {
    func configuredProfile() throws -> SpotifyAuthorizationProfile? { nil }

    @discardableResult
    func saveConfiguration(
        clientID: String,
        redirectURI: String
    ) throws -> SpotifyAuthorizationProfile {
        SpotifyAuthorizationProfile(
            displayName: "Spotify",
            clientID: clientID,
            redirectURI: redirectURI
        )
    }
}

enum CredentialReadInteraction: Equatable, Sendable {
    case silent
    case userInitiated
}

protocol CredentialVault {
    func read(account: String) throws -> String?
    func read(account: String, interaction: CredentialReadInteraction) throws -> String?
    func write(_ secret: String, account: String) throws
    func delete(account: String) throws
}

extension CredentialVault {
    func read(account: String, interaction: CredentialReadInteraction) throws -> String? {
        try read(account: account)
    }
}
