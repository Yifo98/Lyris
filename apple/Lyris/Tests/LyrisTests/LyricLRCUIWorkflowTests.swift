import Foundation
import XCTest
@testable import Lyris

final class LyricLRCUIWorkflowTests: XCTestCase {
    func testImportIssuesAreLocalizedWithExactSourceLineNumbers() {
        let issues = [
            LyricLRCImportIssue(
                lineNumber: 2,
                kind: .missingTimestamp,
                message: "codec message"
            ),
            LyricLRCImportIssue(
                lineNumber: 4,
                kind: .invalidTimestamp,
                message: "codec message"
            ),
            LyricLRCImportIssue(
                lineNumber: 7,
                kind: .missingLyricText,
                message: "codec message"
            ),
        ]

        XCTAssertEqual(
            LyricLRCUIWorkflow.importIssueMessage(
                issues,
                language: .simplifiedChinese
            ),
            "第 2 行：缺少 [mm:ss.xx] 时间戳。\n第 4 行：时间戳无效，请使用 [mm:ss.xx]。\n第 7 行：时间戳后缺少歌词正文。"
        )
        XCTAssertEqual(
            LyricLRCUIWorkflow.importIssueMessage(issues, language: .english),
            "Line 2: Missing [mm:ss.xx] timestamp.\nLine 4: Invalid timestamp; use [mm:ss.xx].\nLine 7: Missing lyric text after the timestamp."
        )
    }

    func testPlainLyricsRequireExplicitEstimationBeforeExport() throws {
        let document = LyricDocument(
            timingLevel: .plainText,
            source: LyricSourceMetadata(sourceID: "fixture:plain", provider: "Fixture"),
            lines: [
                LyricLine(startTime: nil, original: "First"),
                LyricLine(startTime: nil, original: "Second"),
            ]
        )

        XCTAssertEqual(
            try LyricLRCUIWorkflow.prepareExport(
                document: document,
                trackDuration: 20,
                estimateUntimedLines: false
            ),
            .requiresExplicitEstimation(lineNumbers: [1, 2])
        )

        let explicit = try LyricLRCUIWorkflow.prepareExport(
            document: document,
            trackDuration: 20,
            estimateUntimedLines: true
        )
        guard case .requiresLossConfirmation(let result) = explicit else {
            return XCTFail("Explicit estimation must still require a loss warning")
        }
        XCTAssertEqual(result.warnings.map(\.kind), [.untimedLinesEstimated])
        XCTAssertEqual(
            String(data: result.data, encoding: .utf8),
            "[00:00.00]First\n[00:10.00]Second\n"
        )
    }

    func testEstimatedAndWordTimingMustBeConfirmedBeforeSaving() throws {
        let wordDocument = LyricDocument(
            timingLevel: .wordSynced,
            source: LyricSourceMetadata(sourceID: "fixture:word", provider: "Fixture"),
            lines: [
                LyricLine(
                    startTime: nil,
                    original: "Hello",
                    words: [LyricWord(text: "Hello", startTime: 1.25, endTime: 1.8)]
                ),
            ]
        )
        let estimatedDocument = LyricDocument(
            timingLevel: .estimatedLine,
            source: LyricSourceMetadata(sourceID: "fixture:estimated", provider: "Fixture"),
            lines: [LyricLine(startTime: 3, original: "Estimated", isEstimated: true)]
        )

        guard case .requiresLossConfirmation(let wordResult) = try LyricLRCUIWorkflow.prepareExport(
            document: wordDocument,
            trackDuration: 20,
            estimateUntimedLines: false
        ) else {
            return XCTFail("Word timing must show a downgrade warning")
        }
        guard case .requiresLossConfirmation(let estimatedResult) = try LyricLRCUIWorkflow.prepareExport(
            document: estimatedDocument,
            trackDuration: 20,
            estimateUntimedLines: false
        ) else {
            return XCTFail("Estimated timing must show a downgrade warning")
        }

        XCTAssertEqual(wordResult.warnings.map(\.kind), [.wordTimingFlattened])
        XCTAssertEqual(
            estimatedResult.warnings.map(\.kind),
            [.estimatedTimingExportedAsLineTiming]
        )
    }

    func testPreciselyTimedLRCIsReadyWithoutAWarning() throws {
        let document = LyricDocument(
            timingLevel: .lineSynced,
            source: LyricSourceMetadata(sourceID: "fixture:line", provider: "Fixture"),
            lines: [LyricLine(startTime: 1.5, original: "Ready")]
        )

        guard case .ready(let result) = try LyricLRCUIWorkflow.prepareExport(
            document: document,
            trackDuration: 20,
            estimateUntimedLines: false
        ) else {
            return XCTFail("Precisely timed lyrics should be ready to save")
        }
        XCTAssertTrue(result.warnings.isEmpty)
    }
}
