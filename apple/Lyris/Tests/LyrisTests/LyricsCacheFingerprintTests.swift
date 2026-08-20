import Foundation
import XCTest
@testable import Lyris

final class LyricsCacheFingerprintTests: XCTestCase {
    func testGeneratedCacheHitsOnlyWhenEveryFingerprintFieldMatches() async throws {
        try await withCache { cache in
            let fingerprint = makeFingerprint()
            try await cache.save(makeGeneratedEntry(fingerprint: fingerprint))

            let loaded = await cache.loadGenerated(fingerprint: fingerprint)

            XCTAssertEqual(loaded?.lyrics.first?.translation, "cached translation")
            XCTAssertEqual(loaded?.fingerprint, fingerprint)
        }
    }

    func testLatestGeneratedIndexPrefersExactTranslationConfiguration() async throws {
        try await withCache { cache in
            let fingerprint = makeFingerprint()
            let changedModelFingerprint = fingerprint.replacing(model: "different-model")
            try await cache.save(makeGeneratedEntry(fingerprint: fingerprint))
            try await cache.save(
                makeGeneratedEntry(
                    fingerprint: changedModelFingerprint,
                    translation: "different model translation"
                )
            )

            let matching = await cache.loadLatestGenerated(
                matching: LyricsCacheLookupKey(fingerprint: fingerprint)
            )

            XCTAssertEqual(matching?.fingerprint, fingerprint)
            XCTAssertEqual(matching?.lyrics.first?.translation, "cached translation")
        }
    }

    func testLatestGeneratedIndexReusesCompleteLyricsWhenProviderFingerprintChanges() async throws {
        try await withCache { cache in
            let fingerprint = makeFingerprint()
            try await cache.save(makeGeneratedEntry(fingerprint: fingerprint))

            let exactChangedProvider = await cache.loadLatestGenerated(
                matching: LyricsCacheLookupKey(
                    fingerprint: fingerprint.replacing(
                        provider: "OpenAI",
                        model: "gpt-5-mini",
                        thinkingEnabled: true,
                        promptVersion: "lyrics-translation-v3",
                        appVersion: "0.3.0"
                    )
                )
            )
            let changedProvider = await cache.loadCompatibleGeneratedFallback(
                matching: LyricsCacheLookupKey(
                    fingerprint: fingerprint.replacing(
                        provider: "OpenAI",
                        model: "gpt-5-mini",
                        thinkingEnabled: true,
                        promptVersion: "lyrics-translation-v3",
                        appVersion: "0.3.0"
                    )
                )
            )
            let changedTarget = await cache.loadCompatibleGeneratedFallback(
                matching: LyricsCacheLookupKey(
                    fingerprint: fingerprint.replacing(targetLanguage: "Japanese")
                )
            )

            XCTAssertNil(exactChangedProvider)
            XCTAssertEqual(changedProvider?.fingerprint, fingerprint)
            XCTAssertEqual(changedProvider?.lyrics.first?.translation, "cached translation")
            XCTAssertNil(changedTarget)
        }
    }

    func testCompatibleFallbackMigratesExistingFingerprintedEntryWithoutNewIndex() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("LyrisFingerprintTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = LyricsDiskCache(rootURL: root)
        let fingerprint = makeFingerprint()
        try await cache.save(makeGeneratedEntry(fingerprint: fingerprint))
        try FileManager.default.removeItem(
            at: root
                .appendingPathComponent(LyricsCacheSource.generated.rawValue, isDirectory: true)
                .appendingPathComponent("latest-compatible", isDirectory: true)
        )

        let migrated = await cache.loadCompatibleGeneratedFallback(
            matching: LyricsCacheLookupKey(
                fingerprint: fingerprint.replacing(provider: "OpenAI", model: "gpt-5-mini")
            )
        )

        XCTAssertEqual(migrated?.fingerprint, fingerprint)
        XCTAssertEqual(migrated?.lyrics.first?.translation, "cached translation")
    }

    func testEveryFingerprintFieldInvalidatesGeneratedCache() async throws {
        try await withCache { cache in
            let baseline = makeFingerprint()
            try await cache.save(makeGeneratedEntry(fingerprint: baseline))

            let variants: [LyricsCacheFingerprint] = [
                baseline.replacing(trackID: "spotify:track:other"),
                baseline.replacing(lyricsSourceID: "lrclib:record:other"),
                baseline.replacing(originalLyricsHash: "different-original-hash"),
                baseline.replacing(targetLanguage: "Japanese"),
                baseline.replacing(provider: "OpenAI"),
                baseline.replacing(model: "gpt-5-mini"),
                baseline.replacing(thinkingEnabled: true),
                baseline.replacing(promptVersion: "lyrics-translation-v3"),
                baseline.replacing(schemaVersion: baseline.schemaVersion + 1),
                baseline.replacing(appVersion: "0.3.0"),
            ]

            for variant in variants {
                let loaded = await cache.loadGenerated(fingerprint: variant)
                XCTAssertNil(loaded, "A changed fingerprint field must be a cache miss: \(variant)")
            }
        }
    }

    func testGeneratedEntryWithoutFingerprintAndOldSchemaAreRejected() async throws {
        try await withCache { cache in
            let incomplete = makeGeneratedEntry(fingerprint: nil)
            await XCTAssertThrowsErrorAsync(try await cache.save(incomplete)) { error in
                XCTAssertEqual(error as? LyricsCacheError, .missingGeneratedFingerprint)
            }

            let oldFingerprint = makeFingerprint().replacing(
                schemaVersion: LyricsCacheFingerprint.currentSchemaVersion - 1
            )
            await XCTAssertThrowsErrorAsync(
                try await cache.save(makeGeneratedEntry(fingerprint: oldFingerprint))
            ) { error in
                XCTAssertEqual(error as? LyricsCacheError, .unsupportedSchemaVersion)
            }

            let oldSchemaLoad = await cache.loadGenerated(fingerprint: oldFingerprint)
            XCTAssertNil(oldSchemaLoad)
        }
    }

    func testManualLyricsRemainHighestPriorityAcrossGeneratedFingerprints() async throws {
        try await withCache { cache in
            let originalFingerprint = makeFingerprint()
            let changedFingerprint = originalFingerprint.replacing(
                provider: "OpenAI",
                model: "gpt-5-mini",
                appVersion: "0.3.0"
            )
            try await cache.save(makeGeneratedEntry(fingerprint: originalFingerprint))
            try await cache.save(makeManualEntry(trackID: originalFingerprint.trackID))
            try await cache.save(
                makeGeneratedEntry(
                    fingerprint: changedFingerprint,
                    translation: "newer generated translation"
                )
            )

            let manualLoad = await cache.loadManual(trackID: originalFingerprint.trackID)
            let originalLoad = await cache.loadGenerated(fingerprint: originalFingerprint)
            let changedLoad = await cache.loadGenerated(fingerprint: changedFingerprint)

            XCTAssertEqual(manualLoad?.source, .manual)
            XCTAssertEqual(manualLoad?.lyrics.first?.original, "hand written")
            XCTAssertEqual(originalLoad?.source, .generated)
            XCTAssertEqual(originalLoad?.lyrics.first?.original, "First")
            XCTAssertEqual(changedLoad?.source, .generated)
            XCTAssertEqual(changedLoad?.lyrics.first?.original, "First")
            XCTAssertEqual(changedLoad?.lyrics.first?.translation, "newer generated translation")
        }
    }

    func testOriginalLyricsHashChangesWithTextOrTimingButNotTranslation() {
        let baseline = [
            TimedLyric(startTime: 1.25, original: "First", translation: "甲"),
            TimedLyric(startTime: 3.5, original: "Second", translation: "乙"),
        ]
        let translatedDifferently = [
            TimedLyric(startTime: 1.25, original: "First", translation: "A"),
            TimedLyric(startTime: 3.5, original: "Second", translation: "B"),
        ]
        let changedText = [
            TimedLyric(startTime: 1.25, original: "Changed", translation: "甲"),
            baseline[1],
        ]
        let changedTiming = [
            TimedLyric(startTime: 1.5, original: "First", translation: "甲"),
            baseline[1],
        ]

        XCTAssertEqual(
            LyricsCacheFingerprint.originalLyricsHash(for: baseline),
            LyricsCacheFingerprint.originalLyricsHash(for: translatedDifferently)
        )
        XCTAssertNotEqual(
            LyricsCacheFingerprint.originalLyricsHash(for: baseline),
            LyricsCacheFingerprint.originalLyricsHash(for: changedText)
        )
        XCTAssertNotEqual(
            LyricsCacheFingerprint.originalLyricsHash(for: baseline),
            LyricsCacheFingerprint.originalLyricsHash(for: changedTiming)
        )
    }

    private func withCache(
        _ operation: (LyricsDiskCache) async throws -> Void
    ) async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("LyrisFingerprintTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try await operation(LyricsDiskCache(rootURL: root))
    }

    private func makeFingerprint() -> LyricsCacheFingerprint {
        let original = [TimedLyric(startTime: 1.25, original: "First", translation: "")]
        return LyricsCacheFingerprint(
            trackID: "spotify:track:test",
            lyricsSourceID: "lrclib:record:42",
            originalLyricsHash: LyricsCacheFingerprint.originalLyricsHash(for: original),
            targetLanguage: "Simplified Chinese",
            provider: "DeepSeek",
            model: "deepseek-v4-flash",
            thinkingEnabled: false,
            promptVersion: "lyrics-translation-v2",
            schemaVersion: LyricsCacheFingerprint.currentSchemaVersion,
            appVersion: "0.2.0"
        )
    }

    private func makeGeneratedEntry(
        fingerprint: LyricsCacheFingerprint?,
        translation: String = "cached translation"
    ) -> LyricsCacheEntry {
        LyricsCacheEntry(
            trackID: fingerprint?.trackID ?? "spotify:track:test",
            trackTitle: "Track",
            artist: "Artist",
            trackDuration: 180,
            translationTarget: fingerprint?.targetLanguage,
            savedAt: Date(timeIntervalSince1970: 1_700_000_000),
            source: .generated,
            fingerprint: fingerprint,
            lyrics: [TimedLyric(startTime: 1.25, original: "First", translation: translation)]
        )
    }

    private func makeManualEntry(trackID: String) -> LyricsCacheEntry {
        LyricsCacheEntry(
            trackID: trackID,
            trackTitle: "Track",
            artist: "Artist",
            trackDuration: 180,
            savedAt: Date(timeIntervalSince1970: 1_700_000_001),
            source: .manual,
            lyrics: [TimedLyric(startTime: 1.25, original: "hand written", translation: "手写")]
        )
    }
}

private extension LyricsCacheFingerprint {
    func replacing(
        trackID: String? = nil,
        lyricsSourceID: String? = nil,
        originalLyricsHash: String? = nil,
        targetLanguage: String? = nil,
        provider: String? = nil,
        model: String? = nil,
        thinkingEnabled: Bool? = nil,
        promptVersion: String? = nil,
        schemaVersion: Int? = nil,
        appVersion: String? = nil
    ) -> LyricsCacheFingerprint {
        LyricsCacheFingerprint(
            trackID: trackID ?? self.trackID,
            lyricsSourceID: lyricsSourceID ?? self.lyricsSourceID,
            originalLyricsHash: originalLyricsHash ?? self.originalLyricsHash,
            targetLanguage: targetLanguage ?? self.targetLanguage,
            provider: provider ?? self.provider,
            model: model ?? self.model,
            thinkingEnabled: thinkingEnabled ?? self.thinkingEnabled,
            promptVersion: promptVersion ?? self.promptVersion,
            schemaVersion: schemaVersion ?? self.schemaVersion,
            appVersion: appVersion ?? self.appVersion
        )
    }
}

private func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    _ errorHandler: (Error) -> Void = { _ in },
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("Expected expression to throw", file: file, line: line)
    } catch {
        errorHandler(error)
    }
}
