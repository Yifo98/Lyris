import Foundation

@main
private enum LRCLibLyricsProviderHarness {
    static func main() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LRCLibHarnessURLProtocol.self]
        let provider = LRCLibLyricsProvider(session: URLSession(configuration: configuration))
        let track = Track(
            id: "spotify:track:fixture",
            title: "Strategy (from the Netflix film KPop Demon Hunters)",
            artist: "TWICE",
            album: "STRATEGY",
            duration: 166.773
        )

        let result = try await provider.lyrics(for: track)

        precondition(result.sourceID == "lrclib:101")
        precondition(result.lyrics.map(\.original) == ["Line one", "Line two"])

        let reportedChineseTrack = Track(
            id: "spotify:track:reported-actor",
            title: "演员",
            artist: "薛之謙",
            album: "绅士",
            duration: 261
        )
        let reportedResult = try await provider.lyrics(for: reportedChineseTrack)
        precondition(
            !reportedResult.lyrics.isEmpty,
            "Simplified/traditional artist spelling must not discard the reported song match"
        )
        precondition(reportedResult.lyrics.first?.original == "简单点，说话的方式简单点")

        print("lrclib_nullable_duration=PASS valid_candidate_preserved=PASS chinese_script_variant_match=PASS")
    }
}

private final class LRCLibHarnessURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let fixture: (status: Int, body: Data)
        if url.path == "/api/get-cached" {
            fixture = (404, Data())
        } else if url.query?.contains(
            "artist_name=%E8%96%9B%E4%B9%8B%E8%B0%A6"
        ) == true {
            let body = """
            [
              {
                "id": 20260726,
                "trackName": "演员",
                "artistName": "薛之谦",
                "albumName": "绅士",
                "duration": 261.0,
                "plainLyrics": "简单点，说话的方式简单点\\n递进的情绪请省略",
                "syncedLyrics": "[00:21.48] 简单点，说话的方式简单点\\n[00:30.07] 递进的情绪请省略"
              }
            ]
            """
            fixture = (200, Data(body.utf8))
        } else if url.query?.contains(
            "artist_name=%E8%96%9B%E4%B9%8B%E8%AC%99"
        ) == true {
            // LRCLIB currently returns no result for the Traditional spelling
            // reported by Spotify, even though the Simplified spelling is
            // indexed and refers to the same artist.
            fixture = (200, Data("[]".utf8))
        } else {
            let body = """
            [
              {
                "id": 101,
                "trackName": "Strategy (from the Netflix film KPop Demon Hunters)",
                "artistName": "TWICE",
                "albumName": "STRATEGY",
                "duration": 166.0,
                "plainLyrics": "Line one\\nLine two",
                "syncedLyrics": "[00:01.00] Line one\\n[00:03.00] Line two"
              },
              {
                "id": 102,
                "trackName": "Strategy (from the Netflix film KPop Demon Hunters)",
                "artistName": "TWICE",
                "albumName": "STRATEGY",
                "duration": null,
                "plainLyrics": "Other line",
                "syncedLyrics": "[00:01.00] Other line"
              }
            ]
            """
            fixture = (200, Data(body.utf8))
        }
        guard let response = HTTPURLResponse(
            url: url,
            statusCode: fixture.status,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        ) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: fixture.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
