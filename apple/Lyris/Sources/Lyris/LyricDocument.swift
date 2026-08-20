import Foundation

enum LyricTimingLevel: String, Codable, Equatable, Sendable {
    case wordSynced
    case lineSynced
    case estimatedLine
    case plainText
    case unavailable

    var isPreciselySynced: Bool {
        self == .wordSynced || self == .lineSynced
    }
}

struct LyricWord: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let text: String
    let startTime: TimeInterval?
    let endTime: TimeInterval?

    init(
        id: UUID = UUID(),
        text: String,
        startTime: TimeInterval? = nil,
        endTime: TimeInterval? = nil
    ) {
        self.id = id
        self.text = text
        self.startTime = startTime
        self.endTime = endTime
    }
}

struct LyricTranslation: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let targetLanguage: String
    var text: String
    let provider: String?
    let model: String?
    var isUserEdited: Bool

    init(
        id: UUID = UUID(),
        targetLanguage: String,
        text: String,
        provider: String? = nil,
        model: String? = nil,
        isUserEdited: Bool = false
    ) {
        self.id = id
        self.targetLanguage = targetLanguage
        self.text = text
        self.provider = provider
        self.model = model
        self.isUserEdited = isUserEdited
    }
}

struct LyricLine: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let startTime: TimeInterval?
    let endTime: TimeInterval?
    let original: String
    let words: [LyricWord]
    var translations: [LyricTranslation]
    let isEstimated: Bool

    init(
        id: UUID = UUID(),
        startTime: TimeInterval?,
        endTime: TimeInterval? = nil,
        original: String,
        words: [LyricWord] = [],
        translations: [LyricTranslation] = [],
        isEstimated: Bool = false
    ) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.original = original
        self.words = words
        self.translations = translations
        self.isEstimated = isEstimated
    }
}

struct LyricSourceMetadata: Codable, Equatable, Sendable {
    let sourceID: String
    let provider: String
    let matchedTrackID: String?

    init(sourceID: String, provider: String, matchedTrackID: String? = nil) {
        self.sourceID = sourceID
        self.provider = provider
        self.matchedTrackID = matchedTrackID
    }
}

struct LyricDocument: Codable, Equatable, Sendable {
    let trackID: String?
    let timingLevel: LyricTimingLevel
    let source: LyricSourceMetadata
    var lines: [LyricLine]

    init(
        trackID: String? = nil,
        timingLevel: LyricTimingLevel,
        source: LyricSourceMetadata,
        lines: [LyricLine]
    ) {
        self.trackID = trackID
        self.timingLevel = timingLevel
        self.source = source
        self.lines = lines
    }

    init(
        trackID: String? = nil,
        sourceID: String,
        provider: String,
        timedLyrics: [TimedLyric]
    ) {
        self.trackID = trackID
        source = LyricSourceMetadata(
            sourceID: sourceID,
            provider: provider,
            matchedTrackID: trackID
        )
        if timedLyrics.isEmpty {
            timingLevel = .unavailable
        } else if timedLyrics.allSatisfy(\.isEstimated) {
            timingLevel = .estimatedLine
        } else {
            timingLevel = .lineSynced
        }
        lines = timedLyrics.map { lyric in
            LyricLine(
                id: lyric.id,
                startTime: lyric.startTime,
                original: lyric.original,
                translations: lyric.translation.isEmpty
                    ? []
                    : [LyricTranslation(targetLanguage: "unspecified", text: lyric.translation)],
                isEstimated: lyric.isEstimated
            )
        }
    }

    var timedLyrics: [TimedLyric] {
        lines.enumerated().map { index, line in
            TimedLyric(
                id: line.id,
                startTime: line.startTime ?? TimeInterval(index),
                original: line.original,
                translation: line.translations.first?.text ?? "",
                isEstimated: line.isEstimated || timingLevel == .estimatedLine || timingLevel == .plainText
            )
        }
    }
}
