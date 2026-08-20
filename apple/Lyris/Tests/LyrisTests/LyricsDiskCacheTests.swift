import Foundation
import XCTest
@testable import Lyris

final class LyricsDiskCacheTests: XCTestCase {
    func testCacheRoundTripPreservesWordTimingDocument() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("LyrisLyricsTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = LyricsDiskCache(rootURL: root)
        let line = LyricLine(
            startTime: 1,
            endTime: 3,
            original: "Hello world",
            words: [
                LyricWord(text: "Hello", startTime: 1, endTime: 1.8),
                LyricWord(text: "world", startTime: 2, endTime: 3),
            ]
        )
        let document = LyricDocument(
            trackID: "spotify:track:word",
            timingLevel: .wordSynced,
            source: LyricSourceMetadata(sourceID: "fixture:word", provider: "Fixture"),
            lines: [line]
        )
        let entry = LyricsCacheEntry(
            trackID: "spotify:track:word",
            trackTitle: "Track",
            artist: "Artist",
            savedAt: Date(),
            source: .manual,
            lyrics: document.timedLyrics,
            document: document
        )

        try await cache.save(entry)
        let restored = await cache.loadManual(trackID: entry.trackID)

        XCTAssertEqual(restored?.document, document)
        XCTAssertEqual(restored?.document?.lines.first?.words.count, 2)
    }

    func testManualLyricsOverrideGeneratedAndSurviveGeneratedClear() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("LyrisLyricsTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = LyricsDiskCache(rootURL: root)
        let sourceLyrics = [TimedLyric(startTime: 1, original: "generated", translation: "")]
        let fingerprint = LyricsCacheFingerprint(
            trackID: "spotify:track:test",
            lyricsSourceID: "lrclib:record:test",
            originalLyricsHash: LyricsCacheFingerprint.originalLyricsHash(for: sourceLyrics),
            targetLanguage: TranslationTargetLanguage.simplifiedChinese.apiName,
            provider: "DeepSeek",
            model: "deepseek-v4-flash",
            thinkingEnabled: false,
            promptVersion: "lyrics-translation-v2",
            schemaVersion: LyricsCacheFingerprint.currentSchemaVersion,
            appVersion: "0.2.0"
        )
        let generated = LyricsCacheEntry(
            trackID: fingerprint.trackID,
            trackTitle: "Track",
            artist: "Artist",
            translationTarget: fingerprint.targetLanguage,
            savedAt: Date(),
            source: .generated,
            fingerprint: fingerprint,
            lyrics: [TimedLyric(startTime: 1, original: "generated", translation: "自动")]
        )
        let manual = LyricsCacheEntry(
            trackID: generated.trackID,
            trackTitle: generated.trackTitle,
            artist: generated.artist,
            savedAt: Date(),
            source: .manual,
            lyrics: [TimedLyric(startTime: 2, original: "manual", translation: "手写")]
        )

        try await cache.save(generated)
        let generatedLoad = await cache.loadGenerated(fingerprint: fingerprint)
        XCTAssertEqual(generatedLoad?.source, .generated)

        try await cache.save(manual)
        let manualLoad = await cache.loadManual(trackID: generated.trackID)
        XCTAssertEqual(manualLoad?.source, .manual)

        try await cache.clearGenerated()
        let afterGeneratedClear = await cache.loadManual(trackID: generated.trackID)
        XCTAssertEqual(afterGeneratedClear?.source, .manual)
        let generatedAfterClear = await cache.loadGenerated(fingerprint: fingerprint)
        XCTAssertNil(generatedAfterClear)
        let latestAfterClear = await cache.loadLatestGenerated(
            matching: LyricsCacheLookupKey(fingerprint: fingerprint)
        )
        let fallbackAfterClear = await cache.loadCompatibleGeneratedFallback(
            matching: LyricsCacheLookupKey(fingerprint: fingerprint)
        )
        XCTAssertNil(latestAfterClear)
        XCTAssertNil(fallbackAfterClear)

        try await cache.clearManual()
        let afterManualClear = await cache.loadManual(trackID: generated.trackID)
        XCTAssertNil(afterManualClear)
    }

    func testClearingManualLyricsLeavesGeneratedLyricsAndFallbackIndexIntact() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("LyrisLyricsTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = LyricsDiskCache(rootURL: root)
        let sourceLyrics = [TimedLyric(startTime: 1, original: "generated", translation: "")]
        let fingerprint = LyricsCacheFingerprint(
            trackID: "spotify:track:test",
            lyricsSourceID: "lrclib:record:test",
            originalLyricsHash: LyricsCacheFingerprint.originalLyricsHash(for: sourceLyrics),
            targetLanguage: TranslationTargetLanguage.simplifiedChinese.apiName,
            provider: "DeepSeek",
            model: "deepseek-v4-flash",
            thinkingEnabled: false,
            promptVersion: "lyrics-translation-v2",
            schemaVersion: LyricsCacheFingerprint.currentSchemaVersion,
            appVersion: "0.2.0"
        )
        let generated = LyricsCacheEntry(
            trackID: fingerprint.trackID,
            trackTitle: "Track",
            artist: "Artist",
            translationTarget: fingerprint.targetLanguage,
            savedAt: Date(),
            source: .generated,
            fingerprint: fingerprint,
            lyrics: [TimedLyric(startTime: 1, original: "generated", translation: "自动")]
        )
        let manual = LyricsCacheEntry(
            trackID: fingerprint.trackID,
            trackTitle: "Track",
            artist: "Artist",
            savedAt: Date(),
            source: .manual,
            lyrics: [TimedLyric(startTime: 2, original: "manual", translation: "手写")]
        )

        try await cache.save(generated)
        try await cache.save(manual)
        try await cache.clearManual()

        let manualAfterClear = await cache.loadManual(trackID: fingerprint.trackID)
        let generatedAfterClear = await cache.loadGenerated(fingerprint: fingerprint)
        let fallbackAfterClear = await cache.loadCompatibleGeneratedFallback(
            matching: LyricsCacheLookupKey(
                fingerprint: fingerprint.replacingProviderForFallbackTest()
            )
        )

        XCTAssertNil(manualAfterClear)
        XCTAssertEqual(generatedAfterClear?.lyrics.first?.translation, "自动")
        XCTAssertEqual(fallbackAfterClear?.lyrics.first?.translation, "自动")
    }
}

private extension LyricsCacheFingerprint {
    func replacingProviderForFallbackTest() -> LyricsCacheFingerprint {
        LyricsCacheFingerprint(
            trackID: trackID,
            lyricsSourceID: lyricsSourceID,
            originalLyricsHash: originalLyricsHash,
            targetLanguage: targetLanguage,
            provider: "OpenAI",
            model: "gpt-5-mini",
            thinkingEnabled: true,
            promptVersion: "lyrics-translation-v3",
            schemaVersion: schemaVersion,
            appVersion: "0.3.0"
        )
    }
}
