import Foundation

enum FirstUseStep: String, Codable, CaseIterable, Identifiable {
    case localLyrics
    case statusDetection
    case accountEnhancement
    case translation

    var id: Self { self }

    func title(in language: AppLanguage) -> String {
        switch self {
        case .localLyrics:
            language.pick(
                zh: "打开 Spotify，Lyris 会自动显示歌词",
                en: "Open Spotify and Lyris will show lyrics automatically"
            )
        case .statusDetection:
            language.pick(zh: "检查本机播放状态", en: "Check local playback status")
        case .accountEnhancement:
            language.pick(zh: "连接 Spotify 账户（可选）", en: "Connect Spotify account (optional)")
        case .translation:
            language.pick(zh: "设置歌词翻译（可选）", en: "Set up lyric translation (optional)")
        }
    }

    func description(in language: AppLanguage) -> String {
        switch self {
        case .localLyrics:
            language.pick(
                zh: "无需先连接账户；Lyris 会优先读取本机 Spotify 状态。",
                en: "No account connection is required; Lyris checks local Spotify first."
            )
        case .statusDetection:
            language.pick(
                zh: "从 Spotify 是否安装、运行到歌词显示，逐步反馈当前状态。",
                en: "Follow Spotify from installation and playback detection through lyric display."
            )
        case .accountEnhancement:
            language.pick(
                zh: "可使用 Client ID + PKCE 连接账户，解锁收藏和账户播放控制。",
                en: "Optionally connect with Client ID + PKCE for library and account playback controls."
            )
        case .translation:
            language.pick(
                zh: "可配置 DeepSeek、OpenAI-compatible、DeepL 或自定义服务，也可以跳过。",
                en: "Configure DeepSeek, OpenAI-compatible, DeepL, or a custom service, or skip this step."
            )
        }
    }
}

enum LocalLyricsReadiness: String, Codable, CaseIterable {
    case notInstalled
    case notRunning
    case notPlaying
    case recognized
    case searchingLyrics
    case displayed

    func title(in language: AppLanguage) -> String {
        switch self {
        case .notInstalled: language.pick(zh: "未安装", en: "Not installed")
        case .notRunning: language.pick(zh: "未启动", en: "Not running")
        case .notPlaying: language.pick(zh: "未播放", en: "Nothing playing")
        case .recognized: language.pick(zh: "已识别", en: "Track recognized")
        case .searchingLyrics: language.pick(zh: "正在查词", en: "Searching for lyrics")
        case .displayed: language.pick(zh: "已显示", en: "Lyrics displayed")
        }
    }

    func description(in language: AppLanguage) -> String {
        switch self {
        case .notInstalled:
            language.pick(
                zh: "这台 Mac 尚未检测到 Spotify。",
                en: "Spotify is not installed on this Mac."
            )
        case .notRunning:
            language.pick(
                zh: "打开 Spotify 后，Lyris 会自动继续。",
                en: "Open Spotify and Lyris will continue automatically."
            )
        case .notPlaying:
            language.pick(
                zh: "播放一首歌曲即可开始识别。",
                en: "Play a track to begin detection."
            )
        case .recognized:
            language.pick(
                zh: "已读取当前歌曲，准备搜索匹配歌词。",
                en: "The current track is recognized and ready for lyric matching."
            )
        case .searchingLyrics:
            language.pick(
                zh: "正在查找并匹配同步歌词。",
                en: "Finding and matching synchronized lyrics."
            )
        case .displayed:
            language.pick(
                zh: "同步歌词已在卡片上准备就绪。",
                en: "Synchronized lyrics are ready on the card."
            )
        }
    }
}

enum FirstUseOptionalSetupDecision: String, Codable {
    case undecided
    case configured
    case skipped
}

enum FirstUseFlowEvent: Equatable {
    case continueFromLocalLyrics
    case localStatusChanged(LocalLyricsReadiness)
    case continueFromStatusDetection
    case requestAccountEnhancement
    case accountEnhancementFinished
    case skipAccountEnhancement
    case requestTranslation
    case translationFinished
    case skipTranslation
    case finishLater
}

enum FirstUseFlowEffect: Equatable {
    case none
    case observeLocalSpotify
    case presentAccountSetup
    case presentTranslationSetup
    case finished
}

struct FirstUseFlowState: Codable, Equatable {
    private(set) var currentStep: FirstUseStep
    private(set) var localStatus: LocalLyricsReadiness
    private(set) var accountDecision: FirstUseOptionalSetupDecision
    private(set) var translationDecision: FirstUseOptionalSetupDecision
    private(set) var isCompleted: Bool

    init(
        currentStep: FirstUseStep = .localLyrics,
        localStatus: LocalLyricsReadiness = .notRunning,
        accountDecision: FirstUseOptionalSetupDecision = .undecided,
        translationDecision: FirstUseOptionalSetupDecision = .undecided,
        isCompleted: Bool = false
    ) {
        self.currentStep = currentStep
        self.localStatus = localStatus
        self.accountDecision = accountDecision
        self.translationDecision = translationDecision
        self.isCompleted = isCompleted
    }

    var isFirstUse: Bool { !isCompleted }

    /// OAuth always remains an explicit user action in the account-enhancement step.
    var shouldAutomaticallyStartOAuth: Bool { false }

    var nextEffect: FirstUseFlowEffect {
        guard !isCompleted else { return .none }
        switch currentStep {
        case .localLyrics, .statusDetection:
            return .observeLocalSpotify
        case .accountEnhancement, .translation:
            return .none
        }
    }

    @discardableResult
    mutating func transition(_ event: FirstUseFlowEvent) -> FirstUseFlowEffect {
        switch event {
        case .continueFromLocalLyrics where currentStep == .localLyrics && !isCompleted:
            currentStep = .statusDetection
            return .observeLocalSpotify

        case .localStatusChanged(let status) where !isCompleted:
            localStatus = status
            return .none

        case .continueFromStatusDetection where currentStep == .statusDetection && !isCompleted:
            currentStep = .accountEnhancement
            return .none

        case .requestAccountEnhancement where currentStep == .accountEnhancement && !isCompleted:
            return .presentAccountSetup

        case .accountEnhancementFinished where currentStep == .accountEnhancement && !isCompleted:
            accountDecision = .configured
            currentStep = .translation
            return .none

        case .skipAccountEnhancement where currentStep == .accountEnhancement && !isCompleted:
            accountDecision = .skipped
            currentStep = .translation
            return .none

        case .requestTranslation where currentStep == .translation && !isCompleted:
            return .presentTranslationSetup

        case .translationFinished where currentStep == .translation && !isCompleted:
            translationDecision = .configured
            isCompleted = true
            return .finished

        case .skipTranslation where currentStep == .translation && !isCompleted:
            translationDecision = .skipped
            isCompleted = true
            return .finished

        case .finishLater where !isCompleted:
            if accountDecision == .undecided { accountDecision = .skipped }
            if translationDecision == .undecided { translationDecision = .skipped }
            isCompleted = true
            return .finished

        default:
            return .none
        }
    }
}
