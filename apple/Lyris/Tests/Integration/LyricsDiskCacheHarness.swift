import Foundation

#if !SWIFT_PACKAGE
extension Bundle {
    static var module: Bundle { .main }
}
#endif

@main
private enum LyricsDiskCacheHarness {
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("LyrisLyricsHarness-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = LyricsDiskCache(rootURL: root)
        let sourceLyrics = [TimedLyric(startTime: 1, original: "generated", translation: "")]
        let fingerprint = LyricsCacheFingerprint(
            trackID: "spotify:track:test",
            lyricsSourceID: "fixture:1",
            originalLyricsHash: LyricsCacheFingerprint.originalLyricsHash(for: sourceLyrics),
            targetLanguage: TranslationTargetLanguage.simplifiedChinese.apiName,
            provider: TranslationProvider.deepSeek.rawValue,
            model: TranslationProvider.deepSeek.defaultModel,
            thinkingEnabled: false,
            promptVersion: LyricsTranslationPrompt.version,
            schemaVersion: LyricsCacheFingerprint.currentSchemaVersion,
            appVersion: "test"
        )
        let generated = LyricsCacheEntry(
            trackID: fingerprint.trackID,
            trackTitle: "Track",
            artist: "Artist",
            translationTarget: TranslationTargetLanguage.simplifiedChinese.apiName,
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
        precondition(generatedLoad?.source == .generated)
        let latestLoad = await cache.loadLatestGenerated(
            matching: LyricsCacheLookupKey(fingerprint: fingerprint)
        )
        precondition(latestLoad?.fingerprint == fingerprint)
        let changedProvider = LyricsCacheLookupKey(
            trackID: fingerprint.trackID,
            targetLanguage: fingerprint.targetLanguage,
            provider: "OpenAI",
            model: "gpt-5-mini",
            thinkingEnabled: fingerprint.thinkingEnabled,
            promptVersion: fingerprint.promptVersion,
            schemaVersion: fingerprint.schemaVersion,
            appVersion: "next-version"
        )
        let exactChangedProviderLoad = await cache.loadLatestGenerated(matching: changedProvider)
        precondition(exactChangedProviderLoad == nil)
        let compatibleLoad = await cache.loadCompatibleGeneratedFallback(matching: changedProvider)
        precondition(compatibleLoad?.fingerprint == fingerprint)
        try await cache.save(manual)
        let manualLoad = await cache.loadManual(trackID: generated.trackID)
        precondition(manualLoad?.source == .manual)
        let networkCache = root.appendingPathComponent("network", isDirectory: true)
        try FileManager.default.createDirectory(at: networkCache, withIntermediateDirectories: true)
        try Data(repeating: 7, count: 1_024).write(
            to: networkCache.appendingPathComponent("artwork.bin")
        )
        let usage = LyrisStorageUsage.inspect(
            lyricsURL: root,
            cacheURL: networkCache
        )
        precondition(usage.cachedLyricCount == 2)
        precondition(usage.lyricsBytes > 0)
        precondition(usage.networkCacheBytes == 1_024)
        try await cache.clearGenerated()
        let manualAfterGeneratedClear = await cache.loadManual(trackID: generated.trackID)
        precondition(manualAfterGeneratedClear?.source == .manual)
        let generatedAfterClear = await cache.loadGenerated(fingerprint: fingerprint)
        precondition(generatedAfterClear == nil)
        let compatibleAfterClear = await cache.loadCompatibleGeneratedFallback(matching: changedProvider)
        precondition(compatibleAfterClear == nil)
        try await cache.clearManual()
        let afterClear = await cache.loadManual(trackID: generated.trackID)
        precondition(afterClear == nil)
        print("lyrics_disk_cache=PASS latest_offline_reuse=PASS manual_priority=PASS storage_usage=PASS")
    }
}
