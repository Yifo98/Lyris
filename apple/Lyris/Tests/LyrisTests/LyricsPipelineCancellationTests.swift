import Foundation
import XCTest
@testable import Lyris

@MainActor
final class LyricsPipelineCancellationTests: XCTestCase {
    func testStorePublishesWordTimedProgressFromPresentedDocument() async throws {
        let playback = TestPlaybackAdapter()
        let store = makeStore(
            playback: playback,
            lyricsProvider: WordSyncedLyricsProvider(),
            translation: ImmediateTranslationAdapter(),
            vault: EmptyCredentialVault()
        )

        playback.emit(
            PlaybackSnapshot(
                track: Track(
                    id: "spotify:track:word",
                    title: "Word",
                    artist: "Artist",
                    album: "Album",
                    duration: 20
                ),
                position: 10.5,
                isPlaying: true,
                likedState: .unavailable,
                isShuffled: false,
                repeatMode: .off,
                capabilities: .localCompanion
            )
        )
        try await eventually { store.activeLyric?.original == "Hello world" }

        XCTAssertEqual(store.activeLyricProgress, 0.25, accuracy: 0.001)
    }

    func testEmptyProviderResultProducesDedicatedNoLyricsState() async throws {
        let playback = TestPlaybackAdapter()
        let store = makeStore(
            playback: playback,
            lyricsProvider: EmptyLyricsProvider(),
            translation: ImmediateTranslationAdapter(),
            vault: EmptyCredentialVault()
        )

        playback.emit(snapshot(trackID: "spotify:track:empty", title: "Empty"))
        try await eventually {
            store.lyricsPipelineState == .noLyrics(trackID: "spotify:track:empty")
        }

        XCTAssertTrue(store.lyrics.isEmpty)
        XCTAssertEqual(store.lyricPipelineStatus, "未找到歌词")
    }

    func testRateLimitKeepsOnePlanBlocksManualRetryAndRecoversAutomatically() async throws {
        let playback = TestPlaybackAdapter()
        let provider = RateLimitedThenSuccessLyricsProvider()
        let store = makeStore(
            playback: playback,
            lyricsProvider: provider,
            translation: ImmediateTranslationAdapter(),
            vault: EmptyCredentialVault(),
            retryMinimumDelay: 0.1
        )

        playback.emit(snapshot(trackID: "spotify:track:limited", title: "Limited"))
        try await eventually {
            store.lyricsPipelineState == .rateLimited(
                trackID: "spotify:track:limited",
                retryAfter: 0
            )
        }
        let requestCountBeforeRetry = await provider.requestCount()
        XCTAssertEqual(requestCountBeforeRetry, 1)

        store.retryLyrics()
        for _ in 0..<10 { await Task.yield() }
        let requestCountAfterBlockedManualRetry = await provider.requestCount()
        XCTAssertEqual(requestCountAfterBlockedManualRetry, 1)

        try await eventually {
            store.lyrics.first?.original == "recovered-line"
        }

        let requestCountAfterRetry = await provider.requestCount()
        XCTAssertEqual(requestCountAfterRetry, 2)
        guard case .ready(let trackID, let source, _, let origin) = store.lyricsPipelineState else {
            return XCTFail("Retry should finish in the ready state")
        }
        XCTAssertEqual(trackID, "spotify:track:limited")
        XCTAssertEqual(source.sourceID, "fixture:recovered")
        XCTAssertEqual(origin, .provider)
    }

    func testOldLyricsResultCannotReplaceTheNewTrack() async throws {
        let playback = TestPlaybackAdapter()
        let provider = ControlledLyricsProvider()
        let store = makeStore(
            playback: playback,
            lyricsProvider: provider,
            translation: ImmediateTranslationAdapter(),
            vault: EmptyCredentialVault()
        )

        playback.emit(snapshot(trackID: "spotify:track:a", title: "A"))
        await provider.waitUntilRequested(trackID: "spotify:track:a")
        playback.emit(snapshot(trackID: "spotify:track:b", title: "B"))
        await provider.waitUntilRequested(trackID: "spotify:track:b")

        await provider.resolve(trackID: "spotify:track:b", original: "new-track-line")
        try await eventually {
            store.lyrics.first?.original == "new-track-line"
        }

        await provider.resolve(trackID: "spotify:track:a", original: "stale-line")
        for _ in 0..<20 { await Task.yield() }

        XCTAssertEqual(store.playback.track.id, "spotify:track:b")
        XCTAssertEqual(store.lyrics.map(\.original), ["new-track-line"])
    }

    func testChangingTranslationConfigurationCancelsOldTranslationWithoutUsageOrCacheWrite() async throws {
        let playback = TestPlaybackAdapter()
        let translation = ControlledTranslationAdapter()
        let cache = RecordingLyricsCache()
        let store = makeStore(
            playback: playback,
            lyricsProvider: ImmediateLyricsProvider(),
            translation: translation,
            vault: StaticCredentialVault(secret: "fixture-key"),
            cache: cache
        )

        playback.emit(snapshot(trackID: "spotify:track:a", title: "A"))
        await translation.waitUntilRequested()

        store.updateTranslationModelDraft("new-model")
        await translation.resolve(["stale-translation"])
        for _ in 0..<30 { await Task.yield() }

        XCTAssertEqual(store.lyrics.first?.original, "source-line")
        XCTAssertEqual(store.lyrics.first?.translation, "")
        XCTAssertEqual(store.apiRequestCount, 0)
        XCTAssertEqual(store.apiFailureCount, 0)
        let savedEntryCount = await cache.savedEntryCount()
        XCTAssertEqual(savedEntryCount, 0)
    }

    func testTranslationFailureFallsBackToCompatibleLocalCache() async throws {
        let playback = TestPlaybackAdapter()
        let cachedLyrics = [
            TimedLyric(startTime: 0, original: "source-line", translation: "cached-translation")
        ]
        let cache = RecordingLyricsCache(
            compatible: LyricsCacheEntry(
                trackID: "spotify:track:a",
                trackTitle: "A",
                artist: "Artist",
                trackDuration: 180,
                translationTarget: "Simplified Chinese",
                savedAt: Date(timeIntervalSince1970: 1_800_000_000),
                source: .generated,
                fingerprint: LyricsCacheFingerprint(
                    trackID: "spotify:track:a",
                    lyricsSourceID: "fixture:old-provider",
                    originalLyricsHash: LyricsCacheFingerprint.originalLyricsHash(for: cachedLyrics),
                    targetLanguage: "Simplified Chinese",
                    provider: "OldProvider",
                    model: "old-model",
                    thinkingEnabled: false,
                    promptVersion: "old-prompt",
                    schemaVersion: LyricsCacheFingerprint.currentSchemaVersion,
                    appVersion: "0.1.0"
                ),
                lyrics: cachedLyrics
            )
        )
        let store = makeStore(
            playback: playback,
            lyricsProvider: ImmediateLyricsProvider(),
            translation: FailingTranslationAdapter(),
            vault: StaticCredentialVault(secret: "fixture-key"),
            cache: cache
        )

        playback.emit(snapshot(trackID: "spotify:track:a", title: "A"))
        try await eventually {
            store.lyrics.first?.translation == "cached-translation"
        }

        XCTAssertEqual(store.apiRequestCount, 1)
        XCTAssertEqual(store.apiFailureCount, 1)
        XCTAssertTrue(store.lyricPipelineStatus?.contains("兼容缓存") == true)
    }

    private func makeStore(
        playback: TestPlaybackAdapter,
        lyricsProvider: any LyricsProviding,
        translation: any TranslationProviding,
        vault: any CredentialVault,
        cache: RecordingLyricsCache = RecordingLyricsCache(),
        retryMinimumDelay: TimeInterval = 1
    ) -> LyrisStore {
        let suiteName = "Lyris.LyricsPipelineCancellationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return LyrisStore(
            playbackAdapter: playback,
            lyricsProvider: lyricsProvider,
            translationAdapter: translation,
            spotifyAuthorizer: NoopSpotifyAuthorizer(),
            credentialVault: vault,
            lyricsCacheStore: cache,
            translationOverrideStore: EmptyTranslationOverrideStore(),
            defaults: defaults,
            lyricsRetryMinimumDelay: retryMinimumDelay
        )
    }

    private func snapshot(trackID: String, title: String) -> PlaybackSnapshot {
        PlaybackSnapshot(
            track: Track(id: trackID, title: title, artist: "Artist", album: "Album", duration: 180),
            position: 0,
            isPlaying: true,
            likedState: .unavailable,
            isShuffled: false,
            repeatMode: .off,
            capabilities: .localCompanion
        )
    }

    private func eventually(
        _ condition: @MainActor () -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(1))
        while clock.now < deadline {
            if condition() { return }
            try await clock.sleep(for: .milliseconds(5))
        }
        XCTFail("Condition did not become true")
    }
}

@MainActor
private final class TestPlaybackAdapter: PlaybackAdapting {
    var onSnapshot: ((PlaybackSnapshot) -> Void)?
    var onAuthorizationState: ((SpotifyAuthorizationState) -> Void)?

    func start() {}
    func send(_ command: PlaybackCommand) {}
    func emit(_ snapshot: PlaybackSnapshot) { onSnapshot?(snapshot) }
}

private actor ControlledLyricsProvider: LyricsProviding {
    private var continuations: [String: CheckedContinuation<LyricsProviderResult, Error>] = [:]

    func lyrics(for track: Track) async throws -> LyricsProviderResult {
        try await withCheckedThrowingContinuation { continuation in
            continuations[track.id] = continuation
        }
    }

    func waitUntilRequested(trackID: String) async {
        while continuations[trackID] == nil { await Task.yield() }
    }

    func resolve(trackID: String, original: String) {
        continuations.removeValue(forKey: trackID)?.resume(
            returning: LyricsProviderResult(
                sourceID: "fixture:\(trackID)",
                lyrics: [TimedLyric(startTime: 0, original: original, translation: "")]
            )
        )
    }
}

private struct ImmediateLyricsProvider: LyricsProviding {
    func lyrics(for track: Track) async throws -> LyricsProviderResult {
        LyricsProviderResult(
            sourceID: "fixture:immediate",
            lyrics: [TimedLyric(startTime: 0, original: "source-line", translation: "")]
        )
    }
}

private struct WordSyncedLyricsProvider: LyricsProviding {
    func lyrics(for track: Track) async throws -> LyricsProviderResult {
        LyricsProviderResult(
            document: LyricDocument(
                trackID: track.id,
                timingLevel: .wordSynced,
                source: LyricSourceMetadata(sourceID: "fixture:word", provider: "Fixture"),
                lines: [
                    LyricLine(
                        startTime: 10,
                        endTime: 14,
                        original: "Hello world",
                        words: [
                            LyricWord(text: "Hello", startTime: 10, endTime: 11),
                            LyricWord(text: "world", startTime: 12, endTime: 14),
                        ]
                    )
                ]
            )
        )
    }
}

private struct EmptyLyricsProvider: LyricsProviding {
    func lyrics(for track: Track) async throws -> LyricsProviderResult {
        LyricsProviderResult(
            sourceID: "fixture:empty",
            lyrics: [],
            trackID: track.id,
            provider: "Fixture"
        )
    }
}

private actor RateLimitedThenSuccessLyricsProvider: LyricsProviding {
    private var requests = 0

    func lyrics(for track: Track) async throws -> LyricsProviderResult {
        requests += 1
        if requests == 1 {
            throw LRCLibError.rateLimited(retryAfter: 0)
        }
        return LyricsProviderResult(
            sourceID: "fixture:recovered",
            lyrics: [
                TimedLyric(
                    startTime: 0,
                    original: "recovered-line",
                    translation: ""
                )
            ],
            trackID: track.id,
            provider: "Fixture"
        )
    }

    func requestCount() -> Int { requests }
}

private struct ImmediateTranslationAdapter: TranslationProviding {
    func testConnection(
        configuration: TranslationConfiguration,
        apiKey: String
    ) async throws -> TranslationConnectionReport {
        TranslationConnectionReport(models: [], suggestedModel: "", latencyMilliseconds: 0)
    }

    func translate(
        lines: [String],
        targetLanguage: String,
        configuration: TranslationConfiguration,
        apiKey: String
    ) async throws -> [String] {
        lines
    }
}

private struct FailingTranslationAdapter: TranslationProviding {
    func testConnection(
        configuration: TranslationConfiguration,
        apiKey: String
    ) async throws -> TranslationConnectionReport {
        throw URLError(.notConnectedToInternet)
    }

    func translate(
        lines: [String],
        targetLanguage: String,
        configuration: TranslationConfiguration,
        apiKey: String
    ) async throws -> [String] {
        throw URLError(.notConnectedToInternet)
    }
}

private actor ControlledTranslationAdapter: TranslationProviding {
    private var continuation: CheckedContinuation<[String], Error>?
    private var wasRequested = false

    func testConnection(
        configuration: TranslationConfiguration,
        apiKey: String
    ) async throws -> TranslationConnectionReport {
        TranslationConnectionReport(models: [], suggestedModel: "", latencyMilliseconds: 0)
    }

    func translate(
        lines: [String],
        targetLanguage: String,
        configuration: TranslationConfiguration,
        apiKey: String
    ) async throws -> [String] {
        wasRequested = true
        return try await withCheckedThrowingContinuation { continuation = $0 }
    }

    func waitUntilRequested() async {
        while !wasRequested { await Task.yield() }
    }

    func resolve(_ lines: [String]) {
        continuation?.resume(returning: lines)
        continuation = nil
    }
}

private actor RecordingLyricsCache: LyricsCaching {
    private var entries: [LyricsCacheEntry] = []
    private let compatible: LyricsCacheEntry?

    init(compatible: LyricsCacheEntry? = nil) {
        self.compatible = compatible
    }

    func loadManual(trackID: String) async -> LyricsCacheEntry? { nil }
    func loadLatestGenerated(matching key: LyricsCacheLookupKey) async -> LyricsCacheEntry? { nil }
    func loadCompatibleGeneratedFallback(matching key: LyricsCacheLookupKey) async -> LyricsCacheEntry? {
        return compatible?.trackID == key.trackID ? compatible : nil
    }
    func loadGenerated(fingerprint: LyricsCacheFingerprint) async -> LyricsCacheEntry? { nil }

    func save(_ entry: LyricsCacheEntry) async throws {
        try Task.checkCancellation()
        entries.append(entry)
    }

    func clearGenerated() async throws {}
    func clearManual() async throws {}
    func savedEntryCount() -> Int { entries.count }
}

private actor EmptyTranslationOverrideStore: UserTranslationOverrideStoring {
    func load(trackID: String) async -> [UserTranslationOverrideKey: String] { [:] }
    func set(_ translation: String, for key: UserTranslationOverrideKey, trackID: String) async throws {}
    func remove(_ key: UserTranslationOverrideKey, trackID: String) async throws {}
    func clearAll() async throws {}
}

private struct NoopSpotifyAuthorizer: SpotifyAuthorizing {
    func restoreConnection(clientID: String, redirectURI: String) async throws -> SpotifyConnectionReport? { nil }
    func authorize(clientID: String, redirectURI: String) async throws -> SpotifyConnectionReport {
        SpotifyConnectionReport(displayName: "Fixture")
    }
}

private struct EmptyCredentialVault: CredentialVault {
    func read(account: String) throws -> String? { nil }
    func write(_ secret: String, account: String) throws {}
    func delete(account: String) throws {}
}

private struct StaticCredentialVault: CredentialVault {
    let secret: String
    func read(account: String) throws -> String? { secret }
    func write(_ secret: String, account: String) throws {}
    func delete(account: String) throws {}
}
