import XCTest
@testable import Lyris

final class LyricsMatcherTests: XCTestCase {
    private let matcher = LyricsMatcher()

    func testUnicodeCasePunctuationAndWhitespaceStillMatch() {
        let track = makeTrack(
            title: "Ｂｅｙｏｎｃé — Halo!",
            artist: "BEYONCÉ",
            album: "I Am… Sasha Fierce"
        )
        let candidates = [
            candidate(
                title: "Beyonce halo",
                artist: "beyonce",
                album: "I Am Sasha Fierce",
                duration: 240.4
            ),
        ]

        XCTAssertEqual(matcher.bestMatch(for: track, among: candidates)?.index, 0)
    }

    func testFeatAndMultiArtistSpellingsAreEquivalent() {
        let track = makeTrack(
            title: "Stay (feat. Alessia Cara)",
            artist: "Zedd, Alessia Cara",
            album: "Stay"
        )
        let candidates = [
            candidate(
                title: "Stay ft Alessia Cara",
                artist: "Zedd & Alessia Cara",
                album: "Stay",
                duration: 240.2
            ),
        ]

        XCTAssertEqual(matcher.bestMatch(for: track, among: candidates)?.index, 0)
    }

    func testParenthesizedWithCreditDoesNotHideAnOtherwiseExactChineseMatch() {
        let track = makeTrack(
            title: "說好不哭",
            artist: "周杰倫",
            album: "說好不哭",
            duration: 222
        )
        let candidates = [
            candidate(
                title: "说好不哭 (with 五月天阿信)",
                artist: "周杰伦",
                album: "说好不哭 (with 五月天阿信)",
                duration: 222
            ),
        ]

        XCTAssertEqual(matcher.bestMatch(for: track, among: candidates)?.index, 0)
    }

    func testParenthesizedChineseStageNameAliasMatchesTheSpotifyArtist() {
        let track = makeTrack(
            title: "如果你也聽說",
            artist: "張惠妹",
            album: "Star",
            duration: 313
        )
        let candidates = [
            candidate(
                title: "如果你也聽說",
                artist: "aMEI (張惠妹)",
                album: "Star",
                duration: 313
            ),
        ]

        XCTAssertEqual(matcher.bestMatch(for: track, among: candidates)?.index, 0)
    }

    func testFeatureArtistNameIsNotMistakenForARecordingVersion() {
        let track = makeTrack(
            title: "Rather Be (feat. Clean Bandit)",
            artist: "Jess Glynne, Clean Bandit",
            album: "Single"
        )
        let candidates = [
            candidate(
                title: "Rather Be",
                artist: "Jess Glynne & Clean Bandit",
                album: "Single",
                duration: 240
            ),
        ]

        XCTAssertEqual(matcher.bestMatch(for: track, among: candidates)?.index, 0)
    }

    func testFeatureCreditAndRecordingVersionCanCoexist() {
        let track = makeTrack(
            title: "Stay (feat. Alessia Cara) - Live",
            artist: "Zedd, Alessia Cara",
            album: "Live Session"
        )
        let candidates = [
            candidate(
                title: "Stay ft Alessia Cara (Live Version)",
                artist: "Zedd & Alessia Cara",
                album: "Live Session",
                duration: 240
            ),
        ]

        XCTAssertEqual(matcher.bestMatch(for: track, among: candidates)?.index, 0)
    }

    func testAlbumBreaksATieBetweenOtherwiseEquivalentCandidates() {
        let track = makeTrack(title: "Midnight", artist: "Example", album: "Blue Hour")
        let candidates = [
            candidate(title: "Midnight", artist: "Example", album: "Red Hour", duration: 240),
            candidate(title: "Midnight", artist: "Example", album: "Blue Hour", duration: 240),
        ]

        XCTAssertEqual(matcher.bestMatch(for: track, among: candidates)?.index, 1)
    }

    func testDurationUsesContinuousClosenessInsteadOfAThreeSecondCliff() {
        let track = makeTrack(title: "Midnight", artist: "Example", album: "Single", duration: 240)
        let candidates = [
            candidate(title: "Midnight", artist: "Example", album: "Single", duration: 246.0),
            candidate(title: "Midnight", artist: "Example", album: "Single", duration: 243.1),
        ]

        XCTAssertEqual(matcher.bestMatch(for: track, among: candidates)?.index, 1)
    }

    func testVersionLabelsMatchTheirEquivalentSpellings() {
        let equivalentVersions: [(String, String)] = [
            ("Song (Live at Wembley)", "Song - Live"),
            ("Song (2011 Remastered)", "Song - Remaster"),
            ("Song (Acoustic Version)", "Song - Acoustic"),
            ("Song (Instrumental)", "Song - Instrumental Version"),
            ("Song (Karaoke Version)", "Song - Karaoke"),
            ("Song (Radio Edit)", "Song - Radio Version"),
            ("Song (Club Remix)", "Song - Remix"),
            ("Song (Original Demo)", "Song - Demo"),
            ("Song (Sped Up)", "Song - Speed Up Version"),
            ("Song (Slowed + Reverb)", "Song - Slowed Version"),
            ("Song (Clean)", "Song - Clean Version"),
            ("Song (Explicit)", "Song - Explicit Version"),
            ("Song (Deluxe)", "Song - Deluxe Version"),
        ]

        for (queryTitle, candidateTitle) in equivalentVersions {
            let track = makeTrack(title: queryTitle, artist: "Example", album: "Album")
            let candidates = [candidate(
                title: candidateTitle,
                artist: "Example",
                album: "Album",
                duration: 240
            )]

            XCTAssertEqual(
                matcher.bestMatch(for: track, among: candidates)?.index,
                0,
                "Expected equivalent version labels to match: \(queryTitle) / \(candidateTitle)"
            )
        }
    }

    func testAnyVersionConflictRejectsCandidate() {
        let conflicts: [(String, String)] = [
            ("Song (Live)", "Song"),
            ("Song", "Song (Acoustic)"),
            ("Song (Remastered)", "Song (Live)"),
            ("Song (Clean)", "Song (Explicit)"),
            ("Song (Radio Edit)", "Song (Remix)"),
            ("Song (Sped Up)", "Song (Slowed)"),
        ]

        for (queryTitle, candidateTitle) in conflicts {
            let track = makeTrack(title: queryTitle, artist: "Example", album: "Album")
            let candidates = [candidate(
                title: candidateTitle,
                artist: "Example",
                album: "Album",
                duration: 240
            )]

            XCTAssertNil(
                matcher.bestMatch(for: track, among: candidates),
                "Expected conflicting version labels to be rejected: \(queryTitle) / \(candidateTitle)"
            )
        }
    }

    func testLowConfidenceTitleOrArtistDoesNotMatch() {
        let track = makeTrack(title: "Golden Hour", artist: "JVKE", album: "this is what ____ feels like")
        let candidates = [
            candidate(title: "Golden", artist: "Harry Styles", album: "Fine Line", duration: 208),
            candidate(title: "Golden Hour", artist: "Kacey Musgraves", album: "Golden Hour", duration: 208),
        ]

        XCTAssertNil(matcher.bestMatch(for: track, among: candidates))
    }

    func testLargeDurationMismatchFallsBelowConfidenceThreshold() {
        let track = makeTrack(title: "Song", artist: "Example", album: "Album", duration: 240)
        let candidates = [
            candidate(title: "Song", artist: "Example", album: "Album", duration: 390),
        ]

        XCTAssertNil(matcher.bestMatch(for: track, among: candidates))
    }

    private func makeTrack(
        title: String,
        artist: String,
        album: String,
        duration: TimeInterval = 240
    ) -> Track {
        Track(
            id: "spotify:track:test",
            title: title,
            artist: artist,
            album: album,
            duration: duration
        )
    }

    private func candidate(
        title: String,
        artist: String,
        album: String,
        duration: TimeInterval
    ) -> LyricsMatchCandidate {
        LyricsMatchCandidate(
            title: title,
            artist: artist,
            album: album,
            duration: duration
        )
    }
}
