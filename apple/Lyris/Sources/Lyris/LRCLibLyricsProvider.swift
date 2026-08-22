import Foundation

struct LRCLibLyricsProvider: LyricsProviding {
    private let session: URLSession
    private let matcher: LyricsMatcher

    init(session: URLSession = .shared, matcher: LyricsMatcher = LyricsMatcher()) {
        self.session = session
        self.matcher = matcher
    }

    func lyrics(for track: Track) async throws -> LyricsProviderResult {
        guard track.id != "spotify:idle" else {
            return LyricsProviderResult(
                sourceID: "lrclib:unavailable",
                lyrics: [],
                trackID: track.id,
                provider: "LRCLIB"
            )
        }
        if let exact = try await fetchExact(track: track),
           let match = bestRecord(in: [exact], for: track, requiring: \.syncedLyrics),
           let synced = match.syncedLyrics,
           !synced.isEmpty {
            return result(for: match, lyrics: parse(synced), trackID: track.id)
        }

        let candidates = try await search(track: track)
        if let match = bestRecord(in: candidates, for: track, requiring: \.syncedLyrics),
           let synced = match.syncedLyrics {
            return result(for: match, lyrics: parse(synced), trackID: track.id)
        }

        guard let plainMatch = bestRecord(in: candidates, for: track, requiring: \.plainLyrics),
              let plain = plainMatch.plainLyrics else {
            return LyricsProviderResult(
                sourceID: "lrclib:no-match",
                lyrics: [],
                trackID: track.id,
                provider: "LRCLIB"
            )
        }
        return result(
            for: plainMatch,
            lyrics: estimateTiming(for: plain, duration: track.duration),
            trackID: track.id
        )
    }

    private func result(
        for record: LRCLibRecord,
        lyrics: [TimedLyric],
        trackID: String
    ) -> LyricsProviderResult {
        let sourceID: String
        if let id = record.id {
            sourceID = "lrclib:\(id)"
        } else {
            let duration = record.duration.map { String(Int($0.rounded())) } ?? "unknown"
            sourceID = "lrclib:\(record.trackName)|\(record.artistName)|\(record.albumName)|\(duration)"
        }
        return LyricsProviderResult(
            sourceID: sourceID,
            lyrics: lyrics,
            trackID: trackID,
            provider: "LRCLIB"
        )
    }

    private func fetchExact(track: Track) async throws -> LRCLibRecord? {
        var components = URLComponents(string: "https://lrclib.net/api/get-cached")!
        components.queryItems = [
            URLQueryItem(name: "track_name", value: track.title),
            URLQueryItem(name: "artist_name", value: track.artist),
            URLQueryItem(name: "album_name", value: track.album),
            URLQueryItem(name: "duration", value: String(Int(track.duration.rounded()))),
        ]
        let (data, response) = try await request(components.url!)
        if response.statusCode == 404 { return nil }
        try validate(response, data: data)
        return try JSONDecoder().decode(LRCLibRecord.self, from: data)
    }

    private func search(track: Track) async throws -> [LRCLibRecord] {
        var records = try await search(
            trackName: track.title,
            artistName: track.artist
        )

        let compatibilityQueries = [
            (
                LyricsMetadataCanonicalizer.simplifiedChinese(track.title),
                LyricsMetadataCanonicalizer.simplifiedChinese(track.artist)
            ),
            (
                LyricsMetadataCanonicalizer.traditionalChinese(track.title),
                LyricsMetadataCanonicalizer.traditionalChinese(track.artist)
            ),
        ]
        var requestedKeys: Set<String> = [metadataQueryKey(title: track.title, artist: track.artist)]

        for (title, artist) in compatibilityQueries {
            let key = metadataQueryKey(title: title, artist: artist)
            guard requestedKeys.insert(key).inserted else { continue }
            do {
                records += try await search(trackName: title, artistName: artist)
            } catch {
                // Preserve a usable response if only a compatibility lookup
                // fails. If every query is still empty, surface the failure so
                // the UI does not misreport a network problem as "no lyrics".
                guard !records.isEmpty else { throw error }
            }
        }

        if records.isEmpty {
            let titleOnlyQueries = [
                track.title,
                LyricsMetadataCanonicalizer.simplifiedChinese(track.title),
                LyricsMetadataCanonicalizer.traditionalChinese(track.title),
            ]
            var requestedTitles = Set<String>()
            for title in titleOnlyQueries {
                let key = title.trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
                guard !key.isEmpty, requestedTitles.insert(key).inserted else { continue }
                do {
                    records += try await search(trackName: title, artistName: nil)
                } catch {
                    guard !records.isEmpty else { throw error }
                }
            }
        }
        return records
    }

    private func metadataQueryKey(title: String, artist: String) -> String {
        "\(title)\u{1f}\(artist)"
    }

    private func search(
        trackName: String,
        artistName: String?
    ) async throws -> [LRCLibRecord] {
        var components = URLComponents(string: "https://lrclib.net/api/search")!
        components.queryItems = [URLQueryItem(name: "track_name", value: trackName)]
        if let artistName {
            components.queryItems?.append(
                URLQueryItem(name: "artist_name", value: artistName)
            )
        }
        let (data, response) = try await request(components.url!)
        try validate(response, data: data)
        return try JSONDecoder().decode([LRCLibRecord].self, from: data)
    }

    private func request(_ url: URL) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue(
            "Lyris/1.0.0 (https://github.com/Yifo98/Lyris)",
            forHTTPHeaderField: "User-Agent"
        )
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw LRCLibError.invalidResponse }
        return (data, http)
    }

    private func validate(_ response: HTTPURLResponse, data _: Data) throws {
        switch response.statusCode {
        case 200..<300:
            return
        case 401, 403:
            throw LRCLibError.unauthorized(statusCode: response.statusCode)
        case 429:
            throw LRCLibError.rateLimited(
                retryAfter: response.value(forHTTPHeaderField: "Retry-After")
                    .flatMap { SpotifyRetryAfter.parse($0) }
            )
        case 500..<600:
            throw LRCLibError.server(statusCode: response.statusCode)
        default:
            throw LRCLibError.httpStatus(response.statusCode)
        }
    }

    private func bestRecord(
        in records: [LRCLibRecord],
        for track: Track,
        requiring lyrics: KeyPath<LRCLibRecord, String?>
    ) -> LRCLibRecord? {
        let eligible = records.filter { record in
            guard let value = record[keyPath: lyrics] else { return false }
            return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        let candidates = eligible.map { record in
            LyricsMatchCandidate(
                title: record.trackName,
                artist: record.artistName,
                album: record.albumName,
                duration: record.duration ?? 0
            )
        }
        guard let match = matcher.bestMatch(for: track, among: candidates) else { return nil }
        return eligible[match.index]
    }

    private func parse(_ lrc: String) -> [TimedLyric] {
        let expression = try? NSRegularExpression(
            pattern: #"^\[(\d{1,2}):(\d{2})(?:[.:](\d{1,3}))?\]\s*(.*)$"#
        )
        return lrc.split(whereSeparator: \.isNewline).compactMap { rawLine in
            let line = String(rawLine)
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            guard let match = expression?.firstMatch(in: line, range: range),
                  let minutesRange = Range(match.range(at: 1), in: line),
                  let secondsRange = Range(match.range(at: 2), in: line),
                  let textRange = Range(match.range(at: 4), in: line),
                  let minutes = Double(line[minutesRange]),
                  let seconds = Double(line[secondsRange]) else { return nil }
            let fraction: Double
            if let fractionRange = Range(match.range(at: 3), in: line) {
                let rawFraction = String(line[fractionRange])
                let divisor: Double = switch rawFraction.count {
                case 1: 10
                case 2: 100
                default: 1_000
                }
                fraction = (Double(rawFraction) ?? 0) / divisor
            } else {
                fraction = 0
            }
            let text = line[textRange].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return TimedLyric(
                startTime: minutes * 60 + seconds + fraction,
                original: text,
                translation: ""
            )
        }
        .sorted(by: { $0.startTime < $1.startTime })
    }

    private func estimateTiming(for plainLyrics: String, duration: TimeInterval) -> [TimedLyric] {
        let lines = plainLyrics
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !($0.hasPrefix("[") && $0.hasSuffix("]")) }
        guard !lines.isEmpty else { return [] }
        let start = min(8, max(2, duration * 0.04))
        let usableDuration = max(1, duration - start - 3)
        let step = usableDuration / Double(lines.count)
        return lines.enumerated().map { index, line in
            TimedLyric(
                startTime: start + Double(index) * step,
                original: line,
                translation: "",
                isEstimated: true
            )
        }
    }
}

private struct LRCLibRecord: Decodable {
    let id: Int?
    let trackName: String
    let artistName: String
    let albumName: String
    let duration: TimeInterval?
    let plainLyrics: String?
    let syncedLyrics: String?
}

enum LRCLibError: LocalizedError, Equatable {
    case invalidResponse
    case unauthorized(statusCode: Int)
    case rateLimited(retryAfter: TimeInterval?)
    case server(statusCode: Int)
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: "歌词服务没有返回 HTTP 响应。"
        case .unauthorized(let statusCode): "歌词服务拒绝访问（HTTP \(statusCode)）。"
        case .rateLimited(let retryAfter):
            retryAfter.map { "歌词服务请求过于频繁，请至少等待 \(Int(ceil($0))) 秒。" }
                ?? "歌词服务请求过于频繁，请稍后重试。"
        case .server(let statusCode): "歌词服务暂时不可用（HTTP \(statusCode)）。"
        case .httpStatus(let status): "歌词服务请求失败（HTTP \(status)）。"
        }
    }
}
