import Foundation

struct ManualLyricsIssue: Equatable, Sendable {
    let lineNumber: Int
    let message: String
}

struct ManualLyricsParseResult: Equatable, Sendable {
    let lyrics: [TimedLyric]
    let issues: [ManualLyricsIssue]
    let untimedLineNumbers: [Int]

    var canSavePrecisely: Bool {
        !lyrics.isEmpty && issues.isEmpty && untimedLineNumbers.isEmpty
    }
}

enum ManualLyricsParsingMode: Equatable, Sendable {
    case preserveValidTiming
    case estimateAll
}

enum ManualLyricsParser {
    static func parse(
        _ value: String,
        duration: TimeInterval,
        mode: ManualLyricsParsingMode = .preserveValidTiming
    ) -> ManualLyricsParseResult {
        let rows = value
            .components(separatedBy: .newlines)
            .enumerated()
            .compactMap { offset, raw -> (Int, String)? in
                let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                return line.isEmpty ? nil : (offset + 1, line)
            }
        guard !rows.isEmpty else {
            return ManualLyricsParseResult(lyrics: [], issues: [], untimedLineNumbers: [])
        }

        if mode == .estimateAll {
            let start = min(8, max(2, duration * 0.04))
            let step = max(1, duration - start - 3) / Double(rows.count)
            let lyrics = rows.enumerated().compactMap { index, row -> TimedLyric? in
                let content = contentWithoutTimestamp(row.1)
                guard let parts = lyricParts(content), !parts.original.isEmpty else { return nil }
                return TimedLyric(
                    startTime: start + Double(index) * step,
                    original: parts.original,
                    translation: parts.translation,
                    isEstimated: true
                )
            }
            return ManualLyricsParseResult(lyrics: lyrics, issues: [], untimedLineNumbers: [])
        }

        var lyrics: [TimedLyric] = []
        var issues: [ManualLyricsIssue] = []
        var untimed: [Int] = []
        for (lineNumber, line) in rows {
            guard line.hasPrefix("[") else {
                untimed.append(lineNumber)
                continue
            }
            guard let match = timestampExpression.firstMatch(
                in: line,
                range: NSRange(line.startIndex..<line.endIndex, in: line)
            ),
                  let minuteRange = Range(match.range(at: 1), in: line),
                  let secondRange = Range(match.range(at: 2), in: line),
                  let textRange = Range(match.range(at: 3), in: line),
                  let minutes = Double(line[minuteRange]),
                  let seconds = Double(line[secondRange]),
                  seconds >= 0,
                  seconds < 60 else {
                issues.append(ManualLyricsIssue(lineNumber: lineNumber, message: "时间戳应为 [mm:ss.xx]，且秒数小于 60"))
                continue
            }
            guard let parts = lyricParts(String(line[textRange])), !parts.original.isEmpty else {
                issues.append(ManualLyricsIssue(lineNumber: lineNumber, message: "时间戳后缺少歌词正文"))
                continue
            }
            lyrics.append(
                TimedLyric(
                    startTime: minutes * 60 + seconds,
                    original: parts.original,
                    translation: parts.translation
                )
            )
        }

        return ManualLyricsParseResult(
            lyrics: lyrics.sorted(by: { $0.startTime < $1.startTime }),
            issues: issues,
            untimedLineNumbers: untimed
        )
    }

    private static let timestampExpression = try! NSRegularExpression(
        pattern: #"^\[(\d{1,3}):(\d{2}(?:\.\d{1,3})?)\]\s*(.*)$"#
    )

    private static func contentWithoutTimestamp(_ line: String) -> String {
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        if let match = timestampExpression.firstMatch(in: line, range: range),
           let textRange = Range(match.range(at: 3), in: line) {
            return String(line[textRange])
        }
        if line.hasPrefix("["), let closing = line.firstIndex(of: "]") {
            return String(line[line.index(after: closing)...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return line
    }

    private static func lyricParts(_ value: String) -> (original: String, translation: String)? {
        let parts = value.components(separatedBy: "||")
        guard let first = parts.first else { return nil }
        return (
            first.trimmingCharacters(in: .whitespacesAndNewlines),
            parts.dropFirst().joined(separator: "||").trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}
