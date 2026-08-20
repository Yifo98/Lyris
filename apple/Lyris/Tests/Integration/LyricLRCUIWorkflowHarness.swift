import Foundation
@testable import Lyris

@main
private enum LyricLRCUIWorkflowHarness {
    static func main() throws {
        let importIssues = [
            LyricLRCImportIssue(
                lineNumber: 2,
                kind: .missingTimestamp,
                message: "fixture"
            ),
            LyricLRCImportIssue(
                lineNumber: 4,
                kind: .invalidTimestamp,
                message: "fixture"
            ),
            LyricLRCImportIssue(
                lineNumber: 7,
                kind: .missingLyricText,
                message: "fixture"
            ),
        ]
        precondition(
            LyricLRCUIWorkflow.importIssueMessage(
                importIssues,
                language: .simplifiedChinese
            ) == "第 2 行：缺少 [mm:ss.xx] 时间戳。\n第 4 行：时间戳无效，请使用 [mm:ss.xx]。\n第 7 行：时间戳后缺少歌词正文。"
        )
        precondition(
            LyricLRCUIWorkflow.importIssueMessage(importIssues, language: .english)
                == "Line 2: Missing [mm:ss.xx] timestamp.\nLine 4: Invalid timestamp; use [mm:ss.xx].\nLine 7: Missing lyric text after the timestamp."
        )

        let plainDocument = LyricDocument(
            timingLevel: .plainText,
            source: LyricSourceMetadata(sourceID: "fixture:plain", provider: "Fixture"),
            lines: [
                LyricLine(startTime: nil, original: "First"),
                LyricLine(startTime: nil, original: "Second"),
            ]
        )
        let rejectedPlainExport = try LyricLRCUIWorkflow.prepareExport(
            document: plainDocument,
            trackDuration: 20,
            estimateUntimedLines: false
        )
        precondition(rejectedPlainExport == .requiresExplicitEstimation(lineNumbers: [1, 2]))
        let explicitlyEstimated = try LyricLRCUIWorkflow.prepareExport(
            document: plainDocument,
            trackDuration: 20,
            estimateUntimedLines: true
        )
        guard case .requiresLossConfirmation(let estimatedResult) = explicitlyEstimated else {
            preconditionFailure("Explicit estimation did not require confirmation")
        }
        precondition(estimatedResult.warnings.map(\.kind) == [.untimedLinesEstimated])

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
        guard case .requiresLossConfirmation(let wordResult) = try LyricLRCUIWorkflow.prepareExport(
            document: wordDocument,
            trackDuration: 20,
            estimateUntimedLines: false
        ) else {
            preconditionFailure("Word timing did not require downgrade confirmation")
        }
        precondition(wordResult.warnings.map(\.kind) == [.wordTimingFlattened])

        print(
            "lrc_ui_import_lines=PASS plain_requires_confirmation=PASS "
                + "explicit_estimation_warning=PASS word_downgrade_warning=PASS"
        )
    }
}
