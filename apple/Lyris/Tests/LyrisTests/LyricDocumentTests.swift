import XCTest
@testable import Lyris

final class LyricDocumentTests: XCTestCase {
    func testProviderBoundaryCarriesUnifiedDocumentAndKeepsLegacyTimedView() {
        let input = [
            TimedLyric(startTime: 1.25, original: "First", translation: "第一句"),
            TimedLyric(startTime: 3.5, original: "Second", translation: "第二句"),
        ]

        let result = LyricsProviderResult(
            sourceID: "fixture:42",
            lyrics: input,
            trackID: "spotify:track:test",
            provider: "Fixture"
        )

        XCTAssertEqual(result.document.timingLevel, .lineSynced)
        XCTAssertEqual(result.document.source.sourceID, "fixture:42")
        XCTAssertEqual(result.document.trackID, "spotify:track:test")
        XCTAssertEqual(result.lyrics, input)
    }

    func testEstimatedAndPlainTextAreNeverPresentedAsPreciseSync() {
        let estimated = LyricDocument(
            sourceID: "fixture:estimated",
            provider: "Fixture",
            timedLyrics: [TimedLyric(startTime: 0, original: "Line", translation: "", isEstimated: true)]
        )
        let plain = LyricDocument(
            timingLevel: .plainText,
            source: LyricSourceMetadata(sourceID: "fixture:plain", provider: "Fixture"),
            lines: [LyricLine(startTime: nil, original: "Untimed")]
        )

        XCTAssertFalse(estimated.timingLevel.isPreciselySynced)
        XCTAssertFalse(plain.timingLevel.isPreciselySynced)
        XCTAssertTrue(plain.timedLyrics[0].isEstimated)
    }
}
