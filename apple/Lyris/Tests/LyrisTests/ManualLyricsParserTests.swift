import XCTest
@testable import Lyris

final class ManualLyricsParserTests: XCTestCase {
    func testOneInvalidLineDoesNotRetimeValidLines() {
        let result = ManualLyricsParser.parse(
            """
            [00:07.20] First
            [bad] Fix me
            [02:00.40] Third
            """,
            duration: 180
        )

        XCTAssertEqual(result.lyrics.map(\.startTime), [7.2, 120.4])
        XCTAssertEqual(result.issues.map(\.lineNumber), [2])
        XCTAssertTrue(result.lyrics.allSatisfy { !$0.isEstimated })
    }

    func testUntimedLinesRequireExplicitEstimateAll() {
        let precise = ManualLyricsParser.parse("First\nSecond", duration: 100)
        XCTAssertEqual(precise.untimedLineNumbers, [1, 2])
        XCTAssertTrue(precise.lyrics.isEmpty)

        let estimated = ManualLyricsParser.parse("First\nSecond", duration: 100, mode: .estimateAll)
        XCTAssertEqual(estimated.lyrics.count, 2)
        XCTAssertTrue(estimated.lyrics.allSatisfy(\.isEstimated))
    }

    func testTimestampSecondsMustBeBelowSixty() {
        let result = ManualLyricsParser.parse("[01:75.00] Invalid", duration: 180)
        XCTAssertEqual(result.issues.map(\.lineNumber), [1])
        XCTAssertTrue(result.lyrics.isEmpty)
    }
}
