import Foundation

/// Network-independent metadata used to decide whether lyrics belong to a track.
struct LyricsMatchCandidate: Equatable, Sendable {
    let title: String
    let artist: String
    let album: String
    let duration: TimeInterval
}

struct LyricsMatch: Equatable, Sendable {
    let index: Int
    let score: Double
}

/// Conservative matcher for lyrics-provider search results.
///
/// The matcher deliberately returns `nil` instead of guessing when the title,
/// artist, duration or recording-version evidence is weak.
struct LyricsMatcher: Sendable {
    private let minimumConfidence: Double

    init(minimumConfidence: Double = 0.87) {
        self.minimumConfidence = minimumConfidence
    }

    func bestMatch(
        for track: Track,
        among candidates: [LyricsMatchCandidate]
    ) -> LyricsMatch? {
        let queryTitle = ParsedTitle(track.title)
        let queryArtists = ParsedArtists(track.artist)
        let queryAlbum = NormalizedText(track.album)

        let ranked = candidates.enumerated().compactMap { index, candidate -> RankedCandidate? in
            let candidateTitle = ParsedTitle(candidate.title)
            guard queryTitle.versionTags == candidateTitle.versionTags else { return nil }

            let titleScore = textSimilarity(queryTitle.base, candidateTitle.base)
            guard titleScore >= 0.82 else { return nil }

            let artistScore = queryArtists.similarity(to: ParsedArtists(candidate.artist))
            guard artistScore >= 0.65 else { return nil }

            let albumScore = textSimilarity(queryAlbum.value, NormalizedText(candidate.album).value)
            let durationScore = Self.durationScore(
                expected: track.duration,
                candidate: candidate.duration
            )
            let score = titleScore * 0.50
                + artistScore * 0.28
                + albumScore * 0.07
                + durationScore * 0.15

            guard score >= minimumConfidence else { return nil }
            return RankedCandidate(
                match: LyricsMatch(index: index, score: score),
                durationDelta: abs(track.duration - candidate.duration)
            )
        }

        return ranked.sorted { lhs, rhs in
            if abs(lhs.match.score - rhs.match.score) > 0.000_001 {
                return lhs.match.score > rhs.match.score
            }
            if abs(lhs.durationDelta - rhs.durationDelta) > 0.000_001 {
                return lhs.durationDelta < rhs.durationDelta
            }
            return lhs.match.index < rhs.match.index
        }.first?.match
    }

    private static func durationScore(
        expected: TimeInterval,
        candidate: TimeInterval
    ) -> Double {
        guard expected > 0, candidate > 0 else { return 0.5 }
        let tolerance = max(12, expected * 0.05)
        return max(0, 1 - abs(expected - candidate) / tolerance)
    }
}

private struct RankedCandidate {
    let match: LyricsMatch
    let durationDelta: TimeInterval
}

private enum RecordingVersion: String, Hashable {
    case live
    case remaster
    case acoustic
    case instrumental
    case karaoke
    case radioEdit
    case remix
    case demo
    case spedUp
    case slowed
    case clean
    case explicit
    case deluxe
}

private struct ParsedTitle {
    let base: String
    let versionTags: Set<RecordingVersion>

    init(_ rawValue: String) {
        let folded = rawValue.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        ).lowercased()
        let allTags = Self.detectVersionTags(in: NormalizedText(folded).value)
        let featureArtistTags = Self.featureCreditContents(in: folded).reduce(into: Set<RecordingVersion>()) {
            result, credit in
            result.formUnion(Self.detectVersionTags(in: NormalizedText(credit).value))
        }
        versionTags = allTags.subtracting(featureArtistTags)

        var baseValue = Self.removingQualifiedSegments(from: folded)
        baseValue = Self.removingFeatureCredit(from: baseValue)
        baseValue = Self.removingInlineVersionPhrases(from: baseValue)
        base = NormalizedText(baseValue).value
    }

    private static func detectVersionTags(in value: String) -> Set<RecordingVersion> {
        var tags: Set<RecordingVersion> = []

        if containsWord("live", in: value) { tags.insert(.live) }
        if containsAnyWord(["remaster", "remastered", "remastering"], in: value) {
            tags.insert(.remaster)
        }
        if containsAnyWord(["acoustic", "unplugged"], in: value) { tags.insert(.acoustic) }
        if containsWord("instrumental", in: value) { tags.insert(.instrumental) }
        if containsWord("karaoke", in: value) { tags.insert(.karaoke) }
        if containsPhrase("radio edit", in: value) || containsPhrase("radio version", in: value) {
            tags.insert(.radioEdit)
        }
        if containsAnyWord(["remix", "remixed"], in: value) { tags.insert(.remix) }
        if containsWord("demo", in: value) { tags.insert(.demo) }
        if containsPhrase("sped up", in: value) || containsPhrase("speed up", in: value) {
            tags.insert(.spedUp)
        }
        if containsAnyWord(["slowed", "slower"], in: value)
            || containsPhrase("slow down", in: value) {
            tags.insert(.slowed)
        }
        if containsWord("clean", in: value) { tags.insert(.clean) }
        if containsWord("explicit", in: value) { tags.insert(.explicit) }
        if containsWord("deluxe", in: value) { tags.insert(.deluxe) }

        return tags
    }

    private static func removingFeatureCredit(from value: String) -> String {
        let withoutBracketedCredits = replacing(
            #"(?i)[\s\-–—]*(?:\(|\[)\s*(?:feat(?:uring)?|ft)\.?\s+[^\)\]]+(?:\)|\])"#,
            in: value,
            with: " "
        )
        return replacing(
            #"(?i)[\s\-–—]*(?:\(|\[)?\s*(?:feat(?:uring)?|ft)\.?\s+[^\)\]]+(?:\)|\])?\s*$"#,
            in: withoutBracketedCredits,
            with: " "
        )
    }

    private static func featureCreditContents(in value: String) -> [String] {
        let pattern = #"(?i)(?:feat(?:uring)?|ft)\.?\s+(.+?)(?=\s(?:\(|\[)|\s[-–—]\s|\)|\]|$)"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
        let matches = expression.matches(
            in: value,
            range: NSRange(value.startIndex..<value.endIndex, in: value)
        )
        return matches.compactMap { match in
            guard let range = Range(match.range(at: 1), in: value) else { return nil }
            return String(value[range])
        }
    }

    private static func removingQualifiedSegments(from value: String) -> String {
        var result = value
        let bracketPattern = #"[\(\[]([^\)\]]+)[\)\]]"#
        guard let expression = try? NSRegularExpression(pattern: bracketPattern) else { return result }

        let matches = expression.matches(
            in: result,
            range: NSRange(result.startIndex..<result.endIndex, in: result)
        )
        for match in matches.reversed() {
            guard let wholeRange = Range(match.range(at: 0), in: result),
                  let contentRange = Range(match.range(at: 1), in: result) else { continue }
            let content = NormalizedText(String(result[contentRange])).value
            if !detectVersionTags(in: content).isEmpty {
                result.replaceSubrange(wholeRange, with: " ")
            }
        }

        let suffixPattern = #"\s[-–—]\s*([^\n]+)$"#
        if let suffixExpression = try? NSRegularExpression(pattern: suffixPattern) {
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            if let match = suffixExpression.firstMatch(in: result, range: range),
               let wholeRange = Range(match.range(at: 0), in: result),
               let contentRange = Range(match.range(at: 1), in: result) {
                let content = NormalizedText(String(result[contentRange])).value
                if !detectVersionTags(in: content).isEmpty {
                    result.replaceSubrange(wholeRange, with: " ")
                }
            }
        }
        return result
    }

    private static func removingInlineVersionPhrases(from value: String) -> String {
        let patterns = [
            #"\b(?:19|20)\d{2}\s+remaster(?:ed|ing)?\b"#,
            #"\bremaster(?:ed|ing)?\b"#,
            #"\blive(?:\s+version)?\b"#,
            #"\b(?:acoustic|unplugged)(?:\s+version)?\b"#,
            #"\binstrumental(?:\s+version)?\b"#,
            #"\bkaraoke(?:\s+version)?\b"#,
            #"\bradio\s+(?:edit|version)\b"#,
            #"\b(?:club\s+)?remix(?:ed)?(?:\s+version)?\b"#,
            #"\b(?:original\s+)?demo(?:\s+version)?\b"#,
            #"\b(?:sped|speed)\s+up(?:\s+version)?\b"#,
            #"\b(?:slowed|slow\s+down)(?:\s*\+?\s*reverb)?(?:\s+version)?\b"#,
            #"\b(?:clean|explicit|deluxe)(?:\s+version)?\b"#,
        ]
        return patterns.reduce(value) { result, pattern in
            replacing(pattern, in: result, with: " ")
        }
    }
}

private struct ParsedArtists {
    let normalized: String
    let components: [String]

    init(_ rawValue: String) {
        normalized = NormalizedText(rawValue).value
        let folded = rawValue.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        ).lowercased()
        let separatorPattern = #"(?i)\s*(?:,|;|/|&|\+|×|\b(?:feat(?:uring)?|ft|with|and|x)\.?\b)\s*"#
        let separated = replacing(separatorPattern, in: folded, with: "|")
        components = separated
            .split(separator: "|")
            .map { NormalizedText(String($0)).value }
            .filter { !$0.isEmpty }
    }

    func similarity(to other: ParsedArtists) -> Double {
        if normalized == other.normalized, !normalized.isEmpty { return 1 }
        guard let lead = components.first, let otherLead = other.components.first else { return 0 }

        let lhs = Set(components)
        let rhs = Set(other.components)
        let unionCount = lhs.union(rhs).count
        let jaccard = unionCount == 0
            ? 0
            : Double(lhs.intersection(rhs).count) / Double(unionCount)

        if lead == otherLead {
            return 0.84 + 0.16 * jaccard
        }
        if jaccard >= 0.5 {
            return 0.65 + 0.35 * jaccard
        }
        return textSimilarity(lead, otherLead) * 0.6
    }
}

enum LyricsMetadataCanonicalizer {
    static func simplifiedChinese(_ rawValue: String) -> String {
        rawValue.applyingTransform(
            StringTransform("Traditional-Simplified"),
            reverse: false
        ) ?? rawValue
    }

    static func traditionalChinese(_ rawValue: String) -> String {
        rawValue.applyingTransform(
            StringTransform("Simplified-Traditional"),
            reverse: false
        ) ?? rawValue
    }
}

private struct NormalizedText {
    let value: String

    init(_ rawValue: String) {
        // Spotify metadata can follow the listener's locale while LRCLIB may
        // index the same Chinese artist/title using the other script. Compare
        // through a Simplified-Chinese canonical form without changing any
        // user-visible spelling.
        let scriptNormalized = LyricsMetadataCanonicalizer.simplifiedChinese(rawValue)
        let folded = scriptNormalized.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        ).lowercased()
        var scalars: [UnicodeScalar] = []
        scalars.reserveCapacity(folded.unicodeScalars.count)
        var previousWasSeparator = true

        for scalar in folded.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                scalars.append(scalar)
                previousWasSeparator = false
            } else if !previousWasSeparator {
                scalars.append(" ")
                previousWasSeparator = true
            }
        }
        value = String(String.UnicodeScalarView(scalars))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private func textSimilarity(_ lhs: String, _ rhs: String) -> Double {
    guard !lhs.isEmpty, !rhs.isEmpty else { return 0 }
    if lhs == rhs { return 1 }
    let lhsTokens = Set(lhs.split(separator: " ").map(String.init))
    let rhsTokens = Set(rhs.split(separator: " ").map(String.init))
    let unionCount = lhsTokens.union(rhsTokens).count
    guard unionCount > 0 else { return 0 }
    return Double(lhsTokens.intersection(rhsTokens).count) / Double(unionCount)
}

private func containsWord(_ word: String, in value: String) -> Bool {
    value.split(separator: " ").contains(Substring(word))
}

private func containsAnyWord(_ words: [String], in value: String) -> Bool {
    words.contains { containsWord($0, in: value) }
}

private func containsPhrase(_ phrase: String, in value: String) -> Bool {
    " \(value) ".contains(" \(phrase) ")
}

private func replacing(_ pattern: String, in value: String, with replacement: String) -> String {
    guard let expression = try? NSRegularExpression(pattern: pattern) else { return value }
    let range = NSRange(value.startIndex..<value.endIndex, in: value)
    return expression.stringByReplacingMatches(in: value, range: range, withTemplate: replacement)
}
