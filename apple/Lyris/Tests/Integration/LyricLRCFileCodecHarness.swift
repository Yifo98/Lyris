import Foundation

// This lightweight compatibility type keeps the harness independent from the app target.
struct TimedLyric: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let startTime: TimeInterval
    let original: String
    var translation: String
    let isEstimated: Bool

    init(
        id: UUID = UUID(),
        startTime: TimeInterval,
        original: String,
        translation: String,
        isEstimated: Bool = false
    ) {
        self.id = id
        self.startTime = startTime
        self.original = original
        self.translation = translation
        self.isEstimated = isEstimated
    }
}

@main
private enum LyricLRCFileCodecHarness {
    static func main() throws {
        let imported = try LyricLRCFileCodec.decode(
            data: Data("[00:07.20]First || \u{7b2c}\u{4e00}\u{53e5}\r\n[bad]Broken\r\n[02:00.40]Third\r\n".utf8),
            filenameExtension: "lrc",
            options: LyricLRCImportOptions(translationLanguage: "zh-Hans")
        )
        precondition(imported.document.lines.map(\.startTime) == [7.2, 120.4])
        precondition(imported.issues.map(\.lineNumber) == [2])
        precondition(!imported.canSavePrecisely)
        precondition(imported.document.lines.allSatisfy { !$0.isEstimated })

        let wordDocument = LyricDocument(
            timingLevel: .wordSynced,
            source: LyricSourceMetadata(sourceID: "fixture:word", provider: "Fixture"),
            lines: [
                LyricLine(
                    startTime: nil,
                    original: "Hello world",
                    words: [LyricWord(text: "Hello", startTime: 1.25, endTime: 1.8)]
                ),
            ]
        )
        let wordExport = try LyricLRCFileCodec.encode(document: wordDocument)
        precondition(String(data: wordExport.data, encoding: .utf8) == "[00:01.25]Hello world\n")
        precondition(wordExport.warnings.map(\.kind) == [.wordTimingFlattened])

        let estimatedDocument = LyricDocument(
            timingLevel: .estimatedLine,
            source: LyricSourceMetadata(sourceID: "fixture:estimated", provider: "Fixture"),
            lines: [LyricLine(startTime: 3, original: "Estimated", isEstimated: true)]
        )
        let estimatedExport = try LyricLRCFileCodec.encode(document: estimatedDocument)
        precondition(
            estimatedExport.warnings.map(\.kind) == [.estimatedTimingExportedAsLineTiming]
        )

        let plainDocument = LyricDocument(
            timingLevel: .plainText,
            source: LyricSourceMetadata(sourceID: "fixture:plain", provider: "Fixture"),
            lines: [
                LyricLine(startTime: nil, original: "First"),
                LyricLine(startTime: nil, original: "Second"),
            ]
        )
        do {
            _ = try LyricLRCFileCodec.encode(document: plainDocument)
            preconditionFailure("Plain lyrics received silent timestamps")
        } catch let error as LyricLRCFileError {
            precondition(error == .untimedLines([1, 2]))
        }
        let plainExport = try LyricLRCFileCodec.encode(
            document: plainDocument,
            options: LyricLRCExportOptions(
                untimedLineStrategy: .estimateEvenly(duration: 20)
            )
        )
        precondition(
            String(data: plainExport.data, encoding: .utf8)
                == "[00:00.00]First\n[00:10.00]Second\n"
        )
        precondition(plainExport.warnings.map(\.kind) == [.untimedLinesEstimated])

        let blankDocument = LyricDocument(
            timingLevel: .lineSynced,
            source: LyricSourceMetadata(sourceID: "fixture:blank", provider: "Fixture"),
            lines: [LyricLine(startTime: 1, original: " \n ")]
        )
        do {
            _ = try LyricLRCFileCodec.encode(document: blankDocument)
            preconditionFailure("A blank lyric body was exported")
        } catch let error as LyricLRCFileError {
            precondition(error == .missingLyricText(lineNumber: 1))
        }

        print(
            "lyric_lrc_codec=PASS invalid_line_preserves_timing=PASS "
                + "word_degradation=PASS estimated_degradation=PASS "
                + "plain_explicit_estimate=PASS blank_body_rejected=PASS"
        )
    }
}
