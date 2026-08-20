import Foundation

enum LyricsLoadOrigin: String, Equatable, Sendable {
    case userLocal
    case exactCache
    case compatibleCache
    case provider
}

enum LyricsPipelineState: Equatable, Sendable {
    case idle
    case loading(trackID: String)
    case ready(
        trackID: String,
        source: LyricSourceMetadata,
        timingLevel: LyricTimingLevel,
        origin: LyricsLoadOrigin
    )
    case noLyrics(trackID: String)
    case unsupported(trackID: String, kind: PlaybackItemKind)
    case rateLimited(trackID: String, retryAfter: TimeInterval?)
    case offline(trackID: String)
    case unauthorized(trackID: String)
    case providerFailure(trackID: String)

    var trackID: String? {
        switch self {
        case .idle:
            nil
        case .loading(let trackID),
             .ready(let trackID, _, _, _),
             .noLyrics(let trackID),
             .unsupported(let trackID, _),
             .rateLimited(let trackID, _),
             .offline(let trackID),
             .unauthorized(let trackID),
             .providerFailure(let trackID):
            trackID
        }
    }

    var canRetry: Bool {
        switch self {
        case .noLyrics, .offline, .unauthorized, .providerFailure:
            true
        case .idle, .loading, .ready, .unsupported, .rateLimited:
            false
        }
    }
}

struct LyricsPipelinePresentation: Equatable, Sendable {
    let title: String
    let detail: String
    let systemImage: String
    let showsProgress: Bool
    let canRetry: Bool
}

extension LyricsPipelineState {
    func presentation(language: AppLanguage) -> LyricsPipelinePresentation? {
        switch self {
        case .ready:
            return nil
        case .idle:
            return LyricsPipelinePresentation(
                title: language.pick(zh: "等待播放", en: "Waiting for playback"),
                detail: language.pick(
                    zh: "在 Spotify 中播放歌曲后，这里会显示同步歌词。",
                    en: "Play a song in Spotify to show synchronized lyrics here."
                ),
                systemImage: "music.note",
                showsProgress: false,
                canRetry: false
            )
        case .loading:
            return LyricsPipelinePresentation(
                title: language.pick(zh: "正在获取歌词", en: "Loading lyrics"),
                detail: language.pick(
                    zh: "正在检查本机缓存并查询歌词来源。",
                    en: "Checking local caches and the configured lyric source."
                ),
                systemImage: "text.magnifyingglass",
                showsProgress: true,
                canRetry: false
            )
        case .noLyrics:
            return LyricsPipelinePresentation(
                title: language.pick(zh: "未找到歌词", en: "No lyrics found"),
                detail: language.pick(
                    zh: "当前来源没有匹配结果。可以重试，或编写并保存用户歌词。",
                    en: "The current source returned no match. Retry or write and save user lyrics."
                ),
                systemImage: "music.note.slash",
                showsProgress: false,
                canRetry: true
            )
        case .unsupported(_, let kind):
            let detail: String = switch kind {
            case .episode:
                language.pick(
                    zh: "播客不会自动搜索歌曲歌词。",
                    en: "Song lyrics are not searched automatically for podcasts."
                )
            case .advertisement:
                language.pick(
                    zh: "广告播放期间不显示歌词。",
                    en: "Lyrics are hidden while an advertisement is playing."
                )
            case .unknown, .track:
                language.pick(
                    zh: "当前播放内容无法作为歌曲处理。",
                    en: "The current playback item cannot be handled as a song."
                )
            }
            return LyricsPipelinePresentation(
                title: language.pick(zh: "不支持当前内容", en: "Unsupported playback item"),
                detail: detail,
                systemImage: "waveform.slash",
                showsProgress: false,
                canRetry: false
            )
        case .rateLimited(_, let retryAfter):
            let detail = retryAfter.map { delay in
                language.pick(
                    zh: "歌词服务要求等待至少 \(Int(ceil(delay))) 秒；Lyris 只保留一个退避计划。",
                    en: "The lyric service requires a wait of at least \(Int(ceil(delay))) seconds; Lyris keeps only one backoff plan."
                )
            } ?? language.pick(
                zh: "歌词服务请求过于频繁，Lyris 会在退避后重试。",
                en: "The lyric service is rate limiting requests. Lyris will retry after backoff."
            )
            return LyricsPipelinePresentation(
                title: language.pick(zh: "歌词服务限流", en: "Lyric service rate limit"),
                detail: detail,
                systemImage: "clock.badge.exclamationmark",
                showsProgress: true,
                canRetry: false
            )
        case .offline:
            return LyricsPipelinePresentation(
                title: language.pick(zh: "当前离线", en: "You are offline"),
                detail: language.pick(
                    zh: "未找到可用本机缓存。恢复网络后可以重试。",
                    en: "No compatible local cache was found. Retry after network access returns."
                ),
                systemImage: "wifi.slash",
                showsProgress: false,
                canRetry: true
            )
        case .unauthorized:
            return LyricsPipelinePresentation(
                title: language.pick(zh: "歌词来源拒绝访问", en: "Lyric source authorization failed"),
                detail: language.pick(
                    zh: "当前歌词来源拒绝了请求。请检查来源配置后重试。",
                    en: "The lyric source rejected the request. Check its configuration and retry."
                ),
                systemImage: "person.crop.circle.badge.exclamationmark",
                showsProgress: false,
                canRetry: true
            )
        case .providerFailure:
            return LyricsPipelinePresentation(
                title: language.pick(zh: "歌词来源暂时不可用", en: "Lyric source unavailable"),
                detail: language.pick(
                    zh: "请求没有成功，但播放控制仍可继续使用。请稍后重试。",
                    en: "The request failed, but playback controls remain available. Retry later."
                ),
                systemImage: "exclamationmark.triangle",
                showsProgress: false,
                canRetry: true
            )
        }
    }
}

enum LyricsPipelineFailureClassifier {
    static func state(for error: Error, trackID: String) -> LyricsPipelineState {
        if let providerError = error as? LRCLibError {
            switch providerError {
            case .rateLimited(let retryAfter):
                return .rateLimited(trackID: trackID, retryAfter: retryAfter)
            case .unauthorized:
                return .unauthorized(trackID: trackID)
            case .invalidResponse, .server, .httpStatus:
                return .providerFailure(trackID: trackID)
            }
        }

        if let spotifyFailure = error as? SpotifyNetworkFailure {
            switch spotifyFailure {
            case .rateLimited(let retryAfter):
                return .rateLimited(trackID: trackID, retryAfter: retryAfter)
            case .offline:
                return .offline(trackID: trackID)
            case .invalidGrant, .unauthorized, .forbidden:
                return .unauthorized(trackID: trackID)
            case .server, .client, .transport:
                return .providerFailure(trackID: trackID)
            case .cancelled:
                return .providerFailure(trackID: trackID)
            }
        }

        let bridged = error as NSError
        if bridged.domain == NSURLErrorDomain {
            let code = URLError.Code(rawValue: bridged.code)
            switch code {
            case .notConnectedToInternet,
                 .networkConnectionLost,
                 .cannotConnectToHost,
                 .cannotFindHost,
                 .dnsLookupFailed,
                 .internationalRoamingOff,
                 .dataNotAllowed:
                return .offline(trackID: trackID)
            default:
                break
            }
        }
        return .providerFailure(trackID: trackID)
    }
}

struct LyricsRetryKey: Equatable, Sendable {
    let trackID: String
    let generation: UInt64
}

struct LyricsRetryGate: Equatable, Sendable {
    private(set) var reservation: LyricsRetryKey?

    mutating func reserve(_ key: LyricsRetryKey) -> Bool {
        guard reservation == nil else { return false }
        reservation = key
        return true
    }

    mutating func consume(_ key: LyricsRetryKey) -> Bool {
        guard reservation == key else { return false }
        reservation = nil
        return true
    }

    mutating func cancel() {
        reservation = nil
    }
}
