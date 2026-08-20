import Foundation
import XCTest
@testable import Lyris

final class LyricLRCFileCodecTests: XCTestCase {
    func testDecodeBuildsLineSyncedDocumentWithOptionalTranslation() throws {
        let data = Data(
            "\u{FEFF}[ti:Fixture]\r\n[00:07.20] First || \u{7b2c}\u{4e00}\u{53e5}\r\n[02:00.40] Third\r\n".utf8
        )

        let result = try LyricLRCFileCodec.decode(
            data: data,
            filenameExtension: ".LRC",
            options: LyricLRCImportOptions(
                trackID: "spotify:track:test",
                sourceID: "file:fixture.lrc",
                translationLanguage: "zh-Hans"
            )
        )

        XCTAssertEqual(result.document.trackID, "spotify:track:test")
        XCTAssertEqual(result.document.timingLevel, .lineSynced)
        XCTAssertEqual(result.document.lines.map(\.startTime), [7.2, 120.4])
        XCTAssertEqual(result.document.lines.map(\.original), ["First", "Third"])
        XCTAssertEqual(result.document.lines[0].translations.first?.targetLanguage, "zh-Hans")
        XCTAssertEqual(result.document.lines[0].translations.first?.text, "\u{7b2c}\u{4e00}\u{53e5}")
        XCTAssertTrue(result.document.lines[1].translations.isEmpty)
        XCTAssertTrue(result.issues.isEmpty)
        XCTAssertTrue(result.canSavePrecisely)
    }

    func testDecodeReportsEachBrokenSourceLineWithoutRetimingValidLyrics() throws {
        let result = try LyricLRCFileCodec.decode(
            data: Data(
                "[00:07.20]First\r\nUntimed\r\n[01:75.00]Bad seconds\r\n[02:00.40]\r\n[02:10.00]Last\r\n".utf8
            ),
            filenameExtension: "lrc"
        )

        XCTAssertEqual(result.document.lines.map(\.startTime), [7.2, 130])
        XCTAssertEqual(result.issues.map(\.lineNumber), [2, 3, 4])
        XCTAssertEqual(
            result.issues.map(\.kind),
            [.missingTimestamp, .invalidTimestamp, .missingLyricText]
        )
        XCTAssertTrue(result.document.lines.allSatisfy { !$0.isEstimated })
        XCTAssertFalse(result.canSavePrecisely)
    }

    func testDecodeRejectsNonLRCOrNonUTF8DataAtTheFileBoundary() throws {
        do {
            _ = try LyricLRCFileCodec.decode(
                data: Data("[00:01.00]Line".utf8),
                filenameExtension: "txt"
            )
            XCTFail("Unsupported extensions must be rejected")
        } catch let error as LyricLRCFileError {
            XCTAssertEqual(error, .unsupportedFilenameExtension("txt"))
        }

        do {
            _ = try LyricLRCFileCodec.decode(
                data: Data([0xFF, 0xFE, 0xFD]),
                filenameExtension: "lrc"
            )
            XCTFail("Invalid UTF-8 must be rejected")
        } catch let error as LyricLRCFileError {
            XCTAssertEqual(error, .invalidUTF8)
        }

        XCTAssertEqual(LyricLRCFileCodec.supportedFilenameExtensions, ["lrc"])
        XCTAssertTrue(LyricLRCFileCodec.supports(filenameExtension: ".LRC"))
    }

    func testEncodeWritesStandardLineLRCWithSelectedTranslation() throws {
        let document = LyricDocument(
            trackID: "spotify:track:test",
            timingLevel: .lineSynced,
            source: LyricSourceMetadata(sourceID: "fixture:42", provider: "Fixture"),
            lines: [
                LyricLine(
                    startTime: 7.2,
                    original: "First",
                    translations: [
                        LyricTranslation(targetLanguage: "ja", text: "\u{6700}\u{521d}"),
                        LyricTranslation(targetLanguage: "zh-Hans", text: "\u{7b2c}\u{4e00}\u{53e5}"),
                    ]
                ),
                LyricLine(startTime: 120.4, original: "Third"),
            ]
        )

        let result = try LyricLRCFileCodec.encode(
            document: document,
            options: LyricLRCExportOptions(translationLanguage: "zh-Hans")
        )

        XCTAssertEqual(result.filenameExtension, "lrc")
        XCTAssertEqual(
            String(data: result.data, encoding: .utf8),
            "[00:07.20]First || \u{7b2c}\u{4e00}\u{53e5}\n[02:00.40]Third\n"
        )
        XCTAssertTrue(result.warnings.isEmpty)
    }

    func testEncodeFlattensWordTimingToLineTimingAndReportsTheLoss() throws {
        let document = LyricDocument(
            timingLevel: .wordSynced,
            source: LyricSourceMetadata(sourceID: "fixture:word", provider: "Fixture"),
            lines: [
                LyricLine(
                    startTime: nil,
                    original: "Hello world",
                    words: [
                        LyricWord(text: "Hello", startTime: 1.25, endTime: 1.8),
                        LyricWord(text: "world", startTime: 1.85, endTime: 2.4),
                    ]
                ),
            ]
        )

        let result = try LyricLRCFileCodec.encode(document: document)

        XCTAssertEqual(String(data: result.data, encoding: .utf8), "[00:01.25]Hello world\n")
        XCTAssertEqual(result.warnings.map(\.kind), [.wordTimingFlattened])
        XCTAssertEqual(result.warnings.first?.lineNumbers, [1])
    }

    func testEncodeKeepsEstimatedTimestampsButMarksThemAsEstimatedLoss() throws {
        let document = LyricDocument(
            timingLevel: .estimatedLine,
            source: LyricSourceMetadata(sourceID: "fixture:estimated", provider: "Fixture"),
            lines: [
                LyricLine(startTime: 3, original: "Estimated", isEstimated: true),
                LyricLine(startTime: 8, original: "Also estimated", isEstimated: true),
            ]
        )

        let result = try LyricLRCFileCodec.encode(document: document)

        XCTAssertEqual(
            String(data: result.data, encoding: .utf8),
            "[00:03.00]Estimated\n[00:08.00]Also estimated\n"
        )
        XCTAssertEqual(result.warnings.map(\.kind), [.estimatedTimingExportedAsLineTiming])
        XCTAssertEqual(result.warnings.first?.lineNumbers, [1, 2])
    }

    func testPlainTextRequiresExplicitEstimationBeforeLRCExport() throws {
        let document = LyricDocument(
            timingLevel: .plainText,
            source: LyricSourceMetadata(sourceID: "fixture:plain", provider: "Fixture"),
            lines: [
                LyricLine(startTime: nil, original: "First"),
                LyricLine(startTime: nil, original: "Second"),
            ]
        )

        do {
            _ = try LyricLRCFileCodec.encode(document: document)
            XCTFail("Plain lyrics must not receive silent timestamps")
        } catch let error as LyricLRCFileError {
            XCTAssertEqual(error, .untimedLines([1, 2]))
        }

        let estimated = try LyricLRCFileCodec.encode(
            document: document,
            options: LyricLRCExportOptions(
                untimedLineStrategy: .estimateEvenly(duration: 20)
            )
        )

        XCTAssertEqual(
            String(data: estimated.data, encoding: .utf8),
            "[00:00.00]First\n[00:10.00]Second\n"
        )
        XCTAssertEqual(estimated.warnings.map(\.kind), [.untimedLinesEstimated])
        XCTAssertEqual(estimated.warnings.first?.lineNumbers, [1, 2])
    }

    func testExplicitEstimationPreservesExistingLineTiming() throws {
        let document = LyricDocument(
            timingLevel: .plainText,
            source: LyricSourceMetadata(sourceID: "fixture:mixed", provider: "Fixture"),
            lines: [
                LyricLine(startTime: 2, original: "Timed first"),
                LyricLine(startTime: nil, original: "Untimed middle"),
                LyricLine(startTime: 12, original: "Timed last"),
            ]
        )

        let result = try LyricLRCFileCodec.encode(
            document: document,
            options: LyricLRCExportOptions(
                untimedLineStrategy: .estimateEvenly(duration: 20)
            )
        )

        XCTAssertEqual(
            String(data: result.data, encoding: .utf8),
            "[00:02.00]Timed first\n[00:07.00]Untimed middle\n[00:12.00]Timed last\n"
        )
        XCTAssertEqual(result.warnings.first?.lineNumbers, [2])
    }

    func testEncodeRejectsAWhitespaceOnlyLyricLine() throws {
        let document = LyricDocument(
            timingLevel: .lineSynced,
            source: LyricSourceMetadata(sourceID: "fixture:blank", provider: "Fixture"),
            lines: [LyricLine(startTime: 1, original: " \n ")]
        )

        do {
            _ = try LyricLRCFileCodec.encode(document: document)
            XCTFail("An empty LRC body must be rejected")
        } catch let error as LyricLRCFileError {
            XCTAssertEqual(error, .missingLyricText(lineNumber: 1))
        }
    }
}
