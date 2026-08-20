import Foundation

struct LyricLRCImportOptions: Equatable, Sendable {
    let trackID: String?
    let sourceID: String
    let provider: String
    let translationLanguage: String

    init(
        trackID: String? = nil,
        sourceID: String = "lrc:import",
        provider: String = "LRC Import",
        translationLanguage: String = "unspecified"
    ) {
        self.trackID = trackID
        self.sourceID = sourceID
        self.provider = provider
        self.translationLanguage = translationLanguage
    }
}

enum LyricLRCImportIssueKind: String, Equatable, Sendable {
    case missingTimestamp
    case invalidTimestamp
    case missingLyricText
}

struct LyricLRCImportIssue: Equatable, Sendable {
    let lineNumber: Int
    let kind: LyricLRCImportIssueKind
    let message: String
}

struct LyricLRCImportResult: Equatable, Sendable {
    let document: LyricDocument
    let issues: [LyricLRCImportIssue]

    var canSavePrecisely: Bool {
        !document.lines.isEmpty && issues.isEmpty
    }
}

enum LyricLRCUntimedExportStrategy: Equatable, Sendable {
    case reject
    case estimateEvenly(duration: TimeInterval)
}

struct LyricLRCExportOptions: Equatable, Sendable {
    let translationLanguage: String?
    let includeTranslation: Bool
    let untimedLineStrategy: LyricLRCUntimedExportStrategy

    init(
        translationLanguage: String? = nil,
        includeTranslation: Bool = true,
        untimedLineStrategy: LyricLRCUntimedExportStrategy = .reject
    ) {
        self.translationLanguage = translationLanguage
        self.includeTranslation = includeTranslation
        self.untimedLineStrategy = untimedLineStrategy
    }
}

enum LyricLRCExportWarningKind: String, Equatable, Sendable {
    case wordTimingFlattened
    case estimatedTimingExportedAsLineTiming
    case untimedLinesEstimated
}

struct LyricLRCExportWarning: Equatable, Sendable {
    let kind: LyricLRCExportWarningKind
    let lineNumbers: [Int]
    let message: String
}

struct LyricLRCExportResult: Equatable, Sendable {
    let data: Data
    let filenameExtension: String
    let warnings: [LyricLRCExportWarning]
}

enum LyricLRCFileError: Error, Equatable, Sendable {
    case unsupportedFilenameExtension(String)
    case invalidUTF8
    case noLyrics
    case untimedLines([Int])
    case invalidTimestamp(lineNumber: Int)
    case missingLyricText(lineNumber: Int)
    case invalidEstimationDuration
}

enum LyricLRCFileCodec {
    static let preferredFilenameExtension = "lrc"
    static let supportedFilenameExtensions = [preferredFilenameExtension]

    static func supports(filenameExtension: String) -> Bool {
        normalizedFilenameExtension(filenameExtension) == preferredFilenameExtension
    }

    static func decode(
        data: Data,
        filenameExtension: String,
        options: LyricLRCImportOptions = LyricLRCImportOptions()
    ) throws -> LyricLRCImportResult {
        guard supports(filenameExtension: filenameExtension) else {
            throw LyricLRCFileError.unsupportedFilenameExtension(filenameExtension)
        }
        guard var text = String(data: data, encoding: .utf8) else {
            throw LyricLRCFileError.invalidUTF8
        }
        if text.hasPrefix("\u{FEFF}") {
            text.removeFirst()
        }

        var lines: [LyricLine] = []
        var issues: [LyricLRCImportIssue] = []
        for (offset, rawLine) in sourceLines(in: text).enumerated() {
            let lineNumber = offset + 1
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !isMetadataLine(line) else { continue }
            guard let match = timestampExpression.firstMatch(
                in: line,
                range: NSRange(line.startIndex..<line.endIndex, in: line)
            ),
                  let minuteRange = Range(match.range(at: 1), in: line),
                  let secondRange = Range(match.range(at: 2), in: line),
                  let lyricRange = Range(match.range(at: 3), in: line),
                  let minutes = Double(line[minuteRange]),
                  let seconds = Double(line[secondRange]),
                  seconds >= 0,
                  seconds < 60 else {
                issues.append(
                    LyricLRCImportIssue(
                        lineNumber: lineNumber,
                        kind: line.hasPrefix("[") ? .invalidTimestamp : .missingTimestamp,
                        message: "Expected an LRC timestamp in [mm:ss.xx] format."
                    )
                )
                continue
            }

            let parts = lyricParts(String(line[lyricRange]))
            guard !parts.original.isEmpty else {
                issues.append(
                    LyricLRCImportIssue(
                        lineNumber: lineNumber,
                        kind: .missingLyricText,
                        message: "The timestamp is not followed by lyric text."
                    )
                )
                continue
            }
            let translations = parts.translation.isEmpty
                ? []
                : [
                    LyricTranslation(
                        targetLanguage: options.translationLanguage,
                        text: parts.translation
                    ),
                ]
            lines.append(
                LyricLine(
                    startTime: minutes * 60 + seconds,
                    original: parts.original,
                    translations: translations
                )
            )
        }

        let document = LyricDocument(
            trackID: options.trackID,
            timingLevel: lines.isEmpty ? .unavailable : .lineSynced,
            source: LyricSourceMetadata(
                sourceID: options.sourceID,
                provider: options.provider,
                matchedTrackID: options.trackID
            ),
            lines: lines.sorted { lhs, rhs in
                (lhs.startTime ?? 0) < (rhs.startTime ?? 0)
            }
        )
        return LyricLRCImportResult(document: document, issues: issues)
    }

    static func encode(
        document: LyricDocument,
        options: LyricLRCExportOptions = LyricLRCExportOptions()
    ) throws -> LyricLRCExportResult {
        guard !document.lines.isEmpty else {
            throw LyricLRCFileError.noLyrics
        }
        let sourceTimes = document.lines.map(effectiveStartTime)
        let untimedLineNumbers = sourceTimes.enumerated().compactMap { index, startTime in
            startTime == nil ? index + 1 : nil
        }
        let resolvedTimes: [TimeInterval]
        if untimedLineNumbers.isEmpty {
            resolvedTimes = sourceTimes.compactMap { $0 }
        } else {
            switch options.untimedLineStrategy {
            case .reject:
                throw LyricLRCFileError.untimedLines(untimedLineNumbers)
            case .estimateEvenly(let duration):
                resolvedTimes = try estimatedTimes(sourceTimes, duration: duration)
            }
        }

        let renderedLines = try document.lines.enumerated().map { index, line in
            let startTime = resolvedTimes[index]
            guard startTime.isFinite,
                  startTime >= 0 else {
                throw LyricLRCFileError.invalidTimestamp(lineNumber: index + 1)
            }
            let original = singleLineText(line.original)
            guard !original.isEmpty else {
                throw LyricLRCFileError.missingLyricText(lineNumber: index + 1)
            }
            let translation = selectedTranslation(for: line, options: options)
            let content = translation.isEmpty ? original : "\(original) || \(translation)"
            return "\(formattedTimestamp(startTime))\(content)"
        }
        let text = renderedLines.joined(separator: "\n") + "\n"
        guard let data = text.data(using: .utf8) else {
            throw LyricLRCFileError.invalidUTF8
        }
        let wordTimingLineNumbers = document.lines.enumerated().compactMap { index, line in
            (document.timingLevel == .wordSynced || !line.words.isEmpty) ? index + 1 : nil
        }
        var warnings: [LyricLRCExportWarning] = []
        if !wordTimingLineNumbers.isEmpty {
            warnings.append(
                LyricLRCExportWarning(
                    kind: .wordTimingFlattened,
                    lineNumbers: wordTimingLineNumbers,
                    message: "Word-level timing was flattened to one timestamp per lyric line."
                )
            )
        }
        let estimatedLineNumbers = document.lines.enumerated().compactMap { index, line in
            (document.timingLevel == .estimatedLine || line.isEstimated) ? index + 1 : nil
        }
        if !estimatedLineNumbers.isEmpty {
            warnings.append(
                LyricLRCExportWarning(
                    kind: .estimatedTimingExportedAsLineTiming,
                    lineNumbers: estimatedLineNumbers,
                    message: "Estimated timestamps were exported as ordinary LRC line timestamps."
                )
            )
        }
        if !untimedLineNumbers.isEmpty {
            warnings.append(
                LyricLRCExportWarning(
                    kind: .untimedLinesEstimated,
                    lineNumbers: untimedLineNumbers,
                    message: "Untimed lyric lines received explicit, evenly estimated timestamps."
                )
            )
        }
        return LyricLRCExportResult(
            data: data,
            filenameExtension: preferredFilenameExtension,
            warnings: warnings
        )
    }

    private static let timestampExpression = try! NSRegularExpression(
        pattern: #"^\[(\d{1,3}):(\d{2}(?:\.\d{1,3})?)\]\s*(.*)$"#
    )

    private static let metadataExpression = try! NSRegularExpression(
        pattern: #"^\[(?:al|ar|au|by|length|offset|re|ti|tool|ve):.*\]$"#,
        options: [.caseInsensitive]
    )

    private static func isMetadataLine(_ line: String) -> Bool {
        metadataExpression.firstMatch(
            in: line,
            range: NSRange(line.startIndex..<line.endIndex, in: line)
        ) != nil
    }

    private static func lyricParts(_ value: String) -> (original: String, translation: String) {
        let parts = value.components(separatedBy: "||")
        return (
            parts.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            parts.dropFirst().joined(separator: "||")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private static func normalizedFilenameExtension(_ value: String) -> String {
        value.trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .lowercased()
    }

    private static func sourceLines(in text: String) -> [String] {
        var lines: [String] = []
        text.enumerateLines { line, _ in
            lines.append(line)
        }
        return lines
    }

    private static func formattedTimestamp(_ time: TimeInterval) -> String {
        let totalCentiseconds = Int((time * 100).rounded())
        let minutes = totalCentiseconds / 6_000
        let seconds = (totalCentiseconds / 100) % 60
        let centiseconds = totalCentiseconds % 100
        return String(format: "[%02d:%02d.%02d]", minutes, seconds, centiseconds)
    }

    private static func effectiveStartTime(for line: LyricLine) -> TimeInterval? {
        line.startTime ?? line.words.compactMap(\.startTime).min()
    }

    private static func estimatedTimes(
        _ sourceTimes: [TimeInterval?],
        duration: TimeInterval
    ) throws -> [TimeInterval] {
        guard duration.isFinite, duration > 0 else {
            throw LyricLRCFileError.invalidEstimationDuration
        }
        let knownIndices = sourceTimes.indices.filter { sourceTimes[$0] != nil }
        guard let firstKnownIndex = knownIndices.first,
              let lastKnownIndex = knownIndices.last else {
            let step = duration / Double(sourceTimes.count)
            return sourceTimes.indices.map { Double($0) * step }
        }

        var result = sourceTimes
        guard let firstKnownTime = sourceTimes[firstKnownIndex],
              let lastKnownTime = sourceTimes[lastKnownIndex] else {
            throw LyricLRCFileError.invalidEstimationDuration
        }
        if firstKnownIndex > 0 {
            for index in 0..<firstKnownIndex {
                result[index] = firstKnownTime * Double(index) / Double(firstKnownIndex)
            }
        }
        if knownIndices.count > 1 {
            for pairIndex in 0..<(knownIndices.count - 1) {
                let lowerIndex = knownIndices[pairIndex]
                let upperIndex = knownIndices[pairIndex + 1]
                guard upperIndex - lowerIndex > 1,
                      let lowerTime = sourceTimes[lowerIndex],
                      let upperTime = sourceTimes[upperIndex] else { continue }
                for index in (lowerIndex + 1)..<upperIndex {
                    let fraction = Double(index - lowerIndex) / Double(upperIndex - lowerIndex)
                    result[index] = lowerTime + (upperTime - lowerTime) * fraction
                }
            }
        }
        if lastKnownIndex < sourceTimes.count - 1 {
            guard duration > lastKnownTime else {
                throw LyricLRCFileError.invalidEstimationDuration
            }
            let spanCount = sourceTimes.count - lastKnownIndex
            for index in (lastKnownIndex + 1)..<sourceTimes.count {
                let fraction = Double(index - lastKnownIndex) / Double(spanCount)
                result[index] = lastKnownTime + (duration - lastKnownTime) * fraction
            }
        }
        return result.compactMap { $0 }
    }

    private static func selectedTranslation(
        for line: LyricLine,
        options: LyricLRCExportOptions
    ) -> String {
        guard options.includeTranslation else { return "" }
        let translation: LyricTranslation?
        if let language = options.translationLanguage {
            translation = line.translations.first { $0.targetLanguage == language }
        } else {
            translation = line.translations.first
        }
        return singleLineText(translation?.text ?? "")
    }

    private static func singleLineText(_ value: String) -> String {
        value.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
