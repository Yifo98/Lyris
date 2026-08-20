import XCTest
@testable import Lyris

final class LyricsSourceSelectionTests: XCTestCase {
    func testTranslationFirstPrefersCompleteTranslationWithinTheSameMatchTier() throws {
        let qq = candidate(
            sourceID: "qq:1",
            provider: "QQ Music",
            translation: nil
        )
        let netease = candidate(
            sourceID: "netease:1",
            provider: "NetEase Music",
            translation: "译文"
        )
        let policy = LyricsSourceSelectionPolicy(
            providerOrder: ["QQ Music", "NetEase Music"],
            translationPriority: .translationFirst,
            targetLanguage: "zh-Hans"
        )

        XCTAssertEqual(
            try XCTUnwrap(policy.select(from: [qq, netease])).document.source.sourceID,
            "netease:1"
        )
    }

    func testProviderFirstRespectsTheConfiguredSourceOrder() throws {
        let qq = candidate(
            sourceID: "qq:1",
            provider: "QQ Music",
            translation: nil
        )
        let netease = candidate(
            sourceID: "netease:1",
            provider: "NetEase Music",
            translation: "译文"
        )
        let policy = LyricsSourceSelectionPolicy(
            providerOrder: ["QQ Music", "NetEase Music"],
            translationPriority: .providerFirst,
            targetLanguage: "zh-Hans"
        )

        XCTAssertEqual(
            try XCTUnwrap(policy.select(from: [netease, qq])).document.source.sourceID,
            "qq:1"
        )
    }

    func testUserLyricsRemainAuthoritativeOverNetworkCapabilities() throws {
        let user = candidate(
            sourceID: "user:1",
            provider: "User",
            translation: nil,
            authority: .user,
            matchQuality: .high,
            timingLevel: .lineSynced
        )
        let network = candidate(
            sourceID: "network:1",
            provider: "NetEase Music",
            translation: "译文",
            authority: .network,
            matchQuality: .exact,
            timingLevel: .wordSynced
        )
        let policy = LyricsSourceSelectionPolicy(
            providerOrder: ["NetEase Music"],
            translationPriority: .translationFirst,
            targetLanguage: "zh-Hans"
        )

        XCTAssertEqual(
            try XCTUnwrap(policy.select(from: [network, user])).document.source.sourceID,
            "user:1"
        )
    }

    private func candidate(
        sourceID: String,
        provider: String,
        translation: String?,
        authority: LyricsCandidateAuthority = .network,
        matchQuality: LyricsMatchQuality = .high,
        timingLevel: LyricTimingLevel = .lineSynced
    ) -> LyricsSourceCandidate {
        let translations = translation.map {
            [LyricTranslation(targetLanguage: "zh-Hans", text: $0)]
        } ?? []
        return LyricsSourceCandidate(
            document: LyricDocument(
                trackID: "spotify:track:fixture",
                timingLevel: timingLevel,
                source: LyricSourceMetadata(
                    sourceID: sourceID,
                    provider: provider,
                    matchedTrackID: "spotify:track:fixture"
                ),
                lines: [
                    LyricLine(
                        startTime: 0,
                        original: "Fixture",
                        translations: translations
                    ),
                ]
            ),
            authority: authority,
            matchQuality: matchQuality
        )
    }
}
