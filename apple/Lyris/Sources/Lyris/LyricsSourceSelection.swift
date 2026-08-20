import Foundation

enum LyricsCandidateAuthority: Int, Codable, Equatable, Sendable {
    case network = 0
    case verifiedCache = 1
    case user = 2
}

enum LyricsMatchQuality: Int, Codable, Equatable, Comparable, Sendable {
    case low = 0
    case medium = 1
    case high = 2
    case exact = 3

    static func < (lhs: LyricsMatchQuality, rhs: LyricsMatchQuality) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum LyricsTranslationPriority: String, Codable, CaseIterable, Identifiable, Sendable {
    case providerFirst
    case translationFirst

    var id: String { rawValue }
}

struct LyricsSourceCandidate: Equatable, Sendable {
    let document: LyricDocument
    let authority: LyricsCandidateAuthority
    let matchQuality: LyricsMatchQuality

    init(
        document: LyricDocument,
        authority: LyricsCandidateAuthority = .network,
        matchQuality: LyricsMatchQuality
    ) {
        self.document = document
        self.authority = authority
        self.matchQuality = matchQuality
    }

    func translationCoverage(for targetLanguage: String) -> Double {
        let eligibleLines = document.lines.filter {
            !$0.original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard !eligibleLines.isEmpty else { return 0 }

        let translatedLineCount = eligibleLines.reduce(into: 0) { count, line in
            guard line.translations.contains(where: {
                $0.targetLanguage.caseInsensitiveCompare(targetLanguage) == .orderedSame
                    && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }) else { return }
            count += 1
        }
        return Double(translatedLineCount) / Double(eligibleLines.count)
    }
}

struct LyricsSourceSelectionPolicy: Equatable, Sendable {
    let providerOrder: [String]
    let translationPriority: LyricsTranslationPriority
    let targetLanguage: String
    let minimumMatchQuality: LyricsMatchQuality

    init(
        providerOrder: [String] = [],
        translationPriority: LyricsTranslationPriority = .providerFirst,
        targetLanguage: String,
        minimumMatchQuality: LyricsMatchQuality = .medium
    ) {
        self.providerOrder = providerOrder
        self.translationPriority = translationPriority
        self.targetLanguage = targetLanguage
        self.minimumMatchQuality = minimumMatchQuality
    }

    func select(from candidates: [LyricsSourceCandidate]) -> LyricsSourceCandidate? {
        candidates
            .filter(isEligible)
            .sorted(by: isPreferred)
            .first
    }

    private func isEligible(_ candidate: LyricsSourceCandidate) -> Bool {
        candidate.matchQuality >= minimumMatchQuality
            && candidate.document.timingLevel != .unavailable
            && candidate.document.lines.contains {
                !$0.original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
    }

    private func isPreferred(
        _ lhs: LyricsSourceCandidate,
        _ rhs: LyricsSourceCandidate
    ) -> Bool {
        if lhs.authority != rhs.authority {
            return lhs.authority.rawValue > rhs.authority.rawValue
        }
        if lhs.matchQuality != rhs.matchQuality {
            return lhs.matchQuality > rhs.matchQuality
        }

        switch translationPriority {
        case .providerFirst:
            if providerRank(lhs) != providerRank(rhs) {
                return providerRank(lhs) < providerRank(rhs)
            }
            if translationCoverage(lhs) != translationCoverage(rhs) {
                return translationCoverage(lhs) > translationCoverage(rhs)
            }
        case .translationFirst:
            if translationCoverage(lhs) != translationCoverage(rhs) {
                return translationCoverage(lhs) > translationCoverage(rhs)
            }
            if providerRank(lhs) != providerRank(rhs) {
                return providerRank(lhs) < providerRank(rhs)
            }
        }

        if timingRank(lhs.document.timingLevel) != timingRank(rhs.document.timingLevel) {
            return timingRank(lhs.document.timingLevel) > timingRank(rhs.document.timingLevel)
        }
        return lhs.document.source.sourceID < rhs.document.source.sourceID
    }

    private func providerRank(_ candidate: LyricsSourceCandidate) -> Int {
        providerOrder.firstIndex {
            $0.caseInsensitiveCompare(candidate.document.source.provider) == .orderedSame
        } ?? providerOrder.count
    }

    private func translationCoverage(_ candidate: LyricsSourceCandidate) -> Double {
        candidate.translationCoverage(for: targetLanguage)
    }

    private func timingRank(_ timingLevel: LyricTimingLevel) -> Int {
        switch timingLevel {
        case .wordSynced: 4
        case .lineSynced: 3
        case .estimatedLine: 2
        case .plainText: 1
        case .unavailable: 0
        }
    }
}
